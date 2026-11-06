part of '../accord_role_management.dart';

/// The Roles page before a role is picked. With only @everyone it is the
/// reference client's empty state (a glyph, "Organise your members", Create
/// Role); otherwise the description, the "Default permissions" card, the
/// search field with Create Role, and the ROLES / MEMBERS table.
class _RoleListView extends StatefulWidget {
  const _RoleListView({
    required this.roles,
    required this.busy,
    required this.error,
    required this.memberCount,
    required this.onOpen,
    required this.onCreate,
  });

  final List<AccordRole> roles;
  final bool busy;
  final String? error;
  final int Function(AccordRole) memberCount;
  final ValueChanged<String> onOpen;
  final VoidCallback onCreate;

  @override
  State<_RoleListView> createState() => _RoleListViewState();
}

class _RoleListViewState extends State<_RoleListView> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final everyone = widget.roles.firstWhereOrNull((r) => r.position == 0);
    final others = widget.roles.where((r) => r.position != 0).toList();
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? others
        : others.where((r) => r.name.toLowerCase().contains(q)).toList();
    final defaults = everyone == null
        ? null
        : _DefaultPermissionsCard(onTap: () => widget.onOpen(everyone.id));
    final error = widget.error;

    if (others.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Roles', style: SettingsText.pageTitle(colors)),
          const SizedBox(height: 24),
          Icon(AppIcons.groups, size: 96, color: colors.darkGray),
          const SizedBox(height: 20),
          Text(
            'Organise your members',
            textAlign: TextAlign.center,
            style: SettingsText.pageTitle(colors),
          ),
          const SizedBox(height: 8),
          Text(
            'Use roles to group your server members and assign permissions.',
            textAlign: TextAlign.center,
            style: SettingsText.body(colors).copyWith(fontSize: 14),
          ),
          const SizedBox(height: 16),
          Center(
            child: AccordButton(
              key: const Key('roles-create'),
              label: 'Create Role',
              onPressed: widget.busy ? null : widget.onCreate,
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            InlineError(error, centered: true),
          ],
          const SettingsDivider(top: 24, bottom: 24),
          if (defaults != null) defaults,
        ],
      );
    }

    final head = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 16 / 12,
      color: colors.interactive,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsPageHeader(
          title: 'Roles',
          description:
              'Use roles to group your server members and assign '
              'permissions.',
          bottom: 24,
        ),
        if (defaults != null) defaults,
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: settingsFieldDecoration(colors),
                child: Row(
                  children: [
                    Icon(AppIcons.search, size: 16, color: colors.interactive),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const Key('roles-search'),
                        style: TextStyle(fontSize: 16, color: colors.dirtyWhite),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: 'Search Roles',
                          hintStyle: TextStyle(
                            fontSize: 16,
                            color: colors.gray,
                          ),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            AccordButton(
              key: const Key('roles-create'),
              label: 'Create Role',
              onPressed: widget.busy ? null : widget.onCreate,
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          InlineError(error, centered: false),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: Text('ROLES — ${others.length}', style: head),
              ),
              SizedBox(width: 100, child: Text('MEMBERS', style: head)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              for (final role in shown)
                _RoleRow(
                  key: ValueKey('role-row-${role.id}'),
                  role: role,
                  members: widget.memberCount(role),
                  onTap: () => widget.onOpen(role.id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Default permissions · @everyone · applies to all server members ›".
class _DefaultPermissionsCard extends StatelessWidget {
  const _DefaultPermissionsCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('roles-default-permissions'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 74,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.hairline),
          ),
          child: Row(
            children: [
              Icon(AppIcons.groupOutlined, size: 20, color: colors.interactive),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Default permissions',
                      style: SettingsText.label(colors).copyWith(
                        color: colors.dirtyWhite.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@everyone • applies to all server members',
                      style: TextStyle(
                        fontSize: 12,
                        height: 16 / 12,
                        color: colors.interactive,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(AppIcons.chevronRight, size: 20, color: colors.interactive),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleRow extends StatefulWidget {
  const _RoleRow({
    super.key,
    required this.role,
    required this.members,
    required this.onTap,
  });

  final AccordRole role;
  final int members;
  final VoidCallback onTap;

  @override
  State<_RoleRow> createState() => _RoleRowState();
}

class _RoleRowState extends State<_RoleRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final dot = accordRoleColor(widget.role.color) ?? colors.interactive;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hover ? colors.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border(bottom: BorderSide(color: colors.hairline)),
          ),
          child: Row(
            children: [
              Icon(AppIcons.shieldOutlined, size: 20, color: dot),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.role.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SettingsText.label(colors),
                ),
              ),
              SizedBox(
                width: 100,
                child: Row(
                  children: [
                    Text(
                      '${widget.members}',
                      style: SettingsText.body(colors),
                    ),
                    const SizedBox(width: 4),
                    Icon(AppIcons.person, size: 16, color: colors.interactive),
                    const Spacer(),
                    if (_hover)
                      Icon(AppIcons.edit, size: 16, color: colors.interactive),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The role column beside the editor: "← Back" and "+", then every role
/// (draggable when editable), @everyone pinned last.
class _RoleColumn extends StatelessWidget {
  const _RoleColumn({
    required this.roles,
    required this.selectedId,
    required this.busy,
    required this.canEdit,
    required this.onBack,
    required this.onSelect,
    required this.onCreate,
    required this.onReorder,
  });

  final List<AccordRole> roles;
  final String? selectedId;
  final bool busy;
  final bool Function(AccordRole) canEdit;
  final VoidCallback onBack;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<List<AccordRole>> onReorder;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    // @everyone stays pinned at the bottom and isn't draggable.
    final draggable = roles.where((r) => r.position != 0).toList();
    final everyone = roles.firstWhereOrNull((r) => r.position == 0);
    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: colors.hairline)),
      ),
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 24,
            child: Row(
              children: [
                InkWell(
                  key: const Key('roles-back'),
                  onTap: onBack,
                  child: Row(
                    children: [
                      Icon(
                        AppIcons.arrowBack,
                        size: 18,
                        color: colors.dirtyWhite,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Back',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colors.dirtyWhite,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Create Role',
                  child: InkWell(
                    key: const Key('roles-column-create'),
                    onTap: busy ? null : onCreate,
                    child: Icon(AppIcons.add, size: 18, color: colors.dirtyWhite),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ReorderableListView(
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) {
                if (busy) return;
                final reordered = [...draggable];
                final item = reordered.removeAt(oldIndex);
                reordered.insert(newIndex, item);
                onReorder(reordered);
              },
              footer: everyone == null
                  ? null
                  : _RoleListTile(
                      role: everyone,
                      selected: everyone.id == selectedId,
                      draggable: false,
                      onTap: () => onSelect(everyone.id),
                    ),
              children: [
                for (var i = 0; i < draggable.length; i++)
                  _RoleListTile(
                    key: ValueKey(draggable[i].id),
                    index: i,
                    role: draggable[i],
                    selected: draggable[i].id == selectedId,
                    draggable: canEdit(draggable[i]),
                    onTap: () => onSelect(draggable[i].id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleListTile extends StatelessWidget {
  const _RoleListTile({
    super.key,
    required this.role,
    required this.selected,
    required this.draggable,
    required this.onTap,
    this.index,
  });

  final AccordRole role;
  final bool selected;
  final bool draggable;
  final VoidCallback onTap;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final dot = accordRoleColor(role.color) ?? colors.interactive;
    final row = Material(
      color: selected ? colors.selection : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        key: Key('role-tile-${role.id}'),
        borderRadius: BorderRadius.circular(4),
        hoverColor: colors.hover,
        onTap: onTap,
        child: SizedBox(
          height: 34,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    role.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: selected ? colors.dirtyWhite : colors.interactive,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: draggable && index != null
          ? ReorderableDragStartListener(index: index!, child: row)
          : row,
    );
  }
}
