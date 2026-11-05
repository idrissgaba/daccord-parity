part of 'accord_home.dart';

/// What the space menus need to know about the signed-in user in [space],
/// read once per menu from the space's own connection, so actions hit the
/// right server even when it isn't the active one.
class _SpaceMenuFacts {
  _SpaceMenuFacts(WidgetRef ref, this.space, this.serverKey) {
    final conn = ref
        .read(connectionsControllerProvider)
        .connectionFor(serverKey);
    final session = conn?.session;
    final userId = session?.userId;
    final members = ref.read(
      accordMembersControllerProvider(serverKey, space.id),
    );
    final preview = ref.read(rolePreviewControllerProvider);
    perms = accordEffectivePermissions(
      space: space,
      selfMember: userId == null ? null : members?[userId],
      roles: space.roles,
      currentUserId: userId ?? '',
      currentUserIsAdmin: session?.isAdmin ?? false,
      previewRoleId: preview?.spaceId == space.id ? preview?.roleId : null,
    );
    isOwner = userId != null && space.ownerId == userId;
    selfMember = userId == null ? null : members?[userId];
    final settings = ref.read(settingsControllerProvider);
    muted = settings.isSpaceMuted(serverKey, space.id);
    muteUntil = settings.muteExpiry(serverKey, space.id);
    level =
        settings.spaceNotificationLevel(serverKey, space.id) ??
        spaceDefaultLevel(space);
    suppressEveryone = settings.suppressesEveryoneIn(serverKey, space.id);
    suppressRoles = settings.suppressesRolesIn(serverKey, space.id);
    hideMuted = settings.hidesMutedChannels(serverKey, space.id);
    unreadChannels = [
      for (final e in ref.read(readStateControllerProvider(serverKey)).entries.values)
        if (e.spaceId == space.id) e.channelId,
    ];
  }

  final AccordSpace space;
  final String serverKey;
  late final Set<String> perms;
  late final bool isOwner;
  late final AccordMember? selfMember;
  late final bool muted;
  late final DateTime? muteUntil;
  late final String level;
  late final bool suppressEveryone;
  late final bool suppressRoles;
  late final bool hideMuted;
  late final List<String> unreadChannels;

  bool has(String permission) => accordHasPermission(perms, permission);
  bool get canInvite => has(AccordPermission.createInvites);
  bool get canManageChannels => has(AccordPermission.manageChannels);
  bool get canManageEvents => has(AccordPermission.manageEvents);
  bool get canChangeNickname => has(AccordPermission.changeNickname);
  bool get canManage => canManageSpaceSettings(perms);
}

/// "Mark as Read" for a whole space — greyed out when nothing is unread, as
/// the reference client keeps it.
AccordMenuEntry _markSpaceReadEntry(WidgetRef ref, _SpaceMenuFacts f) =>
    AccordMenuEntry(
      label: 'Mark as Read',
      onSelected: f.unreadChannels.isEmpty
          ? null
          : () {
              for (final id in f.unreadChannels) {
                markChannelRead(ref, id, serverKey: f.serverKey);
              }
            },
    );

/// Mute Server › (durations), or Unmute Server once muted.
AccordMenuEntry _muteSpaceEntry(
  BuildContext context,
  WidgetRef ref,
  _SpaceMenuFacts f,
) {
  final ctl = ref.read(settingsControllerProvider.notifier);
  if (f.muted) {
    return AccordMenuEntry(
      label: 'Unmute Server',
      subtitle: mutedUntilLabel(context, f.muteUntil),
      onSelected: () => ctl.setSpaceMuted(f.serverKey, f.space.id, false),
    );
  }
  return AccordMenuEntry(
    label: 'Mute Server',
    onSelected: () => ctl.setSpaceMuted(f.serverKey, f.space.id, true),
    submenu: muteSubmenu(
      (duration) => ctl.setSpaceMuted(
        f.serverKey,
        f.space.id,
        true,
        until: untilFrom(duration),
      ),
    ),
  );
}

/// The server's notification choices: All Messages / Only @mentions / Nothing,
/// then the suppressions Accord can honour. "Suppress Highlights", "Mute New
/// Events" and "Mobile Push Notifications" have no Accord counterpart (§4).
List<AccordMenuEntry> _spaceNotificationChoices(
  WidgetRef ref,
  _SpaceMenuFacts f,
) {
  final ctl = ref.read(settingsControllerProvider.notifier);
  return [
    for (final level in const [
      AccordSettings.channelNotifAll,
      AccordSettings.channelNotifMentions,
      AccordSettings.channelNotifNothing,
    ])
      AccordMenuEntry(
        label: notificationLevelLabel(level),
        radio: f.level == level,
        onSelected: () => ctl.setSpaceNotificationLevel(
          f.serverKey,
          f.space.id,
          level == spaceDefaultLevel(f.space) ? null : level,
        ),
      ),
    const AccordMenuEntry.divider(),
    AccordMenuEntry(
      label: 'Suppress @everyone and @here',
      checked: f.suppressEveryone,
      onSelected: () => ctl.setSpaceSuppressEveryone(
        f.serverKey,
        f.space.id,
        !f.suppressEveryone,
      ),
    ),
    AccordMenuEntry(
      label: 'Suppress All Role @mentions',
      checked: f.suppressRoles,
      onSelected: () =>
          ctl.setSpaceSuppressRoles(f.serverKey, f.space.id, !f.suppressRoles),
    ),
  ];
}

AccordMenuEntry _hideMutedEntry(WidgetRef ref, _SpaceMenuFacts f) =>
    AccordMenuEntry(
      label: 'Hide Muted Channels',
      checked: f.hideMuted,
      onSelected: () => ref
          .read(settingsControllerProvider.notifier)
          .setHideMutedChannels(f.serverKey, f.space.id, !f.hideMuted),
    );

/// Server Settings ›: one row per settings page the user may open, in the
/// reference client's order. Pages Accord lacks (Server Tag, Engagement, Boost
/// Perks, Stickers, Members, Access, App Directory, Safety Setup, Community,
/// Template) are omitted (§4).
List<AccordMenuEntry> _serverSettingsSubmenu(
  BuildContext context,
  _SpaceMenuFacts f,
) {
  final id = f.space.id;
  return [
    if (f.has(AccordPermission.manageSpace))
      AccordMenuEntry(
        label: 'Server Profile',
        onSelected: () => showAccordSpaceSettings(context, spaceId: id),
      ),
    if (f.has(AccordPermission.manageEmojis))
      AccordMenuEntry(
        label: 'Emoji',
        onSelected: () => showAccordEmojiManagement(context, spaceId: id),
      ),
    if (f.has(AccordPermission.manageSoundboard))
      AccordMenuEntry(
        label: 'Soundboard',
        onSelected: () =>
            showAccordSoundboard(context, spaceId: id, canManage: true),
      ),
    if (f.has(AccordPermission.manageRoles))
      AccordMenuEntry(
        label: 'Roles',
        onSelected: () => showAccordRoleManagement(context, spaceId: id),
      ),
    if (f.has(AccordPermission.manageSpace))
      AccordMenuEntry(
        label: 'Invites',
        onSelected: () => showAccordInvites(context, spaceId: id),
      ),
    if (f.has(AccordPermission.manageWebhooks))
      AccordMenuEntry(
        label: 'Integrations',
        onSelected: () => showAccordWebhooks(context, spaceId: id),
      ),
    if (f.has(AccordPermission.viewAuditLog))
      AccordMenuEntry(
        label: 'Audit Log',
        onSelected: () => showAccordAuditLog(context, spaceId: id),
      ),
    if (f.has(AccordPermission.banMembers))
      AccordMenuEntry(
        label: 'Bans',
        onSelected: () => showAccordBanList(context, spaceId: id),
      ),
    if (f.has(AccordPermission.manageSpace))
      AccordMenuEntry(
        label: 'AutoMod',
        onSelected: () => showAutomodPanel(context, id),
      ),
  ];
}

/// "Edit Per-server Profile": the nickname this account shows in the space.
AccordMenuEntry? _perServerProfileEntry(
  BuildContext context,
  WidgetRef ref,
  _SpaceMenuFacts f,
) {
  final member = f.selfMember;
  if (member == null || !f.canChangeNickname) return null;
  return AccordMenuEntry(
    label: 'Edit Per-server Profile',
    onSelected: () => editMemberNickname(
      context,
      ref,
      serverKey: f.serverKey,
      spaceId: f.space.id,
      member: member,
      self: true,
    ),
  );
}

/// The create entries (Create Channel, Create Category, Create Event).
List<AccordMenuEntry> _createEntries(
  BuildContext context,
  _SpaceMenuFacts f,
) => [
  if (f.canManageChannels) ...[
    AccordMenuEntry(
      label: 'Create Channel',
      onSelected: () => showCreateChannelDialog(context, spaceId: f.space.id),
    ),
    AccordMenuEntry(
      label: 'Create Category',
      onSelected: () => showCreateChannelDialog(
        context,
        spaceId: f.space.id,
        initialType: 'category',
      ),
    ),
  ],
  if (f.canManageEvents)
    AccordMenuEntry(
      label: 'Create Event',
      onSelected: () => showEventEditor(context, spaceId: f.space.id),
    ),
];

/// Leave Server (red) for anyone but the owner, then the entries only
/// Accord has: leaving with your data deleted, hiding the space from the rail
/// without leaving, and removing the whole connection (a server hosts several
/// spaces; nothing is deleted there).
List<AccordMenuEntry> _leaveEntries(
  BuildContext context,
  WidgetRef ref,
  _SpaceMenuFacts f,
) => [
  if (!f.isOwner) ...[
    AccordMenuEntry(
      label: 'Leave Server',
      destructive: true,
      onSelected: () => leaveSpace(context, ref, f.space, f.serverKey),
    ),
    AccordMenuEntry(
      label: 'Leave & Delete Data',
      destructive: true,
      sheetSubtitle: 'Permanently delete your messages & data here',
      onSelected: () => leaveSpace(
        context,
        ref,
        f.space,
        f.serverKey,
        deleteData: true,
      ),
    ),
  ],
  AccordMenuEntry(
    label: 'Hide Server',
    sheetSubtitle: 'Remove from your rail without leaving',
    onSelected: () => ref
        .read(settingsControllerProvider.notifier)
        .setSpaceHidden(f.serverKey, f.space.id, true),
  ),
  AccordMenuEntry(
    label: 'Remove Server',
    destructive: true,
    sheetSubtitle: 'Disconnect & remove from this app — works even when offline',
    onSelected: () => _removeServer(context, ref, f.serverKey),
  ),
];

AccordMenuEntry _copySpaceIdEntry(_SpaceMenuFacts f) => AccordMenuEntry(
  label: 'Copy Server ID',
  icon: AppIcons.idCard,
  onSelected: () => Clipboard.setData(ClipboardData(text: f.space.id)),
);

/// The rail icon's menu, in the reference client's order: Mark as Read ·
/// Invite to Server · Mute Server ›, Notification Settings ›, Hide Muted
/// Channels ☐ · Server Settings ›, Edit Per-server Profile · Create Channel,
/// Create Category, Create Event · Move to… › · Leave Server · Copy Server
/// ID. [moveTo] is the rail's Move to… submenu (order and folders).
List<AccordMenuEntry> _spaceIconMenuEntries(
  BuildContext context,
  WidgetRef ref,
  AccordSpace space,
  String serverKey, {
  List<AccordMenuEntry> moveTo = const [],
}) {
  final f = _SpaceMenuFacts(ref, space, serverKey);
  final settingsSubmenu = _serverSettingsSubmenu(context, f);
  return [
    _markSpaceReadEntry(ref, f),
    const AccordMenuEntry.divider(),
    if (f.canInvite)
      AccordMenuEntry(
        label: 'Invite to Server',
        onSelected: () => showAccordInvites(context, spaceId: space.id),
      ),
    const AccordMenuEntry.divider(),
    _muteSpaceEntry(context, ref, f),
    AccordMenuEntry(
      label: 'Notification Settings',
      subtitle: notificationLevelLabel(f.level),
      submenu: _spaceNotificationChoices(ref, f),
    ),
    _hideMutedEntry(ref, f),
    const AccordMenuEntry.divider(),
    if (settingsSubmenu.isNotEmpty)
      AccordMenuEntry(
        label: 'Server Settings',
        onSelected: f.has(AccordPermission.manageSpace)
            ? () => showAccordSpaceSettings(context, spaceId: space.id)
            : null,
        submenu: settingsSubmenu,
      ),
    ?_perServerProfileEntry(context, ref, f),
    const AccordMenuEntry.divider(),
    ..._createEntries(context, f),
    const AccordMenuEntry.divider(),
    if (moveTo.isNotEmpty) AccordMenuEntry(label: 'Move to…', submenu: moveTo),
    const AccordMenuEntry.divider(),
    ..._leaveEntries(context, ref, f),
    const AccordMenuEntry.divider(),
    _copySpaceIdEntry(f),
  ];
}

/// The menu under the space's name: Invite to Server, Server Settings,
/// Create Channel, Create Category, Create Event · Notification Settings ·
/// Edit Per-server Profile, Hide Muted Channels ☐ · Leave Server · Copy
/// Server ID — each with its icon at the left, as the reference client draws
/// this one. "Server Boost", "App Directory" and "Privacy Settings" are
/// omitted (§4).
List<AccordMenuEntry> _spaceHeaderMenuEntries(
  BuildContext context,
  WidgetRef ref,
  AccordSpace space,
  String serverKey, {
  List<AccordChannel>? channels,
  Offset? anchor,
}) {
  final f = _SpaceMenuFacts(ref, space, serverKey);
  final perServer = _perServerProfileEntry(context, ref, f);
  return [
    if (f.canInvite)
      AccordMenuEntry(
        label: 'Invite to Server',
        icon: AppIcons.personAdd,
        onSelected: () => showAccordInvites(context, spaceId: space.id),
      ),
    if (f.canManage)
      AccordMenuEntry(
        label: 'Server Settings',
        icon: AppIcons.settings,
        onSelected: () => showAccordSpaceSettings(context, spaceId: space.id),
      ),
    if (f.canManageChannels) ...[
      AccordMenuEntry(
        label: 'Create Channel',
        icon: AppIcons.addCircleOutline,
        onSelected: () => showCreateChannelDialog(context, spaceId: space.id),
      ),
      AccordMenuEntry(
        label: 'Create Category',
        icon: AppIcons.createNewFolderOutlined,
        onSelected: () => showCreateChannelDialog(
          context,
          spaceId: space.id,
          initialType: 'category',
        ),
      ),
    ],
    if (f.canManageEvents)
      AccordMenuEntry(
        label: 'Create Event',
        icon: AppIcons.eventAvailable,
        onSelected: () => showEventEditor(context, spaceId: space.id),
      ),
    // Touch has no drag in the channel list; its sheet keeps the reorder
    // dialog.
    if (f.canManageChannels &&
        channels != null &&
        !shouldUseDesktopLayout(context))
      AccordMenuEntry(
        label: 'Reorder Channels',
        icon: AppIcons.reorder,
        onSelected: () => showAccordChannelReorder(
          context,
          spaceId: space.id,
          channels: channels,
        ),
      ),
    const AccordMenuEntry.divider(),
    // A plain row here, as the reference client's (which opens its
    // notification dialog): the choices open as a menu in its place.
    AccordMenuEntry(
      label: 'Notification Settings',
      icon: AppIcons.notificationsNone,
      onSelected: () => showAccordContextMenu(
        context,
        globalPosition: anchor,
        anchorX: 0.5,
        title: 'Notification Settings',
        entries: _spaceNotificationChoices(ref, f),
      ),
    ),
    const AccordMenuEntry.divider(),
    if (perServer != null)
      AccordMenuEntry(
        label: perServer.label,
        icon: AppIcons.edit,
        onSelected: perServer.onSelected,
      ),
    AccordMenuEntry(
      label: 'Hide Muted Channels',
      icon: AppIcons.visibilityOff,
      checked: f.hideMuted,
      onSelected: () => ref
          .read(settingsControllerProvider.notifier)
          .setHideMutedChannels(serverKey, space.id, !f.hideMuted),
    ),
    const AccordMenuEntry.divider(),
    for (final e in _leaveEntries(context, ref, f))
      AccordMenuEntry(
        label: e.label,
        icon: switch (e.label) {
          'Remove Server' => AppIcons.linkOff,
          'Hide Server' => AppIcons.visibilityOff,
          _ => AppIcons.logout,
        },
        destructive: e.destructive,
        sheetSubtitle: e.sheetSubtitle,
        onSelected: e.onSelected,
      ),
    const AccordMenuEntry.divider(),
    _copySpaceIdEntry(f),
  ];
}

/// Right-click on the empty part of the channel list: Hide Muted Channels ☐ ·
/// Create Channel, Create Category, Invite to Server.
List<AccordMenuEntry> _channelListMenuEntries(
  BuildContext context,
  WidgetRef ref,
  AccordSpace space,
  String serverKey,
) {
  final f = _SpaceMenuFacts(ref, space, serverKey);
  return [
    _hideMutedEntry(ref, f),
    const AccordMenuEntry.divider(),
    if (f.canManageChannels) ...[
      AccordMenuEntry(
        label: 'Create Channel',
        onSelected: () => showCreateChannelDialog(context, spaceId: space.id),
      ),
      AccordMenuEntry(
        label: 'Create Category',
        onSelected: () => showCreateChannelDialog(
          context,
          spaceId: space.id,
          initialType: 'category',
        ),
      ),
    ],
    if (f.canInvite)
      AccordMenuEntry(
        label: 'Invite to Server',
        onSelected: () => showAccordInvites(context, spaceId: space.id),
      ),
  ];
}

/// Removes the whole server *connection* that hosts a space from this app,
/// purely locally: it disposes the client and clears the saved credentials,
/// the rail entry, open tabs, unread state and the cached space list. Unlike
/// [leaveSpace] it makes no network call, so it works for a server you can no
/// longer reach. A connection can host several spaces, so this removes all of
/// them on that host; nothing is deleted server-side.
Future<void> _removeServer(
  BuildContext context,
  WidgetRef ref,
  String serverKey,
) async {
  final conn = ref.read(connectionsControllerProvider).connectionFor(serverKey);
  if (conn == null) return;
  final server = conn.session.server;
  final label = (server.name?.isNotEmpty ?? false)
      ? server.name!
      : server.homeDomain;
  final confirmed = await showConfirmDialog(
    context,
    title: "Remove '$label'?",
    message:
        'This disconnects your account and removes the server from this app, '
        'including any of its spaces. Nothing is deleted on the server, and you '
        'can add it back later with its address or an invite.',
    confirmLabel: 'Remove',
    danger: true,
  );
  if (confirmed != true) return;
  await ref.read(accordAuthProvider.notifier).removeAccount(conn.session);
  if (context.mounted) showInfoSnack(context, "Removed '$label'");
}
