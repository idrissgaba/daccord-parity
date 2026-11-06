part of '../inbox_popover.dart';

/// The Unread tab: the "Stay up to date" tip until dismissed, then one card
/// per unread channel or DM with its unread messages.
class _UnreadTab extends ConsumerWidget {
  const _UnreadTab({
    required this.serverKey,
    required this.entries,
    required this.loaded,
    required this.collapsed,
    required this.onNeed,
    required this.onToggle,
    required this.onMarkRead,
    required this.onJump,
  });

  final String serverKey;
  final List<ReadEntry> entries;
  final Map<String, List<AccordMessage>> loaded;
  final Set<String> collapsed;
  final ValueChanged<ReadEntry> onNeed;
  final ValueChanged<String> onToggle;
  final ValueChanged<ReadEntry> onMarkRead;
  final void Function(AccordMessage message, {required String? spaceId})
  onJump;

  Future<void> _notificationMenu(
    BuildContext context,
    WidgetRef ref,
    ReadEntry entry,
    Offset position,
  ) async {
    final muted = await readMutedChannels(ref, serverKey);
    if (!context.mounted) return;
    return showAccordContextMenu(
      context,
      globalPosition: position,
      anchorX: 1,
      entries: [
        channelMuteEntry(
          context,
          ref,
          serverKey: serverKey,
          channelId: entry.channelId,
          muted: muted.contains(entry.channelId),
          noun: entry.spaceId == null ? 'Conversation' : 'Channel',
        ),
        const AccordMenuEntry.divider(),
        ...channelNotificationEntries(
          ref,
          serverKey: serverKey,
          spaceId: entry.spaceId,
          channelId: entry.channelId,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tipDismissed = ref.watch(
      settingsControllerProvider.select((s) => s.inboxTipDismissed),
    );
    for (final e in entries) {
      onNeed(e);
    }
    final children = <Widget>[
      if (!tipDismissed) const _InboxTip(),
      for (final e in entries)
        _InboxCard(
          key: Key('inbox-card-${e.channelId}'),
          serverKey: serverKey,
          channelId: e.channelId,
          spaceId: e.spaceId,
          onOpen: () {
            final first = loaded[e.channelId]?.firstOrNull;
            if (first != null) onJump(first, spaceId: e.spaceId);
          },
          actions: [
            _CardButton(
              key: Key('inbox-card-notifications-${e.channelId}'),
              tooltip: 'Notification Settings',
              icon: AppIcons.notificationsNone,
              onTap: (position) =>
                  _notificationMenu(context, ref, e, position),
            ),
            _CardButton(
              key: Key('inbox-card-read-${e.channelId}'),
              tooltip: 'Mark as Read',
              icon: AppIcons.check,
              onTap: (_) => onMarkRead(e),
            ),
            _CollapseButton(
              collapsed: collapsed.contains(e.channelId),
              onTap: () => onToggle(e.channelId),
            ),
          ],
          body: collapsed.contains(e.channelId)
              ? null
              : switch (loaded[e.channelId]) {
                  null => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  final messages => _InboxMessages(
                    serverKey: serverKey,
                    spaceId: e.spaceId,
                    messages: messages,
                    onJump: (m) => onJump(m, spaceId: e.spaceId),
                  ),
                },
        ),
    ];
    if (entries.isEmpty) {
      children.add(
        const _InboxEmpty(
          key: Key('inbox-unread-empty'),
          title: 'You’re all caught up!',
          body: 'Unread messages from your unmuted channels show up here.',
        ),
      );
    }
    return ListView.separated(
      key: const Key('inbox-unread-list'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (_, i) => children[i],
    );
  }
}

/// The Mentions tab: one card per message that mentioned the user, newest
/// first, filtered by "Include @everyone / @role mentions".
class _MentionsTab extends ConsumerWidget {
  const _MentionsTab({
    required this.serverKey,
    required this.unread,
    required this.onNeed,
    required this.onJump,
  });

  final String serverKey;

  /// The unread channels, scanned once for mentions the gateway delivered
  /// before this client ran.
  final List<ReadEntry> unread;
  final ValueChanged<ReadEntry> onNeed;
  final void Function(AccordMessage message, {required String? spaceId})
  onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    for (final e in unread) {
      if (e.spaceId != null && e.mentions > 0) onNeed(e);
    }
    final everyone = ref.watch(
      settingsControllerProvider.select((s) => s.inboxIncludeEveryone),
    );
    final roles = ref.watch(
      settingsControllerProvider.select((s) => s.inboxIncludeRoles),
    );
    final mentions = [
      for (final m in ref.watch(inboxMentionsControllerProvider(serverKey)))
        if (switch (m.kind) {
          InboxMentionKind.direct => true,
          InboxMentionKind.role => roles,
          InboxMentionKind.everyone => everyone,
        })
          m,
    ];
    if (mentions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: _InboxEmpty(
          key: Key('inbox-mentions-empty'),
          title: 'No recent mentions',
          body: 'Messages that mention you show up here for a week.',
        ),
      );
    }
    final controller = ref.read(
      inboxMentionsControllerProvider(serverKey).notifier,
    );
    return ListView.separated(
      key: const Key('inbox-mentions-list'),
      padding: const EdgeInsets.all(16),
      itemCount: mentions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, i) {
        final mention = mentions[i];
        final message = mention.message;
        final spaceId = message.spaceId;
        return _InboxCard(
          key: Key('inbox-mention-${message.id}'),
          serverKey: serverKey,
          channelId: message.channelId,
          spaceId: spaceId,
          onOpen: () => onJump(message, spaceId: spaceId),
          actions: [
            _CardButton(
              key: Key('inbox-mention-jump-${message.id}'),
              tooltip: 'Jump to Message',
              icon: AppIcons.northEast,
              onTap: (_) => onJump(message, spaceId: spaceId),
            ),
            _CardButton(
              key: Key('inbox-mention-read-${message.id}'),
              tooltip: 'Mark as Read',
              icon: AppIcons.check,
              onTap: (_) {
                controller.dismiss(message.id);
                ref
                    .read(readStateControllerProvider(serverKey).notifier)
                    .acknowledge(
                      ref.clientForKey(serverKey),
                      message.channelId,
                      message.id,
                    );
              },
            ),
          ],
          body: _InboxMessages(
            serverKey: serverKey,
            spaceId: spaceId,
            messages: [message],
            showDays: false,
            onJump: (m) => onJump(m, spaceId: spaceId),
          ),
        );
      },
    );
  }
}

/// "Stay up to date with the latest messages!" with its "Got it!" button,
/// until dismissed: `#121214`, rounded 8, padding 16, a 40 px tray disc.
class _InboxTip extends ConsumerWidget {
  const _InboxTip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      key: const Key('inbox-tip'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kInboxTip,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.raised,
              shape: BoxShape.circle,
            ),
            child: Icon(AppIcons.tray, size: 20, color: colors.dirtyWhite),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stay up to date with the latest messages!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 20 / 16,
                    color: colors.dirtyWhite,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Unread messages from all your unmuted channels will show '
                  'up here. Time to get to that zero inbox!',
                  style: TextStyle(
                    fontSize: 14,
                    height: 18 / 14,
                    color: Color(0xFFEFEFF1),
                  ),
                ),
                const SizedBox(height: 12),
                Material(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    key: const Key('inbox-tip-got-it'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => ref
                        .read(settingsControllerProvider.notifier)
                        .setInboxTipDismissed(true),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      child: Text(
                        'Got it!',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 18 / 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
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

/// A tab with nothing to show.
class _InboxEmpty extends StatelessWidget {
  const _InboxEmpty({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.tray, size: 48, color: colors.gray),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.dirtyWhite,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: colors.gray),
          ),
        ],
      ),
    );
  }
}
