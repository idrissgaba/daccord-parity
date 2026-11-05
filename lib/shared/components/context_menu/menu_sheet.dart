part of '../context_menu.dart';

/// The touch form of a menu: a bottom sheet. A submenu row opens its entries
/// in a second sheet titled with the row's label.
Future<void> _showSheet(
  BuildContext context,
  List<AccordMenuEntry> entries,
  String? title,
  IconData? titleIcon,
) async {
  final colors = BonfireThemeExtension.of(context);
  final visible = _collapseDividers(entries);
  final picked = await showModalBottomSheet<AccordMenuEntry>(
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
              for (final entry in visible)
                if (entry.isDivider)
                  const Divider(height: 1)
                else if (entry.isWidget)
                  KeyedSubtree(key: entry.key, child: entry.child!)
                else
                  _SheetRow(entry: entry, colors: colors),
            ],
          ),
        ),
      );
    },
  );
  if (picked == null) return;
  // On touch a submenu row always opens its submenu (which carries the
  // row's own choice, "Until I turn it back on" and the like).
  if (picked.hasSubmenu) {
    if (context.mounted) {
      await _showSheet(context, picked.submenu!, picked.label, picked.icon);
    }
  } else if (picked._activatable) {
    picked.onSelected!.call();
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.entry, required this.colors});

  final AccordMenuEntry entry;
  final BonfireThemeExtension colors;

  @override
  Widget build(BuildContext context) {
    final subtitle = entry.subtitle ?? entry.sheetSubtitle;
    Widget? trailing;
    if (entry.checked != null) {
      trailing = _MenuCheck(
        checked: entry.checked!,
        destructive: entry.destructive,
      );
    } else if (entry.radio != null) {
      trailing = _MenuRadio(selected: entry.radio!);
    } else if (entry._showsChevron) {
      trailing = Icon(AppIcons.chevronRight, size: 18, color: colors.gray);
    }
    if (entry.trailing != null) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [entry.trailing!, if (trailing != null) trailing],
      );
    }
    return ListTile(
      key: entry.key,
      trailing: trailing,
      leading:
          entry.leading ??
          (entry.icon == null
              ? null
              : Icon(entry.icon, color: entry.destructive ? colors.red : null)),
      title: Text(
        entry.label,
        style: entry.destructive ? TextStyle(color: colors.red) : null,
      ),
      subtitle: subtitle == null ? null : Text(subtitle),
      enabled: entry._interactive,
      onTap: entry._interactive
          ? () => Navigator.of(context).pop(entry)
          : null,
    );
  }
}
