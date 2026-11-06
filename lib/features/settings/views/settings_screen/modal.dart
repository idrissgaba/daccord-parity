part of '../accord_settings_screen.dart';

/// The reference client's link colour (measured in lot B).
const Color _kLinkColor = Color(0xFF4D96EE);

/// The red of a destructive sidebar row (Log Out).
const Color _kDangerText = Color(0xFFF87E7A);

/// The reference client's 2026 user settings: a centred modal over a 72 %
/// black backdrop, 1400 px wide at most and 72 px clear of the window's top
/// and bottom, 12 px corners and a hairline border. A 253 px sidebar on the
/// pane colour (you, Edit Profiles, a search field, the pages and their
/// sub-sections, Log Out, version and links) and the page on the raised
/// colour under a 49 px header (title, ✕).
class _SettingsModal extends ConsumerStatefulWidget {
  const _SettingsModal({
    required this.initialPage,
    required this.onLogOut,
    required this.onClose,
  });

  final SettingsPage initialPage;
  final VoidCallback onLogOut;
  final VoidCallback onClose;

  @override
  ConsumerState<_SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends ConsumerState<_SettingsModal> {
  late SettingsPage _page = widget.initialPage;
  final Map<String, GlobalKey> _anchors = {};
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  String? _activeSub;

  /// While an anchor jump animates, the reading position isn't tracked.
  bool _jumping = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_trackActiveSub);
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _select(SettingsPage page) {
    if (page == _page) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
      return;
    }
    setState(() {
      _page = page;
      _activeSub = null;
      _anchors.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// Scrolls the page so [sub]'s title sits 24 px under the header, as the
  /// reference client's anchors do.
  void _jumpTo(SettingsSub sub) {
    setState(() => _activeSub = sub.id);
    final target = _anchors[sub.id]?.currentContext;
    if (target == null || !_scroll.hasClients) return;
    final box = target.findRenderObject() as RenderBox?;
    final viewport =
        _scroll.position.context.storageContext.findRenderObject()
            as RenderBox?;
    if (box == null || viewport == null) return;
    final dy = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final offset = (_scroll.offset + dy - 24).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _jumping = true;
    _scroll
        .animateTo(
          offset,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _jumping = false);
  }

  /// The sub-section being read: the last one whose title has reached the
  /// top third of the page.
  void _trackActiveSub() {
    if (_jumping) return;
    final viewport = _scroll.hasClients
        ? _scroll.position.context.storageContext.findRenderObject()
              as RenderBox?
        : null;
    if (viewport == null) return;
    String? active;
    for (final sub in visibleSubs(_page)) {
      final box =
          _anchors[sub.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final dy = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (dy <= viewport.size.height / 3) active = sub.id;
    }
    // At the very bottom the last section counts as read.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 1) {
      final subs = visibleSubs(_page);
      if (subs.isNotEmpty) active = subs.last.id;
    }
    if (active != _activeSub) setState(() => _activeSub = active);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 80).clamp(0.0, 1400.0);
    final height = (size.height - 144).clamp(0.0, size.height - 16);
    final query = _search.text.trim().toLowerCase();
    final subs = visibleSubs(_page);
    final activeSub = _activeSub ?? (subs.isEmpty ? null : subs.first.id);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const Key('settings-backdrop'),
              onTap: widget.onClose,
              child: const ColoredBox(color: Color(0xB8000000)),
            ),
          ),
          Center(
            child: Container(
              key: const ValueKey('settings-modal'),
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x1F94949C)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x3D000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 253,
                    child: _SettingsSidebar(
                      selected: _page,
                      activeSub: activeSub,
                      query: query,
                      search: _search,
                      onSelect: _select,
                      onSub: (page, sub) {
                        if (page == _page) {
                          _jumpTo(sub);
                          return;
                        }
                        _select(page);
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _jumpTo(sub),
                        );
                      },
                      onLogOut: widget.onLogOut,
                    ),
                  ),
                  Expanded(
                    child: _SettingsContent(
                      page: _page,
                      anchors: _anchors,
                      scroll: _scroll,
                      onClose: widget.onClose,
                      onOpenPage: _select,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The modal's sidebar.
class _SettingsSidebar extends ConsumerWidget {
  const _SettingsSidebar({
    required this.selected,
    required this.activeSub,
    required this.query,
    required this.search,
    required this.onSelect,
    required this.onSub,
    required this.onLogOut,
  });

  final SettingsPage selected;
  final String? activeSub;
  final String query;
  final TextEditingController search;
  final ValueChanged<SettingsPage> onSelect;
  final void Function(SettingsPage page, SettingsSub sub) onSub;
  final VoidCallback onLogOut;

  bool _matches(SettingsPage page) =>
      query.isEmpty ||
      page.label.toLowerCase().contains(query) ||
      visibleSubs(page).any((s) => s.label.toLowerCase().contains(query));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final rows = <Widget>[];
    SettingsGroup? group;
    for (final page in visibleSettingsPages()) {
      if (!_matches(page)) continue;
      if (group != null && page.group != group) {
        rows.add(const _SidebarSeparator());
        if (page.group.label != null) {
          rows.add(_SidebarHeading(page.group.label!));
        }
      }
      group = page.group;
      final isSelected = page == selected;
      rows.add(
        _SidebarItem(
          key: ValueKey('settings-nav-${page.name}'),
          icon: page.icon,
          label: page.label,
          selected: isSelected,
          onTap: () => onSelect(page),
        ),
      );
      final subs = visibleSubs(page);
      final showSubs =
          subs.isNotEmpty &&
          (isSelected ||
              (query.isNotEmpty &&
                  subs.any((s) => s.label.toLowerCase().contains(query))));
      if (showSubs) {
        rows.add(
          _SidebarSubs(
            subs: [
              for (final s in subs)
                if (query.isEmpty ||
                    isSelected ||
                    s.label.toLowerCase().contains(query))
                  s,
            ],
            active: isSelected ? activeSub : null,
            onTap: (sub) => onSub(page, sub),
          ),
        );
      } else {
        rows.add(const SizedBox(height: 4));
      }
    }
    if (query.isEmpty || 'log out'.contains(query)) {
      rows.add(
        _SidebarItem(
          key: const ValueKey('settings-nav-logout'),
          icon: AppIcons.logout,
          label: 'Log Out',
          selected: false,
          danger: true,
          onTap: onLogOut,
        ),
      );
    }
    if (query.isEmpty) rows.add(const _SidebarFooter());

    return Material(
      key: const ValueKey('settings-sidebar'),
      color: colors.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 17, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SidebarHeader(),
            const SizedBox(height: 8),
            _SidebarSearch(controller: search),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 12, bottom: 16),
                children: rows,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// You: 48 px avatar, display name and "Edit Profiles ✎".
class _SidebarHeader extends ConsumerWidget {
  const _SidebarHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final userId = ref.watchUserId();
    final serverKey = ref.watchActiveServerKey() ?? '';
    final user = userId == null
        ? null
        : ref.watch(
            accordUsersControllerProvider(
              serverKey,
            ).select((users) => users[userId]),
          );
    final sessionName = ref.watch(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session.username : null,
      ),
    );
    final name = accordUserName(user, fallback: sessionName ?? '');
    return InkWell(
      key: const Key('settings-edit-profiles'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => showAccordProfileEdit(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              AccordMemberAvatar(
                avatarUrl: user == null
                    ? null
                    : accordAvatarUrl(user, ref.watchCdnUrl()),
                initial: accordInitial(name),
                radius: 24,
                backgroundColor: accordIdColor(userId ?? ''),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        height: 20 / 16,
                        color: colors.dirtyWhite,
                      ),
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Edit Profiles',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              height: 18 / 14,
                              color: colors.gray,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(AppIcons.edit, size: 12, color: colors.gray),
                      ],
                    ),
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

/// The 40 px search field; it filters the pages and their sections.
class _SidebarSearch extends StatelessWidget {
  const _SidebarSearch({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      height: 40,
      decoration: settingsFieldDecoration(colors),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(AppIcons.search, size: 16, color: colors.dirtyWhite),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const Key('settings-search'),
              controller: controller,
              style: TextStyle(
                fontSize: 16,
                height: 20 / 16,
                color: colors.dirtyWhite,
              ),
              cursorColor: colors.dirtyWhite,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search',
                hintStyle: TextStyle(
                  fontSize: 16,
                  height: 20 / 16,
                  color: colors.gray,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final foreground = danger
        ? _kDangerText
        : selected
        ? colors.dirtyWhite
        : colors.gray;
    return Material(
      color: selected ? const Color(0x299595A2) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: colors.hover,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 20 / 16,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A selected page's sections: 20 px labels 16 px apart beside a 2 px track,
/// the section being read in white with a white stretch of the track.
class _SidebarSubs extends StatelessWidget {
  const _SidebarSubs({
    required this.subs,
    required this.active,
    required this.onTap,
  });

  final List<SettingsSub> subs;
  final String? active;
  final ValueChanged<SettingsSub> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(17, 8, 0, 12),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: colors.hairline, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, sub) in subs.indexed)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 16),
                child: _SidebarSubItem(
                  key: ValueKey('settings-sub-${sub.id}'),
                  sub: sub,
                  active: sub.id == active,
                  onTap: () => onTap(sub),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarSubItem extends StatelessWidget {
  const _SidebarSubItem({
    super.key,
    required this.sub,
    required this.active,
    required this.onTap,
  });

  final SettingsSub sub;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 20),
          child: Row(
            children: [
              // Paints the white stretch over the track for the active one.
              Transform.translate(
                offset: const Offset(-2, 0),
                child: Container(
                  width: 2,
                  height: 20,
                  color: active ? colors.dirtyWhite : Colors.transparent,
                ),
              ),
              const SizedBox(width: 17),
              Expanded(
                child: Text(
                  sub.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    height: 20 / 16,
                    color: active ? colors.dirtyWhite : colors.gray,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarSeparator extends StatelessWidget {
  const _SidebarSeparator();

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      height: 1,
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 15),
      color: colors.hairline,
    );
  }
}

class _SidebarHeading extends StatelessWidget {
  const _SidebarHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 7),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 18 / 14,
          color: colors.gray,
        ),
      ),
    );
  }
}

/// Version, then Privacy Policy · Terms of Service · About, in 12 px.
class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter();

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final small = TextStyle(fontSize: 12, height: 16 / 12, color: colors.gray);
    final link = small.copyWith(color: _kLinkColor);
    Widget linkText(String text, VoidCallback onTap, {Key? key}) =>
        GestureDetector(
          key: key,
          onTap: onTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Text(text, style: link),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Daccord v$kAppVersion', style: small),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              linkText(
                'Privacy Policy',
                () => openTrustedUrl(kDaccordPrivacyPolicyUrl),
              ),
              Text(' • ', style: small),
              linkText(
                'Terms of Service',
                () => showAppTermsDialog(context),
                key: const Key('settings-terms'),
              ),
              Text(' • ', style: small),
              Builder(
                builder: (context) => GestureDetector(
                  key: const Key('settings-more'),
                  onTapUp: (details) => showAccordContextMenu(
                    context,
                    globalPosition: details.globalPosition,
                    preferAbove: true,
                    entries: [
                      AccordMenuEntry(
                        label: 'About Daccord',
                        onSelected: () => showAboutDialog(
                          context: context,
                          applicationName: 'Daccord',
                          applicationVersion: 'v$kAppVersion',
                          applicationLegalese:
                              'A native multi-platform Daccord client '
                              '(GPLv3).',
                        ),
                      ),
                      AccordMenuEntry(
                        label: 'Help & Support',
                        onSelected: () => showOnboardingHelpDialog(context),
                      ),
                    ],
                  ),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text('More', style: small),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The page under its 49 px header (title, ✕).
class _SettingsContent extends StatelessWidget {
  const _SettingsContent({
    required this.page,
    required this.anchors,
    required this.scroll,
    required this.onClose,
    required this.onOpenPage,
  });

  final SettingsPage page;
  final Map<String, GlobalKey> anchors;
  final ScrollController scroll;
  final VoidCallback onClose;
  final ValueChanged<SettingsPage> onOpenPage;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    // A Material, not a bare colour: embedded pages still use ListTiles.
    return Material(
      color: colors.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 49,
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    page.label,
                    key: const Key('settings-page-title'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 20 / 16,
                      color: colors.dirtyWhite,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Close',
                  child: InkWell(
                    key: const Key('settings-close'),
                    onTap: onClose,
                    borderRadius: BorderRadius.circular(8),
                    hoverColor: colors.hover,
                    child: SizedBox.square(
                      dimension: 32,
                      child: Icon(
                        AppIcons.close,
                        size: 16,
                        color: colors.interactive,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SettingsAnchors(
              keys: anchors,
              child: SingleChildScrollView(
                key: const ValueKey('settings-scroll'),
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(24, 64, 24, 120),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 696),
                    child: KeyedSubtree(
                      key: const ValueKey('settings-content-column'),
                      child: _SettingsPageBody(
                        page: page,
                        onOpenPage: onOpenPage,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
