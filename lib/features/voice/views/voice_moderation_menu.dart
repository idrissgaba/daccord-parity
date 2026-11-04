import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/voice/utils/stage_logic.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The voice moderation actions a member's permissions allow.
@immutable
class VoiceModerationRights {
  const VoiceModerationRights({
    this.mute = false,
    this.deafen = false,
    this.move = false,
  });

  factory VoiceModerationRights.from(Set<String> permissions) =>
      VoiceModerationRights(
        mute: accordHasPermission(permissions, AccordPermission.muteMembers),
        deafen: accordHasPermission(
          permissions,
          AccordPermission.deafenMembers,
        ),
        move: accordHasPermission(permissions, AccordPermission.moveMembers),
      );

  static const none = VoiceModerationRights();

  /// Server mute / unmute.
  final bool mute;

  /// Server deafen / undeafen.
  final bool deafen;

  /// Move to another voice channel, and disconnect.
  final bool move;

  bool get any => mute || deafen || move;
}

/// The current user's voice moderation rights in [spaceId] (on the active
/// server), or [VoiceModerationRights.none] outside a space.
VoiceModerationRights watchVoiceModerationRights(
  WidgetRef ref,
  String? spaceId,
) {
  if (spaceId == null) return VoiceModerationRights.none;
  final space = ref.watch(
    spacesControllerProvider.select(
      (spaces) => spaces?.firstWhereOrNull((s) => s.id == spaceId),
    ),
  );
  return VoiceModerationRights.from(ref.watchAccordPermissions(space, spaceId));
}

/// The voice channels of a space a member could be moved to from
/// [currentChannelId], in the order given.
List<AccordChannel> voiceMoveTargets(
  Iterable<AccordChannel> channels,
  String currentChannelId,
) => [
  for (final channel in channels)
    if (isVoiceChannelType(channel.type) && channel.id != currentChannelId)
      channel,
];

/// A participant a moderator is dragging to another voice channel.
@immutable
class VoiceMoveDrag {
  const VoiceMoveDrag({
    required this.serverKey,
    required this.spaceId,
    required this.fromChannelId,
    required this.userId,
    required this.name,
  });

  final String serverKey;
  final String spaceId;
  final String fromChannelId;
  final String userId;
  final String name;

  /// Whether dropping on the voice channel [channelId] of [spaceId] moves
  /// anyone.
  bool canDropOn(String spaceId, String channelId) =>
      spaceId == this.spaceId && channelId != fromChannelId;
}

/// Moves the dragged participant into [channelId], reporting a refusal.
Future<void> moveVoiceParticipant(
  BuildContext context,
  WidgetRef ref,
  VoiceMoveDrag drag,
  String channelId,
) async {
  final client = ref
      .read(accordAuthProvider.notifier)
      .clientForKey(drag.serverKey);
  if (client == null) return;
  final result = await client.members.update(drag.spaceId, drag.userId, {
    'channel_id': channelId,
  });
  if (!result.ok && context.mounted) {
    showInfoSnack(
      context,
      result.errorMessageOr('Couldn’t move ${drag.name}.'),
    );
  }
}
