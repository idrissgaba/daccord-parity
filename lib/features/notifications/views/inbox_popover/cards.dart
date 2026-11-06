part of '../inbox_popover.dart';

/// Where a card's messages live: a space channel or a direct message.
class _CardTarget {
  const _CardTarget({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.spaceId,
    this.glyph = AppIcons.tag,
  });

  /// The channel type's glyph before the name (none for a DM).
  final IconData glyph;
  final String title;
  final String subtitle;

  /// The 32 px picture at the left (the space's icon, the DM's avatar).
  final Widget icon;
  final String? spaceId;
}

/// Resolves the header of [channelId]'s card on [serverKey].
_CardTarget _cardTarget(
  WidgetRef ref,
  String serverKey, {
  required String channelId,
  required String? spaceId,
}) {
  final cdnUrl = ref.watchCdnUrl();
  if (spaceId == null) {
    final dm = ref
        .watch(dmChannelsControllerProvider(serverKey))
        ?.firstWhereOrNull((c) => c.id == channelId);
    final selfId = ref.watchUserId();
    final users = ref.watch(accordUsersControllerProvider(serverKey));
    final title = dm == null
        ? 'Direct message'
        : dmChannelTitle(dm, selfId, fallback: 'Direct message', users: users);
    final other = dm?.recipients?.firstWhereOrNull((u) => u.id != selfId);
    final user = other == null ? null : users[other.id] ?? other;
    return _CardTarget(
      title: title,
      subtitle: 'Direct Message',
      spaceId: null,
      icon: AccordMemberAvatar(
        avatarUrl: user == null ? null : accordAvatarUrl(user, cdnUrl),
        initial: accordInitial(title),
        radius: 16,
        backgroundColor: accordIdColor(user?.id ?? channelId),
      ),
    );
  }
  final space = ref
      .watch(spacesControllerProvider)
      ?.firstWhereOrNull((s) => s.id == spaceId);
  final channels = ref.watch(accordChannelsControllerProvider(serverKey, spaceId));
  final channel = channels?.firstWhereOrNull((c) => c.id == channelId);
  final category = channel?.parentId == null
      ? null
      : channels?.firstWhereOrNull((c) => c.id == channel!.parentId);
  final spaceName = space?.name ?? '';
  final iconUrl = space == null ? null : accordSpaceIconUrl(space, cdnUrl);
  return _CardTarget(
    title: channel?.name ?? channelId,
    subtitle: [
      spaceName,
      if (category?.name case final name? when name.isNotEmpty) name,
    ].join(' › '),
    spaceId: spaceId,
    glyph: isVoiceChannelType(channel?.type) ? AppIcons.volumeUp : AppIcons.tag,
    icon: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: 32,
        child: iconUrl == null
            ? ColoredBox(
                color: _kInboxTip,
                child: Center(
                  child: Text(
                    accordSpaceInitials(spaceName),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            : CachedNetworkImage(
                imageUrl: iconUrl,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const ColoredBox(color: _kInboxTip),
              ),
      ),
    ),
  );
}

/// One card: the header (picture, "› # name", "Space › Category", its
/// buttons) over the messages. 520 wide in the 560 panel, `#28282D`,
/// rounded 12, hairline border.
class _InboxCard extends ConsumerWidget {
  const _InboxCard({
    super.key,
    required this.serverKey,
    required this.channelId,
    required this.spaceId,
    required this.actions,
    required this.onOpen,
    this.body,
  });

  final String serverKey;
  final String channelId;
  final String? spaceId;

  /// The header's buttons, right-aligned.
  final List<Widget> actions;

  /// The header's name was clicked.
  final VoidCallback onOpen;
  final Widget? body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final target = _cardTarget(
      ref,
      serverKey,
      channelId: channelId,
      spaceId: spaceId,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kInboxCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                target.icon,
                const SizedBox(width: 8),
                Icon(AppIcons.chevronRight, size: 12, color: colors.interactive),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpen,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              if (spaceId != null) ...[
                                Icon(
                                  target.glyph,
                                  size: 12,
                                  color: colors.dirtyWhite,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  target.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    height: 20 / 16,
                                    color: Color(0xFFEFEFF1),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            target.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 16 / 12,
                              color: Color(0xFFEFEFF1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                for (final (i, action) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  action,
                ],
              ],
            ),
          ),
          ?body,
        ],
      ),
    );
  }
}

/// A 32 px card button (Notification Settings, Mark as Read, Jump to
/// Message), like the header's.
class _CardButton extends StatelessWidget {
  const _CardButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final ValueChanged<Offset> onTap;

  @override
  Widget build(BuildContext context) =>
      _HeaderButton(tooltip: tooltip, icon: icon, onTap: onTap);
}

/// The 24 px chevron that folds a card.
class _CollapseButton extends StatelessWidget {
  const _CollapseButton({
    required this.collapsed,
    required this.onTap,
  });

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Tooltip(
      message: collapsed ? 'Expand' : 'Collapse',
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: SizedBox.square(
          dimension: 24,
          child: AnimatedRotation(
            turns: collapsed ? -0.25 : 0,
            duration: const Duration(milliseconds: 150),
            child: Icon(
              AppIcons.expandMore,
              size: 16,
              color: colors.interactive,
            ),
          ),
        ),
      ),
    );
  }
}

/// A card's messages, oldest first: day dividers, then rows grouped by author
/// within seven minutes as in the channel itself.
class _InboxMessages extends ConsumerWidget {
  const _InboxMessages({
    required this.serverKey,
    required this.spaceId,
    required this.messages,
    required this.onJump,
    this.showDays = true,
  });

  final String serverKey;
  final String? spaceId;
  final List<AccordMessage> messages;
  final ValueChanged<AccordMessage> onJump;

  /// Day dividers between days (a mention's card has none).
  final bool showDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = <Widget>[];
    DateTime? lastDay;
    AccordMessage? previous;
    for (final m in messages) {
      final at = DateTime.tryParse(m.timestamp)?.toLocal();
      final day = at == null ? null : DateTime(at.year, at.month, at.day);
      if (showDays && day != null && day != lastDay) {
        children.add(_InboxDayDivider(day: day));
        lastDay = day;
        previous = null;
      }
      final prevAt = previous == null
          ? null
          : DateTime.tryParse(previous.timestamp)?.toLocal();
      final grouped =
          previous != null &&
          previous.authorId == m.authorId &&
          at != null &&
          prevAt != null &&
          at.difference(prevAt).inMinutes < 7;
      children.add(
        _InboxMessageRow(
          key: ValueKey('inbox-message-${m.id}'),
          serverKey: serverKey,
          spaceId: spaceId,
          message: m,
          showHeader: !grouped,
          onJump: () => onJump(m),
        ),
      );
      previous = m;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// "2 November 2026" on a pill across a hairline.
class _InboxDayDivider extends StatelessWidget {
  const _InboxDayDivider({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: SizedBox(
        height: 17,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 8,
              height: 1,
              child: ColoredBox(color: colors.hairline),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: _kInboxCard,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                messageDayString(day),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: colors.gray,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One message in a card: the avatar and "Name  time" on a group's first
/// row, the text, its files and reactions. A click on the row jumps to it.
class _InboxMessageRow extends ConsumerWidget {
  const _InboxMessageRow({
    super.key,
    required this.serverKey,
    required this.spaceId,
    required this.message,
    required this.showHeader,
    required this.onJump,
  });

  final String serverKey;
  final String? spaceId;
  final AccordMessage message;
  final bool showHeader;
  final VoidCallback onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final members = spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(serverKey, spaceId!));
    final users = ref.watch(accordUsersControllerProvider(serverKey));
    final ensure = ref
        .read(accordUsersControllerProvider(serverKey).notifier)
        .ensure;
    final name = accordAuthorName(
      message.authorId,
      members: members,
      users: users,
      ensure: ensure,
    );
    final author = members?[message.authorId]?.user ?? users[message.authorId];
    final cdnUrl = ref.watchCdnUrl();
    return InkWell(
      onTap: onJump,
      hoverColor: colors.hover,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, showHeader ? 16 : 2, 16, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              child: showHeader
                  ? AccordMemberAvatar(
                      avatarUrl: author == null
                          ? null
                          : accordAvatarUrl(author, cdnUrl),
                      initial: accordInitial(name),
                      radius: 20,
                      backgroundColor: accordIdColor(message.authorId),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showHeader)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              height: 22 / 16,
                              color: colors.dirtyWhite,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          messageTimeFromIso(message.timestamp),
                          style: TextStyle(fontSize: 12, color: colors.gray),
                        ),
                      ],
                    ),
                  if (message.content.trim().isNotEmpty)
                    AccordMessageContent(
                      content: message.content,
                      spaceId: spaceId,
                    ),
                  for (final file in message.attachments)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            AppIcons.insertDriveFileOutlined,
                            size: 16,
                            color: colors.interactive,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              file.filename,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: const Color(0xFF4D96EE),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (message.reactions?.isNotEmpty ?? false)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final r in message.reactions!)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.hover,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${r.emoji['name'] ?? ''} ${r.count}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.interactive,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
