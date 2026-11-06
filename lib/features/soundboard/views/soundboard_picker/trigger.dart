part of '../soundboard_picker.dart';

/// Sends a play of [sound] to the voice channel we sit in (in [spaceId]) and
/// counts it for "Frequently Used". Returns an error message, or null.
Future<String?> _sendPlay(
  WidgetRef ref, {
  required String serverKey,
  required String spaceId,
  required AccordSound sound,
}) async {
  final id = sound.id;
  final client = ref.accordClient;
  if (id == null || client == null) return null;
  ref
      .read(settingsControllerProvider.notifier)
      .recordSoundPlayed(soundSettingsKey(serverKey, id));
  final result = await client.soundboard.play(spaceId, id);
  return result.ok ? null : result.errorOr('Failed to play sound');
}

/// Wraps a soundboard button (voice panel or call bar) with the reference
/// client's behaviour: resting the pointer on it shows a "Suggested Sounds"
/// card (six sounds and "See All"), clicking opens the full picker. [builder]
/// receives the click handler and whether the picker is open (the button
/// stays highlighted meanwhile).
class SoundboardTrigger extends ConsumerStatefulWidget {
  const SoundboardTrigger({
    super.key,
    required this.serverKey,
    required this.spaceId,
    required this.placement,
    required this.builder,
    this.label,
  });

  final String serverKey;
  final String spaceId;
  final SoundboardPlacement placement;
  final Widget Function(BuildContext context, VoidCallback onPressed, bool open)
  builder;

  /// The button's tooltip, drawn by the trigger above the button so that it
  /// sits over the suggestions card as on the reference client (the button
  /// then passes an empty tooltip).
  final String? label;

  @override
  ConsumerState<SoundboardTrigger> createState() => _SoundboardTriggerState();
}

class _SoundboardTriggerState extends ConsumerState<SoundboardTrigger> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  Timer? _showTimer;
  Timer? _hideTimer;
  bool _open = false;
  bool _hovered = false;
  bool _cardShown = false;

  /// How long the pointer rests on the button before the card shows.
  static const _showDelay = Duration(milliseconds: 500);
  static const _hideDelay = Duration(milliseconds: 150);

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  /// Shows or hides the overlay to match the label and the card.
  void _sync() {
    final want = _cardShown || (_hovered && widget.label != null && !_open);
    if (want && !_portal.isShowing) _portal.show();
    if (!want && _portal.isShowing) _portal.hide();
  }

  void _enterButton() {
    if (!shouldUseDesktopLayout(context)) return;
    setState(() {
      _hovered = true;
      _sync();
    });
    _enterCard();
  }

  void _leaveButton() {
    if (!mounted) return;
    setState(() {
      _hovered = false;
      _sync();
    });
    _leave();
  }

  void _enterCard() {
    _hideTimer?.cancel();
    if (_open || _cardShown) return;
    if (!shouldUseDesktopLayout(context)) return;
    _showTimer?.cancel();
    _showTimer = Timer(_showDelay, () {
      if (!mounted || _open) return;
      setState(() {
        _cardShown = true;
        _sync();
      });
    });
  }

  void _leave() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (!mounted || !_cardShown) return;
      setState(() {
        _cardShown = false;
        _sync();
      });
    });
  }

  void _hideNow() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _cardShown = false;
    _hovered = false;
    _sync();
  }

  Future<void> _openPicker() async {
    _hideNow();
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _open = true;
      _sync();
    });
    await showSoundboardPicker(
      context,
      serverKey: widget.serverKey,
      spaceId: widget.spaceId,
      anchor: rect,
      placement: widget.placement,
    );
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final right = widget.placement == SoundboardPlacement.right;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => Stack(
          children: [
            if (_cardShown)
              CompositedTransformFollower(
                link: _link,
                targetAnchor: right
                    ? Alignment.bottomRight
                    : Alignment.topCenter,
                followerAnchor: right
                    ? Alignment.bottomLeft
                    : Alignment.bottomCenter,
                offset: right
                    ? const Offset(SoundboardPopoverLayout.sideGap, 0)
                    : const Offset(0, -SoundboardPopoverLayout.aboveGap),
                child: Align(
                  alignment: right
                      ? Alignment.bottomLeft
                      : Alignment.bottomCenter,
                  child: MouseRegion(
                    onEnter: (_) => _hideTimer?.cancel(),
                    onExit: (_) => _leave(),
                    child: _SuggestedCard(
                      serverKey: widget.serverKey,
                      spaceId: widget.spaceId,
                      onSeeAll: _openPicker,
                    ),
                  ),
                ),
              ),
            // Drawn after the card, so it stays on top of it.
            if (_hovered && widget.label != null && !_open)
              CompositedTransformFollower(
                link: _link,
                targetAnchor: Alignment.topCenter,
                followerAnchor: Alignment.bottomCenter,
                offset: const Offset(0, -8),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: IgnorePointer(child: _LabelBubble(widget.label!)),
                ),
              ),
          ],
        ),
        child: MouseRegion(
          onEnter: (_) => _enterButton(),
          onExit: (_) => _leaveButton(),
          child: widget.builder(context, _openPicker, _open),
        ),
      ),
    );
  }
}

/// The reference client's tooltip bubble, its arrow pointing down.
class _LabelBubble extends StatelessWidget {
  const _LabelBubble(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = TooltipTheme.of(context);
    final decoration = theme.decoration is BoxDecoration
        ? theme.decoration! as BoxDecoration
        : const BoxDecoration(color: Color(0xFF111214));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const Key('soundboard-label'),
          padding: theme.padding,
          decoration: decoration,
          child: Text(label, style: theme.textStyle),
        ),
        CustomPaint(
          size: const Size(10, 5),
          painter: _ArrowPainter(decoration.color ?? const Color(0xFF111214)),
        ),
      ],
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}

/// The card shown while the pointer rests on a soundboard button: "Suggested
/// Sounds" with "See All", then up to six sounds of the space that play on a
/// click. (The reference client suggests its built-in sounds; the space's most
/// played ones stand in for them.)
class _SuggestedCard extends ConsumerStatefulWidget {
  const _SuggestedCard({
    required this.serverKey,
    required this.spaceId,
    required this.onSeeAll,
  });

  final String serverKey;
  final String spaceId;
  final VoidCallback onSeeAll;

  @override
  ConsumerState<_SuggestedCard> createState() => _SuggestedCardState();
}

class _SuggestedCardState extends ConsumerState<_SuggestedCard> {
  final Set<String> _cooling = {};

  Future<void> _play(AccordSound sound) async {
    final id = sound.id;
    if (id == null || _cooling.contains(id)) return;
    setState(() => _cooling.add(id));
    unawaited(
      Future<void>.delayed(_kCooldown, () {
        if (mounted) setState(() => _cooling.remove(id));
      }),
    );
    await _sendPlay(
      ref,
      serverKey: widget.serverKey,
      spaceId: widget.spaceId,
      sound: sound,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final sounds = watchSuggestedSounds(
      ref,
      serverKey: widget.serverKey,
      spaceId: widget.spaceId,
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
    return Material(
      key: const Key('soundboard-suggested'),
      color: const Color(0xFF252429),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 494,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.hairline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 18,
              child: Row(
                children: [
                  Icon(
                    AppIcons.celebration,
                    size: 16,
                    color: const Color(0xFFD4D5D8),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Suggested Sounds',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 18 / 14,
                        color: Color(0xFFD4D5D8),
                      ),
                    ),
                  ),
                  InkWell(
                    key: const Key('soundboard-see-all'),
                    onTap: widget.onSeeAll,
                    child: const Text(
                      'See All',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 18 / 14,
                        color: Color(0xFF6374F4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (sounds.isEmpty)
              SizedBox(
                height: _kCardHeight,
                child: Center(
                  child: Text(
                    'No sounds yet',
                    style: TextStyle(fontSize: 12, color: colors.interactive),
                  ),
                ),
              )
            else
              Wrap(
                spacing: _kCardGap,
                runSpacing: _kCardGap,
                children: [
                  for (final sound in sounds)
                    _SoundCard(
                      key: Key('soundboard-suggested-${sound.id}'),
                      sound: sound,
                      serverKey: widget.serverKey,
                      locked: false,
                      playing:
                          sound.id == playingId || _cooling.contains(sound.id),
                      favorite: favorites.contains(
                        soundSettingsKey(widget.serverKey, sound.id ?? ''),
                      ),
                      onPlay: () => _play(sound),
                      onPreview: () {
                        final client = ref.accordClient;
                        if (client == null) return;
                        soundboardPlayer.play(
                          AccordCDN.resolvePath(
                            sound.audioUrl,
                            cdnUrl: client.config.cdnUrl,
                          ),
                          gain: sound.volume,
                        );
                      },
                      onFavorite: () => ref
                          .read(settingsControllerProvider.notifier)
                          .toggleFavoriteSound(
                            soundSettingsKey(widget.serverKey, sound.id ?? ''),
                          ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
