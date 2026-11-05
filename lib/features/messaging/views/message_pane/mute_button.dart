part of 'message_pane.dart';

/// The header bell: its menu (Mute Channel › · Use category default / All
/// Messages / Only @mentions / Nothing) opens under it, right-aligned, as the
/// reference client's. Server-side mutes come from the shared per-connection
/// cache; levels are app settings.
class _MuteButton extends ConsumerWidget {
  const _MuteButton({required this.channelId, required this.spaceId});

  final String channelId;
  final String? spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeKey = ref.watch(
      connectionsControllerProvider.select((state) => state.activeKey),
    );
    final mutedChannels = activeKey == null
        ? const AsyncData<Set<String>>(<String>{})
        : ref.watch(mutedChannelsControllerProvider(activeKey));
    final muted = mutedChannels.value?.contains(channelId) ?? false;
    final level = ref.watch(
      settingsControllerProvider.select(
        (settings) => activeKey == null
            ? null
            : settings.channelNotificationLevel(activeKey, channelId),
      ),
    );
    return Builder(
      builder: (buttonContext) => _HeaderButton(
        key: const Key('channel-header-notifications'),
        tooltip: 'Notification Settings',
        icon: muted
            ? AppIcons.notificationsOff
            : (level == AccordSettings.channelNotifNothing
                  ? AppIcons.notificationsPaused
                  : AppIcons.notificationsNone),
        onPressed: () {
          final serverKey = activeKey;
          if (serverKey == null) return;
          final box = buttonContext.findRenderObject() as RenderBox?;
          showAccordContextMenu(
            context,
            anchorX: 1,
            globalPosition: box?.localToGlobal(
              Offset(box.size.width / 2 + 15, box.size.height + 4),
            ),
            title: 'Notification Settings',
            entries: [
              channelMuteEntry(
                context,
                ref,
                serverKey: serverKey,
                channelId: channelId,
                muted: muted,
                noun: 'Channel',
              ),
              const AccordMenuEntry.divider(),
              ...channelNotificationEntries(
                ref,
                serverKey: serverKey,
                spaceId: spaceId,
                channelId: channelId,
              ),
            ],
          );
        },
      ),
    );
  }
}
