import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/experiences/views/arcade.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/accord_soundboard.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/services/voice_session.dart';
import 'package:bonfire/features/voice/utils/audio_output_support.dart';
import 'package:bonfire/features/voice/views/screen_share_picker.dart';
import 'package:bonfire/features/voice/views/stream_menu.dart';
import 'package:bonfire/features/voice/views/voice_connection_info.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The voice-connection panel at the foot of the sidebar while connected to a
/// channel, above the user panel: a status row ("Voice Connected" in green
/// over "channel / space", with the connection-info and hang-up buttons on
/// the right) and a row of full-width buttons — camera, screen share, Arcade
/// and soundboard — as in other voice chat apps. Empty when not in a call.
class VoiceBar extends ConsumerStatefulWidget {
  const VoiceBar({super.key, this.onTapStatus});

  /// Called when the status row is tapped — the host opens the voice view for
  /// the connected channel.
  final VoidCallback? onTapStatus;

  @override
  ConsumerState<VoiceBar> createState() => _VoiceBarState();
}

class _VoiceBarState extends ConsumerState<VoiceBar> {
  Timer? _errorTimer;

  @override
  void dispose() {
    _errorTimer?.cancel();
    super.dispose();
  }

  void _scheduleErrorClear() {
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) ref.read(voiceControllerProvider.notifier).clearError();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final voice = ref.watch(voiceControllerProvider);
    if (!voice.isConnected) return const SizedBox.shrink();

    // Capture/connection failures remain actionable until a retry succeeds.
    // Dismissing them would make a broken call look healthy again.
    final persistentError =
        voice.sessionState == VoiceSessionState.failed ||
        (voice.selfMute && (voice.error?.startsWith('Microphone ') ?? false));
    if (persistentError || voice.error == null) {
      _errorTimer?.cancel();
    } else {
      _scheduleErrorClear();
    }

    final serverKey = ref.readActiveServerKey() ?? '';
    final channelName = voice.spaceId == null
        ? null
        : ref
              .watch(
                accordChannelsControllerProvider(serverKey, voice.spaceId!),
              )
              ?.firstWhereOrNull((c) => c.id == voice.channelId)
              ?.name;

    final spaceId = voice.spaceId;
    var canUseSoundboard = false;
    var canManageSoundboard = false;
    if (spaceId != null) {
      final space = ref.watch(
        spacesControllerProvider.select(
          (s) => s?.firstWhereOrNull((sp) => sp.id == spaceId),
        ),
      );
      final perms = ref.watchAccordPermissions(space, spaceId);
      canUseSoundboard = accordHasPermission(
        perms,
        AccordPermission.useSoundboard,
      );
      canManageSoundboard = accordHasPermission(
        perms,
        AccordPermission.manageSoundboard,
      );
    }

    final spaceName = spaceId == null
        ? null
        : ref.watch(
            spacesControllerProvider.select(
              (s) => s?.firstWhereOrNull((sp) => sp.id == spaceId)?.name,
            ),
          );
    final (statusText, statusColor) = _status(voice, colors);
    final where = [
      if (channelName != null) channelName,
      if (spaceName != null) spaceName,
    ].join(' / ');
    // Only read while the mic is live.
    final pushToTalk =
        !voice.selfMute &&
        ref.watch(settingsControllerProvider.select((s) => s.pushToTalk));

    return Container(
      key: const Key('voice-bar'),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Live: a "Go Live" card above the connection row, with the
          // button that ends the stream.
          if (voice.selfStream) ...[
            _GoLiveCard(
              onStop: () => ref
                  .read(voiceControllerProvider.notifier)
                  .toggleScreenShare(),
            ),
            Divider(height: 9, thickness: 1, color: colors.hairline),
          ],
          InkWell(
            onTap: widget.onTapStatus,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 2),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.hover,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      AppIcons.networkCheck,
                      key: const Key('voice-bar-status-icon'),
                      size: 20,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: where.isEmpty
                          ? statusText
                          : '$statusText — $where',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusText,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium!.copyWith(
                              fontSize: 14,
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (where.isNotEmpty)
                            Text(
                              where,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall!.copyWith(
                                fontSize: 12,
                                color: colors.gray,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  _StatusButton(
                    key: const Key('voice-bar-connection-info'),
                    tooltip: 'Connection info',
                    icon: AppIcons.equalizer,
                    onPressed: () => showVoiceConnectionInfo(context),
                  ),
                  _StatusButton(
                    key: const Key('voice-bar-disconnect'),
                    tooltip: 'Disconnect',
                    icon: AppIcons.callEnd,
                    onPressed: () =>
                        ref.read(voiceControllerProvider.notifier).leave(),
                  ),
                ],
              ),
            ),
          ),
          if (voice.sessionState == VoiceSessionState.failed)
            TextButton.icon(
              onPressed: () => ref
                  .read(voiceControllerProvider.notifier)
                  .join(voice.channelId!, voice.spaceId),
              icon: const Icon(AppIcons.refresh, size: 16),
              label: const Text('Retry connection'),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              _VoiceButton(
                key: const Key('voice-bar-camera'),
                icon: voice.selfVideo
                    ? AppIcons.videocam
                    : AppIcons.videocamOff,
                tooltip: voice.selfVideo ? 'Turn Off Camera' : 'Turn On Camera',
                active: voice.selfVideo,
                onPressed: () =>
                    ref.read(voiceControllerProvider.notifier).toggleVideo(),
              ),
              if (canShareScreen) ...[
                const SizedBox(width: 4),
                Builder(
                  builder: (context) => _VoiceButton(
                    key: const Key('voice-bar-screen-share'),
                    icon: AppIcons.screenShare,
                    tooltip: voice.selfStream
                        ? 'Stream options'
                        : 'Share Your Screen',
                    active: voice.selfStream,
                    // Live, the button opens the stream's menu (stop, change
                    // source) instead of ending it outright.
                    onPressed: voice.selfStream
                        ? () => showStreamMenu(
                            context,
                            ref,
                            globalPosition: menuAnchorOf(context),
                          )
                        : () => toggleScreenShareWithPicker(context, ref),
                  ),
                ),
              ],
              // The reference client's "Activities" slot: our Arcade.
              if (spaceId != null) ...[
                const SizedBox(width: 4),
                _VoiceButton(
                  key: const Key('voice-bar-arcade'),
                  icon: AppIcons.sportsEsportsOutlined,
                  tooltip: 'Arcade',
                  active: false,
                  onPressed: () => showSpaceArcade(
                    context,
                    serverKey: serverKey,
                    spaceId: spaceId,
                  ),
                ),
              ],
              if (canUseSoundboard && spaceId != null) ...[
                const SizedBox(width: 4),
                _VoiceButton(
                  key: const Key('voice-bar-soundboard'),
                  icon: AppIcons.graphicEq,
                  tooltip: 'Soundboard',
                  active: false,
                  onPressed: () => showAccordSoundboard(
                    context,
                    spaceId: spaceId,
                    canManage: canManageSoundboard,
                  ),
                ),
              ],
            ],
          ),
          if (pushToTalk) ...[
            const SizedBox(height: 4),
            _PushToTalkButton(
              onChanged: (pressed) => ref
                  .read(voiceControllerProvider.notifier)
                  .setPushToTalkPressed(pressed),
            ),
          ],
        ],
      ),
    );
  }

  (String, Color) _status(VoiceConnection voice, BonfireThemeExtension colors) {
    if (voice.error != null) return (voice.error!, colors.red);
    // Tell the user *why* they've dimmed out in the participant list — an AFK
    // badge nobody explains is just a mystery.
    if (voice.isAfk && voice.sessionState == VoiceSessionState.connected) {
      return ('Away', colors.yellow);
    }
    switch (voice.sessionState) {
      case VoiceSessionState.connected:
        return ('Voice Connected', colors.green);
      case VoiceSessionState.connecting:
        return ('Connecting…', colors.yellow);
      case VoiceSessionState.reconnecting:
        return ('Reconnecting…', colors.yellow);
      case VoiceSessionState.failed:
        return ('Connection failed', colors.red);
      case VoiceSessionState.disconnected:
        return ('Voice', colors.gray);
    }
  }
}

/// Hold-to-talk button for push-to-talk mode — the only way to talk on touch
/// devices, and an alternative to the key on desktop.
class _PushToTalkButton extends StatefulWidget {
  const _PushToTalkButton({required this.onChanged});

  final ValueChanged<bool> onChanged;

  @override
  State<_PushToTalkButton> createState() => _PushToTalkButtonState();
}

class _PushToTalkButtonState extends State<_PushToTalkButton> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
    widget.onChanged(pressed);
  }

  @override
  void dispose() {
    if (_pressed) widget.onChanged(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Tooltip(
      message: 'Hold to talk',
      child: Listener(
        key: const Key('push-to-talk-button'),
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: Container(
          height: 32,
          decoration: BoxDecoration(
            color: _pressed
                ? colors.green.withValues(alpha: 0.3)
                : colors.hover,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                AppIcons.recordVoiceOver,
                size: 20,
                color: _pressed ? colors.green : colors.dirtyWhite,
              ),
              const SizedBox(width: 8),
              Text(
                'Hold to talk',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _pressed ? colors.green : colors.dirtyWhite,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card above the connection row while we stream: the stream icon, "Go
/// Live", and the button that ends the stream.
class _GoLiveCard extends StatelessWidget {
  const _GoLiveCard({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      key: const Key('voice-bar-go-live'),
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors.yellow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              AppIcons.screenShare,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Go Live',
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.dirtyWhite,
              ),
            ),
          ),
          _StatusButton(
            key: const Key('voice-bar-stop-stream'),
            tooltip: 'Stop Streaming',
            icon: AppIcons.stopScreenShareOutlined,
            onPressed: onStop,
          ),
        ],
      ),
    );
  }
}

/// A 32×32 icon button of the status row (connection info, hang up).
class _StatusButton extends StatelessWidget {
  const _StatusButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
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
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          hoverColor: colors.hover,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, size: 20, color: colors.interactive),
          ),
        ),
      ),
    );
  }
}

/// One of the full-width buttons: a 32 px rounded field with a 20 px icon;
/// green while [active] (camera on, streaming).
class _VoiceButton extends StatelessWidget {
  const _VoiceButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: active ? colors.green : colors.hover,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            hoverColor: colors.hover,
            child: SizedBox(
              height: 32,
              child: Icon(
                icon,
                size: 20,
                color: active ? Colors.white : colors.dirtyWhite,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
