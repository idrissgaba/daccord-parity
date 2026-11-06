part of 'accord_space_settings.dart';

/// Server Settings › Members: the reference client's "Server Members" table
/// — a card with the search field over Name / Member Since / Roles columns.
/// A row (or its "…") opens the member menu, where moderation lives.
class _MembersPage extends ConsumerStatefulWidget {
  const _MembersPage({required this.spaceId, required this.serverKey});

  final String spaceId;
  final String serverKey;

  @override
  ConsumerState<_MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends ConsumerState<_MembersPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _date(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '—';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final members =
        ref.watch(
          accordMembersControllerProvider(widget.serverKey, widget.spaceId),
        ) ??
        const <String, AccordMember>{};
    final space = ref.watch(
      spacesControllerProvider.select(
        (s) => s?.firstWhereOrNull((sp) => sp.id == widget.spaceId),
      ),
    );
    final rolesById = {for (final r in space?.roles ?? <AccordRole>[]) r.id: r};
    final query = _search.text.trim().toLowerCase();
    final rows =
        members.values.where((m) {
          if (query.isEmpty) return true;
          final name = accordMemberName(m).toLowerCase();
          final username = (m.user?.username ?? '').toLowerCase();
          return name.contains(query) ||
              username.contains(query) ||
              m.userId == query;
        }).toList()..sort((a, b) => b.joinedAt.compareTo(a.joinedAt));
    final header = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 16 / 12,
      color: colors.dirtyWhite,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsPageHeader(title: 'Server Members', bottom: 24),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 40),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Recent Members',
                          style: SettingsText.label(colors),
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        height: 32,
                        child: Container(
                          decoration: settingsFieldDecoration(colors),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              Icon(
                                AppIcons.search,
                                size: 14,
                                color: colors.interactive,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  key: const Key('space-members-search'),
                                  controller: _search,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colors.dirtyWhite,
                                  ),
                                  decoration: InputDecoration(
                                    isCollapsed: true,
                                    border: InputBorder.none,
                                    hintText: 'Search by username or ID',
                                    hintStyle: TextStyle(
                                      fontSize: 14,
                                      color: colors.gray,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.symmetric(
                      horizontal: BorderSide(color: colors.hairline),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 4, child: Text('Name', style: header)),
                      Expanded(
                        flex: 2,
                        child: Text('Member Since', style: header),
                      ),
                      Expanded(flex: 4, child: Text('Roles', style: header)),
                      const SizedBox(width: 32),
                    ],
                  ),
                ),
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Text(
                            query.isEmpty
                                ? 'No members loaded yet.'
                                : 'No members match your search.',
                            style: SettingsText.description(colors),
                          ),
                        )
                      : ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, i) => _MemberRow(
                            member: rows[i],
                            spaceId: widget.spaceId,
                            joined: _date(rows[i].joinedAt),
                            roles: [
                              for (final id in rows[i].roles)
                                if (rolesById[id] case final role?)
                                  if (role.position > 0) role,
                            ]..sort((a, b) => b.position.compareTo(a.position)),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MemberRow extends ConsumerStatefulWidget {
  const _MemberRow({
    required this.member,
    required this.spaceId,
    required this.joined,
    required this.roles,
  });

  final AccordMember member;
  final String spaceId;
  final String joined;
  final List<AccordRole> roles;

  @override
  ConsumerState<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends ConsumerState<_MemberRow> {
  bool _hover = false;

  void _menu(Offset position) => showUserContextMenu(
    context,
    ref,
    userId: widget.member.userId,
    user: widget.member.user,
    spaceId: widget.spaceId,
    globalPosition: position,
  );

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final member = widget.member;
    final name = accordMemberName(member);
    final username = member.user?.username;
    final roleChips = widget.roles.take(2).toList();
    final more = widget.roles.length - roleChips.length;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (d) => _menu(d.globalPosition),
        onTapUp: (d) => _menu(d.globalPosition),
        child: Container(
          key: Key('space-member-${member.userId}'),
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hover ? colors.hover : Colors.transparent,
            border: Border(bottom: BorderSide(color: colors.hairline)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    AccordMemberAvatar(
                      avatarUrl: member.user == null
                          ? null
                          : accordAvatarUrl(member.user!, ref.watchCdnUrl()),
                      initial: accordInitial(name),
                      radius: 16,
                      backgroundColor: accordIdColor(member.userId),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SettingsText.label(
                              colors,
                            ).copyWith(fontSize: 14),
                          ),
                          if (username != null && username != name)
                            Text(
                              username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SettingsText.description(
                                colors,
                              ).copyWith(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  widget.joined,
                  style: SettingsText.description(colors),
                ),
              ),
              Expanded(
                flex: 4,
                child: Wrap(
                  spacing: 4,
                  children: [
                    for (final role in roleChips) _RoleChip(role: role),
                    if (more > 0)
                      _RoleChip(label: '+$more'),
                  ],
                ),
              ),
              SizedBox(
                width: 32,
                child: _hover
                    ? Builder(
                        builder: (context) => InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTapUp: (d) => _menu(d.globalPosition),
                          onTap: () {},
                          child: Icon(
                            AppIcons.moreHoriz,
                            size: 20,
                            color: colors.interactive,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A role pill: its colour dot and name.
class _RoleChip extends StatelessWidget {
  const _RoleChip({this.role, this.label});

  final AccordRole? role;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final role = this.role;
    final color = role == null || role.color == 0
        ? colors.gray
        : Color(0xFF000000 | role.color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF94949C).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (role != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label ?? role!.name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.dirtyWhite,
            ),
          ),
        ],
      ),
    );
  }
}

/// Server Settings › Arcade (Accord's own, beside Integrations): the
/// reviewed games this space offers.
class _ArcadePage extends StatelessWidget {
  const _ArcadePage({required this.spaceId, required this.serverKey});

  final String spaceId;
  final String serverKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsPageHeader(
          title: 'Arcade',
          description:
              'Enable reviewed games and configure what this server offers in '
              'voice channels.',
        ),
        SettingsLinkCard(
          icon: AppIcons.sportsEsportsOutlined,
          title: 'Manage Arcade',
          description: 'Choose the games members can start in voice.',
          onTap: () => showSpaceArcade(
            context,
            serverKey: serverKey,
            spaceId: spaceId,
            manage: true,
          ),
        ),
      ],
    );
  }
}
