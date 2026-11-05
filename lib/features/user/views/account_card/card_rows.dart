part of '../account_card.dart';

/// A rounded group of the account card (`#2C2D32`, radius 8, padding 8), its
/// rows split by 1 px hairlines with 8 px around.
class _CardGroup extends StatelessWidget {
  const _CardGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: profileBubbleColor(colors),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(height: 1, color: colors.hairline),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A 32 px row of the account card: a 16 px glyph, a 14 / 500 label and an
/// optional "›". Rows with [opensOnHover] open their submenu as soon as the
/// pointer rests on them, as the reference client's do.
class _CardRow extends StatefulWidget {
  const _CardRow({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
    this.chevron = false,
    this.opensOnHover = false,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final bool chevron;
  final bool opensOnHover;

  /// Receives the row's global rect, to place a submenu beside it.
  final FutureOr<void> Function(Rect rowRect) onTap;

  @override
  State<_CardRow> createState() => _CardRowState();
}

class _CardRowState extends State<_CardRow> {
  bool _hover = false;
  bool _open = false;

  Rect _rect() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _activate() async {
    if (_open) return;
    _open = true;
    try {
      // A submenu opener keeps its row lit while the submenu is up.
      await widget.onTap(_rect());
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hover = true);
        if (widget.opensOnHover) _activate();
      },
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _activate,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hover ? colors.interactive.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: Center(
                  child:
                      widget.leading ??
                      Icon(widget.icon, size: 16, color: colors.interactive),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 16 / 14,
                    color: colors.interactive,
                  ),
                ),
              ),
              if (widget.chevron)
                Icon(AppIcons.chevronRight, size: 16, color: colors.interactive),
            ],
          ),
        ),
      ),
    );
  }
}
