import 'package:accordkit/accordkit.dart' show AccordUser;
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/member/views/accord_member_popout.dart';
import 'package:bonfire/features/messaging/utils/composer_insert.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/utils/voice_logic.dart';
import 'package:bonfire/features/voice/views/voice_moderation_menu.dart';
import 'package:bonfire/features/voice/views/stage_view.dart' show updateStage;
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Highest per-user volume the slider offers here. The web plays remote audio
/// through an `HTMLAudioElement`, which cannot amplify past 100 %.
int get maxUserVolumeSlider => kIsWeb ? 100 : AccordSettings.maxUserVolume;

/// The one context menu of a voice participant, wherever they are
/// right-clicked (a tile of the call view, a row under the channel), as other
/// chat apps lay it out:
///
/// Profile · Mention · Message ─ Mute ☐ · Deafen ☐ (ourselves) or Mute ☐ ·
/// User Volume (anyone else) ─ Show Non-Video Participants ☑ (a tile) ─
/// Server Mute ☐ · Server Deafen ☐ · Disconnect · Move To (a moderator) ─
/// Copy User ID.
///
/// Anchored at [globalPosition] on desktop layouts, a bottom sheet otherwise.
/// [showNonVideoParticipants] and [onShowNonVideoParticipants] come from the
/// call view, whose tiles the toggle filters.
Future<void> showVoiceParticipantMenu(
  BuildContext context,
  WidgetRef ref, {
  required String serverKey,
  required String userId,
  required String name,
  required String channelId,
  String? spaceId,
  Offset? globalPosition,
  bool? showNonVideoParticipants,
  ValueChanged<bool>? onShowNonVideoParticipants,
}) {
  final isSelf = userId == ref.readUserId();
  // A tile's menu (the toggles below come from the call view); our own tile
  // offers no "Mention", as in other chat apps.
  final tile = showNonVideoParticipants != null;
  final voice = ref.read(voiceControllerProvider);
  final voiceNotifier = ref.read(voiceControllerProvider.notifier);
  final settings = ref.read(settingsControllerProvider);
  final settingsNotifier = ref.read(settingsControllerProvider.notifier);
  final user = ref.read(accordUsersControllerProvider(serverKey))[userId];
  final rights = _readModerationRights(ref, spaceId);
  final voiceState = ref.read(
    voiceStatesControllerProvider(serverKey),
  )[channelId]?[userId];
  final locallyMuted = settings.isUserLocallyMuted(serverKey, userId);
  final inThisCall = voice.channelId == channelId;
  final stage =
      spaceId != null &&
      ref
              .read(accordChannelsControllerProvider(serverKey, spaceId))
              ?.firstWhereOrNull((c) => c.id == channelId)
              ?.type ==
          'stage';

  final entries = <AccordMenuEntry>[
    AccordMenuEntry(
      key: const Key('voice-menu-profile'),
      label: 'Profile',
      onSelected: () => _openProfile(context, ref, spaceId, userId, user),
    ),
    if (!(isSelf && tile))
      AccordMenuEntry(
        key: const Key('voice-menu-mention'),
        label: 'Mention',
        onSelected: () => requestComposerInsert('@${_handle(user, name)}'),
      ),
    if (!isSelf)
      AccordMenuEntry(
        key: const Key('voice-menu-message'),
        label: 'Message',
        onSelected: () => openAccordDirectMessage(context, ref, userId),
      ),
    const AccordMenuEntry.divider(),
    if (isSelf) ...[
      AccordMenuEntry(
        key: const Key('voice-menu-mute'),
        label: 'Mute',
        checked: voice.selfMute,
        onSelected: voiceNotifier.toggleMute,
      ),
      AccordMenuEntry(
        key: const Key('voice-menu-deafen'),
        label: 'Deafen',
        checked: voice.selfDeaf,
        onSelected: voiceNotifier.toggleDeafen,
      ),
    ] else ...[
      AccordMenuEntry(
        key: const Key('voice-menu-mute'),
        label: 'Mute',
        checked: locallyMuted,
        onSelected: () => settingsNotifier.setUserLocallyMuted(
          serverKey,
          userId,
          !locallyMuted,
        ),
      ),
      AccordMenuEntry.widget(
        child: UserVolumeSlider(
          key: const Key('user-volume-slider'),
          serverKey: serverKey,
          volumeId: userId,
          label: 'User Volume',
        ),
        height: UserVolumeSlider.height,
      ),
    ],
    if (showNonVideoParticipants != null &&
        onShowNonVideoParticipants != null) ...[
      const AccordMenuEntry.divider(),
      AccordMenuEntry(
        key: const Key('voice-menu-non-video'),
        label: 'Show Non-Video Participants',
        checked: showNonVideoParticipants,
        onSelected: () =>
            onShowNonVideoParticipants(!showNonVideoParticipants),
      ),
    ],
    if (spaceId != null && rights.any) ...[
      const AccordMenuEntry.divider(),
      if (rights.mute)
        AccordMenuEntry(
          key: const Key('voice-mod-mute'),
          label: 'Server Mute',
          destructive: true,
          checked: voiceState?.mute ?? false,
          onSelected: () => _updateMember(context, ref, serverKey, spaceId, userId, {
            'mute': !(voiceState?.mute ?? false),
          }),
        ),
      // A stage moderator seats a raised hand on stage, or sends a speaker
      // back to the audience.
      if (rights.mute && stage && voiceState != null && !isSelf)
        AccordMenuEntry(
          key: const Key('voice-mod-stage'),
          label: voiceState.suppress ? 'Invite to Speak' : 'Move to Audience',
          icon: voiceState.suppress ? AppIcons.micExternalOn : AppIcons.group,
          onSelected: () => updateStage(
            context,
            ref,
            serverKey: serverKey,
            spaceId: spaceId,
            userId: userId,
            suppress: !voiceState.suppress,
          ),
        ),
      if (rights.deafen)
        AccordMenuEntry(
          key: const Key('voice-mod-deafen'),
          label: 'Server Deafen',
          destructive: true,
          checked: voiceState?.deaf ?? false,
          onSelected: () => _updateMember(context, ref, serverKey, spaceId, userId, {
            'deaf': !(voiceState?.deaf ?? false),
          }),
        ),
      if (rights.move && !isSelf) ...[
        AccordMenuEntry(
          key: const Key('voice-mod-disconnect'),
          label: 'Disconnect',
          destructive: true,
          onSelected: () => _updateMember(context, ref, serverKey, spaceId, userId, {
            'channel_id': null,
          }),
        ),
        AccordMenuEntry(
          key: const Key('voice-mod-move'),
          label: 'Move To',
          icon: AppIcons.chevronRight,
          onSelected: () => _showMoveMenu(
            context,
            ref,
            serverKey: serverKey,
            spaceId: spaceId,
            channelId: channelId,
            userId: userId,
            globalPosition: globalPosition,
          ),
        ),
      ],
    ],
    const AccordMenuEntry.divider(),
    AccordMenuEntry(
      key: const Key('voice-menu-copy-id'),
      label: 'Copy User ID',
      icon: AppIcons.badge,
      onSelected: () async {
        await Clipboard.setData(ClipboardData(text: userId));
        if (context.mounted) showInfoSnack(context, 'User ID copied');
      },
    ),
  ];
  // Outside the call we're in, our own self-mute/deafen rows make no sense:
  // drop the empty self group rather than show toggles for nothing.
  if (isSelf && !inThisCall) {
    entries.removeWhere(
      (e) =>
          e.key == const Key('voice-menu-mute') ||
          e.key == const Key('voice-menu-deafen'),
    );
  }
  return showAccordContextMenu(
    context,
    globalPosition: globalPosition,
    title: name,
    entries: _trimDividers(entries),
  );
}

/// The menu of a screen share we are watching ("…" on its tile, right-click):
/// Stop Watching ─ Mute ☐ · Stream Volume ─ Show Non-Video Participants ☑
/// [─ Pop Out Stream], as the reference client lays it out.
Future<void> showWatchedStreamMenu(
  BuildContext context,
  WidgetRef ref, {
  required String serverKey,
  required String userId,
  required String name,
  required VoidCallback onStopWatching,
  Offset? globalPosition,
  VoidCallback? onPopOut,
  bool? showNonVideoParticipants,
  ValueChanged<bool>? onShowNonVideoParticipants,
}) {
  final volumeId = streamVolumeId(userId);
  final settings = ref.read(settingsControllerProvider);
  final settingsNotifier = ref.read(settingsControllerProvider.notifier);
  final muted = settings.isUserLocallyMuted(serverKey, volumeId);
  return showAccordContextMenu(
    context,
    globalPosition: globalPosition,
    title: "$name's Screen",
    entries: [
      AccordMenuEntry(
        key: const Key('stream-stop-watching'),
        label: 'Stop Watching',
        onSelected: onStopWatching,
      ),
      const AccordMenuEntry.divider(),
      AccordMenuEntry(
        key: const Key('stream-mute'),
        label: 'Mute',
        checked: muted,
        onSelected: () =>
            settingsNotifier.setUserLocallyMuted(serverKey, volumeId, !muted),
      ),
      AccordMenuEntry.widget(
        child: UserVolumeSlider(
          key: const Key('stream-volume-slider'),
          serverKey: serverKey,
          volumeId: volumeId,
          label: 'Stream Volume',
        ),
        height: UserVolumeSlider.height,
      ),
      if (showNonVideoParticipants != null &&
          onShowNonVideoParticipants != null) ...[
        const AccordMenuEntry.divider(),
        AccordMenuEntry(
          key: const Key('voice-menu-non-video'),
          label: 'Show Non-Video Participants',
          checked: showNonVideoParticipants,
          onSelected: () =>
              onShowNonVideoParticipants(!showNonVideoParticipants),
        ),
      ],
      if (onPopOut != null) ...[
        const AccordMenuEntry.divider(),
        AccordMenuEntry(
          key: const Key('stream-pop-out'),
          label: 'Pop Out Stream',
          icon: AppIcons.openInNew,
          onSelected: onPopOut,
        ),
      ],
    ],
  );
}

/// "User Volume" (or "Stream Volume") with its percentage and a slider,
/// inside a menu. Changes apply live and only affect what we hear.
class UserVolumeSlider extends ConsumerWidget {
  const UserVolumeSlider({
    super.key,
    required this.serverKey,
    required this.volumeId,
    required this.label,
  });

  /// The menu row height this widget takes.
  static const double height = 64;

  final String serverKey;

  /// The user id, or [streamVolumeId] of a stream.
  final String volumeId;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final volume = ref.watch(
      settingsControllerProvider.select(
        (s) => s.userVolume(serverKey, volumeId),
      ),
    );
    final muted = ref.watch(
      settingsControllerProvider.select(
        (s) => s.isUserLocallyMuted(serverKey, volumeId),
      ),
    );
    final max = maxUserVolumeSlider;
    final shown = volume.clamp(0, max);
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  muted ? 'Muted' : '$shown%',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: colors.gray),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: shown.toDouble(),
                max: max.toDouble(),
                divisions: max,
                label: '$shown%',
                padding: const EdgeInsets.symmetric(vertical: 8),
                onChanged: muted
                    ? null
                    : (v) => ref
                          .read(settingsControllerProvider.notifier)
                          .setUserVolume(serverKey, volumeId, v.round()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

VoiceModerationRights _readModerationRights(WidgetRef ref, String? spaceId) {
  if (spaceId == null) return VoiceModerationRights.none;
  final space = ref
      .read(spacesControllerProvider)
      ?.firstWhereOrNull((s) => s.id == spaceId);
  return VoiceModerationRights.from(ref.readAccordPermissions(space, spaceId));
}

/// The `@handle` a mention of this participant types: their username, else
/// the name shown.
String _handle(AccordUser? user, String name) {
  final username = user?.username ?? '';
  return username.isNotEmpty ? username : name;
}

Future<void> _openProfile(
  BuildContext context,
  WidgetRef ref,
  String? spaceId,
  String userId,
  AccordUser? user,
) {
  if (spaceId != null) {
    return showAccordMemberPopout(context, spaceId: spaceId, userId: userId);
  }
  return showAccordUserProfile(
    context,
    user ?? AccordUser(id: userId),
    cdnUrl: ref.readCdnUrl(),
  );
}

/// Sends a member update (server mute / deafen / move / disconnect),
/// reporting a refusal. Moderation never retries silently.
Future<void> _updateMember(
  BuildContext context,
  WidgetRef ref,
  String serverKey,
  String spaceId,
  String userId,
  Map<String, dynamic> body,
) async {
  final client = ref.read(accordAuthProvider.notifier).clientForKey(serverKey);
  if (client == null) return;
  final result = await client.members.update(spaceId, userId, body);
  if (!result.ok && context.mounted) {
    showInfoSnack(context, result.errorMessageOr('That didn’t work.'));
  }
}

/// "Move To": a second menu listing the other voice channels of the space.
Future<void> _showMoveMenu(
  BuildContext context,
  WidgetRef ref, {
  required String serverKey,
  required String spaceId,
  required String channelId,
  required String userId,
  Offset? globalPosition,
}) {
  final targets = voiceMoveTargets(
    ref.read(accordChannelsControllerProvider(serverKey, spaceId)) ?? const [],
    channelId,
  );
  return showAccordContextMenu(
    context,
    globalPosition: globalPosition,
    title: 'Move To',
    entries: [
      for (final channel in targets)
        AccordMenuEntry(
          label: channel.name ?? channel.id,
          icon: channel.type == 'stage' ? AppIcons.podcasts : AppIcons.volumeUp,
          onSelected: () => _updateMember(context, ref, serverKey, spaceId, userId, {
            'channel_id': channel.id,
          }),
        ),
    ],
  );
}

/// Drops leading, trailing and doubled dividers left by conditional groups.
List<AccordMenuEntry> _trimDividers(List<AccordMenuEntry> entries) {
  final out = <AccordMenuEntry>[];
  for (final e in entries) {
    if (e.isDivider && (out.isEmpty || out.last.isDivider)) continue;
    out.add(e);
  }
  while (out.isNotEmpty && out.last.isDivider) {
    out.removeLast();
  }
  return out;
}
