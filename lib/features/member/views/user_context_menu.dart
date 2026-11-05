import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/channels/utils/mark_channel_read.dart';
import 'package:bonfire/features/channels/views/channel_context_menu.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_actions.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/member/views/full_profile.dart';
import 'package:bonfire/features/messaging/utils/composer_insert.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/accord_reports.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a user menu was opened from; each has the reference client's own
/// entry list.
enum UserMenuOrigin {
  /// A member row, a message author, a mention: the member menu.
  member,

  /// A row of the Direct Messages list.
  dmRow,

  /// The "…" of a row of the Friends page.
  friendRow,

  /// The "…" of a profile popout or full profile.
  profile,
}

/// Opens the menu for [userId], in the reference client's order. For
/// [UserMenuOrigin.member] in a space: Profile, Mention, Message, Start a
/// Call, Add Note · Invite to Server ›, Add Friend, Block · the moderation
/// the user may do (Change Nickname, Roles ›, Timeout ›, Kick, Ban — order à
/// confirmer: no moderator's menu on another member was capturable) · Copy
/// User ID. Yourself: Profile, Mention · Edit Per-server Profile · Copy User
/// ID. "Apps ›", "Ignore", "Add Friend Nickname", "Open in Mod View" and "Add
/// to Favourites" are omitted (§4). [dmChannel] is the conversation of a DM
/// row; [onCloseDm] closes it.
Future<void> showUserContextMenu(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  AccordUser? user,
  String? spaceId,
  AccordChannel? dmChannel,
  Offset? globalPosition,
  UserMenuOrigin origin = UserMenuOrigin.member,
  VoidCallback? onCloseDm,
  List<AccordMenuEntry> extraEntries = const [],
}) async {
  // No active connection (a host without one) still gets the menu.
  final serverKey = ref.readActiveServerKey() ?? '';
  final selfId = ref.readUserId();
  final isSelf = selfId != null && selfId == userId;
  final relationship = isSelf ? null : await fetchRelationshipType(ref, userId);
  final mutedChannels = dmChannel == null
      ? const <String>{}
      : await readMutedChannels(ref, serverKey);
  if (!context.mounted) return;

  final members = spaceId == null
      ? null
      : ref.read(accordMembersControllerProvider(serverKey, spaceId));
  final member = members?[userId];
  final cached = ref.read(accordUsersControllerProvider(serverKey))[userId];
  final resolvedUser = member?.user ?? user ?? cached;
  final name = member != null
      ? accordMemberName(member)
      : accordUserName(resolvedUser, fallback: userId);
  final handle = (resolvedUser?.username ?? '').isNotEmpty
      ? resolvedUser!.username
      : name;
  final space = spaceId == null
      ? null
      : ref
            .read(spacesControllerProvider)
            ?.firstWhereOrNull((s) => s.id == spaceId);

  void openProfile({bool focusNote = false}) => showFullProfile(
    context,
    userId: userId,
    spaceId: spaceId,
    focusNote: focusNote,
  );

  final blocked = relationship == AccordRelationshipType.blocked;
  final friendEntry = isSelf || blocked
      ? null
      : AccordMenuEntry(
          label: switch (relationship) {
            AccordRelationshipType.friend => 'Remove Friend',
            AccordRelationshipType.pendingIn => 'Accept Friend Request',
            AccordRelationshipType.pendingOut => 'Cancel Friend Request',
            _ => 'Add Friend',
          },
          onSelected: () =>
              changeRelationship(context, ref, userId, relationship),
        );
  final blockEntry = isSelf
      ? null
      : blocked
      ? AccordMenuEntry(
          label: 'Unblock',
          onSelected: () =>
              changeRelationship(context, ref, userId, relationship),
        )
      : AccordMenuEntry(
          label: 'Block',
          destructive: true,
          onSelected: () => blockUser(context, ref, userId, name),
        );
  final inviteEntry = isSelf
      ? null
      : _inviteToServerEntry(context, ref, serverKey, userId, exclude: spaceId);
  final copyUserId = AccordMenuEntry(
    label: 'Copy User ID',
    icon: AppIcons.idCard,
    onSelected: () => Clipboard.setData(ClipboardData(text: userId)),
  );

  final List<AccordMenuEntry> entries;
  switch (origin) {
    case UserMenuOrigin.friendRow:
      entries = [
        AccordMenuEntry(
          label: 'Start Video Call',
          onSelected: () => startCallWith(context, ref, userId, video: true),
        ),
        AccordMenuEntry(
          label: 'Start Voice Call',
          onSelected: () => startCallWith(context, ref, userId),
        ),
        if (relationship == AccordRelationshipType.friend)
          AccordMenuEntry(
            label: 'Remove Friend',
            destructive: true,
            onSelected: () =>
                changeRelationship(context, ref, userId, relationship),
          ),
      ];
    case UserMenuOrigin.profile:
      entries = [
        if (!isSelf) ...[
          ?inviteEntry,
          const AccordMenuEntry.divider(),
          ?blockEntry,
          AccordMenuEntry(
            label: 'Report User Profile',
            destructive: true,
            onSelected: () => showReportDialog(
              context,
              spaceId: spaceId,
              targetType: 'user',
              targetId: userId,
              reportedUserId: userId,
              reportedName: name,
            ),
          ),
          const AccordMenuEntry.divider(),
        ],
        copyUserId,
      ];
    case UserMenuOrigin.dmRow:
      final channel = dmChannel;
      final readState = ref.read(readStateControllerProvider(serverKey));
      final pinned =
          channel != null &&
          ref.read(settingsControllerProvider).isChannelPinned(serverKey, channel.id);
      entries = [
        if (channel != null) ...[
          AccordMenuEntry(
            label: 'Mark as Read',
            onSelected: readState.isUnread(channel.id)
                ? () => markChannelRead(
                    ref,
                    channel.id,
                    fallbackMessageId: channel.lastMessageId,
                  )
                : null,
          ),
          const AccordMenuEntry.divider(),
          AccordMenuEntry(
            label: pinned ? 'Unpin' : 'Pin',
            icon: AppIcons.pushPin,
            onSelected: () => ref
                .read(settingsControllerProvider.notifier)
                .setChannelPinned(serverKey, channel.id, !pinned),
          ),
          const AccordMenuEntry.divider(),
        ],
        AccordMenuEntry(label: 'Profile', onSelected: openProfile),
        if (!isSelf)
          AccordMenuEntry(
            label: 'Start a Call',
            onSelected: () => startCallWith(context, ref, userId),
          ),
        if (!isSelf)
          AccordMenuEntry(
            label: 'Add Note',
            subtitle: 'Only visible to you',
            onSelected: () => openProfile(focusNote: true),
          ),
        if (onCloseDm != null)
          AccordMenuEntry(label: 'Close DM', onSelected: onCloseDm),
        const AccordMenuEntry.divider(),
        ?inviteEntry,
        ?friendEntry,
        ?blockEntry,
        if (channel != null) ...[
          const AccordMenuEntry.divider(),
          channelMuteEntry(
            context,
            ref,
            serverKey: serverKey,
            channelId: channel.id,
            muted: mutedChannels.contains(channel.id),
            noun: '@$handle',
          ),
        ],
        const AccordMenuEntry.divider(),
        copyUserId,
        if (channel != null)
          AccordMenuEntry(
            label: 'Copy Channel ID',
            icon: AppIcons.idCard,
            onSelected: () =>
                Clipboard.setData(ClipboardData(text: channel.id)),
          ),
      ];
    case UserMenuOrigin.member:
      final perms = spaceId == null
          ? const <String>{}
          : ref.readAccordPermissions(space, spaceId);
      entries = [
        AccordMenuEntry(label: 'Profile', onSelected: openProfile),
        AccordMenuEntry(
          label: 'Mention',
          onSelected: () => requestComposerInsert('@$handle'),
        ),
        if (!isSelf) ...[
          AccordMenuEntry(
            label: 'Message',
            onSelected: () => openAccordDirectMessage(context, ref, userId),
          ),
          AccordMenuEntry(
            label: 'Start a Call',
            onSelected: () => startCallWith(context, ref, userId),
          ),
          AccordMenuEntry(
            label: 'Add Note',
            subtitle: 'Only visible to you',
            onSelected: () => openProfile(focusNote: true),
          ),
        ],
        const AccordMenuEntry.divider(),
        if (isSelf &&
            member != null &&
            spaceId != null &&
            accordHasPermission(perms, AccordPermission.changeNickname))
          AccordMenuEntry(
            label: 'Edit Per-server Profile',
            onSelected: () => editMemberNickname(
              context,
              ref,
              serverKey: serverKey,
              spaceId: spaceId,
              member: member,
              self: true,
            ),
          ),
        ?inviteEntry,
        ?friendEntry,
        ?blockEntry,
        if (!isSelf && member != null && spaceId != null)
          ..._moderationEntries(
            context,
            ref,
            serverKey: serverKey,
            space: space,
            spaceId: spaceId,
            member: member,
            name: name,
            perms: perms,
          ),
        const AccordMenuEntry.divider(),
        copyUserId,
      ];
  }

  if (extraEntries.isNotEmpty) {
    // Host-specific rows (Remove From Group) go just above the copy-ID rows.
    final at = entries.lastIndexWhere((e) => e.isDivider);
    entries.insertAll(at < 0 ? entries.length : at, [
      const AccordMenuEntry.divider(),
      ...extraEntries,
    ]);
  }
  await showAccordContextMenu(
    context,
    entries: entries,
    globalPosition: globalPosition,
    title: name,
    titleIcon: AppIcons.personOutline,
  );
}

/// The moderator's part of the member menu: Change Nickname · Roles › ·
/// Timeout › / Remove Timeout, Kick, Ban. A federated member (homed on
/// another server) can't be moderated here.
List<AccordMenuEntry> _moderationEntries(
  BuildContext context,
  WidgetRef ref, {
  required String serverKey,
  required AccordSpace? space,
  required String spaceId,
  required AccordMember member,
  required String name,
  required Set<String> perms,
}) {
  if (accordMemberOrigin(member) != null) return const [];
  bool can(String p) => accordHasPermission(perms, p);
  final roles = (space?.roles ?? const <AccordRole>[])
      .where((r) => r.position != 0 && !r.managed)
      .sortedBy<num>((r) => -r.position);
  final timedOut =
      member.timedOutUntil != null &&
      member.timedOutUntil.toString().isNotEmpty;
  return [
    const AccordMenuEntry.divider(),
    if (can(AccordPermission.manageNicknames))
      AccordMenuEntry(
        label: 'Change Nickname',
        onSelected: () => editMemberNickname(
          context,
          ref,
          serverKey: serverKey,
          spaceId: spaceId,
          member: member,
        ),
      ),
    if (can(AccordPermission.manageRoles) && roles.isNotEmpty)
      AccordMenuEntry(
        label: 'Roles',
        submenu: [
          for (final role in roles)
            AccordMenuEntry(
              label: role.name,
              checked: member.roles.contains(role.id),
              onSelected: () => setMemberRole(
                context,
                ref,
                spaceId: spaceId,
                member: member,
                role: role,
                add: !member.roles.contains(role.id),
              ),
            ),
        ],
      ),
    if (can(AccordPermission.moderateMembers))
      timedOut
          ? AccordMenuEntry(
              label: 'Remove Timeout',
              onSelected: () => timeoutMember(
                context,
                ref,
                spaceId: spaceId,
                userId: member.userId,
              ),
            )
          : AccordMenuEntry(
              label: 'Timeout $name',
              destructive: true,
              submenu: [
                for (final (label, seconds) in kTimeoutDurations)
                  AccordMenuEntry(
                    label: label,
                    onSelected: () => timeoutMember(
                      context,
                      ref,
                      spaceId: spaceId,
                      userId: member.userId,
                      seconds: seconds,
                    ),
                  ),
              ],
            ),
    if (can(AccordPermission.kickMembers))
      AccordMenuEntry(
        label: 'Kick $name',
        destructive: true,
        onSelected: () => kickMember(
          context,
          ref,
          spaceId: spaceId,
          userId: member.userId,
          name: name,
        ),
      ),
    if (can(AccordPermission.banMembers))
      AccordMenuEntry(
        label: 'Ban $name',
        destructive: true,
        onSelected: () => banMember(
          context,
          ref,
          spaceId: spaceId,
          userId: member.userId,
          name: name,
        ),
      ),
  ];
}

/// "Invite to Server ›": the spaces of this connection (but [exclude]) where
/// the user may create invites; picking one sends its invite link to [userId]
/// in your DM with them.
AccordMenuEntry? _inviteToServerEntry(
  BuildContext context,
  WidgetRef ref,
  String serverKey,
  String userId, {
  String? exclude,
}) {
  final spaces = ref.read(spacesControllerProvider) ?? const <AccordSpace>[];
  final targets = [
    for (final s in spaces)
      if (s.id != exclude &&
          accordHasPermission(
            ref.readAccordPermissions(s, s.id),
            AccordPermission.createInvites,
          ))
        s,
  ];
  if (targets.isEmpty) return null;
  return AccordMenuEntry(
    label: 'Invite to Server',
    submenu: [
      for (final s in targets)
        AccordMenuEntry(
          label: s.name,
          onSelected: () async {
            final link = await inviteLinkForSpace(
              ref,
              serverKey: serverKey,
              spaceId: s.id,
            );
            if (!context.mounted) return;
            if (link == null) {
              showInfoSnack(context, 'Could not create an invite');
              return;
            }
            final sent = await sendDirectMessage(context, ref, userId, link);
            if (sent && context.mounted) showInfoSnack(context, 'Invite sent');
          },
        ),
    ],
  );
}
