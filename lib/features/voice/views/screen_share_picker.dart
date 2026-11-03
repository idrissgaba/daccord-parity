import 'package:bonfire/theme/app_icons.dart';
import 'dart:async';

import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:universal_platform/universal_platform.dart';

/// Lists the capturable sources of one kind; tests swap it for a fake since
/// the desktop capturer only exists inside the native plugin.
typedef ScreenShareSourceLoader =
    Future<List<rtc.DesktopCapturerSource>> Function(rtc.SourceType type);

/// Shows the desktop "Screen Share" window: a first step picking an
/// application window or a screen (live thumbnails), then — unless
/// [changing] an already live stream — the stream quality step ending in
/// "Go Live". [channelName] names the channel being streamed to. Returns the
/// chosen source, or null if cancelled.
///
/// Not LiveKit's bundled `ScreenSelectDialog`: it calls `setState` from
/// flutter_webrtc's thumbnail stream without a `mounted` guard or cancelling on
/// dispose, so a late thumbnail throws "setState() called after dispose()".
Future<rtc.DesktopCapturerSource?> showScreenShareSourcePicker(
  BuildContext context, {
  bool changing = false,
  String? channelName,
  @visibleForTesting ScreenShareSourceLoader? sourceLoader,
}) {
  return showDialog<rtc.DesktopCapturerSource>(
    context: context,
    barrierDismissible: true,
    builder: (_) => ScreenShareDialog(
      changing: changing,
      channelName: channelName,
      sourceLoader: sourceLoader,
    ),
  );
}

/// Starts or stops screen sharing for the current voice session.
///
/// On desktop, starting first prompts the user to pick a window or screen
/// and a quality; cancelling aborts without sharing. On web/mobile the
/// platform shows its own native capture prompt and the share starts as soon
/// as it is confirmed, so we toggle directly (quality comes from Settings).
Future<void> toggleScreenShareWithPicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final notifier = ref.read(voiceControllerProvider.notifier);
  final voice = ref.read(voiceControllerProvider);

  if (voice.selfStream) {
    await notifier.toggleScreenShare();
    return;
  }

  if (UniversalPlatform.isDesktop) {
    final source = await showScreenShareSourcePicker(
      context,
      channelName: _voiceChannelName(ref, voice),
    );
    if (source == null) return; // cancelled
    await notifier.toggleScreenShare(sourceId: source.id);
  } else {
    await notifier.toggleScreenShare();
  }
}

String? _voiceChannelName(WidgetRef ref, VoiceConnection voice) {
  final spaceId = voice.spaceId;
  final serverKey = voice.serverKey ?? ref.readActiveServerKey();
  if (spaceId == null || serverKey == null) return null;
  return ref
      .read(accordChannelsControllerProvider(serverKey, spaceId))
      ?.firstWhereOrNull((c) => c.id == voice.channelId)
      ?.name;
}

/// The desktop "Screen Share" window (see [showScreenShareSourcePicker]).
class ScreenShareDialog extends StatefulWidget {
  const ScreenShareDialog({
    super.key,
    this.changing = false,
    this.channelName,
    this.sourceLoader,
  });

  /// Only the source is being changed: no quality step, the choice applies
  /// at once.
  final bool changing;

  /// The voice channel streamed to, for the "Streaming channel" row.
  final String? channelName;

  /// Replaces the desktop capturer's source list (tests).
  final ScreenShareSourceLoader? sourceLoader;

  @override
  State<ScreenShareDialog> createState() => _ScreenShareDialogState();
}

class _ScreenShareDialogState extends State<ScreenShareDialog>
    with SingleTickerProviderStateMixin {
  // Applications first, screens second, as in other chat apps.
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(_onTabChanged);

  final List<StreamSubscription<rtc.DesktopCapturerSource>> _subscriptions = [];
  final Map<String, rtc.DesktopCapturerSource> _sources = {};

  rtc.SourceType _sourceType = rtc.SourceType.Window;
  rtc.DesktopCapturerSource? _selectedSource;
  Timer? _refreshTimer;

  /// Step two: the stream quality, after a source was chosen.
  bool _qualityStep = false;

  @override
  void initState() {
    super.initState();

    if (widget.sourceLoader == null) {
      _subscriptions.add(
        rtc.desktopCapturer.onAdded.stream.listen((source) {
          if (!mounted) return;
          setState(() => _sources[source.id] = source);
        }),
      );
      _subscriptions.add(
        rtc.desktopCapturer.onRemoved.stream.listen((source) {
          if (!mounted) return;
          setState(() => _sources.remove(source.id));
        }),
      );
      _subscriptions.add(
        rtc.desktopCapturer.onThumbnailChanged.stream.listen((_) {
          if (!mounted) return;
          setState(() {});
        }),
      );
    }

    _loadSources();
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _refreshTimer?.cancel();
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    final type = _tabs.index == 0
        ? rtc.SourceType.Window
        : rtc.SourceType.Screen;
    if (type == _sourceType) return;
    _sourceType = type;
    _loadSources();
  }

  Future<void> _loadSources() async {
    try {
      final loader = widget.sourceLoader;
      final sources = loader != null
          ? await loader(_sourceType)
          : await rtc.desktopCapturer.getSources(types: [_sourceType]);
      if (!mounted) return;
      setState(() {
        _sources
          ..clear()
          ..addEntries(sources.map((s) => MapEntry(s.id, s)));
      });
      if (loader != null) return;
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        unawaited(rtc.desktopCapturer.updateSources(types: [_sourceType]));
      });
    } catch (_) {
      // Enumeration can fail transiently (e.g. permissions not yet granted);
      // the periodic refresh and add/remove streams will recover.
    }
  }

  void _pick(rtc.DesktopCapturerSource source) {
    if (widget.changing) {
      Navigator.of(context).pop(source);
      return;
    }
    setState(() {
      _selectedSource = source;
      _qualityStep = true;
    });
  }

  void _confirm() => Navigator.of(context).pop(_selectedSource);
  void _cancel() => Navigator.of(context).pop();
  void _back() => setState(() => _qualityStep = false);

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: _qualityStep ? _qualityPage(colors) : _sourcePage(colors),
      ),
    );
  }

  Widget _header(BonfireThemeExtension colors, {String? subtitle}) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, subtitle == null ? 16 : 8),
          child: Column(
            children: [
              Text(
                'Screen Share',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.dirtyWhite,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.gray,
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          right: 8,
          top: 8,
          child: IconButton(
            tooltip: 'Close',
            onPressed: _cancel,
            icon: Icon(AppIcons.close, color: colors.gray),
          ),
        ),
      ],
    );
  }

  Widget _sourcePage(BonfireThemeExtension colors) {
    final theme = Theme.of(context);
    final sources = _sources.values
        .where((s) => s.type == _sourceType)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(
          colors,
          subtitle: widget.changing
              ? 'Select something else to stream.'
              : 'Select something to stream and have your friends grab a seat!',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerHeight: 0,
            labelColor: colors.dirtyWhite,
            unselectedLabelColor: colors.gray,
            indicatorColor: colors.dirtyWhite,
            tabs: const [
              Tab(text: 'Applications'),
              Tab(text: 'Screens'),
            ],
          ),
        ),
        Flexible(
          child: sources.isEmpty
              ? SizedBox(
                  height: 200,
                  child: Center(
                    child: Text(
                      'No sources available',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.gray,
                      ),
                    ),
                  ),
                )
              : GridView.count(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.45,
                  children: [
                    for (final source in sources)
                      _SourceTile(
                        source: source,
                        selected: _selectedSource?.id == source.id,
                        colors: colors,
                        onTap: () => _pick(source),
                      ),
                  ],
                ),
        ),
        _footer(
          colors,
          left: TextButton(
            onPressed: _cancel,
            style: TextButton.styleFrom(foregroundColor: colors.dirtyWhite),
            child: const Text('Cancel'),
          ),
          right: FilledButton(
            key: const Key('share-go-live'),
            onPressed: _selectedSource == null ? null : _confirm,
            child: const Text('Go Live'),
          ),
        ),
      ],
    );
  }

  Widget _qualityPage(BonfireThemeExtension colors) {
    final theme = Theme.of(context);
    final source = _selectedSource!;
    final label = theme.textTheme.labelSmall?.copyWith(
      color: colors.gray,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    );
    final isScreen = source.type == rtc.SourceType.Screen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(colors),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("WHAT YOU'RE STREAMING", style: label),
                const SizedBox(height: 8),
                _Field(
                  colors: colors,
                  icon: isScreen
                      ? AppIcons.desktopWindowsOutlined
                      : AppIcons.webAssetOutlined,
                  text: source.name,
                  trailing: TextButton(
                    key: const Key('share-change-source'),
                    onPressed: _back,
                    style: TextButton.styleFrom(
                      backgroundColor: colors.darkGray,
                      foregroundColor: colors.dirtyWhite,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('Change'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(AppIcons.infoOutline, size: 16, color: colors.gray),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        // Desktop captures carry no sound (the share's audio
                        // only exists in a browser).
                        isScreen
                            ? 'Sound may not be available when sharing a '
                                  'screen on your device.'
                            : 'Sound may not be available when sharing an '
                                  'application on your device.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.gray,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.channelName != null) ...[
                  const SizedBox(height: 20),
                  Text('STREAMING CHANNEL', style: label),
                  const SizedBox(height: 8),
                  _Field(
                    colors: colors,
                    icon: AppIcons.volumeUp,
                    text: widget.channelName!,
                  ),
                ],
                const SizedBox(height: 20),
                Text('STREAM QUALITY', style: label),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.background),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const ShareQualityRow(),
                ),
              ],
            ),
          ),
        ),
        _footer(
          colors,
          left: TextButton(
            onPressed: _back,
            style: TextButton.styleFrom(
              backgroundColor: colors.darkGray,
              foregroundColor: colors.dirtyWhite,
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            child: const Text('Back'),
          ),
          right: FilledButton(
            key: const Key('share-go-live'),
            onPressed: _confirm,
            child: const Text('Go Live'),
          ),
        ),
      ],
    );
  }

  Widget _footer(
    BonfireThemeExtension colors, {
    required Widget left,
    required Widget right,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [left, right],
      ),
    );
  }
}

/// A read-only row of the quality step: icon, text and an optional button.
class _Field extends StatelessWidget {
  const _Field({
    required this.colors,
    required this.icon,
    required this.text,
    this.trailing,
  });

  final BonfireThemeExtension colors;
  final IconData icon;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.dirtyWhite),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.dirtyWhite),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final rtc.DesktopCapturerSource source;
  final bool selected;
  final BonfireThemeExtension colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumbnail = source.thumbnail;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  width: 2,
                  color: selected ? colors.primary : Colors.transparent,
                ),
              ),
              child: thumbnail != null && thumbnail.isNotEmpty
                  ? Image.memory(
                      thumbnail,
                      gaplessPlayback: true,
                      fit: BoxFit.cover,
                    )
                  : const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            source.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.dirtyWhite,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stream quality picked right before going live, as in other voice chat
/// apps: a preset (smoother video or sharper text), then resolution and frame
/// rate side by side (the same settings as Voice & Video).
class ShareQualityRow extends ConsumerWidget {
  const ShareQualityRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final colors = BonfireThemeExtension.of(context);
    final label = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: colors.gray,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButton<bool>(
            key: const Key('share-preset'),
            value: settings.screenShareMotionPriority,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: true, child: Text('Smoother Video')),
              DropdownMenuItem(
                value: false,
                child: Text('Better Text Readability'),
              ),
            ],
            onChanged: (v) {
              if (v != null) controller.setScreenShareMotionPriority(v);
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('RESOLUTION', style: label),
                  const SizedBox(height: 6),
                  _Segments<int>(
                    key: const Key('share-quality'),
                    values: [
                      for (
                        var i = 0;
                        i < AccordSettings.screenShareResolutionLabels.length;
                        i++
                      )
                        (
                          i,
                          AccordSettings.screenShareResolutionLabels[i]
                              .replaceFirst('p', '')
                              .toUpperCase(),
                        ),
                    ],
                    selected: settings.screenShareResolution,
                    onSelected: controller.setScreenShareResolution,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FRAME RATE', style: label),
                  const SizedBox(height: 6),
                  _Segments<int>(
                    key: const Key('share-fps'),
                    values: [
                      for (final fps in AccordSettings.screenShareFpsOptions)
                        (fps, '$fps'),
                    ],
                    selected: settings.screenShareFps,
                    onSelected: controller.setScreenShareFps,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A row of joined option buttons, the chosen one filled with the accent.
class _Segments<T> extends StatelessWidget {
  const _Segments({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  final List<(T, String)> values;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (final (value, text) in values)
            Expanded(
              child: InkWell(
                onTap: () => onSelected(value),
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  color: value == selected ? colors.primary : null,
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: value == selected
                          ? Colors.white
                          : colors.dirtyWhite,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
