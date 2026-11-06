part of '../soundboard_picker.dart';

/// A sound card of the reference client's soundboard, 148×40: the sound's
/// emoji and name on a translucent fill. Hovering fades them behind three
/// actions — preview (heard by us only) on the left, play in the middle, the
/// favourite star on the right — and the name shows below in a tooltip. A
/// card of another space shows a lock instead; a card that is playing wears
/// a green outline.
class _SoundCard extends StatefulWidget {
  const _SoundCard({
    super.key,
    required this.sound,
    required this.serverKey,
    required this.locked,
    this.lockOnHover = false,
    required this.playing,
    required this.favorite,
    required this.onPlay,
    this.onPreview,
    this.onFavorite,
  });

  final AccordSound sound;
  final String serverKey;
  final bool locked;

  /// A locked card that looks like any other until hovered (the other
  /// spaces' sections); otherwise a locked card is always faded with a lock
  /// (another space's sound in Favorites / Frequently Used).
  final bool lockOnHover;
  final bool playing;
  final bool favorite;
  final VoidCallback onPlay;
  final VoidCallback? onPreview;
  final VoidCallback? onFavorite;

  @override
  State<_SoundCard> createState() => _SoundCardState();
}

class _SoundCardState extends State<_SoundCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final showLock = widget.locked && (!widget.lockOnHover || _hover);
    final faded = showLock || _hover;
    final content = AnimatedOpacity(
      opacity: faded ? 0.2 : 1,
      duration: const Duration(milliseconds: 100),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SoundEmoji(
              sound: widget.sound,
              serverKey: widget.serverKey,
              size: 20,
              fallbackColor: colors.interactive,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.sound.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 16 / 12,
                  color: colors.dirtyWhite,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Widget action(
      IconData icon,
      String tooltip,
      VoidCallback? onTap, {
      double size = 16,
      Color? color,
      Key? key,
    }) => Tooltip(
      message: tooltip,
      child: InkResponse(
        key: key,
        onTap: onTap,
        radius: 14,
        child: SizedBox.square(
          dimension: 24,
          child: Icon(icon, size: size, color: color ?? colors.dirtyWhite),
        ),
      ),
    );
    final id = widget.sound.id ?? '';
    return Tooltip(
      message: widget.locked
          ? '${widget.sound.name} — plays only in its own space'
          : widget.sound.name,
      preferBelow: true,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: widget.locked
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.locked ? null : widget.onPlay,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: _kCardWidth,
            height: _kCardHeight,
            decoration: BoxDecoration(
              color: _hover && !widget.locked ? _kCardHoverFill : _kCardFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.playing ? colors.green : Colors.transparent,
                width: 2,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                content,
                if (showLock)
                  Center(
                    child: Icon(
                      AppIcons.lock,
                      size: 16,
                      color: colors.dirtyWhite,
                    ),
                  )
                else if (_hover && !widget.locked)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        action(
                          AppIcons.volumeUp,
                          'Preview',
                          widget.onPreview,
                          key: Key('soundboard-preview-$id'),
                        ),
                        Expanded(
                          child: Center(
                            child: Icon(
                              AppIcons.playArrow,
                              size: 20,
                              color: colors.dirtyWhite,
                            ),
                          ),
                        ),
                        action(
                          widget.favorite ? AppIcons.star : AppIcons.starBorder,
                          widget.favorite
                              ? 'Remove from Favorites'
                              : 'Add to Favorites',
                          widget.onFavorite,
                          color: widget.favorite ? colors.yellow : null,
                          key: Key('soundboard-favorite-$id'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The dashed "+ Add Sound" card closing this space's section.
class _AddSoundCard extends StatefulWidget {
  const _AddSoundCard({required this.onTap});

  final VoidCallback? onTap;

  @override
  State<_AddSoundCard> createState() => _AddSoundCardState();
}

class _AddSoundCardState extends State<_AddSoundCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final ink = _hover ? colors.dirtyWhite : const Color(0xFF96979E);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const Key('soundboard-add-sound'),
        onTap: widget.onTap,
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: const Color(0xFF96979E).withValues(alpha: 0.24),
            radius: 8,
          ),
          child: SizedBox(
            width: _kCardWidth,
            height: _kCardHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(AppIcons.add, size: 12, color: ink),
                const SizedBox(width: 4),
                Text(
                  'Add Sound',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 16 / 12,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 1 px dashed rounded rectangle along the widget's edge.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.5),
      );
    const dash = 3.0;
    const gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            math.min(distance + dash, metric.length),
          ),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
