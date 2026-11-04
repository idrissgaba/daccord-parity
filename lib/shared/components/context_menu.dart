import 'package:bonfire/shared/utils/platform.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// Context menus open and close a third faster than Material's defaults, which
/// feel sluggish for a menu you flick open dozens of times a session. Each
/// constant is ~⅔ of the framework value it overrides.

/// Open *and* close duration of the anchored desktop menu (Material: 300ms).
const _kAnchoredMenuDuration = Duration(milliseconds: 200);

/// Enter duration of the mobile bottom sheet (Material: 250ms).
const _kSheetEnterDuration = Duration(milliseconds: 167);

/// Exit duration of the mobile bottom sheet (Material: 200ms).
const _kSheetExitDuration = Duration(milliseconds: 133);

/// One row in an Accord context menu. A null [onSelected] (or [enabled] false)
/// renders the entry disabled. Use [AccordMenuEntry.divider] for a separator.
class AccordMenuEntry {
  const AccordMenuEntry({
    required this.label,
    this.key,
    this.icon,
    this.subtitle,
    this.onSelected,
    this.destructive = false,
    this.enabled = true,
    this.checked,
  }) : isDivider = false,
       child = null,
       height = 40;

  const AccordMenuEntry.divider()
    : label = '',
      key = null,
      icon = null,
      subtitle = null,
      onSelected = null,
      destructive = false,
      enabled = false,
      checked = null,
      isDivider = true,
      child = null,
      height = 1;

  /// A row holding an arbitrary live widget (a slider, say) of [height]
  /// pixels in the anchored menu. It is never "selected": the widget handles
  /// its own interaction and the menu stays open.
  const AccordMenuEntry.widget({required Widget this.child, this.height = 56})
    : label = '',
      key = null,
      icon = null,
      subtitle = null,
      onSelected = null,
      destructive = false,
      enabled = true,
      checked = null,
      isDivider = false;

  final String label;

  /// Identifies the row in the tree (tests).
  final Key? key;
  final IconData? icon;

  /// Secondary line shown under [label] in the bottom-sheet form only (anchored
  /// menus stay compact).
  final String? subtitle;

  /// Run after the menu closes. Null = disabled.
  final VoidCallback? onSelected;

  /// Tints the entry with the theme's danger color.
  final bool destructive;
  final bool enabled;
  final bool isDivider;

  /// A checkbox at the row's right edge, as the menus of other chat apps draw
  /// their toggles (Mute, Deafen, …). Selecting the row calls [onSelected].
  final bool? checked;

  /// See [AccordMenuEntry.widget].
  final Widget? child;
  final double height;

  bool get isWidget => child != null;

  bool get _interactive =>
      isDivider || isWidget ? false : enabled && onSelected != null;
}

/// The right-aligned checkbox of a toggling menu row: a 20 px rounded square,
/// filled with the accent colour and a tick when on.
class _MenuCheck extends StatelessWidget {
  const _MenuCheck({required this.checked, this.destructive = false});

  final bool checked;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final on = destructive ? colors.red : colors.primary;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: checked ? on : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: checked ? null : Border.all(color: colors.gray, width: 1.5),
      ),
      child: checked
          ? const Icon(AppIcons.check, size: 16, color: Colors.white)
          : null,
    );
  }
}

/// Hosts a live widget inside an anchored menu, which otherwise only offers
/// selectable rows.
class _WidgetMenuEntry extends PopupMenuEntry<int> {
  const _WidgetMenuEntry({super.key, required this.height, required this.child});

  final Widget child;

  @override
  final double height;

  @override
  bool represents(int? value) => false;

  @override
  State<_WidgetMenuEntry> createState() => _WidgetMenuEntryState();
}

class _WidgetMenuEntryState extends State<_WidgetMenuEntry> {
  @override
  Widget build(BuildContext context) => widget.child;
}

/// Shows a context menu for [entries]. On desktop layouts it opens an anchored
/// [showMenu] next to [globalPosition]; on mobile/touch (or when no position is
/// given) it opens a bottom sheet titled [title]. The chosen entry's
/// [AccordMenuEntry.onSelected] runs after the menu closes — callbacks must not
/// dismiss the menu themselves.
Future<void> showAccordContextMenu(
  BuildContext context, {
  required List<AccordMenuEntry> entries,
  Offset? globalPosition,
  String? title,
  IconData? titleIcon,
  bool preferAbove = false,
}) {
  if (shouldUseDesktopLayout(context) && globalPosition != null) {
    return _showAnchored(context, entries, globalPosition, preferAbove);
  }
  return _showSheet(context, entries, title, titleIcon);
}

/// The height an anchored menu of [entries] takes (rows, dividers and the
/// menu's own padding), for placing it above its anchor.
double _anchoredHeight(List<AccordMenuEntry> entries) {
  var height = 16.0;
  for (final e in entries) {
    height += e.isDivider ? 16 : e.height;
  }
  return height;
}

Future<void> _showAnchored(
  BuildContext context,
  List<AccordMenuEntry> entries,
  Offset position,
  bool preferAbove,
) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;
  final colors = BonfireThemeExtension.of(context);
  // Opened from a button in a bottom bar, the menu stands above the button
  // (8 px clear of it) rather than spilling below.
  final anchor = preferAbove
      ? Rect.fromLTWH(
          (position.dx - 90).clamp(8.0, overlay.size.width - 8),
          (position.dy - 8 - _anchoredHeight(entries)).clamp(0.0, position.dy),
          0,
          0,
        )
      : position & const Size(40, 40);
  final items = <PopupMenuEntry<int>>[];
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    if (entry.isDivider) {
      items.add(const PopupMenuDivider());
      continue;
    }
    if (entry.isWidget) {
      items.add(
        _WidgetMenuEntry(key: entry.key, height: entry.height, child: entry.child!),
      );
      continue;
    }
    final color = entry.destructive ? colors.red : colors.dirtyWhite;
    items.add(
      PopupMenuItem<int>(
        key: entry.key,
        value: i,
        enabled: entry._interactive,
        height: 40,
        child: Row(
          children: [
            if (entry.icon != null) ...[
              Icon(entry.icon, size: 18, color: color),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                entry.label,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: entry.destructive
                      ? colors.red
                      : entry._interactive
                      ? colors.dirtyWhite
                      : colors.gray,
                ),
              ),
            ),
            if (entry.checked != null) ...[
              const SizedBox(width: 16),
              _MenuCheck(
                checked: entry.checked!,
                destructive: entry.destructive,
              ),
            ],
          ],
        ),
      ),
    );
  }
  final selected = await showMenu<int>(
    context: context,
    color: colors.foreground,
    position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
    items: items,
    popUpAnimationStyle: AnimationStyle(duration: _kAnchoredMenuDuration),
  );
  if (selected != null) entries[selected].onSelected?.call();
}

Future<void> _showSheet(
  BuildContext context,
  List<AccordMenuEntry> entries,
  String? title,
  IconData? titleIcon,
) {
  final colors = BonfireThemeExtension.of(context);
  return showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: AnimationStyle(
      duration: _kSheetEnterDuration,
      reverseDuration: _kSheetExitDuration,
    ),
    builder: (sheetCtx) {
      final theme = Theme.of(sheetCtx);
      return SafeArea(
        // Scrollable: the sheet is capped at a fraction of the viewport, so a
        // long menu would otherwise clip its last entries on short screens.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null) ...[
                ListTile(
                  dense: true,
                  leading: titleIcon == null
                      ? null
                      : Icon(titleIcon, color: colors.dirtyWhite),
                  title: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const Divider(height: 1),
              ],
              for (final entry in entries)
                if (entry.isDivider)
                  const Divider(height: 1)
                else if (entry.isWidget)
                  KeyedSubtree(key: entry.key, child: entry.child!)
                else
                  ListTile(
                    key: entry.key,
                    trailing: entry.checked == null
                        ? null
                        : _MenuCheck(
                            checked: entry.checked!,
                            destructive: entry.destructive,
                          ),
                    leading: entry.icon == null
                        ? null
                        : Icon(
                            entry.icon,
                            color: entry.destructive ? colors.red : null,
                          ),
                    title: Text(
                      entry.label,
                      style: entry.destructive
                          ? TextStyle(color: colors.red)
                          : null,
                    ),
                    subtitle: entry.subtitle == null
                        ? null
                        : Text(entry.subtitle!),
                    enabled: entry._interactive,
                    onTap: entry._interactive
                        ? () {
                            Navigator.of(sheetCtx).pop();
                            entry.onSelected!.call();
                          }
                        : null,
                  ),
            ],
          ),
        ),
      );
    },
  );
}
