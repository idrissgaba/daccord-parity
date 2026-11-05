import 'dart:math' as math;

import 'package:bonfire/shared/utils/platform.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'context_menu/anchored_menu.dart';
part 'context_menu/menu_rows.dart';
part 'context_menu/menu_sheet.dart';

/// Enter duration of the mobile bottom sheet (Material: 250ms).
const _kSheetEnterDuration = Duration(milliseconds: 167);

/// Exit duration of the mobile bottom sheet (Material: 200ms).
const _kSheetExitDuration = Duration(milliseconds: 133);

/// One row in an Accord context menu — the single menu every context menu,
/// "…" button and dropdown of the app is built from. A null [onSelected] (or
/// [enabled] false) renders the entry disabled: shown at half opacity, as the
/// reference client keeps "Mark as Read" in place when nothing is unread. Use
/// [AccordMenuEntry.divider] for a separator and [submenu] for a "›" row that
/// opens a further menu on hover.
class AccordMenuEntry {
  const AccordMenuEntry({
    required this.label,
    this.key,
    this.icon,
    this.subtitle,
    this.sheetSubtitle,
    this.onSelected,
    this.destructive = false,
    this.enabled = true,
    this.checked,
    this.radio,
    this.trailingChevron = false,
    this.submenu,
    this.trailing,
    this.leading,
  }) : isDivider = false,
       child = null,
       height = 0;

  const AccordMenuEntry.divider()
    : label = '',
      key = null,
      icon = null,
      subtitle = null,
      sheetSubtitle = null,
      onSelected = null,
      destructive = false,
      enabled = false,
      checked = null,
      radio = null,
      trailingChevron = false,
      submenu = null,
      trailing = null,
      leading = null,
      isDivider = true,
      child = null,
      height = 1;

  /// A row holding an arbitrary live widget (a slider, say) of [height]
  /// pixels in the anchored menu. It is never "selected": the widget handles
  /// its own interaction and the menu stays open.
  const AccordMenuEntry.widget({
    required Widget this.child,
    this.height = 56,
    this.key,
  }) : label = '',
       icon = null,
       subtitle = null,
       sheetSubtitle = null,
       onSelected = null,
       destructive = false,
       enabled = true,
       checked = null,
       radio = null,
       trailingChevron = false,
       submenu = null,
       trailing = null,
       leading = null,
       isDivider = false;

  final String label;

  /// Identifies the row in the tree (tests).
  final Key? key;

  /// A 20 px glyph at the row's left edge.
  final IconData? icon;

  /// A second, smaller line under [label] ("All Messages", "Only visible to
  /// you"), in the anchored menu and the sheet alike.
  final String? subtitle;

  /// A description shown under [label] in the bottom-sheet form only.
  final String? sheetSubtitle;

  /// Run after the menu closes. Null = disabled (unless [submenu] is set).
  final VoidCallback? onSelected;

  /// Tints the entry with the theme's danger color.
  final bool destructive;
  final bool enabled;
  final bool isDivider;

  /// A checkbox at the row's right edge. Selecting the row calls
  /// [onSelected].
  final bool? checked;

  /// A radio button at the row's right edge, filled when true.
  final bool? radio;

  /// A "›" at the row's right edge: the entry opens something further (a
  /// picker, a dialog) rather than acting at once. Rows with a [submenu]
  /// always show it.
  final bool trailingChevron;

  /// Entries of a further menu, opened beside this row on hover, → or a
  /// click. A row with both a submenu and [onSelected] runs [onSelected]
  /// when clicked (Mute Server mutes until turned back on) and opens the
  /// submenu on hover.
  final List<AccordMenuEntry>? submenu;

  /// A small widget at the row's right edge before any chevron (a badge).
  final Widget? trailing;

  /// A small widget in the 20 px slot at the left, in place of [icon] (a
  /// status dot, an account's avatar).
  final Widget? leading;

  /// See [AccordMenuEntry.widget].
  final Widget? child;
  final double height;

  bool get isWidget => child != null;

  bool get hasSubmenu => submenu != null && submenu!.isNotEmpty;

  bool get _activatable =>
      !isDivider && !isWidget && enabled && onSelected != null;

  bool get _interactive =>
      isDivider || isWidget ? false : enabled && (onSelected != null || hasSubmenu);

  bool get _showsChevron => trailingChevron || hasSubmenu;

  bool get _hasGlyph =>
      icon != null ||
      leading != null ||
      checked != null ||
      radio != null ||
      _showsChevron ||
      trailing != null;

  /// The row's height in the anchored menu: 34 for a bare label, 36 with a
  /// 20 px glyph, 52 with a subtitle, 17 for a separator (1 px + 8 above and
  /// below) — the reference client's measurements.
  double get _rowHeight {
    if (isDivider) return 17;
    if (isWidget) return height;
    if (subtitle != null) return 52;
    return _hasGlyph ? 36 : 34;
  }
}

/// Shows a context menu for [entries]. On desktop layouts it opens an anchored
/// menu at [globalPosition] (submenus cascade beside their row); on
/// mobile/touch (or when no position is given) it opens a bottom sheet titled
/// [title]. [anchorX] places the menu's left edge (0), centre (0.5) or right
/// edge (1) at the position: a header button's menu sits right-aligned under
/// it, the space name's menu centred under the column header. The chosen entry's [AccordMenuEntry.onSelected] runs after the
/// menu closes — callbacks must not dismiss the menu themselves.
Future<void> showAccordContextMenu(
  BuildContext context, {
  required List<AccordMenuEntry> entries,
  Offset? globalPosition,
  String? title,
  IconData? titleIcon,
  bool preferAbove = false,
  bool anchorLeft = false,
  double anchorX = 0,
  double? width,
}) {
  if (shouldUseDesktopLayout(context) && globalPosition != null) {
    return _showAnchored(
      context,
      entries,
      globalPosition,
      preferAbove: preferAbove,
      anchorLeft: anchorLeft,
      anchorX: anchorX,
      width: width,
    );
  }
  return _showSheet(context, entries, title, titleIcon);
}

/// A button (a "…", a chevron) that opens [entries] as an Accord menu where
/// it was tapped — the replacement for Material's `PopupMenuButton`.
class AccordMenuButton extends StatelessWidget {
  const AccordMenuButton({
    super.key,
    required this.entries,
    required this.child,
    this.tooltip,
    this.title,
    this.preferAbove = false,
  });

  /// Built when the button is pressed, so the menu reflects current state.
  final List<AccordMenuEntry> Function() entries;
  final Widget child;
  final String? tooltip;
  final String? title;
  final bool preferAbove;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTapUp: (details) => showAccordContextMenu(
        context,
        entries: entries(),
        globalPosition: details.globalPosition,
        title: title,
        preferAbove: preferAbove,
      ),
      onTap: () {},
      child: child,
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// The surface of an anchored menu: `#28282D` on the Dark preset, the pane
/// background lifted by a touch of the text colour.
Color menuSurfaceColor(BonfireThemeExtension colors) => Color.alphaBlend(
  colors.dirtyWhite.withValues(alpha: 0.063),
  colors.background,
);

/// Width of an anchored menu that hosts a live widget row (a slider, the
/// quick-reaction row). Text-only menus size to their widest row.
const double kAccordMenuWidth = 222;

/// The narrowest anchored menu, and the narrowest submenu.
const double kAccordMenuMinWidth = 144;
const double kAccordSubmenuMinWidth = 188;

/// The widest an anchored menu grows for a row that needs the room.
const double kAccordMenuMaxWidth = 320;

/// Leading and trailing dividers, and runs of them, collapse: entries are
/// often built with optional groups.
List<AccordMenuEntry> _collapseDividers(List<AccordMenuEntry> entries) {
  final visible = <AccordMenuEntry>[];
  for (final entry in entries) {
    if (entry.isDivider && (visible.isEmpty || visible.last.isDivider)) {
      continue;
    }
    visible.add(entry);
  }
  while (visible.isNotEmpty && visible.last.isDivider) {
    visible.removeLast();
  }
  return visible;
}
