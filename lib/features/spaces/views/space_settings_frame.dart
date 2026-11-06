import 'dart:math' as math;

import 'package:bonfire/shared/components/escape_to_close.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// One page entry of the server-settings sidebar.
class SpaceSettingsItem {
  const SpaceSettingsItem({
    required this.key,
    required this.label,
    this.danger = false,
    this.trailingIcon,
  });

  final String key;
  final String label;

  /// Red, like "Delete Server" / "Delete Channel".
  final bool danger;

  /// A 16 px glyph at the row's right edge (the trash of Delete Server).
  final IconData? trailingIcon;
}

/// A titled group of [SpaceSettingsItem]s ("Expression", "People", …).
class SpaceSettingsGroup {
  const SpaceSettingsGroup({this.title, required this.items});

  final String? title;
  final List<SpaceSettingsItem> items;
}

/// The red of a destructive sidebar row.
const Color kSettingsDangerText = Color(0xFFF87E7A);

/// The reference client's full-screen server (and channel) settings: a dark
/// sidebar region whose 238 px menu hugs its right edge (the space name, then
/// titled groups split by hairlines), and a raised content region holding a
/// 740 px column (60/40/80 padding) with the round ✕ / "ESC" close button at
/// its right. Measured at 1920×927: sidebar region 692 px, content 1228 px.
///
/// [wide] pages (Server Profile, Members) use the whole region with the ✕ at
/// its right edge; non-[scrollable] pages get a bounded height and scroll
/// themselves. [overlay] floats 20 px over the region's bottom-left, 700 px
/// wide — the unsaved-changes bar.
class SpaceSettingsFrame extends StatelessWidget {
  const SpaceSettingsFrame({
    super.key,
    required this.spaceName,
    required this.groups,
    required this.selected,
    required this.onSelect,
    required this.child,
    this.header,
    this.wide = false,
    this.scrollable = true,
    this.overlay,
  });

  final String spaceName;

  /// Replaces the plain space-name heading (the channel settings show
  /// "# name  Category").
  final Widget? header;
  final List<SpaceSettingsGroup> groups;
  final String selected;
  final ValueChanged<String> onSelect;
  final Widget child;
  final bool wide;
  final bool scrollable;
  final Widget? overlay;

  /// The sidebar region's width for a window [width]: 218 px at least, 692 at
  /// 1920 (the reference client's flex split).
  static double sidebarWidth(double width) =>
      math.max(218, 218 + (width - 1018) * 0.5255);

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return EscapeToClose(
      child: Material(
        color: colors.raised,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 720;
            final content = _ContentRegion(
              wide: wide,
              scrollable: scrollable,
              overlay: overlay,
              child: child,
            );
            if (narrow) return SafeArea(child: content);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: sidebarWidth(constraints.maxWidth),
                  child: ColoredBox(
                    color: colors.foreground,
                    child: Align(
                      alignment: Alignment.topRight,
                      // The menu column ends 8 px short of the region's edge.
                      child: _Sidebar(
                        spaceName: spaceName,
                        header: header,
                        groups: groups,
                        selected: selected,
                        onSelect: onSelect,
                      ),
                    ),
                  ),
                ),
                Expanded(child: content),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A settings page's 20/600 title and its optional 14/500 description, 8 px
/// apart, as every server-settings page opens.
class SettingsPageHeader extends StatelessWidget {
  const SettingsPageHeader({
    super.key,
    required this.title,
    this.description,
    this.trailing,
    this.bottom = 40,
  });

  final String title;
  final String? description;
  final Widget? trailing;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    height: 24 / 20,
                    color: colors.dirtyWhite,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    description!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 18 / 14,
                      color: colors.dirtyWhite.withValues(alpha: 0.94),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.spaceName,
    required this.header,
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  final String spaceName;
  final Widget? header;
  final List<SpaceSettingsGroup> groups;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final heading = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 18 / 14,
      color: colors.gray,
    );
    return Container(
      width: 264,
      margin: const EdgeInsets.only(right: 8),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 60, 6, 60),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child:
                header ??
                Text(
                  spaceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: heading,
                ),
          ),
          for (final (i, group) in groups.indexed) ...[
            if (i > 0)
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                color: colors.hairline,
              ),
            if (group.title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Text(group.title!, style: heading),
              ),
            for (final item in group.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _SidebarItem(
                  item: item,
                  selected: item.key == selected,
                  onTap: () => onSelect(item.key),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final SpaceSettingsItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final foreground = item.danger
        ? kSettingsDangerText
        : selected
        ? colors.dirtyWhite
        : colors.interactive;
    return Material(
      color: selected ? colors.selection : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        key: Key('space-settings-nav-${item.key}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        hoverColor: colors.hover,
        child: Container(
          height: 32,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    height: 20 / 16,
                    color: foreground,
                  ),
                ),
              ),
              if (item.trailingIcon != null)
                Icon(item.trailingIcon, size: 16, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

/// The page column with the close button beside it.
class _ContentRegion extends StatelessWidget {
  const _ContentRegion({
    required this.child,
    required this.wide,
    required this.scrollable,
    required this.overlay,
  });

  final Widget child;
  final bool wide;
  final bool scrollable;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Wide pages run to 74 px short of the region's right edge, where
        // the ✕ sits; the others keep the 660 px column with the ✕ at 740.
        final closeLeft = wide
            ? math.max(740.0, constraints.maxWidth - 74)
            : 740.0;
        final maxWidth = wide ? closeLeft - 60 : 660.0;
        final page = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: scrollable
                  ? SingleChildScrollView(
                      key: const Key('space-settings-scroll'),
                      padding: const EdgeInsets.fromLTRB(40, 60, 40, 80),
                      child: Align(alignment: Alignment.topLeft, child: page),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(40, 60, 40, 0),
                      child: Align(alignment: Alignment.topLeft, child: page),
                    ),
            ),
            Positioned(top: 60, left: closeLeft, child: const _CloseButton()),
            if (overlay != null)
              Positioned(
                left: 20,
                bottom: 20,
                width: math.min(700, constraints.maxWidth - 40),
                child: overlay!,
              ),
          ],
        );
      },
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Close',
          child: InkWell(
            key: const Key('space-settings-close'),
            onTap: () => Navigator.of(context).maybePop(),
            customBorder: const CircleBorder(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colors.interactive, width: 2),
              ),
              child: Icon(AppIcons.close, size: 18, color: colors.interactive),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'ESC',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 16 / 12,
            color: colors.interactive,
          ),
        ),
      ],
    );
  }
}
