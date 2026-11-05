import 'package:bonfire/theme/app_icons.dart';
import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/channels/utils/mark_channel_read.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/shared/components/user_avatar.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/text_prompt_dialog.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/member/views/remote_origin_badge.dart';
import 'package:bonfire/features/member/views/accord_member_popout.dart';
import 'package:bonfire/features/member/views/full_profile.dart';
import 'package:bonfire/features/member/views/user_context_menu.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/user/controllers/blocked_users.dart';
import 'package:bonfire/features/voice/controllers/call.dart';
import 'package:bonfire/features/voice/controllers/missed_calls.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/channels/utils/message_position.dart';
import 'package:bonfire/shared/utils/server_timestamp.dart';
import 'package:bonfire/features/voice/views/voice_view.dart';
import 'package:bonfire/features/spaces/views/quick_switcher.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'accord_direct_messages_home.dart';
part 'accord_direct_messages_conversation.dart';
part 'accord_direct_messages_groups.dart';
part 'accord_direct_messages_user_search.dart';

/// Relationship type enum mirrored from the server: 1 = friend, 2 = blocked,
/// 3 = pending incoming, 4 = pending outgoing.
class _Rel {
  static const friend = 1;
  static const blocked = 2;
  static const pendingIn = 3;
  static const pendingOut = 4;
}

/// Best display name for a user, falling back to the raw id rather than
/// "Unknown" so an unhydrated recipient stays identifiable (and reportable).
String _userName(AccordUser? user) =>
    user == null ? 'Unknown' : accordUserName(user, fallback: user.id);

/// The recipients of [channel] excluding the current user.
List<AccordUser> _others(AccordChannel channel, String? selfId) =>
    (channel.recipients ?? const <AccordUser>[])
        .where((u) => u.id != selfId)
        .toList();

/// The home domain of a 1:1 DM's remote participant, or null for a local DM or
/// a group. Drives the federated-origin badge so a cross-server DM is visually
/// distinguishable from a same-server one.
String? _dmRemoteOrigin(AccordChannel channel, String? selfId) {
  final others = _others(channel, selfId);
  if (others.length != 1) return null;
  return accordUserOrigin(others.first);
}

/// Whether [channel] is a group DM (3+ participants). Accord types DM channels
/// as `dm` (1:1) or `group_dm`; we also fall back to the recipient count since
/// some payloads omit the type.
bool _isGroup(AccordChannel channel, String? selfId) =>
    channel.type == 'group_dm' || _others(channel, selfId).length > 1;

/// Title for a DM/group channel: a group's custom name, else the joined
/// recipient names.
String _channelTitle(AccordChannel channel, String? selfId) =>
    dmChannelTitle(channel, selfId, fallback: 'Direct message');

/// Brings the direct-messages home on screen — the Friends page, or straight
/// into [initialChannel] — in place of the channel the home was showing, as
/// the reference client's home button does. Any popup it was asked from (a
/// profile popout, a menu) closes first.
Future<void> showAccordDirectMessages(
  BuildContext context, {
  AccordChannel? initialChannel,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  navigator.popUntil((route) => route is! PopupRoute);
  dmHome.open(initialChannel);
}

/// Brings the DM conversation [channelId] on screen for its call: the call
/// view lives above that conversation's messages. Nothing happens when the
/// conversation is already the visible channel (no second dialog, and no
/// second set of video renderers).
Future<void> showAccordDmCall(
  BuildContext context,
  WidgetRef ref,
  String channelId,
) async {
  final serverKey =
      ref.read(voiceControllerProvider).serverKey ?? ref.readActiveServerKey();
  if (serverKey == null) return;
  if (accordVisibleChannel?.channelId == channelId) return;
  final dmChannels = ref.read(dmChannelsControllerProvider(serverKey).notifier);
  var channel = ref
      .read(dmChannelsControllerProvider(serverKey))
      ?.firstWhereOrNull((c) => c.id == channelId);
  if (channel == null) {
    // A first call from someone we never messaged: the conversation isn't
    // cached yet. Fetch it, or open a bare one rather than no call view.
    final client = ref
        .read(accordAuthProvider.notifier)
        .clientForKey(serverKey);
    final data = client == null
        ? null
        : (await client.channels.fetch(channelId)).data;
    if (data is AccordChannel) {
      dmChannels.upsert(data);
      channel = data;
    } else {
      channel = AccordChannel(id: channelId, type: 'dm');
    }
    if (!context.mounted) return;
  }
  await showAccordDirectMessages(context, initialChannel: channel);
}

/// Opens a cached 1:1 conversation with [userId], or creates one using a
/// normalized recipient id. Qualified ids on other domains use federation;
/// ids qualified with our own domain use the local DM path.
Future<void> openAccordDirectMessage(
  BuildContext context,
  WidgetRef ref,
  String userId,
) async {
  final client = ref.accordClient;
  final serverKey = ref.readActiveServerKey();
  if (client == null || serverKey == null) return;
  final dmChannels = ref.read(dmChannelsControllerProvider(serverKey).notifier);
  final existing = dmChannels.findDirectMessage(userId);
  if (existing != null) {
    await showAccordDirectMessages(context, initialChannel: existing);
    return;
  }
  final result = await client.users.createDm(
    dmCreateBody(userId, homeDomain: ref.readHomeDomain()),
  );
  if (!context.mounted || ref.readActiveServerKey() != serverKey) return;
  final data = result.data;
  if (result.ok && data is AccordChannel) {
    dmChannels.upsert(data);
    await showAccordDirectMessages(context, initialChannel: data);
  } else {
    // Surface the server's reason (federation disabled, recipient not
    // qualified, peer untrusted, recipient blocked, …) rather than a generic
    // failure, so a rejected cross-server open is actionable.
    showInfoSnack(
      context,
      result.errorMessageOr('Failed to open direct message'),
    );
  }
}

