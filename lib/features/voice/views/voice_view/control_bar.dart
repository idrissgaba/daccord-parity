part of '../voice_view.dart';

/// The call controls along the bottom of the call view, laid out as the
/// reference client's: an invite button at the left; in the middle a pill
/// group [Mic ▾][Camera ▾], a group [Share][Arcade][Soundboard][…] and a
/// wide red hang-up; pop-out (web) and full screen at the right. Deafen and
/// the voice settings live in the user panel and the "…" menu, not here.
class _ControlBar extends ConsumerWidget {
  const _ControlBar({required this.channelId, required this.spaceId});

  final String channelId;
  final String? spaceId;

  /// The strip the controls sit in: buttons of 48 centred 16 px above the
  /// bottom edge, the rest clearing the tiles above.
  static const double height = 112;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final space = spaceId == null
        ? null
        : ref.watch(
            spacesControllerProvider.select(
              (spaces) => spaces?.firstWhereOrNull((s) => s.id == spaceId),
            ),
          );
    final permissions = spaceId == null
        ? const <String>{}
        : ref.watchAccordPermissions(space, spaceId!);
    final canInvite =
        spaceId != null &&
        accordHasPermission(permissions, AccordPermission.createInvites);
    final canUseSoundboard =
        spaceId != null &&
        accordHasPermission(permissions, AccordPermission.useSoundboard);
    final muted = voice.selfMute || !voice.canSpeak;
    final blockedReason = voice.speakBlockedReason;
    final popOutTrack = canPopOutStream ? _popOutTrack(notifier.session) : null;

    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 16,
            bottom: 16,
            child: canInvite
                ? _PlainBarButton(
                    key: const Key('voice-invite'),
                    icon: AppIcons.personAdd,
                    tooltip: 'Invite to Voice',
                    onPressed: () =>
                        showAccordInvites(context, spaceId: spaceId!),
                  )
                : const SizedBox(width: 48, height: 48),
          ),
          // Pop-out and full screen sit at the right end of the bar, apart
          // from the call controls.
          Positioned(
            right: 16,
            bottom: 16,
            child: ValueListenableBuilder<bool>(
              valueListenable: voiceViewExpanded,
              builder: (context, expanded, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Full screen keeps only its own exit button at the right.
                  if (popOutTrack != null && !expanded)
                    _PlainBarButton(
                      key: const Key('voice-pop-out'),
                      icon: AppIcons.openInNew,
                      tooltip: 'Pop Out',
                      onPressed: () => popOutStream(popOutTrack),
                    ),
                  _PlainBarButton(
                    key: const Key('voice-full-screen'),
                    icon: expanded ? AppIcons.fullscreenExit : AppIcons.fullscreen,
                    tooltip: expanded
                        ? 'Exit full screen (Esc)'
                        : 'Full screen',
                    onPressed: () => setVoiceViewExpanded(!expanded),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BarGroup(
                  children: [
                    _BarButton(
                      key: const Key('voice-mic'),
                      icon: muted ? AppIcons.micOff : AppIcons.mic,
                      tooltip:
                          blockedReason ?? (voice.selfMute ? 'Unmute' : 'Mute'),
                      tint: muted ? _BarTint.red : null,
                      onPressed: notifier.toggleMute,
                    ),
                    _BarChevron(
                      key: const Key('voice-mic-devices'),
                      tooltip: 'Audio devices',
                      tint: muted ? _BarTint.red : null,
                      onPressed: (anchor) =>
                          _showAudioDeviceMenu(context, ref, anchor),
                    ),
                    if (!inAudience) ...[
                      _BarButton(
                        key: const Key('voice-camera'),
                        icon: voice.selfVideo
                            ? AppIcons.videocam
                            : AppIcons.videocamOff,
                        tooltip: voice.selfVideo
                            ? 'Turn Off Camera'
                            : 'Turn On Camera',
                        tint: voice.selfVideo ? _BarTint.green : null,
                        onPressed: notifier.toggleVideo,
                      ),
                      _BarChevron(
                        key: const Key('voice-camera-devices'),
                        tooltip: 'Camera devices',
                        tint: voice.selfVideo ? _BarTint.green : null,
                        onPressed: (anchor) =>
                            _showCameraDeviceMenu(context, ref, anchor),
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 16),
                _BarGroup(
                  children: [
                    if (stageAction != null && spaceId != null)
                      _BarButton(
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
                        tint: stageAction == StageAction.lowerHand
                            ? _BarTint.primary
                            : null,
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
                    if (canShareScreen && !inAudience) ...[
                      _BarButton(
                        key: const Key('voice-share'),
                        icon: AppIcons.screenShare,
                        tooltip: voice.selfStream
                            ? 'Stream options'
                            : 'Share Your Screen',
                        tint: voice.selfStream ? _BarTint.green : null,
                        onPressed: () =>
                            toggleScreenShareWithPicker(context, ref),
                      ),
                      // Live, the share button grows a chevron with the
                      // stream's menu (stop, change source, pop out).
                      if (voice.selfStream)
                        _BarChevron(
                          key: const Key('stream-menu-chevron'),
                          tooltip: 'Stream options',
                          tint: _BarTint.green,
                          onPressed: (anchor) => showStreamMenu(
                            context,
                            ref,
                            globalPosition: anchor,
                            popOutTrack: notifier.session?.localScreenTrack,
                            preferAbove: true,
                          ),
                        ),
                    ],
                    // The reference client's "Activities" slot: our Arcade.
                    if (spaceId != null)
                      _BarButton(
                        key: const Key('voice-arcade'),
                        icon: AppIcons.sportsEsportsOutlined,
                        tooltip: 'Arcade',
                        onPressed: () => showSpaceArcade(
                          context,
                          serverKey: serverKey,
                          spaceId: spaceId!,
                        ),
                      ),
                    if (canUseSoundboard)
                      SoundboardTrigger(
                        serverKey: serverKey,
                        spaceId: spaceId!,
                        placement: SoundboardPlacement.above,
                        label: 'Open Soundboard',
                        builder: (context, onPressed, open) => _BarButton(
                          key: const Key('voice-soundboard'),
                          icon: AppIcons.celebration,
                          tooltip: '',
                          highlighted: open,
                          onPressed: onPressed,
                        ),
                      ),
                    _BarButton(
                      key: const Key('voice-more'),
                      icon: AppIcons.moreHoriz,
                      tooltip: 'More',
                      onPressed: () {},
                      onPressedAt: (anchor) => showAccordContextMenu(
                        context,
                        globalPosition: anchor,
                        preferAbove: true,
                        title: 'More',
                        entries: [
                          AccordMenuEntry(
                            label: 'Voice Settings',
                            icon: AppIcons.settings,
                            onSelected: () => showVoiceSettings(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                _HangUpButton(
                  onPressed: () => unawaited(
                    ref
                        .read(callControllerProvider.notifier)
                        .hangUp(channelId, spaceId),
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

/// Lists the microphones and speakers; picking one applies at once.
Future<void> _showAudioDeviceMenu(
  BuildContext context,
  WidgetRef ref,
  Offset? anchor,
) async {
  final inputs = await _devices(lk.Hardware.instance.audioInputs);
  final outputs = await _devices(lk.Hardware.instance.audioOutputs);
  if (!context.mounted) return;
  final settings = ref.read(settingsControllerProvider);
  final notifier = ref.read(settingsControllerProvider.notifier);
  await showAccordContextMenu(
    context,
    globalPosition: anchor,
    preferAbove: true,
    title: 'Audio devices',
    entries: [
      ..._deviceEntries(
        'Input Device',
        inputs,
        settings.audioInputDeviceId,
        notifier.setAudioInputDevice,
        fallbackLabel: 'Microphone',
      ),
      if (canPickAudioOutputDevice) ...[
        const AccordMenuEntry.divider(),
        ..._deviceEntries(
          'Output Device',
          outputs,
          settings.audioOutputDeviceId,
          notifier.setAudioOutputDevice,
          fallbackLabel: 'Speakers',
        ),
      ],
      const AccordMenuEntry.divider(),
      AccordMenuEntry(
        label: 'Voice Settings',
        icon: AppIcons.settings,
        onSelected: () => showVoiceSettings(context),
      ),
    ],
  );
}

/// Lists the cameras; picking one applies at once.
Future<void> _showCameraDeviceMenu(
  BuildContext context,
  WidgetRef ref,
  Offset? anchor,
) async {
  final cameras = await _devices(lk.Hardware.instance.videoInputs);
  if (!context.mounted) return;
  final settings = ref.read(settingsControllerProvider);
  final notifier = ref.read(settingsControllerProvider.notifier);
  await showAccordContextMenu(
    context,
    globalPosition: anchor,
    preferAbove: true,
    title: 'Camera',
    entries: [
      ..._deviceEntries(
        'Camera',
        cameras,
        settings.videoInputDeviceId,
        notifier.setVideoInputDevice,
        fallbackLabel: 'Camera',
      ),
      const AccordMenuEntry.divider(),
      AccordMenuEntry(
        label: 'Voice Settings',
        icon: AppIcons.settings,
        onSelected: () => showVoiceSettings(context),
      ),
    ],
  );
}

Future<List<lk.MediaDevice>> _devices(
  Future<List<lk.MediaDevice>> Function() list,
) async {
  try {
    return await list();
  } catch (_) {
    return const [];
  }
}

/// A heading row, then one checked row per device ("System default" first).
List<AccordMenuEntry> _deviceEntries(
  String heading,
  List<lk.MediaDevice> devices,
  String selectedId,
  ValueChanged<String> onPick, {
  required String fallbackLabel,
}) {
  final ids = devices.map((d) => d.deviceId).toSet();
  final current = ids.contains(selectedId) ? selectedId : '';
  return [
    AccordMenuEntry(label: heading, enabled: false),
    AccordMenuEntry(
      label: 'System default',
      checked: current == '',
      onSelected: () => onPick(''),
    ),
    for (var i = 0; i < devices.length; i++)
      AccordMenuEntry(
        label: devices[i].label.isNotEmpty
            ? devices[i].label
            : '$fallbackLabel ${i + 1}',
        checked: current == devices[i].deviceId,
        onSelected: () => onPick(devices[i].deviceId),
      ),
  ];
}

enum _BarTint { red, green, primary }

extension on _BarTint {
  Color color(BonfireThemeExtension colors) => switch (this) {
    _BarTint.red => colors.red,
    _BarTint.green => colors.green,
    _BarTint.primary => colors.primary,
  };
}

/// A rounded group of adjoining buttons on a faint fill, as the reference
/// client groups its call controls.
class _BarGroup extends StatelessWidget {
  const _BarGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// One 48×48 control inside a [_BarGroup]. A [tint] colours the icon and
/// washes the cell with the same colour (muted mic: red; live camera or
/// share: green).
class _BarButton extends StatelessWidget {
  const _BarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.onPressedAt,
    this.tint,
    this.highlighted = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Its popover is open (soundboard): drawn in the hover tint.
  final bool highlighted;

  /// Replaces [onPressed] with a handler given the button's anchor (menus).
  final void Function(Offset? anchor)? onPressedAt;
  final _BarTint? tint;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final tintColor = tint?.color(colors);
    return Tooltip(
      message: tooltip,
      child: Material(
        color:
            tintColor?.withValues(alpha: 0.2) ??
            (highlighted ? colors.hover : Colors.transparent),
        child: InkWell(
          onTap: onPressedAt == null
              ? onPressed
              : () => onPressedAt!(menuAnchorOf(context)),
          hoverColor: colors.hover,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              icon,
              size: 20,
              color: tintColor ?? colors.dirtyWhite,
            ),
          ),
        ),
      ),
    );
  }
}

/// The narrow "▾" glued to a split button, opening its device or stream menu.
class _BarChevron extends StatelessWidget {
  const _BarChevron({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.tint,
  });

  final String tooltip;
  final void Function(Offset? anchor) onPressed;
  final _BarTint? tint;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final tintColor = tint?.color(colors);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tintColor?.withValues(alpha: 0.2) ?? Colors.transparent,
        child: InkWell(
          onTap: () => onPressed(menuAnchorOf(context)),
          hoverColor: colors.hover,
          child: SizedBox(
            width: 24,
            height: 48,
            child: Icon(
              AppIcons.keyboardArrowDown,
              size: 12,
              color: tintColor ?? colors.dirtyWhite,
            ),
          ),
        ),
      ),
    );
  }
}

/// A bare 48×48 icon button (invite, pop-out, full screen).
class _PlainBarButton extends StatelessWidget {
  const _PlainBarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          hoverColor: colors.hover,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, size: 22, color: colors.dirtyWhite),
          ),
        ),
      ),
    );
  }
}

/// The wide red hang-up at the end of the controls.
class _HangUpButton extends StatelessWidget {
  const _HangUpButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Tooltip(
      message: 'Disconnect',
      child: Material(
        color: colors.red,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: const SizedBox(
            width: 68,
            height: 48,
            child: Icon(AppIcons.callEnd, size: 22, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
