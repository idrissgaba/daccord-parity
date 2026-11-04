part of 'message_pane.dart';

/// Floats [actions] over the top-right corner of [child], or renders [child]
/// untouched when there are none. The bar straddles the row's top edge (16 px
/// above it, 14 px in from the right), as the reference client's does; it is
/// only passed in while the row is hovered, so nothing overlaps the message
/// the rest of the time.
class _FloatingActionsOverlay extends StatelessWidget {
  const _FloatingActionsOverlay({required this.actions, required this.child});

  final Widget? actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final actions = this.actions;
    // Always a Stack, the message first: swapping between the bare child and
    // a Stack on hover would remount the message, losing a text selection
    // (and restarting any media in it).
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (actions != null) Positioned(top: -16, right: 14, child: actions),
      ],
    );
  }
}

/// Wraps [child] in a click-to-open gesture (with a pointer cursor) when
/// [enabled]; otherwise renders the child untouched. Used so message authors are
/// only tappable inside a space (where a profile popout makes sense).
class _MaybeTappable extends StatelessWidget {
  const _MaybeTappable({
    required this.enabled,
    required this.onTap,
    required this.child,
    this.onLongPressStart,
    this.onSecondaryTapUp,
  });

  final bool enabled;
  final VoidCallback onTap;
  final Widget child;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureTapUpCallback? onSecondaryTapUp;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        onLongPressStart: onLongPressStart,
        onSecondaryTapUp: onSecondaryTapUp,
        child: child,
      ),
    );
  }
}

/// The hover-only timestamp shown in the avatar gutter of a grouped row (which
/// has no author header of its own): bare HH:MM, 11 px, centred under where
/// the avatar would be, with the full date in a tooltip.
class _GutterTimestamp extends StatelessWidget {
  const _GutterTimestamp({
    required this.width,
    required this.visible,
    required this.clock,
    required this.fullTime,
  });

  final double width;
  final bool visible;
  final String clock;
  final String fullTime;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return SizedBox(
      width: width,
      height: 22,
      child: Opacity(
        opacity: visible ? 1 : 0,
        child: Center(
          child: Tooltip(
            message: fullTime,
            child: Text(
              clock,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1,
                color: colors.interactive,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The emoji the hover bar and the context menu offer in one click: the
/// user's most recent picks, padded with a fixed set until they have any.
List<EmojiPick> quickReactionPicks(List<String> recents, {int count = 3}) {
  const fallback = ['👍', '❤️', '😂', '😮'];
  final picks = <EmojiPick>[];
  for (final token in recents) {
    // Custom emoji (`name:id`) belong to one space; the quick slots stay
    // unicode so they work in every channel.
    if (token.contains(':')) continue;
    picks.add(EmojiPick(name: token, char: token));
    if (picks.length == count) return picks;
  }
  for (final char in fallback) {
    if (picks.length == count) break;
    if (picks.any((p) => p.char == char)) continue;
    picks.add(EmojiPick(name: char, char: char));
  }
  return picks;
}

/// The desktop hover bar floated over a message: three quick-reaction emoji,
/// Add Reaction, then Edit + Forward on your own message or Reply on someone
/// else's, and "…" for the full menu. Buttons are 28 px on a 34 px raised
/// strip; the icons are 24 px.
class _HoverActionBar extends StatelessWidget {
  const _HoverActionBar({
    required this.quickPicks,
    required this.onQuickReact,
    required this.onReact,
    required this.onReply,
    required this.onForward,
    required this.onEdit,
    required this.onMore,
    required this.isOwn,
  });

  final List<EmojiPick> quickPicks;
  final ValueChanged<EmojiPick> onQuickReact;
  final VoidCallback onReact;
  final VoidCallback onReply;
  final VoidCallback onForward;
  final VoidCallback onEdit;

  /// Opens the message menu; receives the "…" button's global position so the
  /// menu anchors under it.
  final ValueChanged<Offset> onMore;
  final bool isOwn;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Material(
      key: const Key('message-hover-bar'),
      color: popoverSurfaceColor(colors),
      borderRadius: BorderRadius.circular(8),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final pick in quickPicks)
              _HoverBarButton(
                tooltip: 'React with ${pick.name}',
                onPressed: () => onQuickReact(pick),
                child: Text(pick.char, style: const TextStyle(fontSize: 20)),
              ),
            if (quickPicks.isNotEmpty) const SizedBox(width: 8),
            _HoverBarButton(
              tooltip: 'Add Reaction',
              onPressed: onReact,
              child: Icon(
                AppIcons.addReactionOutlined,
                size: 24,
                color: colors.interactive,
              ),
            ),
            if (isOwn) ...[
              _HoverBarButton(
                tooltip: 'Edit',
                onPressed: onEdit,
                child: Icon(AppIcons.edit, size: 24, color: colors.interactive),
              ),
              _HoverBarButton(
                tooltip: 'Forward',
                onPressed: onForward,
                child: Icon(
                  AppIcons.forward,
                  size: 24,
                  color: colors.interactive,
                ),
              ),
            ] else
              _HoverBarButton(
                tooltip: 'Reply',
                onPressed: onReply,
                child: Icon(
                  AppIcons.reply,
                  size: 24,
                  color: colors.interactive,
                ),
              ),
            Builder(
              builder: (context) => _HoverBarButton(
                tooltip: 'More',
                onPressed: () {
                  final box = context.findRenderObject() as RenderBox?;
                  final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
                  onMore(origin + Offset(0, box?.size.height ?? 28));
                },
                child: Icon(
                  AppIcons.moreHoriz,
                  size: 24,
                  color: colors.interactive,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One 28×28 slot of the hover bar, lit on hover.
class _HoverBarButton extends StatelessWidget {
  const _HoverBarButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        hoverColor: colors.hover,
        child: SizedBox(width: 28, height: 28, child: Center(child: child)),
      ),
    );
  }
}

/// The raised surface of the hover bar, tooltips and dialogs: the pane
/// background lifted by a touch of the text colour (`#242429` on the Dark
/// preset's `#1A1A1E`).
Color popoverSurfaceColor(BonfireThemeExtension colors) => Color.alphaBlend(
  colors.dirtyWhite.withValues(alpha: 0.045),
  colors.background,
);

/// The composer box (and the inline editor): the pane background lifted a
/// touch less than a popover (`#222327` on the Dark preset).
Color composerSurfaceColor(BonfireThemeExtension colors) => Color.alphaBlend(
  colors.dirtyWhite.withValues(alpha: 0.035),
  colors.background,
);
