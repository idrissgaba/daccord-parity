part of 'accord_direct_messages.dart';

/// The friends-page tabs, as the reference client's header lists them.
enum FriendsPage { online, all, pending, blocked, addFriend }

/// The direct-messages home: whether it is the screen on show, which
/// conversation is open in it (none = the Friends page), which Friends tab is
/// selected and whether a 1:1 conversation shows its profile panel. A single
/// instance, like [voiceViewExpanded]: the rail's home button, every "Message"
/// action and the incoming-call banner all open it.
class DmHomeController extends ChangeNotifier {
  bool _active = false;
  AccordChannel? _channel;
  FriendsPage _page = FriendsPage.online;
  bool _profileShown = true;

  bool get active => _active;
  AccordChannel? get channel => _channel;
  FriendsPage get page => _page;
  bool get profileShown => _profileShown;

  /// Shows the home; with [channel] that conversation, else the Friends page.
  void open([AccordChannel? channel]) {
    _active = true;
    _channel = channel;
    notifyListeners();
  }

  /// Back to the Friends page, keeping the home on screen.
  void showFriends([FriendsPage? page]) {
    _channel = null;
    if (page != null) _page = page;
    notifyListeners();
  }

  void selectPage(FriendsPage page) {
    _page = page;
    notifyListeners();
  }

  void toggleProfile() {
    _profileShown = !_profileShown;
    notifyListeners();
  }

  /// A space was picked: the home steps aside.
  void leave() {
    if (!_active) return;
    _active = false;
    notifyListeners();
  }

  /// Keeps the open conversation current when the cache updates it.
  void replaceChannel(AccordChannel channel) {
    if (_channel?.id != channel.id) return;
    _channel = channel;
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    _active = false;
    _channel = null;
    _page = FriendsPage.online;
    _profileShown = true;
  }
}

final DmHomeController dmHome = DmHomeController();

/// The direct-messages column that takes the channel list's place while the
/// home is on show: "Find or start a conversation", the Friends row, and the
/// "Direct Messages" list with its "+" (new group).
class DmHomeSidebar extends ConsumerStatefulWidget {
  const DmHomeSidebar({super.key, this.onNavigate});

  /// After a row is chosen (the narrow layout closes its drawer).
  final VoidCallback? onNavigate;

  @override
  ConsumerState<DmHomeSidebar> createState() => _DmHomeSidebarState();
}

class _DmHomeSidebarState extends ConsumerState<DmHomeSidebar> {
  @override
  void initState() {
    super.initState();
    dmHome.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    dmHome.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String? get _selfId => ref.readUserId();

  /// The conversation list with each one's latest message (for the order and
  /// the previews).
  Future<void> _load() async {
    final client = ref.accordClient;
    final serverKey = ref.readActiveServerKey();
    if (client == null || serverKey == null) return;
    final result = await client.users.listChannels();
    if (!mounted || ref.readActiveServerKey() != serverKey) return;
    final data = result.data;
    final channels = data is List
        ? data.whereType<AccordChannel>().toList()
        : <AccordChannel>[];
    final controller = ref.read(
      dmChannelsControllerProvider(serverKey).notifier,
    );
    controller.setChannels(channels);
  }

  Future<void> _findOrStart() async {
    final channel = await showDialog<AccordChannel>(
      context: context,
      builder: (_) => const _CreateGroupDialog(),
    );
    if (channel == null || !mounted) return;
    final serverKey = ref.readActiveServerKey();
    if (serverKey != null) {
      ref
          .read(dmChannelsControllerProvider(serverKey).notifier)
          .upsert(channel);
    }
    dmHome.open(channel);
    widget.onNavigate?.call();
  }

  Future<void> _close(AccordChannel channel) async {
    final selfId = _selfId;
    final group = _isGroup(channel, selfId);
    final client = ref.accordClient;
    final serverKey = ref.readActiveServerKey();
    if (client == null || serverKey == null) return;
    if (group && selfId == null) return;
    final result = group
        ? await client.channels.removeRecipient(channel.id, selfId!)
        : await client.channels.delete(channel.id);
    if (!mounted) return;
    if (!result.ok) {
      showInfoSnack(
        context,
        result.errorMessageOr(
          group ? 'Failed to leave group' : 'Failed to close conversation',
        ),
      );
      return;
    }
    ref
        .read(dmChannelsControllerProvider(serverKey).notifier)
        .remove(channel.id);
    if (dmHome.channel?.id == channel.id) dmHome.showFriends();
  }

  void _menu(AccordChannel channel, Offset position) {
    final selfId = _selfId;
    final group = _isGroup(channel, selfId);
    final others = _others(channel, selfId);
    final user = !group && others.isNotEmpty ? others.first : null;
    final closeEntry = AccordMenuEntry(
      label: group ? 'Leave Group' : 'Close DM',
      icon: group ? AppIcons.logout : AppIcons.close,
      destructive: true,
      onSelected: () => _close(channel),
    );
    if (user != null) {
      showAccordDmUserContextMenu(
        context,
        ref,
        user,
        globalPosition: position,
        currentDmUserId: user.id,
        extraEntries: [const AccordMenuEntry.divider(), closeEntry],
      );
      return;
    }
    showAccordContextMenu(
      context,
      entries: [closeEntry],
      globalPosition: position,
      title: _channelTitle(channel, selfId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final serverKey = ref.watchActiveServerKey() ?? '';
    final channels = ref.watch(dmChannelsControllerProvider(serverKey));
    final previews = ref.read(dmChannelsControllerProvider(serverKey).notifier);
    final presences = ref.watch(activePresencesProvider);
    final readState = ref.watch(readStateControllerProvider(serverKey));
    final channelLevels = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.channelNotificationsFor(serverKey),
      ),
    );
    final cdnUrl = ref.watchCdnUrl();
    final selfId = ref.watchUserId();
    final missed = ref.watch(missedCallsControllerProvider);
    final sorted = [...?channels]
      ..sort((a, b) {
        final ta = previews.previewTimeFor(a.id);
        final tb = previews.previewTimeFor(b.id);
        if (ta == null && tb == null) return compareMessageIds(b.id, a.id);
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
    final openId = dmHome.channel?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 49,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.hairline)),
          ),
          alignment: Alignment.center,
          child: Material(
            color: colors.raised,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: const Key('dm-find-or-start'),
              borderRadius: BorderRadius.circular(8),
              onTap: _findOrStart,
              child: SizedBox(
                height: 30,
                width: double.infinity,
                child: Center(
                  child: Text(
                    'Find or start a conversation',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.dirtyWhite,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            children: [
              _DmNavRow(
                key: const Key('dm-home-friends'),
                icon: AppIcons.peopleAltOutlined,
                label: 'Friends',
                selected: openId == null,
                onTap: () {
                  dmHome.showFriends();
                  widget.onNavigate?.call();
                },
              ),
              const SizedBox(height: 8),
              Divider(height: 1, thickness: 1, color: colors.hairline),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 0, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Direct Messages',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colors.gray,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'Create DM',
                      child: InkWell(
                        key: const Key('dm-create'),
                        onTap: _findOrStart,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            AppIcons.add,
                            size: 16,
                            color: colors.interactive,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (channels == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              for (final channel in sorted)
                Builder(
                  builder: (context) {
                    final group = _isGroup(channel, selfId);
                    final others = _others(channel, selfId);
                    final other = group || others.isEmpty ? null : others.first;
                    final status = other == null
                        ? null
                        : accordPresenceStatus(presences, other.id);
                    final mentions = readState.visibleMentionCount(
                      channel.id,
                      channelLevels: channelLevels,
                    );
                    final unread =
                        readState.isUnreadVisible(
                          channel.id,
                          channelLevels: channelLevels,
                        ) ||
                        mentions > 0;
                    final missedCall = missed[channel.id];
                    return _DmListRow(
                      key: ValueKey('dm-row-${channel.id}'),
                      title: _channelTitle(channel, selfId),
                      subtitle: missedCall != null
                          ? missedCall.label
                          : group
                          ? '${others.length + 1} Members'
                          : null,
                      subtitleAlert: missedCall != null,
                      group: group,
                      avatarId: other?.id ?? channel.id,
                      avatarUrl: other == null
                          ? null
                          : accordAvatarUrl(other, cdnUrl),
                      status: status,
                      origin: _dmRemoteOrigin(channel, selfId),
                      selected: channel.id == openId,
                      unread: unread,
                      mentions: mentions,
                      onTap: () {
                        dmHome.open(channel);
                        widget.onNavigate?.call();
                      },
                      onClose: () => _close(channel),
                      onMenu: (position) => _menu(channel, position),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A 40 px navigation row of the DM column (Friends).
class _DmNavRow extends StatelessWidget {
  const _DmNavRow({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final color = selected ? colors.dirtyWhite : colors.gray;
    return Material(
      color: selected ? colors.selection : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: colors.hover,
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(icon, size: 24, color: color),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One conversation of the DM column: a 32 px avatar with its presence dot,
/// the name (and a member count for a group), the ✕ that closes it on hover.
class _DmListRow extends StatefulWidget {
  const _DmListRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.subtitleAlert = false,
    required this.group,
    required this.avatarId,
    required this.avatarUrl,
    required this.status,
    this.origin,
    required this.selected,
    required this.unread,
    this.mentions = 0,
    required this.onTap,
    required this.onClose,
    required this.onMenu,
  });

  /// The home domain of a remote (federated) participant.
  final String? origin;

  final String title;
  final String? subtitle;

  /// The subtitle is a missed call: red.
  final bool subtitleAlert;
  final bool group;
  final String avatarId;
  final String? avatarUrl;
  final String? status;
  final bool selected;
  final bool unread;
  final int mentions;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final ValueChanged<Offset> onMenu;

  /// The row read as one phrase, e.g. "bob, online, Unread, 2 mentions":
  /// unread, mentions and presence are drawn as weight and dots, which a
  /// screen reader can't see.
  String get semanticsLabel => [
    title,
    if (origin != null && origin!.isNotEmpty) 'homed on $origin',
    if (group)
      'group'
    else if (status != null)
      switch (status) {
        'online' => 'online',
        'idle' => 'idle',
        'dnd' => 'do not disturb',
        _ => 'offline',
      },
    if (unread || mentions > 0) 'Unread',
    if (mentions == 1) '1 mention' else if (mentions > 1) '$mentions mentions',
    if (subtitle != null) subtitle!,
  ].join(', ');

  @override
  State<_DmListRow> createState() => _DmListRowState();
}

class _DmListRowState extends State<_DmListRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final emphasised = widget.selected || widget.unread || _hover;
    final nameColor = emphasised ? colors.dirtyWhite : colors.gray;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onSecondaryTapUp: (d) => widget.onMenu(d.globalPosition),
        onLongPressStart: (d) => widget.onMenu(d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Material(
            color: widget.selected
                ? colors.selection
                : _hover
                ? colors.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: MergeSemantics(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: widget.onTap,
                child: Semantics(
                  button: true,
                  label: widget.semanticsLabel,
                  excludeSemantics: true,
                  child: SizedBox(
                    height: 42,
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        widget.group
                            ? CircleAvatar(
                                radius: 16,
                                backgroundColor: accordIdColor(widget.avatarId),
                                child: Icon(
                                  AppIcons.group,
                                  size: 18,
                                  color: accordOnColor(
                                    accordIdColor(widget.avatarId),
                                  ),
                                ),
                              )
                            : AccordMemberAvatar(
                                avatarUrl: widget.avatarUrl,
                                initial: accordInitial(widget.title),
                                status: widget.status,
                                radius: 16,
                                backgroundColor: accordIdColor(widget.avatarId),
                                statusRingColor: colors.foreground,
                              ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      widget.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        height: 20 / 16,
                                        color: nameColor,
                                      ),
                                    ),
                                  ),
                                  if (widget.origin != null) ...[
                                    const SizedBox(width: 6),
                                    RemoteOriginBadge(
                                      domain: widget.origin!,
                                      showDomain: false,
                                    ),
                                  ],
                                ],
                              ),
                              if (widget.subtitle != null)
                                Text(
                                  widget.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: widget.subtitleAlert
                                        ? colors.red
                                        : colors.gray,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_hover)
                          Tooltip(
                            message: widget.group ? 'Leave Group' : 'Close DM',
                            child: InkWell(
                              onTap: widget.onClose,
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  AppIcons.close,
                                  size: 16,
                                  color: colors.interactive,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the home shows beside the DM column: the Friends page, or the open
/// conversation (with the other person's profile at its right).
class DmHomeMain extends ConsumerStatefulWidget {
  const DmHomeMain({super.key, this.compact = false});

  /// The narrow layout: no Active Now column, a back affordance.
  final bool compact;

  @override
  ConsumerState<DmHomeMain> createState() => _DmHomeMainState();
}

class _DmHomeMainState extends ConsumerState<DmHomeMain> {
  @override
  void initState() {
    super.initState();
    dmHome.addListener(_changed);
  }

  @override
  void dispose() {
    dmHome.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final channel = dmHome.channel;
    if (channel == null) return _FriendsPage(compact: widget.compact);
    final voiceChannelId = ref.watch(
      voiceControllerProvider.select((v) => v.channelId),
    );
    return ValueListenableBuilder<bool>(
      valueListenable: voiceViewExpanded,
      builder: (context, expanded, _) => _DmConversation(
        key: ValueKey('dm-conversation-${channel.id}'),
        channel: channel,
        selfId: ref.watchUserId(),
        expanded: expanded && channel.id == voiceChannelId,
        showBack: widget.compact,
        onBack: dmHome.showFriends,
      ),
    );
  }
}

/// The Friends page: the header with its Online / All / Pending / Blocked
/// tabs and the "Add Friend" button, the searchable list (or the Add Friend
/// form), and the Active Now column at the right.
class _FriendsPage extends ConsumerStatefulWidget {
  const _FriendsPage({required this.compact});

  final bool compact;

  @override
  ConsumerState<_FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends ConsumerState<_FriendsPage> {
  List<AccordRelationship>? _relationships;
  final _search = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = ref.accordClient;
    if (client == null) {
      // Signed out: nothing will arrive, so no endless loading state.
      setState(() => _relationships = const []);
      return;
    }
    final result = await client.users.listRelationships();
    if (!mounted) return;
    final data = result.data;
    final relationships = data is List
        ? data.whereType<AccordRelationship>().toList()
        : <AccordRelationship>[];
    if (result.ok) ref.blockedUsers.sync(relationships);
    setState(() => _relationships = relationships);
  }

  Future<void> _mutate(
    Future<RestResult> Function() op,
    String failureFallback,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await op();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.ok ? null : result.errorMessageOr(failureFallback);
    });
    if (result.ok) await _load();
  }

  Future<void> _message(AccordUser user) =>
      openAccordDirectMessage(context, ref, user.id);

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final page = dmHome.page;
    final all = _relationships;
    final presences = ref.watch(activePresencesProvider);
    final query = _search.text.trim().toLowerCase();
    bool matches(AccordRelationship r) =>
        query.isEmpty || _userName(r.user).toLowerCase().contains(query);
    final friends = [
      for (final r in all ?? const <AccordRelationship>[])
        if (r.type == _Rel.friend && matches(r)) r,
    ];
    final shown = switch (page) {
      FriendsPage.online => [
        for (final r in friends)
          if (r.user != null &&
              accordPresenceStatus(presences, r.user!.id) != 'offline')
            r,
      ],
      FriendsPage.all => friends,
      FriendsPage.pending => [
        for (final r in all ?? const <AccordRelationship>[])
          if ((r.type == _Rel.pendingIn || r.type == _Rel.pendingOut) &&
              matches(r))
            r,
      ],
      FriendsPage.blocked => [
        for (final r in all ?? const <AccordRelationship>[])
          if (r.type == _Rel.blocked && matches(r)) r,
      ],
      FriendsPage.addFriend => const <AccordRelationship>[],
    };
    final label = switch (page) {
      FriendsPage.online => 'Online',
      FriendsPage.all => 'All friends',
      FriendsPage.pending => 'Pending',
      FriendsPage.blocked => 'Blocked',
      FriendsPage.addFriend => '',
    };
    final pendingCount = (all ?? const <AccordRelationship>[])
        .where((r) => r.type == _Rel.pendingIn)
        .length;
    // The reference client lists Pending only while there are requests, and
    // no Blocked tab; both stay reachable here while they hold someone.
    final pendingAny = (all ?? const <AccordRelationship>[]).any(
      (r) => r.type == _Rel.pendingIn || r.type == _Rel.pendingOut,
    );
    final blockedAny = (all ?? const <AccordRelationship>[]).any(
      (r) => r.type == _Rel.blocked,
    );

    Widget tab(FriendsPage value, String text, {int badge = 0}) {
      final selected = page == value;
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Material(
          color: selected ? colors.selection : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: Key('friends-tab-${value.name}'),
            borderRadius: BorderRadius.circular(8),
            hoverColor: colors.hover,
            onTap: () => dmHome.selectPage(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: selected ? colors.dirtyWhite : colors.interactive,
                    ),
                  ),
                  if (badge > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: colors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$badge',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    final addSelected = page == FriendsPage.addFriend;
    final header = Container(
      height: 49,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      child: Row(
        children: [
          Icon(AppIcons.peopleAltOutlined, size: 20, color: colors.interactive),
          const SizedBox(width: 8),
          Text(
            'Friends',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.dirtyWhite,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: colors.gray,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  tab(FriendsPage.online, 'Online'),
                  tab(FriendsPage.all, 'All'),
                  if (pendingAny || page == FriendsPage.pending)
                    tab(FriendsPage.pending, 'Pending', badge: pendingCount),
                  if (blockedAny || page == FriendsPage.blocked)
                    tab(FriendsPage.blocked, 'Blocked'),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Material(
                      color: addSelected
                          ? colors.primary.withValues(alpha: 0.24)
                          : colors.primary,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        key: const Key('friends-tab-addFriend'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => dmHome.selectPage(FriendsPage.addFriend),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            'Add Friend',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: addSelected
                                  ? const Color(0xFFA9BBFF)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Tooltip(
            message: 'New Group DM',
            child: InkWell(
              key: const Key('friends-new-group'),
              onTap: () async {
                final channel = await showDialog<AccordChannel>(
                  context: context,
                  builder: (_) => const _CreateGroupDialog(),
                );
                if (channel != null) dmHome.open(channel);
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  AppIcons.groupAddOutlined,
                  size: 24,
                  color: colors.interactive,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final list = page == FriendsPage.addFriend
        ? const _AddFriendPanel()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 20, 8),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.hairline),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        AppIcons.search,
                        size: 18,
                        color: colors.interactive,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const Key('friends-search'),
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(
                            fontSize: 16,
                            color: colors.dirtyWhite,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Search',
                            hintStyle: TextStyle(
                              fontSize: 16,
                              color: colors.gray,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 20, 16),
                child: Text(
                  '$label — ${shown.length}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.interactive,
                  ),
                ),
              ),
              Expanded(
                child: all == null
                    ? const LoadingView()
                    : shown.isEmpty
                    ? Center(
                        child: Text(switch (page) {
                          FriendsPage.online => "No one's around right now.",
                          FriendsPage.pending =>
                            'There are no pending friend requests.',
                          FriendsPage.blocked => "You haven't blocked anyone.",
                          _ => 'No friends yet.',
                        }, style: TextStyle(fontSize: 16, color: colors.gray)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final r = shown[i];
                          final user = r.user;
                          return _FriendListRow(
                            user: user,
                            name: _userName(user),
                            status: user == null
                                ? 'offline'
                                : accordPresenceStatus(presences, user.id),
                            relationship: r.type,
                            busy: _busy,
                            onMessage: user == null
                                ? null
                                : () => _message(user),
                            onAccept: user == null
                                ? null
                                : () => _mutate(
                                    () =>
                                        ref.accordClient!.users.putRelationship(
                                          user.id,
                                          {'type': _Rel.friend},
                                        ),
                                    'Could not accept that friend request.',
                                  ),
                            onRemove: user == null
                                ? null
                                : () => _mutate(
                                    () => ref.accordClient!.users
                                        .deleteRelationship(user.id),
                                    'Could not remove that relationship.',
                                  ),
                          );
                        },
                      ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: InlineError(_error!, centered: false),
                ),
            ],
          );

    return ColoredBox(
      color: colors.background,
      child: Column(
        children: [
          header,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: list),
                if (!widget.compact &&
                    MediaQuery.sizeOf(context).width >=
                        kDmSideColumnMinWindowWidth)
                  Container(
                    width: 420,
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: colors.hairline)),
                    ),
                    child: _ActiveNow(
                      friendIds: {
                        for (final r in friends)
                          if (r.user != null) r.user!.id,
                      },
                      users: {
                        for (final r in friends)
                          if (r.user != null) r.user!.id: r.user!,
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One friend: a 62 px row (separated by hairlines) with the avatar, name and
/// status, and at the right the round Message and More buttons — or Accept /
/// Ignore for a request, Unblock for a blocked user.
class _FriendListRow extends ConsumerStatefulWidget {
  const _FriendListRow({
    required this.user,
    required this.name,
    required this.status,
    required this.relationship,
    required this.busy,
    required this.onMessage,
    required this.onAccept,
    required this.onRemove,
  });

  final AccordUser? user;
  final String name;
  final String status;
  final int relationship;
  final bool busy;
  final VoidCallback? onMessage;
  final VoidCallback? onAccept;
  final VoidCallback? onRemove;

  @override
  ConsumerState<_FriendListRow> createState() => _FriendListRowState();
}

class _FriendListRowState extends ConsumerState<_FriendListRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final user = widget.user;
    String statusLabel() => switch (widget.relationship) {
      _Rel.pendingIn => 'Incoming Friend Request',
      _Rel.pendingOut => 'Outgoing Friend Request',
      _Rel.blocked => 'Blocked',
      _ => switch (widget.status) {
        'online' => 'Online',
        'idle' => 'Idle',
        'dnd' => 'Do Not Disturb',
        _ => 'Offline',
      },
    };
    Widget round(
      String tooltip,
      IconData icon,
      VoidCallback? onTap, {
      Color? color,
    }) => Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: _hover ? colors.background : Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.busy ? null : onTap,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(icon, size: 20, color: color ?? colors.interactive),
            ),
          ),
        ),
      ),
    );
    final actions = switch (widget.relationship) {
      _Rel.pendingIn => [
        round('Accept', AppIcons.check, widget.onAccept, color: colors.green),
        round('Ignore', AppIcons.close, widget.onRemove, color: colors.red),
      ],
      _Rel.pendingOut => [round('Cancel', AppIcons.close, widget.onRemove)],
      _Rel.blocked => [
        round('Unblock', AppIcons.personRemove, widget.onRemove),
      ],
      _ => [
        round('Message', AppIcons.chatBubble, widget.onMessage),
        Builder(
          builder: (context) => round('More', AppIcons.moreVert, () {
            if (user == null) return;
            final box = context.findRenderObject() as RenderBox?;
            showAccordDmUserContextMenu(
              context,
              ref,
              user,
              globalPosition: box?.localToGlobal(Offset(0, box.size.height)),
            );
          }),
        ),
      ],
    };
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _hover ? colors.hover : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onMessage,
          child: Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.hairline)),
            ),
            child: Row(
              children: [
                AccordMemberAvatar(
                  avatarUrl: accordAvatarUrl(user, ref.watchCdnUrl()),
                  initial: accordInitial(widget.name),
                  status: widget.relationship == _Rel.friend
                      ? widget.status
                      : null,
                  radius: 16,
                  backgroundColor: accordAvatarColor(user, user?.id ?? ''),
                  statusRingColor: colors.background,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 20 / 16,
                          color: colors.dirtyWhite,
                        ),
                      ),
                      Text(
                        statusLabel(),
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.interactive,
                        ),
                      ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Add Friend": the reference client's form — a title, a line of help, and
/// a username field with "Send Friend Request" inside it.
class _AddFriendPanel extends ConsumerStatefulWidget {
  const _AddFriendPanel();

  @override
  ConsumerState<_AddFriendPanel> createState() => _AddFriendPanelState();
}

class _AddFriendPanelState extends ConsumerState<_AddFriendPanel> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final client = ref.accordClient;
    final username = _controller.text.trim();
    if (client == null || username.isEmpty) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    final search = await client.users.searchUsers(username);
    final users = search.data is List
        ? (search.data as List).whereType<AccordUser>()
        : const <AccordUser>[];
    final match = users.firstWhereOrNull(
      (u) => u.username.toLowerCase() == username.toLowerCase(),
    );
    if (match == null) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ok = false;
        _result = "Hm, didn't work. Double check that the username is correct.";
      });
      return;
    }
    final result = await client.users.putRelationship(match.id, {
      'type': _Rel.friend,
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = result.ok;
      _result = result.ok
          ? 'Success! Your friend request to ${match.username} was sent.'
          : result.errorMessageOr('Failed to send the friend request.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 30, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add Friend',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: colors.dirtyWhite,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You can add friends with their Daccord usernames.',
            style: TextStyle(fontSize: 14, color: colors.interactive),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _result == null
                    ? colors.hairline
                    : (_ok ? colors.green : colors.red),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('add-friend-username'),
                    controller: _controller,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _send(),
                    style: TextStyle(fontSize: 16, color: colors.dirtyWhite),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Enter a username',
                      hintStyle: TextStyle(fontSize: 16, color: colors.gray),
                    ),
                  ),
                ),
                SizedBox(
                  height: 32,
                  child: FilledButton(
                    key: const Key('add-friend-send'),
                    onPressed: _busy || _controller.text.trim().isEmpty
                        ? null
                        : _send,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      disabledBackgroundColor: colors.primary.withValues(
                        alpha: 0.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Send Friend Request',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_result != null) ...[
            const SizedBox(height: 8),
            Text(
              _result!,
              style: TextStyle(
                fontSize: 14,
                color: _ok ? colors.green : colors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Active Now": friends who are in a voice channel right now, one card each
/// with the channel; "It's quiet for now…" when there are none.
class _ActiveNow extends ConsumerWidget {
  const _ActiveNow({required this.friendIds, required this.users});

  final Set<String> friendIds;
  final Map<String, AccordUser> users;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final serverKey = ref.watchActiveServerKey() ?? '';
    final states = ref.watch(voiceStatesControllerProvider(serverKey));
    final cdnUrl = ref.watchCdnUrl();
    final active = <(AccordUser, AccordVoiceState)>[];
    for (final bucket in states.values) {
      for (final state in bucket.values) {
        final user = users[state.userId];
        if (user != null && friendIds.contains(state.userId)) {
          active.add((user, state));
        }
      }
    }
    final card = BoxDecoration(
      color: colors.raised,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: colors.hairline),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Text(
          'Active Now',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: colors.dirtyWhite,
          ),
        ),
        const SizedBox(height: 16),
        if (active.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: card,
            child: Column(
              children: [
                Text(
                  "It's quiet for now...",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.dirtyWhite,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'When a friend starts an activity — like hanging out on '
                  "voice — we'll show it here!",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: colors.interactive),
                ),
              ],
            ),
          )
        else
          for (final (user, state) in active)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: card,
                child: Row(
                  children: [
                    AccordMemberAvatar(
                      avatarUrl: accordAvatarUrl(user, cdnUrl),
                      initial: accordInitial(_userName(user)),
                      radius: 16,
                      backgroundColor: accordAvatarColor(user, user.id),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userName(user),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colors.dirtyWhite,
                            ),
                          ),
                          Text(
                            'In a Voice Channel',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.interactive,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (state.selfStream)
                      Icon(
                        AppIcons.desktopWindows,
                        size: 16,
                        color: colors.red,
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

/// The narrowest window that shows the DM home's right column (Active Now
/// beside the friends list, the profile beside a 1:1 conversation).
const double kDmSideColumnMinWindowWidth = 1000;

/// The profile of the other person in a 1:1 conversation, at its right as in
/// the reference client: banner, 80 px avatar, name and username, when they
/// joined, and "View Full Profile".
class _DmProfilePanel extends ConsumerWidget {
  const _DmProfilePanel({required this.user});

  final AccordUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final cdnUrl = ref.watchCdnUrl();
    final presences = ref.watch(activePresencesProvider);
    final name = _userName(user);
    final joined = parseServerTimestamp(user.createdAt)?.toLocal();
    final banner = accordAvatarColor(user, user.id);
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(left: BorderSide(color: colors.hairline)),
      ),
      padding: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(
          color: colors.raised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 162,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(height: 104, color: banner),
                  Positioned(
                    left: 16,
                    top: 56,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colors.raised,
                        shape: BoxShape.circle,
                      ),
                      child: AccordMemberAvatar(
                        avatarUrl: accordAvatarUrl(user, cdnUrl),
                        initial: accordInitial(name),
                        status: accordPresenceStatus(presences, user.id),
                        radius: 40,
                        backgroundColor: banner,
                        statusRingColor: colors.raised,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.dirtyWhite,
                    ),
                  ),
                  if (user.username.isNotEmpty)
                    Text(
                      user.username,
                      style: TextStyle(fontSize: 14, color: colors.dirtyWhite),
                    ),
                  if (joined != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Member Since',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.dirtyWhite,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${joined.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][joined.month - 1]} ${joined.year}',
                      style: TextStyle(fontSize: 14, color: colors.dirtyWhite),
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: 40,
                child: TextButton(
                  key: const Key('dm-view-full-profile'),
                  onPressed: () =>
                      showAccordUserProfile(context, user, cdnUrl: cdnUrl),
                  style: TextButton.styleFrom(
                    backgroundColor: colors.selection.withValues(alpha: 0.12),
                    foregroundColor: colors.dirtyWhite,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'View Full Profile',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
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
