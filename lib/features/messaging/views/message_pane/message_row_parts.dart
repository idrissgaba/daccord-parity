part of 'message_pane.dart';

/// The row's sub-trees: thread chip, reactions, reply preview, attachments. Split from [_MessageRowState] for size.
mixin _MessageRowParts
    on ConsumerState<_MessageRow>, _MessageRowEditing, _MessageRowHandlers {
  Widget _buildThreadChip(
    AccordMessage message,
    ThemeData theme,
    BonfireThemeExtension colors,
  ) {
    final count = message.replyCount;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _openThread(message),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.forumOutlined, size: 14, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                '$count ${count == 1 ? 'reply' : 'replies'}',
                style: theme.textTheme.labelMedium!.copyWith(
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReactions(
    AccordMessage message,
    ThemeData theme,
    BonfireThemeExtension colors,
    String? cdnUrl, {
    bool showAdd = false,
  }) {
    final messageId = message.id;
    final spaceId = widget.spaceId;
    final customEmoji = spaceId == null
        ? const <AccordEmoji>[]
        : ref.watch(
                accordEmojisControllerProvider(
                  ref.readActiveServerKey() ?? '',
                  spaceId,
                ),
              ) ??
              const <AccordEmoji>[];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final sup in message.superReactions)
            _SuperReactionPill(
              key: ValueKey('super-${sup.emoji}'),
              superReaction: sup,
              child: (reaction) => _ReactionPill(
                reaction: reaction,
                superReaction: true,
                imageUrl: _reactionEmojiUrl(reaction, customEmoji, cdnUrl),
                trustedMediaBaseUrl: cdnUrl,
                onTap: () => _toggleSuperReaction(messageId, sup.emoji),
                onShowReactors: () =>
                    _toggleSuperReaction(messageId, sup.emoji),
              ),
            ),
          for (final reaction in message.reactions ?? const <AccordReaction>[])
            _ReactionPill(
              reaction: reaction,
              imageUrl: _reactionEmojiUrl(reaction, customEmoji, cdnUrl),
              trustedMediaBaseUrl: cdnUrl,
              onTap: () => _toggleReaction(
                messageId,
                reaction.emoji['name']?.toString() ?? '',
                emojiId: reaction.emoji['id']?.toString(),
              ),
              onShowReactors: () => _showReactors(messageId, reaction),
              reactorNames: () => _reactorNames(messageId, reaction),
            ),
          // The reference client's "add another" pill, on hover only.
          if (showAdd)
            _AddReactionPill(onTap: () => _openReactionPicker(messageId)),
        ],
      ),
    );
  }

  /// Who reacted with [reaction], for the pill's tooltip. Fetched once per
  /// message/emoji and kept while the row lives; the cache is dropped when the
  /// count changes so a new reactor shows up.
  final Map<String, (int, Future<List<String>>)> _reactorNameCache = {};

  Future<List<String>> _reactorNames(
    String messageId,
    AccordReaction reaction,
  ) {
    final emojiName = reaction.emoji['name']?.toString() ?? '';
    final emojiId = reaction.emoji['id']?.toString();
    final key = '$messageId/${emojiId ?? emojiName}';
    final cached = _reactorNameCache[key];
    if (cached != null && cached.$1 == reaction.count) return cached.$2;
    final client = _client;
    final future = client == null
        ? Future.value(const <String>[])
        : ref
              .read(
                accordMessagesControllerProvider(
                  ref.readActiveServerKey() ?? '',
                  widget.channelId,
                ).notifier,
              )
              .reactionUsers(client, messageId, emojiName, emojiId: emojiId)
              .then(
                (users) => [
                  for (final user in users)
                    accordUserName(user, fallback: user.id),
                ],
              );
    _reactorNameCache[key] = (reaction.count, future);
    return future;
  }

  /// Resolves a custom reaction's image URL. Reactions only carry `{id, name}`,
  /// so the emoji is looked up from the space's catalog by id and resolved via
  /// the shared, federation-aware [accordEmojiUrl] (remote emoji resolve
  /// against their home CDN, as in message markup). A *qualified* id missing
  /// from the catalog resolves to nothing rather than the local CDN, because
  /// stripping its domain would request an unrelated local emoji with the same
  /// local id. Null for unicode reactions.
  String? _reactionEmojiUrl(
    AccordReaction reaction,
    List<AccordEmoji> customEmoji,
    String? cdnUrl,
  ) {
    final rawId = reaction.emoji['id']?.toString();
    final id =
        rawId ?? parseEmojiToken(reaction.emoji['name']?.toString() ?? '').id;
    if (id == null) return null;
    final match = customEmoji.firstWhereOrNull((e) => e.id == id);
    if (match == null && isRemoteId(id)) return null;
    return accordEmojiUrl(match ?? AccordEmoji(id: id), cdnUrl);
  }

  /// The reference client's reply context above a reply: a line curving out
  /// of the avatar column, the replied-to author's 16 px avatar and name, then
  /// a one-line preview; clicking it scrolls to that message. The target is
  /// resolved from the loaded channel cache when available.
  Widget _buildReplyPreview(
    AccordMessage message,
    BonfireThemeExtension colors, {
    required double spineLeft,
  }) {
    final referenced = widget.messagesById[message.replyTo];
    String name = 'Unknown';
    String preview = '';
    String? avatarUrl;
    Color? nameColor;
    AccordMember? member;
    AccordUser? user;
    if (referenced != null) {
      // Same resolution order as the row header: member nickname → on-demand
      // user cache → "Unknown" while the fetch lands. Never the raw snowflake.
      final authorId = referenced.authorId;
      member = widget.spaceId == null
          ? null
          : ref.watch(
              accordMembersControllerProvider(
                ref.readActiveServerKey() ?? '',
                widget.spaceId!,
              ).select((m) => m?[authorId]),
            );
      user = ref.watch(
        accordUsersControllerProvider(
          ref.readActiveServerKey() ?? '',
        ).select((u) => u[authorId]),
      );
      name = accordAuthorNameOf(
        authorId,
        member: member,
        user: user,
        ensure: ref
            .read(
              accordUsersControllerProvider(
                ref.readActiveServerKey() ?? '',
              ).notifier,
            )
            .ensure,
      );
      final cdnUrl = ref.watchCdnUrl();
      avatarUrl = member != null
          ? accordMemberAvatarUrl(member, cdnUrl)
          : accordAvatarUrl(user, cdnUrl);
      if (member != null && widget.spaceId != null) {
        final roles = ref.watch(
          spacesControllerProvider.select(
            (s) => s?.firstWhereOrNull((sp) => sp.id == widget.spaceId)?.roles,
          ),
        );
        final colorRole = memberColorRole(member, roles ?? const []);
        if (colorRole != null && colorRole.color != 0) {
          nameColor = accordRoleColor(colorRole.color);
        }
      }
      final text = accordMessageText(referenced, authorName: name);
      // A system line is already plain text, and a profile name in it stays
      // literal rather than being read as Markdown.
      final content = isSystemMessage(referenced)
          ? text
          : plainMessagePreview(text);
      preview = content.isEmpty
          ? (referenced.attachments.isNotEmpty ? 'Click to see attachment' : '')
          : content;
    } else {
      preview = 'Original message was deleted';
    }
    final theme = Theme.of(context);
    final targetId = message.replyTo;
    final jump = widget.onJumpTo;
    final line = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (referenced != null) ...[
          AccordMemberAvatar(
            avatarUrl: avatarUrl,
            initial: accordInitial(name),
            radius: 8,
            backgroundColor: accordAvatarColor(
              member?.user ?? user,
              referenced.authorId,
            ),
            initialStyle: const TextStyle(fontSize: 8),
          ),
          const SizedBox(width: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 18 / 14,
              color: nameColor ?? colors.dirtyWhite,
            ),
          ),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 18 / 14,
              fontStyle: referenced == null ? FontStyle.italic : null,
              color: referenced == null
                  ? colors.gray
                  : theme.textTheme.bodyLarge?.color ?? colors.dirtyWhite,
            ),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // From the middle of this line, left into the gutter, then down to
          // the top of the author's avatar.
          Positioned(
            left: -spineLeft,
            top: 9,
            width: spineLeft - 4,
            height: 9 + 4 + 2,
            child: CustomPaint(painter: _ReplySpinePainter(colors.hairline)),
          ),
          SizedBox(
            height: 18,
            child: referenced != null && jump != null && targetId != null
                ? MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => jump(targetId),
                      child: line,
                    ),
                  )
                : line,
          ),
        ],
      ),
    );
  }

  /// Renders one attachment inline: tappable image (→ lightbox), video player,
  /// audio player, or a filename chip for other types.
  Widget _buildAttachment(
    AccordAttachment attachment,
    String? cdnUrl,
    ThemeData theme,
  ) {
    if (attachment.encryption != null) {
      final client = ref.accordClient;
      if (client != null && client.encryption != null) {
        return EncryptedAttachment(attachment: attachment, client: client);
      }
      return const Text('Encrypted attachment unavailable.');
    }
    final url = _attachmentUrl(attachment, cdnUrl);
    switch (_previewOf(attachment)) {
      case AttachmentPreview.image:
        return MessageMediaGate(
          source: attachment.url,
          trustedBaseUrl: cdnUrl,
          builder: (_, safeUrl) => MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => showImageLightbox(
                context,
                safeUrl,
                attachmentId: attachmentKey(attachment),
              ),
              child: _ImageAttachment(
                url: safeUrl,
                width: _asDouble(attachment.width),
                height: _asDouble(attachment.height),
              ),
            ),
          ),
        );
      case AttachmentPreview.video:
        return InlineVideoPlayer(
          url: url,
          filename: attachment.filename,
          width: _asDouble(attachment.width),
          height: _asDouble(attachment.height),
        );
      case AttachmentPreview.audio:
        return InlineAudioPlayer(url: url, filename: attachment.filename);
      case AttachmentPreview.none:
        return _FileAttachmentCard(
          attachment: attachment,
          url: url,
          onOpen: () => openExternalUrl(context, url),
        );
    }
  }
}

/// Draws the reply spine: a line from the right edge (the reply context's
/// left) leftwards, rounding down into a vertical that ends at the bottom (the
/// top of the author's avatar).
class _ReplySpinePainter extends CustomPainter {
  const _ReplySpinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 6.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..moveTo(size.width, 1)
      ..lineTo(r + 1, 1)
      ..arcToPoint(
        Offset(1, r + 1),
        radius: const Radius.circular(r),
        clockwise: false,
      )
      ..lineTo(1, size.height);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ReplySpinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A non-previewable attachment as the reference client shows it: a 432 px
/// card with the file icon, the name as a link and the size underneath.
class _FileAttachmentCard extends StatelessWidget {
  const _FileAttachmentCard({
    required this.attachment,
    required this.url,
    required this.onOpen,
  });

  final AccordAttachment attachment;
  final String url;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 432),
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: popoverSurfaceColor(colors),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        children: [
          Icon(
            fileKindIcon(attachment.filename, AttachmentPreview.none),
            size: 40,
            color: const Color(0xFFC6CAF7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onOpen,
                    child: Text(
                      attachment.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 20 / 16,
                        color: Color(0xFF4D96EE),
                      ),
                    ),
                  ),
                ),
                Text(
                  formatFileSize(attachment.size),
                  style: TextStyle(
                    fontSize: 12,
                    height: 16 / 12,
                    color: colors.interactive,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Download',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  AppIcons.download,
                  size: 20,
                  color: colors.interactive,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
