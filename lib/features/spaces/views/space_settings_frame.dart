import 'dart:math' as math;

import 'package:bonfire/shared/components/escape_to_close.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// One page entry of the server-settings sidebar.
class SpaceSettingsItem {
  const SpaceSettingsItem({required this.key, required this.label});

  final String key;
  final String label;
}

/// A titled group of [SpaceSettingsItem]s ("Expression", "People", …).
class SpaceSettingsGroup {
  const SpaceSettingsGroup({this.title, required this.items});

  final String? title;
  final List<SpaceSettingsItem> items;
}

/// The reference client's full-screen server settings: a dark sidebar region
/// whose 238 px menu hugs its right edge (the space name, then titled groups
/// split by hairlines), and a raised content region holding a 740 px column
/// (60/40/80 padding) with the round ✕ / "ESC" close button at its right.
/// Measured at 1920×927: sidebar region 692 px, content 1228 px.
class SpaceSettingsFrame extends StatelessWidget {
  const SpaceSettingsFrame({
    super.key,
    required this.spaceName,
    required this.groups,
    required this.selected,
    required this.onSelect,
    required this.child,
  });

  final String spaceName;
  final List<SpaceSettingsGroup> groups;
  final String selected;
  final ValueChanged<String> onSelect;
  final Widget child;

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
            final content = _ContentRegion(child: child);
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

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.spaceName,
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  final String spaceName;
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
            child: Text(
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
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              height: 20 / 16,
              color: selected ? colors.dirtyWhite : colors.interactive,
            ),
          ),
        ),
      ),
    );
  }
}

/// The page column with the close button beside it.
class _ContentRegion extends StatelessWidget {
  const _ContentRegion({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(40, 60, 40, 80),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 660),
                child: child,
              ),
            ),
          ),
        ),
        const Positioned(top: 60, left: 740, child: _CloseButton()),
      ],
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
