import 'dart:async';
import 'dart:math' as math;

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/soundboard/controllers/soundboard_activity.dart';
import 'package:bonfire/features/soundboard/controllers/soundboard_sounds.dart';
import 'package:bonfire/features/soundboard/views/sound_emoji.dart';
import 'package:bonfire/features/soundboard/views/soundboard_settings_page.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/utils/space_display.dart';
import 'package:bonfire/features/voice/services/soundboard_player.dart';
import 'package:bonfire/shared/components/accord_slider.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/platform.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'soundboard_picker/sound_card.dart';
part 'soundboard_picker/sections.dart';
part 'soundboard_picker/volume.dart';
part 'soundboard_picker/trigger.dart';

/// Where the soundboard opens from its button, as on the reference client:
/// to the right of the voice panel's button with their bottoms aligned, or
/// centred 16 px above the call view's control bar.
enum SoundboardPlacement { right, above }

/// The picker's size at 1920×927 on the reference client.
const Size kSoundboardPickerSize = Size(531, 520);

/// Card size and gaps of the reference client's soundboard grid.
const double _kCardWidth = 148;
const double _kCardHeight = 40;
const double _kCardGap = 8;

/// The card fill — the reference client's white-grey at 12 % over its
/// `#1A1A1E` card base — and its hover shade (sampled from the captures).
const Color _kCardFill = Color(0xFF29282D);
const Color _kCardHoverFill = Color(0xFF2D2C31);

/// How long a played card stays out of reach, like the reference client's
/// per-sound cooldown.
const Duration _kCooldown = Duration(milliseconds: 1500);

/// Whether a soundboard picker is open (the call view keeps its control bar
/// visible meanwhile).
final ValueNotifier<bool> soundboardPickerOpen = ValueNotifier(false);

/// Opens the soundboard for the voice channel we sit in, in [spaceId] of
/// [serverKey]: a popover beside [anchor] on desktop layouts, a bottom sheet
/// on touch ones. Clicking a card plays it to the channel; hovering one offers
/// a private preview and a favourite star. "Add Sound" opens the space's
/// Soundboard settings with the upload dialog.
Future<void> showSoundboardPicker(
  BuildContext context, {
  required String serverKey,
  required String spaceId,
  required Rect anchor,
  required SoundboardPlacement placement,
}) async {
  soundboardPickerOpen.value = true;
  try {
    await _showPicker(
      context,
      serverKey: serverKey,
      spaceId: spaceId,
      anchor: anchor,
      placement: placement,
    );
  } finally {
    soundboardPickerOpen.value = false;
  }
}

Future<void> _showPicker(
  BuildContext context, {
  required String serverKey,
  required String spaceId,
  required Rect anchor,
  required SoundboardPlacement placement,
}) {
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  void addSound() {
    final host = rootNavigator.context;
    if (!host.mounted) return;
    showSpaceSoundboardSettings(
      host,
      serverKey: serverKey,
      spaceId: spaceId,
      openUpload: true,
    );
  }

  if (!shouldUseDesktopLayout(context)) {
    final colors = BonfireThemeExtension.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.raised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: SoundboardPickerPanel(
          serverKey: serverKey,
          spaceId: spaceId,
          compact: true,
          onAddSound: () {
            Navigator.of(ctx).pop();
            addSound();
          },
        ),
      ),
    );
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close soundboard',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 100),
    pageBuilder: (ctx, _, _) => CustomSingleChildLayout(
      delegate: SoundboardPopoverLayout(
        anchor: anchor,
        placement: placement,
        size: kSoundboardPickerSize,
      ),
      child: SoundboardPickerPanel(
        serverKey: serverKey,
        spaceId: spaceId,
        onAddSound: () {
          Navigator.of(ctx).pop();
          addSound();
        },
      ),
    ),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// Places a soundboard popover of [size] beside [anchor] (see
/// [SoundboardPlacement]), kept 8 px inside the window.
class SoundboardPopoverLayout extends SingleChildLayoutDelegate {
  const SoundboardPopoverLayout({
    required this.anchor,
    required this.placement,
    required this.size,
  });

  final Rect anchor;
  final SoundboardPlacement placement;
  final Size size;

  /// Gap to the button: 7 px beside the voice panel's; above the call bar,
  /// 16 px over the reference client's 40 px button, i.e. 12 px over our
  /// 48 px one.
  static const double sideGap = 7;
  static const double aboveGap = 12;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.tight(
      Size(
        math.min(size.width, constraints.maxWidth - 16),
        math.min(size.height, constraints.maxHeight - 16),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double left;
    final double top;
    switch (placement) {
      case SoundboardPlacement.right:
        left = anchor.right + sideGap;
        top = anchor.bottom - childSize.height;
      case SoundboardPlacement.above:
        left = anchor.center.dx - childSize.width / 2;
        top = anchor.top - aboveGap - childSize.height;
    }
    return Offset(
      left.clamp(8.0, math.max(8.0, size.width - childSize.width - 8)),
      top.clamp(8.0, math.max(8.0, size.height - childSize.height - 8)),
    );
  }

  @override
  bool shouldRelayout(SoundboardPopoverLayout old) =>
      old.anchor != anchor || old.placement != placement || old.size != size;
}

/// The soundboard picker: a search field and the volume control on top, the
/// section rail on the left, and the sections (Favorites, Frequently Used,
/// this space with "Add Sound", then the other spaces' sounds, which only
/// play in their own space).
class SoundboardPickerPanel extends ConsumerStatefulWidget {
  const SoundboardPickerPanel({
    super.key,
    required this.serverKey,
    required this.spaceId,
    this.compact = false,
    this.onAddSound,
  });

  final String serverKey;

  /// The space of the voice channel we play into.
  final String spaceId;

  /// Touch layout (bottom sheet): no rail, no popover chrome.
  final bool compact;
  final VoidCallback? onAddSound;

  @override
  ConsumerState<SoundboardPickerPanel> createState() =>
      _SoundboardPickerPanelState();
}

class _SoundboardPickerPanelState extends ConsumerState<SoundboardPickerPanel> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  final Set<String> _collapsed = {};
  final Map<String, GlobalKey> _sectionKeys = {};
  final Set<String> _cooling = {};
  String _query = '';
  String? _railSelected;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_trackSection);
    if (!widget.compact) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String section) =>
      _sectionKeys.putIfAbsent(section, GlobalKey.new);

  /// Highlights in the rail the section whose header was scrolled past last.
  void _trackSection() {
    String? current;
    final viewport = context.findRenderObject();
    if (viewport is! RenderBox) return;
    final top = viewport.localToGlobal(Offset.zero).dy + 64;
    for (final entry in _sectionKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy <= top + 4) current = entry.key;
    }
    if (current != null && current != _railSelected) {
      setState(() => _railSelected = current);
    }
  }

  void _jumpTo(String section) {
    setState(() => _railSelected = section);
    final ctx = _sectionKeys[section]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 150),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
  }

  Future<void> _play(AccordSound sound) async {
    final id = sound.id;
    final client = ref.accordClient;
    if (id == null || client == null || _cooling.contains(id)) return;
    if (sound.spaceId != null && sound.spaceId != widget.spaceId) return;
    setState(() {
      _cooling.add(id);
      _error = null;
    });
    unawaited(
      Future<void>.delayed(_kCooldown, () {
        if (mounted) setState(() => _cooling.remove(id));
      }),
    );
    final error = await _sendPlay(
      ref,
      serverKey: widget.serverKey,
      spaceId: widget.spaceId,
      sound: sound,
    );
    if (!mounted || error == null) return;
    setState(() => _error = error);
  }

  void _preview(AccordSound sound) {
    final client = ref.accordClient;
    if (client == null) return;
    soundboardPlayer.play(
      AccordCDN.resolvePath(sound.audioUrl, cdnUrl: client.config.cdnUrl),
      gain: sound.volume,
    );
  }

  void _toggleFavorite(AccordSound sound) {
    final id = sound.id;
    if (id == null) return;
    ref
        .read(settingsControllerProvider.notifier)
        .toggleFavoriteSound(soundSettingsKey(widget.serverKey, id));
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final data = _watchSoundboardSections(
      ref,
      serverKey: widget.serverKey,
      spaceId: widget.spaceId,
      query: _query,
    );
    final me = ref.watchUserId();
    final playingId = me == null
        ? null
        : ref.watch(
            soundboardActivityControllerProvider.select((a) => a[me]?.sound.id),
          );
    final favorites = ref.watch(
      settingsControllerProvider.select((s) => s.favoriteSounds),
    );
    final cdnUrl = ref.watchCdnUrl();
    final selected = _railSelected ?? data.sections.firstOrNull?.key;

    Widget card(AccordSound sound, {bool lockOnHover = false}) {
      final id = sound.id ?? '';
      final locked = sound.spaceId != null && sound.spaceId != widget.spaceId;
      return _SoundCard(
        key: Key('soundboard-card-$id'),
        sound: sound,
        serverKey: widget.serverKey,
        locked: locked,
        lockOnHover: lockOnHover,
        playing: id == playingId || _cooling.contains(id),
        favorite: favorites.contains(soundSettingsKey(widget.serverKey, id)),
        onPlay: () => _play(sound),
        onPreview: () => _preview(sound),
        onFavorite: () => _toggleFavorite(sound),
      );
    }

    final grid = data.sections.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                data.loading
                    ? ''
                    : _query.isEmpty
                    ? 'No sounds yet'
                    : 'No sounds match your search',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: colors.interactive),
              ),
            ),
          )
        : Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.only(top: 0, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final section in data.sections) ...[
                    if (section.lockedDivider) const _LockDivider(),
                    _SectionHeader(
                      key: _keyFor(section.key),
                      title: section.title,
                      icon: section.headerIcon(context, cdnUrl),
                      collapsed: _collapsed.contains(section.key),
                      onToggle: () => setState(() {
                        if (!_collapsed.remove(section.key)) {
                          _collapsed.add(section.key);
                        }
                      }),
                    ),
                    if (!_collapsed.contains(section.key))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 3),
                        child: Wrap(
                          spacing: _kCardGap,
                          runSpacing: _kCardGap,
                          children: [
                            for (final sound in section.sounds)
                              card(sound, lockOnHover: section.locked),
                            if (section.addCard && _query.isEmpty)
                              _AddSoundCard(onTap: widget.onAddSound),
                          ],
                        ),
                      ),
                    if (!_collapsed.contains(section.key))
                      const SizedBox(height: _kCardGap),
                  ],
                ],
              ),
            ),
          );

    final header = Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: _SearchField(
              controller: _search,
              focusNode: _searchFocus,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(width: 12),
          const _VolumeButton(),
        ],
      ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              _error!,
              style: TextStyle(fontSize: 12, color: colors.red),
            ),
          ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.compact)
                _SectionRail(
                  sections: data.sections,
                  selected: selected,
                  cdnUrl: cdnUrl,
                  onSelect: _jumpTo,
                ),
              Expanded(child: grid),
            ],
          ),
        ),
      ],
    );

    if (widget.compact) return body;
    return Material(
      key: const Key('soundboard-picker'),
      color: colors.raised,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x3D000000),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: body,
      ),
    );
  }
}

/// The search box at the top of the picker: black at 12 %, 8 px corners, a
/// magnifier, and the accent outline while focused.
class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final focused = widget.focusNode.hasFocus;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: focused ? colors.primary : colors.hairline),
      ),
      padding: const EdgeInsets.only(left: 12, right: 12),
      child: Row(
        children: [
          Icon(AppIcons.search, size: 16, color: colors.interactive),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const Key('soundboard-search'),
              controller: widget.controller,
              focusNode: widget.focusNode,
              onChanged: widget.onChanged,
              cursorColor: colors.dirtyWhite,
              style: TextStyle(fontSize: 16, color: colors.dirtyWhite),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintText: 'Find the perfect sound',
                hintStyle: TextStyle(fontSize: 16, color: colors.gray),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
