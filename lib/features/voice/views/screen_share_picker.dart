import 'dart:async';

import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/shared/components/dialog_title_bar.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:universal_platform/universal_platform.dart';

/// Shows the desktop screen-share window: a first step picking an
/// application window or a screen (live thumbnails), then — unless
/// [changing] an already live stream — the stream quality step ending in
/// "Go Live". Returns the chosen source, or null if cancelled.
///
/// Not LiveKit's bundled `ScreenSelectDialog`: it calls `setState` from
/// flutter_webrtc's thumbnail stream without a `mounted` guard or cancelling on
/// dispose, so a late thumbnail throws "setState() called after dispose()".
Future<rtc.DesktopCapturerSource?> showScreenShareSourcePicker(
  BuildContext context, {
  bool changing = false,
}) {
  return showDialog<rtc.DesktopCapturerSource>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _ScreenShareSourceDialog(changing: changing),
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
  final sharing = ref.read(voiceControllerProvider).selfStream;

  if (sharing) {
    await notifier.toggleScreenShare();
    return;
  }

  if (UniversalPlatform.isDesktop) {
    final source = await showScreenShareSourcePicker(context);
    if (source == null) return; // cancelled
    await notifier.toggleScreenShare(sourceId: source.id);
  } else {
    await notifier.toggleScreenShare();
  }
}

class _ScreenShareSourceDialog extends StatefulWidget {
  const _ScreenShareSourceDialog({required this.changing});

  /// Only the source is being changed: no quality step, the choice applies
  /// at once.
  final bool changing;

  @override
  State<_ScreenShareSourceDialog> createState() =>
      _ScreenShareSourceDialogState();
}

class _ScreenShareSourceDialogState extends State<_ScreenShareSourceDialog>
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
      final sources = await rtc.desktopCapturer.getSources(
        types: [_sourceType],
      );
      if (!mounted) return;
      setState(() {
        _sources
          ..clear()
          ..addEntries(sources.map((s) => MapEntry(s.id, s)));
      });
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 600),
        child: _qualityStep ? _qualityPage(colors) : _sourcePage(colors),
      ),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
          child: DialogTitleBar(
            widget.changing ? 'Change Stream' : 'Screen Share',
            icon: Icons.screen_share_outlined,
          ),
        ),
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Applications'),
            Tab(text: 'Screens'),
          ],
        ),
        Flexible(
          child: sources.isEmpty
              ? Center(
                  child: Text(
                    'No sources available',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.gray,
                    ),
                  ),
                )
              : GridView.count(
                  padding: const EdgeInsets.all(16),
                  crossAxisCount: _sourceType == rtc.SourceType.Screen ? 2 : 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.4,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: _cancel, child: const Text('Cancel')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _qualityPage(BonfireThemeExtension colors) {
    final theme = Theme.of(context);
    final source = _selectedSource!;
    final thumbnail = source.thumbnail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 12, 0),
          child: DialogTitleBar(
            'Screen Share',
            icon: Icons.screen_share_outlined,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 160,
                  height: 90,
                  child: ColoredBox(
                    color: colors.background,
                    child: thumbnail != null && thumbnail.isNotEmpty
                        ? Image.memory(
                            thumbnail,
                            gaplessPlayback: true,
                            fit: BoxFit.contain,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.type == rtc.SourceType.Screen
                          ? 'Screen'
                          : 'Application',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.gray,
                      ),
                    ),
                    Text(
                      source.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.dirtyWhite,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton(
                      key: const Key('share-change-source'),
                      onPressed: _back,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(
            'STREAM QUALITY',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.gray,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: ShareQualityRow(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: _cancel, child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('share-go-live'),
                onPressed: _confirm,
                child: const Text('Go Live'),
              ),
            ],
          ),
        ),
      ],
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
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            width: 2,
            color: selected ? colors.primary : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: thumbnail != null && thumbnail.isNotEmpty
                  ? Image.memory(
                      thumbnail,
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                    )
                  : const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              source.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: selected ? colors.dirtyWhite : colors.gray,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stream quality picked right before going live, as in other voice chat
/// apps: resolution and frame rate (the same settings as Voice & Video).
class ShareQualityRow extends ConsumerWidget {
  const ShareQualityRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final colors = BonfireThemeExtension.of(context);
    final label = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: colors.gray);
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('RESOLUTION', style: label),
        SegmentedButton<int>(
          key: const Key('share-quality'),
          showSelectedIcon: false,
          segments: [
            for (
              var i = 0;
              i < AccordSettings.screenShareResolutionLabels.length;
              i++
            )
              ButtonSegment(
                value: i,
                label: Text(
                  AccordSettings.screenShareResolutionLabels[i]
                      .split(' ')
                      .first,
                ),
              ),
          ],
          selected: {settings.screenShareResolution},
          onSelectionChanged: (v) =>
              controller.setScreenShareResolution(v.first),
        ),
        Text('FRAME RATE', style: label),
        SegmentedButton<int>(
          key: const Key('share-fps'),
          showSelectedIcon: false,
          segments: [
            for (final fps in AccordSettings.screenShareFpsOptions)
              ButtonSegment(value: fps, label: Text('$fps')),
          ],
          selected: {settings.screenShareFps},
          onSelectionChanged: (v) => controller.setScreenShareFps(v.first),
        ),
      ],
    );
  }
}
