import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/spaces/views/accord_invites.dart';
import 'package:bonfire/features/user/controllers/blocked_users.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/voice/controllers/call.dart';
import 'package:bonfire/shared/components/accord_dialog.dart';
import 'package:bonfire/shared/utils/ban_dialog.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/text_prompt_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The server's relationship types (`AccordRelationship.type`).
abstract final class AccordRelationshipType {
  static const int friend = 1;
  static const int blocked = 2;
  static const int pendingIn = 3;
  static const int pendingOut = 4;
}

/// The timeout choices of "Timeout …" (label, seconds).
const List<(String, int)> kTimeoutDurations = [
  ('60 Seconds', 60),
  ('5 Minutes', 300),
  ('10 Minutes', 600),
  ('1 Hour', 3600),
  ('1 Day', 86400),
  ('1 Week', 604800),
];

/// The signed-in account's relationship with [userId] (a
/// [AccordRelationshipType]), or null for none or when it can't be fetched.
Future<int?> fetchRelationshipType(WidgetRef ref, String userId) async {
  final client = ref.accordClient;
  if (client == null) return null;
  final RestResult result;
  try {
    result = await client.users.listRelationships().timeout(
      const Duration(seconds: 3),
    );
  } catch (_) {
    return null;
  }
  final data = result.data;
  if (data is! List) return null;
  for (final item in data.whereType<AccordRelationship>()) {
    if (item.user?.id == userId) return item.type;
  }
  return null;
}

/// Add Friend / Remove Friend / Accept / Cancel / Unblock, in step with
/// [currentType].
Future<void> changeRelationship(
  BuildContext context,
  WidgetRef ref,
  String userId,
  int? currentType,
) async {
  final client = ref.accordClient;
  if (client == null) return;
  final removing =
      currentType == AccordRelationshipType.friend ||
      currentType == AccordRelationshipType.blocked ||
      currentType == AccordRelationshipType.pendingOut;
  final result = removing
      ? await client.users.deleteRelationship(userId)
      : await client.users.putRelationship(userId, {
          'type': AccordRelationshipType.friend,
        });
  // An unblock has to lift the message filter as promptly as the block applied
  // it, or their messages stay hidden until the next relationship fetch.
  if (result.ok && currentType == AccordRelationshipType.blocked) {
    ref.blockedUsers.unblock(userId);
  }
  if (!context.mounted) return;
  showInfoSnack(
    context,
    result.ok
        ? switch (currentType) {
            AccordRelationshipType.friend => 'Friend removed',
            AccordRelationshipType.blocked => 'User unblocked',
            AccordRelationshipType.pendingIn => 'Friend request accepted',
            AccordRelationshipType.pendingOut => 'Friend request cancelled',
            _ => 'Friend request sent',
          }
        : 'Failed to update relationship',
  );
}

/// Blocks [userId] after the confirmation modal. The wording of the reference
/// client's modal was not captured (no Block was ever confirmed on a real
/// account): "à confirmer".
Future<bool> blockUser(
  BuildContext context,
  WidgetRef ref,
  String userId,
  String name,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AccordDialog(
      title: 'Block $name?',
      subtitle:
          'They won\'t be able to message you or notify you. Their messages in '
          'servers stay visible.',
      primaryLabel: 'Block',
      tone: AccordDialogTone.danger,
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  final result = await ref.accordClient?.users.putRelationship(userId, {
    'type': AccordRelationshipType.blocked,
  });
  final ok = result?.ok == true;
  if (ok) ref.blockedUsers.block(userId);
  if (context.mounted) {
    showInfoSnack(context, ok ? 'User blocked' : 'Failed to block user');
  }
  return ok;
}

/// The cached 1:1 conversation with [userId], or a new one.
Future<AccordChannel?> ensureDmChannel(WidgetRef ref, String userId) async {
  final client = ref.accordClient;
  final serverKey = ref.readActiveServerKey();
  if (client == null || serverKey == null) return null;
  final dmChannels = ref.read(dmChannelsControllerProvider(serverKey).notifier);
  final existing = dmChannels.findDirectMessage(userId);
  if (existing != null) return existing;
  final result = await client.users.createDm(
    dmCreateBody(userId, homeDomain: ref.readHomeDomain()),
  );
  final data = result.data;
  if (result.ok && data is AccordChannel) {
    dmChannels.upsert(data);
    return data;
  }
  return null;
}

/// "Start a Call": rings [userId] in your DM with them.
Future<void> startCallWith(
  BuildContext context,
  WidgetRef ref,
  String userId, {
  bool video = false,
}) async {
  final channel = await ensureDmChannel(ref, userId);
  if (channel == null) {
    if (context.mounted) showInfoSnack(context, 'Could not start the call');
    return;
  }
  await ref.read(callControllerProvider.notifier).startCall(channel, video: video);
}

/// Sends [text] to [userId] in your DM with them, without leaving the current
/// view (the profile popout's "Message @x" field).
Future<bool> sendDirectMessage(
  BuildContext context,
  WidgetRef ref,
  String userId,
  String text,
) async {
  final client = ref.accordClient;
  final channel = await ensureDmChannel(ref, userId);
  if (client == null || channel == null) return false;
  final result = await client.messages.create(channel.id, {'content': text});
  if (!result.ok && context.mounted) {
    showInfoSnack(context, result.errorMessageOr('Failed to send message'));
  }
  return result.ok;
}

AccordMembersController _members(WidgetRef ref, String spaceId) => ref.read(
  accordMembersControllerProvider(
    ref.readActiveServerKey() ?? '',
    spaceId,
  ).notifier,
);

/// A removal (kick/ban) whose target is already gone counts as done.
bool _missing(RestResult result) {
  if (result.statusCode == 404) return true;
  final msg = result.error?.toString().toLowerCase() ?? '';
  return msg.contains('does not exist') || msg.contains('not found');
}

Future<void> kickMember(
  BuildContext context,
  WidgetRef ref, {
  required String spaceId,
  required String userId,
  required String name,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AccordDialog(
      title: "Kick '$name' from Server",
      subtitle:
          'Are you sure you want to kick @$name from the server? They will be '
          'able to rejoin again with a new invite.',
      primaryLabel: 'Kick',
      tone: AccordDialogTone.danger,
    ),
  );
  if (confirmed != true) return;
  final client = ref.accordClient;
  if (client == null) return;
  final result = await client.members.kick(spaceId, userId);
  if (result.ok || _missing(result)) {
    _members(ref, spaceId).removeMember(userId);
  } else if (context.mounted) {
    showInfoSnack(context, result.errorOr('Failed to kick member'));
  }
}

Future<void> banMember(
  BuildContext context,
  WidgetRef ref, {
  required String spaceId,
  required String userId,
  required String name,
}) async {
  final request = await showBanDialog(context, memberName: name);
  if (request == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final client = ref.accordClient;
  if (client == null) return;
  final result = await client.bans.create(
    spaceId,
    userId,
    data: request.toJson(),
  );
  if (!(result.ok || _missing(result))) {
    messenger?.showSnackBar(
      SnackBar(content: Text(result.errorOr('Failed to ban member'))),
    );
    return;
  }
  _members(ref, spaceId).removeMember(userId);
  if (request.deleteMessageSeconds == 0) return;
  // Reported rather than assumed: a server that predates the purge ignores the
  // field, and this is the only way that shows up.
  final data = result.data;
  final count = data is Map ? asInt(data['deleted_message_count']) : 0;
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        count == 1
            ? 'Banned $name and deleted 1 message'
            : 'Banned $name and deleted $count messages',
      ),
    ),
  );
}

/// Times [userId] out for [seconds], or lifts the timeout with null.
Future<void> timeoutMember(
  BuildContext context,
  WidgetRef ref, {
  required String spaceId,
  required String userId,
  int? seconds,
}) async {
  final client = ref.accordClient;
  if (client == null) return;
  String? iso;
  if (seconds != null) {
    final until = DateTime.now().toUtc().add(Duration(seconds: seconds));
    iso = '${until.toIso8601String().split('.').first}Z';
  }
  final result = await client.members.update(spaceId, userId, {
    'communication_disabled_until': iso,
  });
  if (!result.ok && context.mounted) {
    showInfoSnack(
      context,
      result.errorOr(
        seconds == null ? 'Failed to remove timeout' : 'Failed to time out',
      ),
    );
  }
}

/// Sets or clears [member]'s nickname ("Change Nickname" for a moderator,
/// "Edit Per-server Profile" for yourself). Empty resets to the display name.
Future<void> editMemberNickname(
  BuildContext context,
  WidgetRef ref, {
  required String serverKey,
  required String spaceId,
  required AccordMember member,
  bool self = false,
}) async {
  final initial = member.nickname ?? '';
  final next = (await showTextPromptDialog(
    context,
    title: self ? 'Edit Per-server Profile' : 'Change Nickname',
    label: 'Nickname',
    hintText: self
        ? 'Leave empty to use your display name'
        : 'Leave empty to reset to their display name',
    initial: initial,
    resetLabel: initial.isNotEmpty ? 'Reset' : null,
  ))?.trim();
  if (next == null || !context.mounted) return;
  final client = ref.read(accordAuthProvider.notifier).clientForKey(serverKey);
  if (client == null) return;
  final result = await client.members.update(spaceId, member.userId, {
    'nickname': next.isEmpty ? null : next,
  });
  if (!result.ok) {
    if (context.mounted) {
      showInfoSnack(context, result.errorOr('Failed to update nickname'));
    }
    return;
  }
  member.nickname = next.isEmpty ? null : next;
  ref
      .read(accordMembersControllerProvider(serverKey, spaceId).notifier)
      .upsertMember(member);
}

/// Gives [member] [role], or takes it away.
Future<void> setMemberRole(
  BuildContext context,
  WidgetRef ref, {
  required String spaceId,
  required AccordMember member,
  required AccordRole role,
  required bool add,
}) async {
  final client = ref.accordClient;
  if (client == null) return;
  final result = add
      ? await client.members.addRole(spaceId, member.userId, role.id)
      : await client.members.removeRole(spaceId, member.userId, role.id);
  if (!result.ok) {
    if (context.mounted) {
      showInfoSnack(context, result.errorOr('Failed to update roles'));
    }
    return;
  }
  final roles = [...member.roles];
  if (add) {
    if (!roles.contains(role.id)) roles.add(role.id);
  } else {
    roles.remove(role.id);
  }
  member.roles = roles;
  _members(ref, spaceId).upsertMember(member);
}

/// A shareable invite link for [spaceId] on [serverKey]: an existing invite
/// when there is one, else a new 7-day one. Null when the server refuses.
Future<String?> inviteLinkForSpace(
  WidgetRef ref, {
  required String serverKey,
  required String spaceId,
}) async {
  final client = ref.read(accordAuthProvider.notifier).clientForKey(serverKey);
  if (client == null) return null;
  final baseUrl = ref
      .read(connectionsControllerProvider)
      .connectionFor(serverKey)
      ?.session
      .server
      .baseUrl;
  String? code;
  final existing = await client.invites.listSpace(spaceId);
  if (existing.ok && existing.data is List) {
    code = (existing.data as List).whereType<AccordInvite>().firstOrNull?.code;
  }
  if (code == null) {
    final created = await client.invites.createSpace(
      spaceId,
      data: {'max_age': 604800, 'max_uses': 0, 'temporary': false},
    );
    if (created.ok && created.data is AccordInvite) {
      code = (created.data as AccordInvite).code;
    } else if (created.ok) {
      // Some servers return no body on create; refetch to recover the code.
      final refetch = await client.invites.listSpace(spaceId);
      if (refetch.ok && refetch.data is List) {
        code = (refetch.data as List)
            .whereType<AccordInvite>()
            .firstOrNull
            ?.code;
      }
    }
  }
  return code == null ? null : accordInviteLink(baseUrl, code);
}
