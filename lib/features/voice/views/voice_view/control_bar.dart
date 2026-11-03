part of '../voice_view.dart';

class _ControlBar extends ConsumerWidget {
  const _ControlBar({required this.channelId, required this.spaceId});

  final String channelId;
  final String? spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final voice = ref.watch(voiceControllerProvider);
    final notifier = ref.read(voiceControllerProvider.notifier);
    final serverKey = ref.watchActiveServerKey() ?? '';
    final stage = watchIsStage(ref, spaceId, channelId);
    final myId = ref.watchUserId();
    final me = stage
        ? ref.watch(
            voiceStatesControllerProvider(
              serverKey,
            ).select((cache) => cache[channelId]?[myId]),
          )
        : null;
    final inAudience = stage && (me?.suppress ?? true);
    final stageAction = stage
        ? stageActionFor(
            me,
            moderator: watchVoiceModerationRights(ref, spaceId).mute,
          )
        : null;
    if (stage) {
      ref.listen(
        voiceStatesControllerProvider(
          serverKey,
        ).select((cache) => cache[channelId]?[myId]?.suppress),
        (prev, next) {
          if (prev == true && next == false) {
            showInfoSnack(context, 'You’re on stage — you can speak now.');
          }
        },
      );
    }
    final blockedReason = voice.speakBlockedReason;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colors.foreground,
        border: Border(top: BorderSide(color: colors.background, width: 1)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pop-out and full screen sit at the right end of the bar, apart
          // from the call controls, as in other chat apps.
          Positioned(
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canPopOutStream && _popOutTrack(notifier.session) != null)
                  _ControlButton(
                    key: const Key('voice-pop-out'),
                    icon: AppIcons.openInNew,
                    tooltip: 'Pop Out',
                    active: false,
                    activeColor: colors.primary,
                    onPressed: () =>
                        popOutStream(_popOutTrack(notifier.session)!),
                  ),
                ValueListenableBuilder<bool>(
                  valueListenable: voiceViewExpanded,
                  builder: (context, expanded, _) => _ControlButton(
                    key: const Key('voice-full-screen'),
                    icon: expanded ? AppIcons.fullscreenExit : AppIcons.fullscreen,
                    tooltip: expanded
                        ? 'Exit full screen (Esc)'
                        : 'Full screen',
                    active: false,
                    activeColor: colors.primary,
                    onPressed: () => setVoiceViewExpanded(!expanded),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ControlButton(
                icon: voice.selfMute || !voice.canSpeak
                    ? AppIcons.micOff
                    : AppIcons.mic,
                tooltip: blockedReason ?? (voice.selfMute ? 'Unmute' : 'Mute'),
                active: voice.selfMute || !voice.canSpeak,
                activeColor: colors.red,
                onPressed: notifier.toggleMute,
              ),
              _ControlButton(
                icon: voice.selfDeaf || voice.serverDeaf
                    ? AppIcons.headsetOff
                    : AppIcons.headset,
                tooltip: voice.serverDeaf
                    ? 'A moderator has deafened you.'
                    : (voice.selfDeaf ? 'Undeafen' : 'Deafen'),
                active: voice.selfDeaf || voice.serverDeaf,
                activeColor: colors.red,
                onPressed: notifier.toggleDeafen,
              ),
              if (stageAction != null && spaceId != null)
                _ControlButton(
                  key: const Key('stage-action'),
                  icon: switch (stageAction) {
                    StageAction.raiseHand => AppIcons.backHandOutlined,
                    StageAction.lowerHand => AppIcons.backHand,
                    StageAction.speak => AppIcons.micExternalOn,
                    StageAction.leaveStage => AppIcons.group,
                  },
                  tooltip: switch (stageAction) {
                    StageAction.raiseHand => 'Raise hand to speak',
                    StageAction.lowerHand => 'Lower hand',
                    StageAction.speak => 'Speak on stage',
                    StageAction.leaveStage => 'Move to audience',
                  },
                  active: stageAction == StageAction.lowerHand,
                  activeColor: colors.primary,
                  onPressed: () {
                    final update = stageUpdateFor(stageAction);
                    updateStage(
                      context,
                      ref,
                      serverKey: serverKey,
                      spaceId: spaceId!,
                      userId: '@me',
                      suppress: update.suppress,
                      requestToSpeak: update.requestToSpeak,
                    );
                  },
                ),
              if (!inAudience)
                _ControlButton(
                  icon: voice.selfVideo ? AppIcons.videocamOff : AppIcons.videocam,
                  tooltip: voice.selfVideo ? 'Stop camera' : 'Camera',
                  active: voice.selfVideo,
                  activeColor: colors.green,
                  onPressed: notifier.toggleVideo,
                ),
              if (canShareScreen && !inAudience) ...[
                _ControlButton(
                  icon: voice.selfStream
                      ? AppIcons.stopScreenShare
                      : AppIcons.screenShare,
                  tooltip: voice.selfStream
                      ? 'Stop Streaming'
                      : 'Share Your Screen',
                  active: voice.selfStream,
                  activeColor: colors.green,
                  onPressed: () => toggleScreenShareWithPicker(context, ref),
                ),
                // Live, the share button grows a chevron with the stream's menu
                // (stop, change source, pop out), as in other chat apps.
                if (voice.selfStream)
                  Builder(
                    builder: (context) => _ControlButton(
                      key: const Key('stream-menu-chevron'),
                      icon: AppIcons.keyboardArrowDown,
                      tooltip: 'Stream options',
                      active: true,
                      activeColor: colors.green,
                      compact: true,
                      onPressed: () => showStreamMenu(
                        context,
                        ref,
                        globalPosition: menuAnchorOf(context),
                        popOutTrack: notifier.session?.localScreenTrack,
                      ),
                    ),
                  ),
              ],
              _ControlButton(
                icon: AppIcons.settings,
                tooltip: 'Voice settings',
                active: false,
                activeColor: colors.primary,
                onPressed: () => showVoiceSettings(context),
              ),
              _ControlButton(
                icon: AppIcons.callEnd,
                tooltip: 'Disconnect',
                active: true,
                activeColor: colors.red,
                onPressed: () => unawaited(
                  ref
                      .read(callControllerProvider.notifier)
                      .hangUp(channelId, spaceId),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The stream a web pop-out takes: our own share, else the first stream we
/// watch.
VideoTrack? _popOutTrack(VoiceSession? session) {
  if (session == null) return null;
  final own = session.localScreenTrack;
  if (own != null) return own;
  final room = session.room;
  if (room == null) return null;
  for (final p in room.remoteParticipants.values) {
    if (!session.isWatchingStream(p.identity)) continue;
    final track = session.remoteScreenTrack(p.identity);
    if (track != null) return track;
  }
  return null;
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.activeColor,
    required this.onPressed,
    this.compact = false,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final Color activeColor;
  final VoidCallback onPressed;

  /// A narrow companion button (the chevron beside a split button).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: EdgeInsets.only(left: compact ? 0 : 6, right: 6),
      child: Material(
        color: active ? activeColor : colors.darkGray,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          visualDensity: compact ? VisualDensity.compact : null,
          padding: compact ? EdgeInsets.zero : null,
          constraints: compact
              ? const BoxConstraints(minWidth: 28, minHeight: 40)
              : null,
          icon: Icon(
            icon,
            size: 20,
            color: active ? Colors.white : colors.dirtyWhite,
          ),
        ),
      ),
    );
  }
}
