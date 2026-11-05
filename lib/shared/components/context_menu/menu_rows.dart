part of '../context_menu.dart';

/// The menu's danger red (`#F87E7A`) and its hover wash (`#CC2633` at 8 %).
const _kDangerText = Color(0xFFF87E7A);
const _kDangerHover = Color(0x14CC2633);

/// Label: 14 / 500, line 18.
TextStyle _labelStyle(Color color) => TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w500,
  height: 18 / 14,
  color: color,
);

/// Subtitle: 12 / 400, line 16.
TextStyle _subtitleStyle(Color color) =>
    TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 16 / 12, color: color);

/// The subtitle grey (`#96979E` on Dark), halfway between muted text and
/// secondary icons.
Color _subtitleColor(BonfireThemeExtension colors) =>
    Color.lerp(colors.gray, colors.interactive, 0.5)!;

/// The width a panel needs for [entries]: its widest row plus the panel's
/// 8 px padding and 1 px border on each side, clamped to [minWidth]..320.
double _panelWidth(
  BuildContext context,
  List<AccordMenuEntry> entries, {
  required double minWidth,
}) {
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  // The app's own font (Noto Sans), or labels measure narrower than they
  // paint.
  final base =
      Theme.of(context).textTheme.bodyMedium ??
      DefaultTextStyle.of(context).style;
  var widest = 0.0;
  var hasWidget = false;
  double measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: base.merge(style)),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }

  for (final e in entries) {
    if (e.isDivider) continue;
    if (e.isWidget) {
      hasWidget = true;
      continue;
    }
    var text = measure(e.label, _labelStyle(Colors.white));
    if (e.subtitle != null) {
      text = math.max(text, measure(e.subtitle!, _subtitleStyle(Colors.white)));
    }
    var row = 16 + text; // 8 px padding each side
    if (e.icon != null || e.leading != null) row += 28;
    if (e.checked != null || e.radio != null) row += 28;
    if (e._showsChevron) row += 28;
    if (e.trailing != null) row += 40;
    widest = math.max(widest, row);
  }
  final floor = hasWidget ? math.max(minWidth, kAccordMenuWidth) : minWidth;
  return (widest + 18).ceilToDouble().clamp(floor, kAccordMenuMaxWidth);
}

/// One selectable row of an anchored panel.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.entry,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final AccordMenuEntry entry;
  final bool highlighted;
  final ValueChanged<Rect> onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final interactive = entry._interactive;
    final labelColor = entry.destructive ? _kDangerText : colors.dirtyWhite;
    final glyphColor = entry.destructive ? _kDangerText : colors.interactive;
    final hoverColor = entry.destructive
        ? _kDangerHover
        : colors.interactive.withValues(alpha: 0.12);
    final row = Container(
      height: entry._rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: highlighted && interactive ? hoverColor : null,
        borderRadius: BorderRadius.circular(highlighted ? 4 : 2),
      ),
      child: Row(
        children: [
          if (entry.leading != null) ...[
            entry.leading!,
            const SizedBox(width: 8),
          ] else if (entry.icon != null) ...[
            Icon(entry.icon, size: 20, color: glyphColor),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _labelStyle(labelColor),
                ),
                if (entry.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _subtitleStyle(_subtitleColor(colors)),
                  ),
                ],
              ],
            ),
          ),
          if (entry.trailing != null) ...[
            const SizedBox(width: 8),
            entry.trailing!,
          ],
          if (entry.checked != null) ...[
            const SizedBox(width: 8),
            _MenuCheck(checked: entry.checked!, destructive: entry.destructive),
          ],
          if (entry.radio != null) ...[
            const SizedBox(width: 8),
            _MenuRadio(selected: entry.radio!),
          ],
          if (entry._showsChevron) ...[
            const SizedBox(width: 8),
            Icon(AppIcons.chevronRight, size: 20, color: glyphColor),
          ],
        ],
      ),
    );
    return Opacity(
      opacity: interactive ? 1 : 0.5,
      child: MouseRegion(
        cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) return;
          onHover(box.localToGlobal(Offset.zero) & box.size);
        },
        child: GestureDetector(
          key: entry.key,
          behavior: HitTestBehavior.opaque,
          onTap: interactive ? onTap : null,
          child: row,
        ),
      ),
    );
  }
}

/// The right-aligned checkbox of a toggling menu row: an 18 px rounded square
/// (in a 20 px slot), filled with the accent colour and a tick when on.
class _MenuCheck extends StatelessWidget {
  const _MenuCheck({required this.checked, this.destructive = false});

  final bool checked;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final on = destructive ? colors.red : colors.primary;
    return SizedBox(
      width: 20,
      height: 20,
      child: Center(
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: checked ? on : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: checked
                ? null
                : Border.all(color: colors.interactive, width: 1.5),
          ),
          child: checked
              ? const Icon(AppIcons.check, size: 14, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

/// The right-aligned radio of a choice row: a 20 px ring, filled with the
/// accent colour around an 8 px white dot when selected.
class _MenuRadio extends StatelessWidget {
  const _MenuRadio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.primary : Colors.transparent,
        border: selected
            ? null
            : Border.all(color: colors.interactive, width: 1.5),
      ),
      alignment: Alignment.center,
      child: selected
          ? Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}
