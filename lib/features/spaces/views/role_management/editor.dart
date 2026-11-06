part of '../accord_role_management.dart';

/// The reference client's heading for each permission group.
String _groupTitle(String label) => switch (label) {
  'General' => 'General Server Permissions',
  'Text' => 'Text Channel Permissions',
  'Threads' => 'Thread Permissions',
  'Voice' => 'Voice Channel Permissions',
  'Moderation' => 'Moderation Permissions',
  'Administration' => 'Advanced Permissions',
  _ => '$label Permissions',
};

/// A permission's name in the role editor: the server-wide plural where the
/// reference client uses one ("View Channels"; a channel's own overwrite
/// says "View Channel").
String _roleLabel(String perm) => perm == AccordPermission.viewChannel
    ? 'View Channels'
    : accordPermissionLabel(perm);

/// The editor of one role: "Edit Role – name" with its "…" menu, the
/// Display / Permissions / Manage Members tabs, and the unsaved-changes bar
/// for the Display and Permissions draft. @everyone only has Permissions.
class _RoleEditor extends StatefulWidget {
  const _RoleEditor({
    super.key,
    required this.role,
    required this.editable,
    required this.busy,
    required this.error,
    required this.members,
    required this.candidates,
    required this.onSave,
    required this.onDelete,
    required this.onPreview,
    required this.onAddMember,
    required this.onRemoveMember,
  });

  final AccordRole role;
  final bool editable;
  final bool busy;
  final String? error;
  final List<AccordMember> members;
  final List<AccordMember> candidates;
  final Future<bool> Function(AccordRole) onSave;
  final VoidCallback? onDelete;
  final VoidCallback onPreview;
  final ValueChanged<String> onAddMember;
  final ValueChanged<String> onRemoveMember;

  @override
  State<_RoleEditor> createState() => _RoleEditorState();
}

enum _RoleTab { display, permissions, members }

class _RoleEditorState extends State<_RoleEditor> {
  late final TextEditingController _name;
  late int _color;
  late bool _hoist;
  late bool _mentionable;
  late Set<String> _permissions;
  late _RoleTab _tab;
  String _permissionQuery = '';
  String _memberQuery = '';

  bool get _isEveryone => widget.role.position == 0;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController()..addListener(() => setState(() {}));
    _seed();
    _tab = _isEveryone ? _RoleTab.permissions : _RoleTab.display;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _seed() {
    _name.text = widget.role.name;
    _color = widget.role.color;
    _hoist = widget.role.hoist;
    _mentionable = widget.role.mentionable;
    _permissions = widget.role.permissions.map((p) => p.toString()).toSet();
  }

  bool get _dirty =>
      _name.text.trim() != widget.role.name ||
      _color != widget.role.color ||
      _hoist != widget.role.hoist ||
      _mentionable != widget.role.mentionable ||
      !const SetEquality<String>().equals(
        _permissions,
        widget.role.permissions.map((p) => p.toString()).toSet(),
      );

  Future<void> _save() async {
    final edited = AccordRole(
      id: widget.role.id,
      name: _name.text.trim().isEmpty ? widget.role.name : _name.text.trim(),
      color: _color,
      hoist: _hoist,
      icon: widget.role.icon,
      position: widget.role.position,
      permissions: _permissions.toList(),
      managed: widget.role.managed,
      mentionable: _mentionable,
    );
    await widget.onSave(edited);
  }

  @override
  void didUpdateWidget(covariant _RoleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A save (or a gateway update) lands: follow the server's copy.
    if (oldWidget.role != widget.role && !_dirty) setState(_seed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final enabled = widget.editable && !widget.busy;
    final tabs = <(_RoleTab, String)>[
      (_RoleTab.display, 'Display'),
      (_RoleTab.permissions, 'Permissions'),
      (
        _RoleTab.members,
        _isEveryone
            ? 'Manage Members'
            : 'Manage Members (${widget.members.length})',
      ),
    ];
    final body = switch (_tab) {
      _RoleTab.display => _displayTab(colors, enabled),
      _RoleTab.permissions => _permissionsTab(colors, enabled),
      _RoleTab.members => _membersTab(colors),
    };
    return UnsavedChangesHost(
      dirty: _dirty,
      saving: widget.busy,
      onReset: () => setState(_seed),
      onSave: enabled ? _save : null,
      inset: const EdgeInsets.only(left: -236),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 25,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Edit Role – ${widget.role.name}',
                    key: const Key('role-editor-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 20 / 16,
                      color: colors.dirtyWhite,
                    ),
                  ),
                ),
                AccordMenuButton(
                  key: const Key('role-editor-more'),
                  tooltip: 'More',
                  entries: () => [
                    AccordMenuEntry(
                      label: 'View Server As Role',
                      onSelected: widget.onPreview,
                    ),
                    if (widget.onDelete != null) ...[
                      const AccordMenuEntry.divider(),
                      AccordMenuEntry(
                        label: 'Delete Role',
                        destructive: true,
                        enabled: enabled,
                        onSelected: widget.onDelete,
                      ),
                    ],
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      AppIcons.moreHoriz,
                      size: 22,
                      color: colors.dirtyWhite,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.hairline)),
            ),
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (tab, label) in tabs) ...[
                    _TabLabel(
                      key: Key('role-tab-${tab.name}'),
                      label: label,
                      selected: _tab == tab,
                      enabled: !_isEveryone || tab == _RoleTab.permissions,
                      onTap: () => setState(() => _tab = tab),
                    ),
                    const SizedBox(width: 54),
                  ],
                ],
              ),
            ),
          ),
          if (!widget.editable) ...[
            const SizedBox(height: 12),
            Text(
              widget.role.managed
                  ? 'This role is managed by an integration.'
                  : 'This role is at or above your highest role.',
              style: SettingsText.description(colors),
            ),
          ],
          if (widget.error != null) ...[
            const SizedBox(height: 12),
            InlineError(widget.error!, centered: false),
          ],
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _displayTab(BonfireThemeExtension colors, bool enabled) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 120),
      children: [
        const _RequiredLabel('Role Name'),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: settingsFieldDecoration(colors),
          child: TextField(
            key: const Key('role-name'),
            controller: _name,
            enabled: enabled,
            style: TextStyle(fontSize: 16, color: colors.dirtyWhite),
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
            ),
          ),
        ),
        const SettingsDivider(top: 24, bottom: 24),
        const _RequiredLabel('Role Colour'),
        Text(
          'Members use the colour of the highest role they have on the roles '
          'list.',
          style: SettingsText.description(colors),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in _palette)
              _ColorSwatch(
                value: value,
                selected: value == _color,
                onTap: enabled ? () => setState(() => _color = value) : null,
              ),
          ],
        ),
        const SettingsDivider(top: 24, bottom: 24),
        SettingsSwitchRow(
          key: const Key('role-hoist'),
          label: 'Display role members separately from online members',
          value: _hoist,
          onChanged: enabled ? (v) => setState(() => _hoist = v) : null,
        ),
        const SettingsDivider(top: 24, bottom: 24),
        SettingsSwitchRow(
          key: const Key('role-mentionable'),
          label: 'Allow anyone to @mention this role',
          description:
              'Note: Members with the "Mention @everyone, @here, and all '
              'roles" permission will always be able to ping this role.',
          value: _mentionable,
          onChanged: enabled ? (v) => setState(() => _mentionable = v) : null,
        ),
        const SettingsDivider(top: 24, bottom: 24),
        SettingsLinkCard(
          icon: AppIcons.visibility,
          title: 'View Server As Role',
          description:
              'Test the permissions on this role by viewing the '
              'app as a member with only this role.',
          onTap: widget.onPreview,
        ),
      ],
    );
  }

  Widget _permissionsTab(BonfireThemeExtension colors, bool enabled) {
    final q = _permissionQuery.trim().toLowerCase();
    final groups = [
      for (final group in accordPermissionGroups)
        (
          label: group.label,
          permissions: [
            for (final p in group.permissions)
              if (q.isEmpty || _roleLabel(p).toLowerCase().contains(q)) p,
          ],
        ),
    ].where((g) => g.permissions.isNotEmpty).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 120),
      children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: settingsFieldDecoration(colors),
          child: Row(
            children: [
              Icon(AppIcons.search, size: 16, color: colors.interactive),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('role-permission-search'),
                  style: TextStyle(fontSize: 16, color: colors.dirtyWhite),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Search permissions',
                    hintStyle: TextStyle(fontSize: 16, color: colors.gray),
                  ),
                  onChanged: (v) => setState(() => _permissionQuery = v),
                ),
              ),
            ],
          ),
        ),
        for (final (i, group) in groups.indexed) ...[
          SizedBox(height: i == 0 ? 32 : 40),
          Row(
            children: [
              Expanded(
                child: Text(
                  _groupTitle(group.label),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    height: 24 / 20,
                    color: colors.dirtyWhite,
                  ),
                ),
              ),
              if (i == 0)
                GestureDetector(
                  key: const Key('role-clear-permissions'),
                  onTap: enabled
                      ? () => setState(() => _permissions.clear())
                      : null,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text(
                      'Clear permissions',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (j, perm) in group.permissions.indexed) ...[
            if (j > 0) const SettingsDivider(top: 24, bottom: 24),
            SettingsSwitchRow(
              key: Key('role-perm-$perm'),
              label: _roleLabel(perm),
              description: AccordPermission.description(perm).isEmpty
                  ? null
                  : AccordPermission.description(perm),
              value: _permissions.contains(perm),
              onChanged: enabled
                  ? (v) => setState(() {
                      if (v) {
                        _permissions.add(perm);
                      } else {
                        _permissions.remove(perm);
                      }
                    })
                  : null,
            ),
          ],
        ],
      ],
    );
  }

  Widget _membersTab(BonfireThemeExtension colors) {
    final q = _memberQuery.trim().toLowerCase();
    final shown = widget.members
        .where(
          (m) => q.isEmpty || accordMemberName(m).toLowerCase().contains(q),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
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
                        key: const Key('role-member-search'),
                        style: TextStyle(
                          fontSize: 16,
                          color: colors.dirtyWhite,
                        ),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: 'Search Members',
                          hintStyle: TextStyle(
                            fontSize: 16,
                            color: colors.gray,
                          ),
                        ),
                        onChanged: (v) => setState(() => _memberQuery = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            AccordButton(
              key: const Key('role-add-members'),
              label: 'Add Members',
              onPressed: !widget.editable || widget.busy
                  ? null
                  : () async {
                      final picked = await showDialog<String>(
                        context: context,
                        builder: (_) => ChannelMemberPickerDialog(
                          members: widget.candidates,
                        ),
                      );
                      if (picked != null) widget.onAddMember(picked);
                    },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    widget.members.isEmpty
                        ? 'No members were found. Add members to this role.'
                        : 'No members match your search.',
                    style: SettingsText.description(colors),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 40),
                  children: [
                    for (final m in shown)
                      _RoleMemberRow(
                        key: ValueKey('role-member-${m.userId}'),
                        member: m,
                        onRemove: widget.editable && !widget.busy
                            ? () => widget.onRemoveMember(m.userId)
                            : null,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// A 16/500 label with the reference client's red asterisk.
class _RequiredLabel extends StatelessWidget {
  const _RequiredLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: label),
            TextSpan(
              text: ' *',
              style: TextStyle(color: colors.red),
            ),
          ],
        ),
        style: SettingsText.label(colors),
      ),
    );
  }
}

/// A tab of the role editor: 16/400, the accent and a 2 px underline when
/// selected, dimmed when not available (@everyone).
class _TabLabel extends StatelessWidget {
  const _TabLabel({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final color = selected
        ? const Color(0xFF798DF9)
        : colors.gray.withValues(alpha: enabled ? 1 : 0.5);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          height: 31,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? const Color(0xFF798DF9) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              height: 14 / 16,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleMemberRow extends ConsumerStatefulWidget {
  const _RoleMemberRow({super.key, required this.member, this.onRemove});

  final AccordMember member;
  final VoidCallback? onRemove;

  @override
  ConsumerState<_RoleMemberRow> createState() => _RoleMemberRowState();
}

class _RoleMemberRowState extends ConsumerState<_RoleMemberRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final m = widget.member;
    final name = accordMemberName(m);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: _hover ? colors.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            AccordMemberAvatar(
              avatarUrl: m.user == null
                  ? null
                  : accordAvatarUrl(m.user!, ref.watchCdnUrl()),
              initial: accordInitial(name),
              radius: 16,
              backgroundColor: accordIdColor(m.userId),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: SettingsText.label(colors).copyWith(fontSize: 14),
              ),
            ),
            if (_hover && widget.onRemove != null)
              Tooltip(
                message: 'Remove Member',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onRemove,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: colors.raised,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      AppIcons.close,
                      size: 14,
                      color: colors.dirtyWhite,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The role editor's 28px rounded-square variant of [ColorSwatchChip]; keeps
/// the role-value → colour mapping (0 = "no colour") local to this screen.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final color = accordRoleColor(value);
    return ColorSwatchChip(
      color: color ?? colors.darkGray,
      selected: selected,
      onTap: onTap,
      size: value == 0 ? 64 : 32,
      borderRadius: BorderRadius.circular(4),
      borderWidth: 2,
      icon: color == null ? AppIcons.check : null,
      iconColor: color == null ? colors.dirtyWhite : Colors.white,
      iconSize: 20,
      ink: true,
    );
  }
}
