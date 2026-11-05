import 'package:bonfire/theme/app_icons.dart';
import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/channels/controllers/muted_channels.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/channels/utils/mark_channel_read.dart';
import 'package:bonfire/features/channels/utils/toggle_channel_mute.dart';
import 'package:bonfire/features/channels/views/channel_management.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:collection/collection.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/views/accord_invites.dart';
import 'package:bonfire/features/user/controllers/self_presence.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/in_app_links.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

IconData _glyphFor(String? type) {
  switch (type) {
    case 'voice':
      return AppIcons.volumeUp;
    case 'stage':
      return AppIcons.podcasts;
    case 'forum':
      return AppIcons.forum;
    case 'announcement':
      return AppIcons.campaign;
    case 'arcade':
      return AppIcons.sportsEsportsOutlined;
    case 'category':
      return AppIcons.folder;
    default:
      return AppIcons.tag;
  }
}

/// The reference client's name for a notification level.
String notificationLevelLabel(String level) => switch (level) {
  AccordSettings.channelNotifAll => 'All Messages',
  AccordSettings.channelNotifNothing => 'Nothing',
  _ => 'Only @mentions',
};

/// A space's default level when no one chose one: the space's own
/// `default_notifications`, else all messages.
String spaceDefaultLevel(AccordSpace? space) =>
    switch (space?.defaultNotifications) {
      AccordSettings.channelNotifMentions => AccordSettings.channelNotifMentions,
      AccordSettings.channelNotifNothing => AccordSettings.channelNotifNothing,
      _ => AccordSettings.channelNotifAll,
    };

/// The entries of a "Mute …" submenu: For 15 Minutes … Until I turn it back
/// on. [onMute] receives the chosen duration (null = until turned back on).
List<AccordMenuEntry> muteSubmenu(void Function(Duration? duration) onMute) => [
  for (final choice in kMuteDurations)
    AccordMenuEntry(
      label: choice.label,
      onSelected: () => onMute(choice.duration),
    ),
];

/// "Muted until 14:05" under an Unmute row for a timed mute.
String? mutedUntilLabel(BuildContext context, DateTime? until) {
  if (until == null) return null;
  final time = TimeOfDay.fromDateTime(until).format(context);
  final now = DateTime.now();
  final sameDay =
      until.year == now.year && until.month == now.month && until.day == now.day;
  if (sameDay) return 'Muted until $time';
  return 'Muted until ${until.day}/${until.month}, $time';
}

/// The radio list of a channel's or category's "Notification Settings"
/// submenu: "Use … Default" (showing what it resolves to), then the three
/// levels.
List<AccordMenuEntry> inheritedLevelSubmenu({
  required String defaultLabel,
  required String inheritedLevel,
  required String? ownLevel,
  required ValueChanged<String?> onLevel,
}) => [
  AccordMenuEntry(
    label: defaultLabel,
    subtitle: notificationLevelLabel(inheritedLevel),
    radio: ownLevel == null,
    onSelected: () => onLevel(null),
  ),
  for (final level in const [
    AccordSettings.channelNotifAll,
    AccordSettings.channelNotifMentions,
    AccordSettings.channelNotifNothing,
  ])
    AccordMenuEntry(
      label: notificationLevelLabel(level),
      radio: ownLevel == level,
      onSelected: () => onLevel(level),
    ),
];

/// Everything the channel and category menus read, gathered once.
class _ChannelMenuContext {
  _ChannelMenuContext(this.ref, this.serverKey, this.spaceId, AccordSpace? space)
    : space =
          space ??
          ref
              .read(spacesControllerProvider)
              ?.firstWhereOrNull((s) => s.id == spaceId);

  final WidgetRef ref;
  final String serverKey;
  final String spaceId;
  final AccordSpace? space;

  AccordSettings get settings => ref.read(settingsControllerProvider);
  SettingsController get settingsCtl =>
      ref.read(settingsControllerProvider.notifier);

  List<AccordChannel> get channels =>
      ref.read(accordChannelsControllerProvider(serverKey, spaceId)) ??
      const <AccordChannel>[];

  List<AccordChannel> get categories => [
    for (final c in channels)
      if (c.type == 'category') c,
  ];

  /// The level a channel in [categoryId] inherits when it has none.
  String categoryLevel(String? categoryId) =>
      (categoryId == null
          ? null
          : settings.channelNotificationLevel(serverKey, categoryId)) ??
      settings.spaceNotificationLevel(serverKey, spaceId) ??
      spaceDefaultLevel(space);

  String spaceLevel() =>
      settings.spaceNotificationLevel(serverKey, spaceId) ??
      spaceDefaultLevel(space);
}

/// The server-side mutes of [serverKey], or none when they can't be read in
/// time — a menu never waits on them.
Future<Set<String>> readMutedChannels(WidgetRef ref, String serverKey) async {
  try {
    return await ref
        .read(mutedChannelsControllerProvider(serverKey).future)
        .timeout(const Duration(seconds: 2));
  } catch (_) {
    return const <String>{};
  }
}

/// Mutes [channelId] (a channel, category or DM) on the server, timed by
/// [duration] (null = until turned back on).
Future<void> muteChannelFor(
  BuildContext context,
  WidgetRef ref, {
  required String serverKey,
  required String channelId,
  Duration? duration,
}) async {
  ref
      .read(settingsControllerProvider.notifier)
      .setMuteExpiry(serverKey, channelId, untilFrom(duration));
  final result = await ref
      .read(mutedChannelsControllerProvider(serverKey).notifier)
      .setMuted(channelId, true);
  if (result == MuteResult.failed) {
    ref
        .read(settingsControllerProvider.notifier)
        .setMuteExpiry(serverKey, channelId, null);
    if (context.mounted) showInfoSnack(context, 'Failed to mute channel');
  }
}

/// The Mute / Unmute row for a channel, category or DM, labelled [noun]
/// ("Channel", "Category", "@name").
AccordMenuEntry channelMuteEntry(
  BuildContext context,
  WidgetRef ref, {
  required String serverKey,
  required String channelId,
  required bool muted,
  required String noun,
}) {
  if (muted) {
    return AccordMenuEntry(
      label: 'Unmute $noun',
      subtitle: mutedUntilLabel(
        context,
        ref.read(settingsControllerProvider).muteExpiry(serverKey, channelId),
      ),
      onSelected: () => toggleChannelMute(
        context,
        ref,
        serverKey: serverKey,
        channelId: channelId,
        muted: true,
      ),
    );
  }
  return AccordMenuEntry(
    label: 'Mute $noun',
    onSelected: () => muteChannelFor(
      context,
      ref,
      serverKey: serverKey,
      channelId: channelId,
    ),
    submenu: muteSubmenu(
      (duration) => muteChannelFor(
        context,
        ref,
        serverKey: serverKey,
        channelId: channelId,
        duration: duration,
      ),
    ),
  );
}

/// "Move to… › Category › Uncategorised / categories": re-parents a channel.
AccordMenuEntry _moveToEntry(
  BuildContext hostContext,
  _ChannelMenuContext m,
  AccordChannel channel,
) {
  Future<void> moveTo(String? parentId) async {
    final client = m.ref.accordClient;
    if (client == null) return;
    await m.ref
        .read(accordChannelsControllerProvider(m.serverKey, m.spaceId).notifier)
        .updateChannel(client, channel.id, {'parent_id': parentId});
  }

  return AccordMenuEntry(
    label: 'Move to…',
    submenu: [
      AccordMenuEntry(
        label: 'Category',
        submenu: [
          AccordMenuEntry(
            label: 'Uncategorised',
            onSelected: channel.parentId == null ? null : () => moveTo(null),
          ),
          if (m.categories.isNotEmpty) const AccordMenuEntry.divider(),
          for (final category in m.categories)
            AccordMenuEntry(
              label: category.name ?? category.id,
              onSelected: category.id == channel.parentId
                  ? null
                  : () => moveTo(category.id),
            ),
        ],
      ),
    ],
  );
}

/// "Move to… › First in List / Last in List": moves a category to either end.
AccordMenuEntry _moveCategoryEntry(
  _ChannelMenuContext m,
  AccordChannel category,
) {
  final categories = m.categories;
  final index = categories.indexWhere((c) => c.id == category.id);
  Future<void> move({required bool first}) async {
    final client = m.ref.accordClient;
    if (client == null) return;
    final ordered = [...categories]..removeAt(index);
    first ? ordered.insert(0, category) : ordered.add(category);
    final controller = m.ref.read(
      accordChannelsControllerProvider(m.serverKey, m.spaceId).notifier,
    );
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i].position == i) continue;
      await controller.updateChannel(client, ordered[i].id, {'position': i});
    }
  }

  return AccordMenuEntry(
    label: 'Move to…',
    submenu: [
      AccordMenuEntry(
        label: 'First in List',
        onSelected: index <= 0 ? null : () => move(first: true),
      ),
      AccordMenuEntry(
        label: 'Last in List',
        onSelected: index < 0 || index == categories.length - 1
            ? null
            : () => move(first: false),
      ),
    ],
  );
}

/// Creates a copy of [channel] (name, type, topic, category, limits and
/// permission overwrites) right after it.
Future<void> duplicateChannel(
  BuildContext context,
  WidgetRef ref, {
  required String serverKey,
  required String spaceId,
  required AccordChannel channel,
}) async {
  final client = ref.accordClient;
  if (client == null) return;
  final data = channel.toJson()
    ..remove('id')
    ..remove('space_id')
    ..remove('last_message_id')
    ..remove('created_at')
    ..remove('recipients')
    ..remove('owner_id')
    ..remove('origin');
  final copy = await ref
      .read(accordChannelsControllerProvider(serverKey, spaceId).notifier)
      .createChannel(client, data);
  if (copy == null && context.mounted) {
    showInfoSnack(context, 'Could not duplicate the channel');
  }
}

/// Opens the right-click / long-press menu of a text or voice [channel], in
/// the reference client's order: Mark as Read · Invite to Channel (Invite to
/// Voice), Pin Channel to Top, Copy Link · Open Chat, Hide Names (voice) ·
/// Mute Channel ›, Notification Settings › (text) · Move to… › · Edit,
/// Duplicate, Create, Delete (managers) · Copy Channel ID. "Add to
/// Favourites" is omitted (§4). [hostContext] is the launching tile's
/// context, so dialogs opened after the menu closes still have a live
/// ancestor. [onOpenChat] selects the voice channel's text chat.
Future<void> showChannelContextMenu(
  BuildContext hostContext,
  WidgetRef ref, {
  required AccordChannel channel,
  required String spaceId,
  required bool canManageChannels,
  bool canInvite = false,
  AccordSpace? space,
  Offset? globalPosition,
  VoidCallback? onOpenChat,
  List<AccordMenuEntry> touchLeadingEntries = const [],
}) async {
  final serverKey = ref.readActiveServerKey();
  if (serverKey == null) return;
  final mutedChannels = await readMutedChannels(ref, serverKey);
  if (!hostContext.mounted) return;
  final m = _ChannelMenuContext(ref, serverKey, spaceId, space);
  final settings = m.settings;
  final muted = mutedChannels.contains(channel.id);
  final isVoice = channel.type == 'voice' || channel.type == 'stage';
  final unread = ref.read(readStateControllerProvider(serverKey)).isUnread(
    channel.id,
  );
  final pinned = settings.isChannelPinned(serverKey, channel.id);
  final ownLevel = settings.channelNotificationLevel(serverKey, channel.id);

  final entries = <AccordMenuEntry>[
    // Touch has no hover, so its sheet carries the voice join / disconnect.
    if (globalPosition == null) ...touchLeadingEntries,
    AccordMenuEntry(
      label: 'Mark as Read',
      onSelected: unread
          ? () => markChannelRead(
              ref,
              channel.id,
              fallbackMessageId: channel.lastMessageId,
            )
          : null,
    ),
    const AccordMenuEntry.divider(),
    if (canInvite)
      AccordMenuEntry(
        label: isVoice ? 'Invite to Voice' : 'Invite to Channel',
        onSelected: () => showAccordInvites(hostContext, spaceId: spaceId),
      ),
    AccordMenuEntry(
      label: pinned ? 'Unpin Channel' : 'Pin Channel to Top',
      onSelected: () =>
          m.settingsCtl.setChannelPinned(serverKey, channel.id, !pinned),
    ),
    AccordMenuEntry(
      label: 'Copy Link',
      onSelected: () {
        Clipboard.setData(
          ClipboardData(
            text: channelLink(spaceId: spaceId, channelId: channel.id),
          ),
        );
        showInfoSnack(hostContext, 'Link copied');
      },
    ),
    const AccordMenuEntry.divider(),
    if (isVoice) ...[
      AccordMenuEntry(label: 'Open Chat', onSelected: onOpenChat),
      AccordMenuEntry(
        label: 'Hide Names',
        checked: settings.hidesVoiceNames(serverKey, channel.id),
        onSelected: () => m.settingsCtl.setVoiceNamesHidden(
          serverKey,
          channel.id,
          !settings.hidesVoiceNames(serverKey, channel.id),
        ),
      ),
      const AccordMenuEntry.divider(),
    ],
    channelMuteEntry(
      hostContext,
      ref,
      serverKey: serverKey,
      channelId: channel.id,
      muted: muted,
      noun: 'Channel',
    ),
    if (!isVoice)
      AccordMenuEntry(
        label: 'Notification Settings',
        subtitle: notificationLevelLabel(
          ownLevel ?? m.categoryLevel(channel.parentId),
        ),
        submenu: inheritedLevelSubmenu(
          defaultLabel: channel.parentId == null
              ? 'Use server default'
              : 'Use category default',
          inheritedLevel: m.categoryLevel(channel.parentId),
          ownLevel: ownLevel,
          onLevel: (level) => m.settingsCtl.setChannelNotificationLevel(
            serverKey,
            channel.id,
            level,
          ),
        ),
      ),
    if (canManageChannels) ...[
      const AccordMenuEntry.divider(),
      _moveToEntry(hostContext, m, channel),
      const AccordMenuEntry.divider(),
      AccordMenuEntry(
        label: 'Edit Channel',
        onSelected: () => showEditChannelDialog(
          hostContext,
          spaceId: spaceId,
          channel: channel,
        ),
      ),
      AccordMenuEntry(
        label: 'Duplicate Channel',
        onSelected: () => duplicateChannel(
          hostContext,
          ref,
          serverKey: serverKey,
          spaceId: spaceId,
          channel: channel,
        ),
      ),
      AccordMenuEntry(
        label: isVoice ? 'Create Voice Channel' : 'Create Text Channel',
        onSelected: () => showCreateChannelDialog(
          hostContext,
          spaceId: spaceId,
          parentId: channel.parentId,
          initialType: isVoice ? 'voice' : 'text',
        ),
      ),
      AccordMenuEntry(
        label: 'Delete Channel',
        destructive: true,
        onSelected: () => confirmAndDeleteChannel(
          hostContext,
          ref,
          spaceId: spaceId,
          channel: channel,
        ),
      ),
    ],
    const AccordMenuEntry.divider(),
    AccordMenuEntry(
      label: 'Copy Channel ID',
      icon: AppIcons.idCard,
      onSelected: () => Clipboard.setData(ClipboardData(text: channel.id)),
    ),
  ];

  return showAccordContextMenu(
    hostContext,
    entries: entries,
    globalPosition: globalPosition,
    title: channel.name ?? channel.id,
    titleIcon: _glyphFor(channel.type),
  );
}

/// Opens the menu of a [category] header: Mark as Read · Collapse Category ☐,
/// Collapse All Categories · Mute Category ›, Notification Settings › ·
/// Move to… › (managers) · Edit / Delete Category (managers) · Copy
/// Category ID.
Future<void> showCategoryContextMenu(
  BuildContext hostContext,
  WidgetRef ref, {
  required AccordChannel category,
  required String spaceId,
  required bool canManageChannels,
  required bool collapsed,
  required VoidCallback onToggle,
  AccordSpace? space,
  Offset? globalPosition,
}) async {
  final serverKey = ref.readActiveServerKey();
  if (serverKey == null) return;
  final mutedChannels = await readMutedChannels(ref, serverKey);
  if (!hostContext.mounted) return;
  final m = _ChannelMenuContext(ref, serverKey, spaceId, space);
  final readState = ref.read(readStateControllerProvider(serverKey));
  final children = [
    for (final c in m.channels)
      if (c.parentId == category.id) c,
  ];
  final unread = children.any((c) => readState.isUnread(c.id));
  final ownLevel = m.settings.channelNotificationLevel(serverKey, category.id);

  final entries = <AccordMenuEntry>[
    AccordMenuEntry(
      label: 'Mark as Read',
      onSelected: unread
          ? () {
              for (final c in children) {
                markChannelRead(ref, c.id, fallbackMessageId: c.lastMessageId);
              }
            }
          : null,
    ),
    const AccordMenuEntry.divider(),
    AccordMenuEntry(
      label: 'Collapse Category',
      checked: collapsed,
      onSelected: onToggle,
    ),
    AccordMenuEntry(
      label: 'Collapse All Categories',
      onSelected: () {
        for (final c in m.categories) {
          m.settingsCtl.setCategoryCollapsed(serverKey, spaceId, c.id, true);
        }
      },
    ),
    const AccordMenuEntry.divider(),
    channelMuteEntry(
      hostContext,
      ref,
      serverKey: serverKey,
      channelId: category.id,
      muted: mutedChannels.contains(category.id),
      noun: 'Category',
    ),
    AccordMenuEntry(
      label: 'Notification Settings',
      subtitle: notificationLevelLabel(ownLevel ?? m.spaceLevel()),
      submenu: inheritedLevelSubmenu(
        defaultLabel: 'Use Server Default',
        inheritedLevel: m.spaceLevel(),
        ownLevel: ownLevel,
        onLevel: (level) => m.settingsCtl.setChannelNotificationLevel(
          serverKey,
          category.id,
          level,
        ),
      ),
    ),
    if (canManageChannels) ...[
      const AccordMenuEntry.divider(),
      _moveCategoryEntry(m, category),
      const AccordMenuEntry.divider(),
      AccordMenuEntry(
        label: 'Edit Category',
        onSelected: () => showEditChannelDialog(
          hostContext,
          spaceId: spaceId,
          channel: category,
        ),
      ),
      AccordMenuEntry(
        label: 'Delete Category',
        destructive: true,
        onSelected: () => confirmAndDeleteChannel(
          hostContext,
          ref,
          spaceId: spaceId,
          channel: category,
        ),
      ),
    ],
    const AccordMenuEntry.divider(),
    AccordMenuEntry(
      label: 'Copy Category ID',
      icon: AppIcons.idCard,
      onSelected: () => Clipboard.setData(ClipboardData(text: category.id)),
    ),
  ];

  return showAccordContextMenu(
    hostContext,
    entries: entries,
    globalPosition: globalPosition,
    title: category.name ?? category.id,
    titleIcon: AppIcons.folder,
  );
}

/// The notification choices of [channelId] (a channel of [spaceId], or a DM
/// with no space): "Use category default" (or server / plain default) and the
/// three levels — shared by the channel menu's submenu and the header bell.
List<AccordMenuEntry> channelNotificationEntries(
  WidgetRef ref, {
  required String serverKey,
  required String? spaceId,
  required String channelId,
}) {
  final settings = ref.read(settingsControllerProvider);
  final ctl = ref.read(settingsControllerProvider.notifier);
  final own = settings.channelNotificationLevel(serverKey, channelId);
  void set(String? level) =>
      ctl.setChannelNotificationLevel(serverKey, channelId, level);
  if (spaceId == null) {
    return inheritedLevelSubmenu(
      defaultLabel: 'Use default',
      inheritedLevel: AccordSettings.channelNotifAll,
      ownLevel: own,
      onLevel: set,
    );
  }
  final m = _ChannelMenuContext(ref, serverKey, spaceId, null);
  final parentId = m.channels
      .firstWhereOrNull((c) => c.id == channelId)
      ?.parentId;
  return inheritedLevelSubmenu(
    defaultLabel: parentId == null
        ? 'Use server default'
        : 'Use category default',
    inheritedLevel: m.categoryLevel(parentId),
    ownLevel: own,
    onLevel: set,
  );
}
