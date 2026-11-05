import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/user/views/account_card.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/views/voice_settings_screen.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' show Hardware, MediaDevice;

/// The 58 px panel at the foot of the sidebar: who you are (avatar with
/// presence, name, a status line — click for status, account switching and
/// log out) and the mic, headset and settings buttons. Mic and headset carry a
/// chevron that lists the audio devices; both tint red on a red field while
/// muted or deafened, as in other voice chat apps.
class UserPanel extends ConsumerWidget {
  const UserPanel({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final userId = ref.watchUserId();
    final serverKey = ref.watchActiveServerKey() ?? '';
    final user = userId == null
        ? null
        : ref.watch(
            accordUsersControllerProvider(
              serverKey,
            ).select((users) => users[userId]),
          );
    final status = ref.watch(
      activePresencesProvider.select(
        (p) => userId == null ? 'offline' : accordPresenceStatus(p, userId),
      ),
    );
    final customStatus = ref.watch(
      activePresencesProvider.select(
        (p) => userId == null ? null : accordCustomStatus(p, userId),
      ),
    );
    // The users cache may not hold us yet: fetch ourselves, and meanwhile
    // show the name we signed in with rather than a raw id.
    if (user == null && userId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref
            .read(accordUsersControllerProvider(serverKey).notifier)
            .ensure(userId),
      );
    }
    final sessionName = ref.watch(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session.username : null,
      ),
    );
    final name = accordUserName(user, fallback: sessionName ?? userId ?? '');
    final voice = ref.watch(voiceControllerProvider);
    final voiceNotifier = ref.read(voiceControllerProvider.notifier);
    final muted = voice.selfMute || voice.selfDeaf;

    // Status line: what we're doing in voice wins over the custom status,
    // which wins over the plain presence word.
    final Widget subtitle;
    final subtitleStyle = theme.textTheme.bodySmall!.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: colors.interactive,
    );
    if (voice.selfStream) {
      subtitle = _SubtitleWithIcon(
        key: const Key('user-panel-streaming'),
        icon: AppIcons.screenShare,
        iconColor: colors.green,
        text: 'Sharing their screen',
        style: subtitleStyle,
      );
    } else if (voice.isConnected) {
      subtitle = _SubtitleWithIcon(
        key: const Key('user-panel-in-voice'),
        icon: AppIcons.volumeUp,
        iconColor: colors.green,
        text: 'In voice',
        style: subtitleStyle,
      );
    } else {
      subtitle = Text(
        (customStatus?.isNotEmpty ?? false)
            ? customStatus!
            : accordPresenceLabel(status),
        key: const Key('user-panel-status'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: subtitleStyle,
      );
    }

    return SizedBox(
      key: const Key('user-panel'),
      height: 58,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: _AccountButton(
                child: Row(
                  children: [
                    AccordMemberAvatar(
                      avatarUrl: user == null
                          ? null
                          : accordAvatarUrl(user, ref.watchCdnUrl()),
                      initial: accordInitial(name),
                      radius: 16,
                      backgroundColor: accordIdColor(userId ?? ''),
                      status: status,
                      statusRingColor: colors.raised,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: colors.dirtyWhite,
                            ),
                          ),
                          subtitle,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            _SplitButton(
              key: const Key('user-panel-mute'),
              tooltip: voice.selfMute ? 'Unmute' : 'Mute',
              icon: muted ? AppIcons.micOff : AppIcons.mic,
              active: muted,
              onPressed: voiceNotifier.toggleMute,
              chevronKey: const Key('user-panel-mute-devices'),
              onChevron: () => _showDeviceMenu(context, ref, input: true),
            ),
            const SizedBox(width: 8),
            _SplitButton(
              key: const Key('user-panel-deafen'),
              tooltip: voice.selfDeaf ? 'Undeafen' : 'Deafen',
              icon: voice.selfDeaf ? AppIcons.headsetOff : AppIcons.headset,
              active: voice.selfDeaf,
              onPressed: voiceNotifier.toggleDeafen,
              chevronKey: const Key('user-panel-deafen-devices'),
              onChevron: () => _showDeviceMenu(context, ref, input: false),
            ),
            const SizedBox(width: 8),
            _PanelButton(
              key: const Key('user-panel-settings'),
              tooltip: 'User Settings',
              icon: AppIcons.settings,
              onPressed: onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }

  /// The chevron's menu: the audio inputs (or outputs) to pick from, then the
  /// voice settings page.
  Future<void> _showDeviceMenu(
    BuildContext context,
    WidgetRef ref, {
    required bool input,
  }) async {
    final settings = ref.read(settingsControllerProvider);
    final current = input
        ? settings.audioInputDeviceId
        : settings.audioOutputDeviceId;
    List<MediaDevice> devices = const [];
    try {
      devices = input
          ? await Hardware.instance.audioInputs()
          : await Hardware.instance.audioOutputs();
    } catch (_) {
      // No permission / no media stack (web before any call): still offer the
      // settings page below.
    }
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final anchor = box == null
        ? null
        : box.localToGlobal(Offset(0, 0));
    final controller = ref.read(settingsControllerProvider.notifier);
    final currentLabel = devices
        .where(
          (d) =>
              d.deviceId == current ||
              (current.isEmpty && d == devices.first),
        )
        .map((d) => d.label.isEmpty ? d.deviceId : d.label)
        .firstOrNull;
    await showAccordContextMenu(
      context,
      globalPosition: anchor,
      preferAbove: true,
      anchorLeft: true,
      entries: [
        // The reference client's chevron menu was not captured (à
        // confirmer): the device list as a submenu, then the settings.
        AccordMenuEntry(
          label: input ? 'Input Device' : 'Output Device',
          subtitle: currentLabel ?? 'No devices found',
          submenu: [
            for (final device in devices)
              AccordMenuEntry(
                label: device.label.isEmpty ? device.deviceId : device.label,
                radio:
                    device.deviceId == current ||
                    (current.isEmpty && device == devices.first),
                onSelected: () => input
                    ? controller.setAudioInputDevice(device.deviceId)
                    : controller.setAudioOutputDevice(device.deviceId),
              ),
          ],
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
}

/// "Online" / "Idle" / "Do Not Disturb" / "Invisible" for the panel's status
/// line.
String accordPresenceLabel(String status) => switch (status) {
  'online' => 'Online',
  'idle' => 'Idle',
  'dnd' => 'Do Not Disturb',
  'invisible' || 'offline' => 'Invisible',
  _ => status,
};

class _SubtitleWithIcon extends StatelessWidget {
  const _SubtitleWithIcon({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.style,
  });

  final IconData icon;
  final Color iconColor;
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 12, color: iconColor),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    ],
  );
}

/// A 32×32 icon button of the panel.
class _PanelButton extends StatelessWidget {
  const _PanelButton({
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

/// A 32×32 action with a 16 px chevron attached on its right, the two sharing
/// one rounded pill. [active] (muted / deafened) tints the icon red on a
/// translucent red field.
class _SplitButton extends StatelessWidget {
  const _SplitButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onPressed,
    required this.onChevron,
    this.chevronKey,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;
  final VoidCallback onChevron;
  final Key? chevronKey;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final field = active ? colors.red.withValues(alpha: 0.12) : null;
    final tint = active ? colors.red : colors.interactive;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: tooltip,
          child: Material(
            color: field ?? Colors.transparent,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(8),
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(8),
              ),
              hoverColor: colors.hover,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(icon, size: 20, color: tint),
              ),
            ),
          ),
        ),
        const SizedBox(width: 1),
        Material(
          key: chevronKey,
          color: field ?? Colors.transparent,
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(8),
          ),
          child: InkWell(
            onTap: onChevron,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(8),
            ),
            hoverColor: colors.hover,
            child: SizedBox(
              width: 16,
              height: 32,
              child: Icon(AppIcons.expandMore, size: 12, color: tint),
            ),
          ),
        ),
      ],
    );
  }
}

/// Your avatar and name in the panel: a click opens the account card above
/// the panel.
class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return InkWell(
      key: const Key('user-panel-account'),
      borderRadius: BorderRadius.circular(8),
      hoverColor: colors.hover,
      onTap: () {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        showAccountCard(context, anchor: rect.shift(const Offset(0, -2)));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: child,
      ),
    );
  }
}
