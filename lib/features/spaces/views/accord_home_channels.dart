part of 'accord_home.dart';

class _ChannelList extends ConsumerStatefulWidget {
  const _ChannelList({
    required this.spaceId,
    required this.spaceName,
    required this.channels,
    required this.selectedChannelId,
    required this.onSelect,
    required this.onSearchSelect,
  });

  final String? spaceId;
  final String? spaceName;
  final List<AccordChannel>? channels;
  final String? selectedChannelId;
  final ValueChanged<String> onSelect;
  final ValueChanged<AccordSearchSelection> onSearchSelect;

  @override
  ConsumerState<_ChannelList> createState() => _ChannelListState();
}

class _ChannelListState extends ConsumerState<_ChannelList> {
  /// What to render in place of the channel list while there is none.
  ///
  /// A null channel list can mean loading, a failed request, or a successfully
  /// loaded account with no spaces. Only the loading case should spin.
  Widget _emptyState(BuildContext context, {required String? spaceId}) {
    final serverKey = ref.watchActiveServerKey() ?? '';

    if (spaceId != null &&
        ref.watch(channelsLoadFailedProvider(serverKey, spaceId))) {
      return ServerUnreachable(
        title: "Couldn't load channels",
        message: 'Something went wrong fetching this space’s channels.',
        onRetry: () {
          ref
              .read(channelsLoadFailedProvider(serverKey, spaceId).notifier)
              .set(false);
          ref.invalidate(accordChannelsControllerProvider(serverKey, spaceId));
        },
      );
    }

    if (ref.watch(spacesLoadFailedProvider(serverKey))) {
      return ServerUnreachable(
        title: "Couldn't load your spaces",
        message: 'Something went wrong fetching this server’s space list.',
        onRetry: () {
          final client = ref.accordClient;
          if (client == null) return;
          unawaited(ref.read(retryLoadSpacesProvider)(client, serverKey));
        },
      );
    }

    final connection = ref.watch(
      connectionsControllerProvider.select((connections) => connections.active),
    );
    final status = connection?.status ?? ConnectionStatus.disconnected;
    if (status.isUnreachable) {
      return ServerUnreachable(
        onRetry: () => ref.accordClient?.ensureConnected(),
      );
    }
    // Auth seeds an empty cache before READY. Wait for the authoritative space
    // fetch before treating that cache as an account with no memberships.
    if (spaceId == null &&
        status == ConnectionStatus.ready &&
        connection?.spacesReady == true &&
        ref.watch(spacesControllerProvider)?.isEmpty == true) {
      final isAdmin = ref.watchIsAdmin();
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.gridViewOutlined, size: 40),
              const SizedBox(height: 12),
              Text(
                'No spaces yet',
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'You haven’t joined any spaces on this server.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => showAddServerDialog(context),
                child: const Text('Join with invite'),
              ),
              TextButton(
                onPressed: () => showAccordDiscovery(context),
                child: const Text('Explore public spaces'),
              ),
              if (isAdmin) ...[
                const SizedBox(height: 8),
                const Text(
                  'You can manage this server without joining a space.',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: () => context.push('/admin'),
                  child: const Text('Server administration'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return const LoadingView();
  }

  void _toggleCollapsed(String categoryId) {
    final spaceId = widget.spaceId;
    if (spaceId == null) return;
    final serverKey = ref.readActiveServerKey();
    if (serverKey == null) return;
    final settings = ref.read(settingsControllerProvider);
    ref
        .read(settingsControllerProvider.notifier)
        .setCategoryCollapsed(
          serverKey,
          spaceId,
          categoryId,
          !settings.isCategoryCollapsed(serverKey, spaceId, categoryId),
        );
  }

  /// The space menu under its name, as in other chat apps: invite, settings,
  /// create channel or category, mark as read, then the per-server entries
  /// (mute, hide, leave) shared with the rail's menu.
  Future<void> _openSpaceMenu(
    BuildContext anchorContext, {
    required AccordSpace space,
    required List<AccordChannel>? channels,
    required bool canInvite,
    required bool canManage,
    required bool canManageChannels,
  }) {
    final serverKey = ref.read(connectionsControllerProvider).activeKey;
    if (serverKey == null) return Future.value();
    final box = anchorContext.findRenderObject() as RenderBox?;
    final anchor = box == null
        ? null
        : box.localToGlobal(Offset(0, box.size.height));
    const duplicated = {'Invite people', 'Space settings'};
    return showAccordContextMenu(
      context,
      globalPosition: anchor,
      title: space.name,
      entries: [
        if (canInvite)
          AccordMenuEntry(
            label: 'Invite people',
            icon: AppIcons.personAddOutlined,
            onSelected: () => showAccordInvites(context, spaceId: space.id),
          ),
        if (canManage)
          AccordMenuEntry(
            label: 'Space settings',
            icon: AppIcons.settingsOutlined,
            onSelected: () =>
                showAccordSpaceSettings(context, spaceId: space.id),
          ),
        if (canManageChannels) ...[
          AccordMenuEntry(
            label: 'Create channel',
            icon: AppIcons.addCircleOutline,
            onSelected: () =>
                showCreateChannelDialog(context, spaceId: space.id),
          ),
          AccordMenuEntry(
            label: 'Create category',
            icon: AppIcons.createNewFolderOutlined,
            onSelected: () => showCreateChannelDialog(
              context,
              spaceId: space.id,
              initialType: 'category',
            ),
          ),
          if (channels != null)
            AccordMenuEntry(
              label: 'Reorder channels',
              icon: AppIcons.reorder,
              onSelected: () => showAccordChannelReorder(
                context,
                spaceId: space.id,
                channels: channels,
              ),
            ),
        ],
        AccordMenuEntry(
          label: 'Mark as read',
          icon: AppIcons.markChatReadOutlined,
          enabled: channels != null,
          onSelected: () {
            for (final channel in channels ?? const <AccordChannel>[]) {
              if (channel.type == 'category') continue;
              markChannelRead(
                ref,
                channel.id,
                fallbackMessageId: channel.lastMessageId,
              );
            }
          },
        ),
        const AccordMenuEntry.divider(),
        for (final entry in _serverActionEntries(
          context,
          ref,
          space,
          serverKey,
        ))
          if (!duplicated.contains(entry.label)) entry,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final spaceId = widget.spaceId;
    final spaceName = widget.spaceName;
    final channels = widget.channels;
    final selectedChannelId = widget.selectedChannelId;
    final onSelect = widget.onSelect;
    final colors = BonfireThemeExtension.of(context);
    final id = spaceId;
    final space = id == null
        ? null
        : ref.watch(
            spacesControllerProvider.select(
              (s) => s?.firstWhereOrNull((sp) => sp.id == id),
            ),
          );
    final cdnUrl = ref.watchCdnUrl();
    final bannerUrl = space == null
        ? null
        : accordSpaceBannerUrl(space, cdnUrl);

    // Collapsed categories are persisted per-space via SettingsController
    // (mirrors the reference client's Config.set_category_collapsed).
    final collapsed = id == null
        ? const <String>{}
        : ref.watch(
            settingsControllerProvider.select(
              (s) => s.collapsedCategories[id]?.toSet() ?? const <String>{},
            ),
          );

    // Show the settings gear only to members who can manage the space or roles,
    // and the channel-management affordances to those with manage_channels.
    var canManage = false;
    var canManageChannels = false;
    var canInvite = false;
    if (id != null) {
      final perms = ref.watchAccordPermissions(space, id);
      canManage = canManageSpaceSettings(perms);
      canManageChannels = accordHasPermission(
        perms,
        AccordPermission.manageChannels,
      );
      canInvite = accordHasPermission(perms, AccordPermission.createInvites);
    }

    final header = _SpaceHeader(
      name: spaceName ?? 'Select a space',
      origin: space?.origin,
      canInvite: canInvite && id != null,
      onInvite: id == null
          ? null
          : () => showAccordInvites(context, spaceId: id),
      onMenu: id == null || space == null
          ? null
          : (anchorContext) => _openSpaceMenu(
              anchorContext,
              space: space,
              channels: channels,
              canInvite: canInvite,
              canManage: canManage,
              canManageChannels: canManageChannels,
            ),
    );

    return ColoredBox(
      color: colors.foreground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The banner, when there is one, sits behind the header and fades
          // into the column.
          if (bannerUrl != null)
            SizedBox(
              height: 135,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: bannerUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.6),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.6],
                      ),
                    ),
                  ),
                  Align(alignment: Alignment.topCenter, child: header),
                ],
              ),
            )
          else
            header,
          if (id != null)
            WelcomeScreenGate(spaceId: id, onOpenChannel: onSelect),
          if (id != null) SpaceEventsEntry(spaceId: id),
          Expanded(
            child: channels == null
                ? _emptyState(context, spaceId: id)
                : (canManageChannels && id != null)
                ? _ChannelDragList(
                    spaceId: id,
                    channels: channels,
                    selectedChannelId: selectedChannelId,
                    onSelect: onSelect,
                    collapsed: collapsed,
                    onToggleCollapsed: _toggleCollapsed,
                    canInvite: canInvite,
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: _buildChannelEntries(
                      context,
                      spaceId: id,
                      channels: channels,
                      selectedChannelId: selectedChannelId,
                      onSelect: onSelect,
                      canManageChannels: canManageChannels,
                      canInvite: canInvite,
                      collapsed: collapsed,
                      onToggleCollapsed: _toggleCollapsed,
                      unread: _visibleUnreadChannelIds(ref, channels),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The 49 px header of the channel column: the space name (16 px semibold)
/// with a caret that opens the space menu and turns into a cross while it is
/// open, and the invite button at the right; a hairline underneath.
class _SpaceHeader extends StatefulWidget {
  const _SpaceHeader({
    required this.name,
    required this.origin,
    required this.canInvite,
    required this.onInvite,
    required this.onMenu,
  });

  final String name;
  final String? origin;
  final bool canInvite;
  final VoidCallback? onInvite;

  /// Opens the space menu anchored under the widget of [anchorContext]; the
  /// returned future completes when the menu closes.
  final Future<void> Function(BuildContext anchorContext)? onMenu;

  @override
  State<_SpaceHeader> createState() => _SpaceHeaderState();
}

class _SpaceHeaderState extends State<_SpaceHeader> {
  bool _menuOpen = false;

  Future<void> _open(BuildContext anchorContext) async {
    final onMenu = widget.onMenu;
    if (onMenu == null) return;
    setState(() => _menuOpen = true);
    try {
      await onMenu(anchorContext);
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      key: const Key('space-header'),
      height: 49,
      padding: const EdgeInsets.fromLTRB(8, 9, 8, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Builder(
              builder: (nameContext) => InkWell(
                onTap: widget.onMenu == null ? null : () => _open(nameContext),
                borderRadius: BorderRadius.circular(8),
                hoverColor: colors.hover,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.name,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall!
                              .copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: colors.dirtyWhite,
                              ),
                        ),
                      ),
                      if (widget.origin != null) ...[
                        const SizedBox(width: 6),
                        RemoteOriginBadge(domain: widget.origin),
                      ],
                      if (widget.onMenu != null) ...[
                        const SizedBox(width: 4),
                        Icon(
                          _menuOpen ? AppIcons.close : AppIcons.expandMore,
                          key: const Key('space-header-caret'),
                          size: 14,
                          color: colors.dirtyWhite,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.canInvite && widget.onInvite != null)
            Tooltip(
              message: 'Invite',
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  key: const Key('space-header-invite'),
                  onTap: widget.onInvite,
                  borderRadius: BorderRadius.circular(8),
                  hoverColor: colors.hover,
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Icon(
                      AppIcons.personAdd,
                      size: 20,
                      color: colors.dirtyWhite,
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

/// The channel ids among [channels] that are unread and not silenced on the
/// active connection, for keeping them in view under a collapsed category.
Set<String> _visibleUnreadChannelIds(
  WidgetRef ref,
  Iterable<AccordChannel> channels,
) {
  final activeKey = ref.watch(
    connectionsControllerProvider.select((s) => s.activeKey),
  );
  if (activeKey == null) return const {};
  // `channelNotificationsFor` builds a fresh map, so the stored map is
  // watched instead.
  ref.watch(settingsControllerProvider.select((s) => s.channelNotifications));
  final levels = ref
      .read(settingsControllerProvider)
      .channelNotificationsFor(activeKey);
  return ref.watch(
    readStateControllerProvider(activeKey).select(
      (readState) => {
        for (final channel in channels)
          if (channel.type != 'category' &&
              readState.isUnreadVisible(channel.id, channelLevels: levels))
            channel.id,
      },
    ),
  );
}

/// A thin draggable divider between the channel list and the message pane that
/// resizes the channel column. Shows a horizontal-resize cursor on hover and
/// highlights while being dragged.
class _ChannelListResizeHandle extends StatefulWidget {
  const _ChannelListResizeHandle({
    required this.onDragDelta,
    required this.onDragEnd,
  });

  final ValueChanged<double> onDragDelta;
  final VoidCallback onDragEnd;

  @override
  State<_ChannelListResizeHandle> createState() =>
      _ChannelListResizeHandleState();
}

class _ChannelListResizeHandleState extends State<_ChannelListResizeHandle> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => setState(() => _active = true),
        onHorizontalDragUpdate: (d) => widget.onDragDelta(d.delta.dx),
        onHorizontalDragEnd: (_) {
          widget.onDragEnd();
          setState(() => _active = false);
        },
        child: SizedBox(
          width: kChannelListHandleWidth,
          child: Center(
            child: Container(
              width: 2,
              color: _active ? colors.primary : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}

/// Groups [channels] into uncategorized channels (rendered first) followed by
/// each category with its child channels. When [canManageChannels] is true,
/// categories show an inline "add channel" button and channels an edit button.
/// [collapsed] lists category IDs whose children should be hidden; tapping a
/// category header calls [onToggleCollapsed] to flip its state.
List<Widget> _buildChannelEntries(
  BuildContext context, {
  required String? spaceId,
  required List<AccordChannel> channels,
  required String? selectedChannelId,
  required ValueChanged<String> onSelect,
  required bool canManageChannels,
  required bool canInvite,
  required Set<String> collapsed,
  required ValueChanged<String> onToggleCollapsed,
  required Set<String> unread,
}) {
  final categories = channels.where((c) => c.type == 'category').toList();
  final leaves = channels.where((c) => c.type != 'category').toList();
  final byParent = <String?, List<AccordChannel>>{};
  for (final c in leaves) {
    byParent.putIfAbsent(c.parentId, () => []).add(c);
  }

  Widget tile(AccordChannel channel) => _channelTile(
    context,
    channel,
    spaceId: spaceId,
    selected: channel.id == selectedChannelId,
    canManageChannels: canManageChannels,
    canInvite: canInvite,
    onTap: () => onSelect(channel.id),
  );

  final entries = <Widget>[];
  for (final channel in byParent[null] ?? const <AccordChannel>[]) {
    entries.add(tile(channel));
  }
  for (final category in categories) {
    final isCollapsed = collapsed.contains(category.id);
    entries.add(
      _categoryHeader(
        context,
        category,
        spaceId: spaceId,
        canManageChannels: canManageChannels,
        collapsed: isCollapsed,
        onToggle: () => onToggleCollapsed(category.id),
      ),
    );
    // A collapsed category keeps its selected and unread channels in view.
    for (final channel in byParent[category.id] ?? const <AccordChannel>[]) {
      if (!isCollapsed ||
          channel.id == selectedChannelId ||
          unread.contains(channel.id)) {
        entries.add(tile(channel));
      }
    }
  }
  return entries;
}
