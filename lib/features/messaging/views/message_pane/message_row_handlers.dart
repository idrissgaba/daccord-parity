part of 'message_pane.dart';

/// What the row's hover bar and actions menu do: reactions, pins, threads, polls, forward, report, delete, block. Split from [_MessageRowState] for size.
mixin _MessageRowHandlers on ConsumerState<_MessageRow>, _MessageRowEditing {
  String get _authorName;
  String get _fullTime;
  String get _time;
  String? get _avatarUrl;
  AccordMessagesController? get _channelMessages;

  /// Whether the row's "⋯" actions menu is open. Only meaningful when [narrow],
  /// where the action bar is mounted on hover alone — see [_menuStateChanged].
  bool _menuOpen = false;

  void _openPopout(String authorId) {
    final spaceId = widget.spaceId;
    if (spaceId != null) {
      showAccordMemberPopout(context, spaceId: spaceId, userId: authorId);
      return;
    }
    final user = widget.authorUser;
    if (user != null) widget.onUserTap?.call(user);
  }

  void _openUserMenu([Offset? position]) {
    final user = widget.author?.user ?? widget.authorUser;
    if (user == null) return;
    widget.onUserContextMenu?.call(user, position);
  }

  /// Opens a popup listing the users who added [reaction], lazy-loaded.
  void _showReactors(String messageId, AccordReaction reaction) {
    showDialog<void>(
      context: context,
      builder: (_) => _ReactorsDialog(
        channelId: widget.channelId,
        messageId: messageId,
        emojiName: reaction.emoji['name']?.toString() ?? '',
        emojiId: reaction.emoji['id']?.toString(),
      ),
    );
  }

  Future<void> _toggleReaction(
    String messageId,
    String emojiName, {
    String? emojiId,
  }) async {
    final client = _client;
    if (client == null) return;
    // The optimistic badge is rolled back on failure; without this the reaction
    // just vanishes again with no explanation (#306).
    final error = await ref
        .read(
          accordMessagesControllerProvider(
            ref.readActiveServerKey() ?? '',
            widget.channelId,
          ).notifier,
        )
        .toggleReaction(client, messageId, emojiName, emojiId: emojiId);
    if (error != null && mounted) showInfoSnack(context, error);
  }

  Future<void> _toggleSuperReaction(String messageId, String emoji) async {
    final client = _client;
    if (client == null) return;
    final error = await ref
        .read(
          accordMessagesControllerProvider(
            ref.readActiveServerKey() ?? '',
            widget.channelId,
          ).notifier,
        )
        .toggleSuperReaction(client, messageId, emoji);
    if (error != null && mounted) showInfoSnack(context, error);
  }

  /// The reaction picker; with its Super Reaction toggle on, the pick is
  /// sent as a super reaction.
  Future<void> _openReactionPicker(String messageId) async {
    final pick = await showAccordEmojiPicker(
      context,
      spaceId: widget.spaceId,
      reaction: true,
    );
    if (pick == null || !mounted) return;
    if (pick.superReaction) {
      await _toggleSuperReaction(messageId, pick.superToken);
    } else {
      await _toggleReaction(messageId, pick.reactionName, emojiId: pick.id);
    }
  }

  Future<void> _togglePin(String messageId, {required bool pinned}) async {
    final client = _client;
    if (client == null) return;
    final message = _message;
    final channelName = widget.spaceId == null
        ? null
        : ref
              .read(
                accordChannelsControllerProvider(
                  ref.readActiveServerKey() ?? '',
                  widget.spaceId!,
                ),
              )
              ?.firstWhereOrNull((c) => c.id == widget.channelId)
              ?.name;
    final confirmed =
        HardwareKeyboard.instance.isShiftPressed ||
        await showDialog<bool>(
              context: context,
              builder: (_) => AccordDialog(
                title: pinned ? 'Unpin Message' : 'Pin It. Pin It Good.',
                subtitle: pinned
                    ? 'You sure you want to remove this pinned message?'
                    : 'Hey, just double-checking that you want to pin this '
                          'message to ${channelName == null ? 'this conversation' : '#$channelName'} '
                          'for posterity and greatness?',
                primaryLabel: pinned ? 'Remove it please!' : 'Oh yeah. Pin it',
                tone: pinned
                    ? AccordDialogTone.danger
                    : AccordDialogTone.primary,
                body: _MessagePreviewCard(
                  message: message,
                  authorName: _authorName,
                  when: _time,
                  avatarUrl: _avatarUrl,
                  replyName: _replyContext(message)?.$1,
                  replyText: _replyContext(message)?.$2,
                ),
              ),
            ) ==
            true;
    if (!confirmed || !mounted) return;
    final controller = ref.read(
      accordMessagesControllerProvider(
        ref.readActiveServerKey() ?? '',
        widget.channelId,
      ).notifier,
    );
    // As with reactions: the pin marker flips back on failure, so the reason has
    // to be reported or the action reads as a no-op (#306).
    final error = pinned
        ? await controller.unpin(client, messageId)
        : await controller.pin(client, messageId);
    if (error != null && mounted) showInfoSnack(context, error);
  }

  /// Keeps the floating action bar mounted for as long as its menu is open.
  ///
  /// When [_MessageRow.narrow] the bar is only built while the row is hovered,
  /// but opening a [PopupMenuButton] pushes a modal barrier that ends the hover
  /// — which unmounted the button mid-menu, and Flutter drops the selection
  /// when the button is gone (`if (!mounted) return` in `showButtonMenu`).
  /// Every item in that menu (delete, edit, pin, report) silently did nothing
  /// in the voice channel's chat panel as a result.
  void _menuStateChanged(bool open) {
    if (!mounted) return;
    setState(() => _menuOpen = open);
  }

  @override
  void _onEmptyEdit(String messageId) => _delete(messageId);

  /// The replied-to author and a one-line preview, for the dialogs' card.
  (String, String)? _replyContext(AccordMessage message) {
    final target = widget.messagesById[message.replyTo];
    if (target == null) return null;
    final members = widget.spaceId == null
        ? null
        : ref.read(
            accordMembersControllerProvider(
              ref.readActiveServerKey() ?? '',
              widget.spaceId!,
            ),
          );
    final users = ref.read(
      accordUsersControllerProvider(ref.readActiveServerKey() ?? ''),
    );
    final name = accordAuthorName(
      target.authorId,
      members: members,
      users: users,
    );
    return (
      name,
      plainMessagePreview(accordMessageText(target, authorName: name)),
    );
  }

  Future<void> _delete(String messageId) async {
    final client = _client;
    if (client == null || _busy) return;
    // Shift held while choosing Delete skips the confirmation, as in other
    // chat apps.
    final confirmed =
        HardwareKeyboard.instance.isShiftPressed ||
        await _confirmDelete(_message, _authorName, _fullTime) == true;
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(
          accordMessagesControllerProvider(
            ref.readActiveServerKey() ?? '',
            widget.channelId,
          ).notifier,
        )
        .delete(client, messageId);
    if (!mounted) return;
    // Row disappears on success; if it failed we re-enable and say so, rather
    // than leaving the message sitting there as if nothing had been asked.
    setState(() => _busy = false);
    if (!ok) showInfoSnack(context, 'Failed to delete message');
  }

  /// "Delete Message" with a preview of what goes, and the Shift tip.
  Future<bool?> _confirmDelete(
    AccordMessage message,
    String authorName,
    String when,
  ) {
    final colors = BonfireThemeExtension.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AccordDialog(
        title: 'Delete Message',
        subtitle: 'Are you sure you want to delete this message?',
        primaryLabel: 'Delete',
        tone: AccordDialogTone.danger,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MessagePreviewCard(
              message: message,
              authorName: authorName,
              when: _time,
              avatarUrl: _avatarUrl,
              replyName: _replyContext(message)?.$1,
              replyText: _replyContext(message)?.$2,
            ),
            const SizedBox(height: 20),
            const Text(
              'Protip:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 18 / 14,
                color: Color(0xFF5EB479),
              ),
            ),
            Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 14,
                  height: 18 / 14,
                  color: colors.dirtyWhite,
                ),
                children: const [
                  TextSpan(
                    text: 'You can hold down shift when clicking ',
                    style: TextStyle(fontWeight: FontWeight.w400),
                  ),
                  TextSpan(
                    text: 'delete message',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: ' to bypass this confirmation entirely.',
                    style: TextStyle(fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _blockFiles(AccordMessage message) async {
    final client = ref.accordClient;
    if (client == null) return;
    final removed = await showBlockAttachmentDialog(
      context,
      client: client,
      message: message,
      isInstanceAdmin: ref.readIsAdmin(),
      stillActive: () => mounted && identical(ref.accordClient, client),
    );
    if (mounted && removed == true && identical(ref.accordClient, client)) {
      ref
          .read(
            accordMessagesControllerProvider(
              ref.readActiveServerKey() ?? '',
              widget.channelId,
            ).notifier,
          )
          .removeMessage(message.id);
    }
  }

  Future<String?> _votePoll(
    String messageId,
    int answerId, {
    required bool remove,
  }) async {
    final client = ref.accordClient;
    final controller = _channelMessages;
    if (client == null || controller == null) return 'Not connected.';
    return controller.votePoll(client, messageId, answerId, remove: remove);
  }

  Future<void> _endPoll(String messageId) async {
    final client = ref.accordClient;
    final controller = _channelMessages;
    if (client == null || controller == null) return;
    final error = await controller.endPoll(client, messageId);
    if (error != null && mounted) showInfoSnack(context, error);
  }

  void _openThread(AccordMessage message) => showAccordThread(
    context,
    channelId: widget.channelId,
    spaceId: widget.spaceId,
    root: message,
    canManageMessages: widget.canManageMessages,
    onUserTap: widget.onUserTap,
    onUserContextMenu: widget.onUserContextMenu,
  );

  /// "Mark unread": this message and everything after it become unread again
  /// (here, on the server and on the user's other devices).
  void _markUnread(AccordMessage message) {
    final serverKey = ref.readActiveServerKey();
    if (serverKey == null) return;
    final loaded =
        ref.read(
          accordMessagesControllerProvider(serverKey, widget.channelId),
        ) ??
        const <AccordMessage>[];
    final position = readPositionBefore(loaded.map((m) => m.id), message.id);
    ref
        .read(readStateControllerProvider(serverKey).notifier)
        .markUnreadFrom(
          ref.read(accordAuthProvider.notifier).clientForKey(serverKey),
          widget.channelId,
          position,
          spaceId: widget.spaceId,
          latestMessageId: loaded.isEmpty ? message.id : loaded.last.id,
        );
  }

  /// Forwards [message] to another channel or direct message.
  void _forward(AccordMessage message) {
    final spaceId = widget.spaceId;
    final serverKey = ref.readActiveServerKey() ?? '';
    final channelName = spaceId == null
        ? null
        : ref
              .read(accordChannelsControllerProvider(serverKey, spaceId))
              ?.firstWhereOrNull((c) => c.id == widget.channelId)
              ?.name;
    showForwardMessageDialog(
      context,
      message: message,
      authorName: _authorName,
      sourceLabel: channelName != null
          ? '#$channelName'
          : spaceId == null
          ? 'a direct message'
          : 'a channel',
      spaceId: spaceId,
    );
  }

  /// Reports [message]. Available in DMs too, where [_MessageRow.spaceId] is
  /// null: the dialog then files an account-level report and offers to block
  /// the author, rather than the action disappearing (#290).
  void _report(AccordMessage message) {
    showReportDialog(
      context,
      spaceId: widget.spaceId,
      targetType: 'message',
      targetId: message.id,
      channelId: widget.channelId,
      reportedUserId: message.authorId.isEmpty ? null : message.authorId,
      reportedName: _authorName,
    );
  }

  /// The long-press (mobile) / right-click (desktop) message menu, in the
  /// reference client's order: a row of quick reactions, Add Reaction (and
  /// View Reactions once there are any); Edit, Reply, Forward, Create Thread;
  /// Copy Text, Pin, Mark Unread, Copy Message Link; the red Delete (or
  /// Report); Copy Message ID. Accord's own entries (End poll, Block files,
  /// Select messages) slot into the group they belong with. Bulk-select lives
  /// here as one entry rather than being the long-press itself, so the
  /// per-message actions stay reachable on touch.
  ///
  /// [message] is captured when the menu opens: the entries' callbacks only run
  /// once the menu has closed (an await), by which point the row may already be
  /// bound to a different message. Completes when the menu closes.
  Future<void> _showActionsMenu(
    AccordMessage message, [
    Offset? position,
    VoidCallback? copySelection,
  ]) async {
    if (_editing) return;
    final canDelete = widget.isOwn || widget.canManageMessages;
    final canReport = !widget.isOwn;
    final desktop = shouldUseDesktopLayout(context);
    final system = isSystemMessage(message);
    final content = system
        ? ''
        : accordMessageText(message, authorName: _authorName);
    final hasReactions =
        (message.reactions ?? const []).isNotEmpty ||
        message.superReactions.isNotEmpty;
    final quickPicks = desktop
        ? quickReactionPicks(
            ref.read(settingsControllerProvider).recentEmoji,
            count: 4,
          )
        : const <EmojiPick>[];
    final entries = <AccordMenuEntry>[
      if (copySelection != null)
        AccordMenuEntry(
          label: 'Copy selection',
          icon: AppIcons.contentCopy,
          onSelected: copySelection,
        ),
      if (quickPicks.isNotEmpty)
        AccordMenuEntry.widget(
          height: 52,
          child: _QuickReactionRow(
            picks: quickPicks,
            onPick: (pick) {
              Navigator.of(context).pop();
              _toggleReaction(message.id, pick.reactionName, emojiId: pick.id);
            },
          ),
        ),
      AccordMenuEntry(
        label: 'Add Reaction',
        icon: AppIcons.addReactionOutlined,
        trailingChevron: true,
        onSelected: () => _openReactionPicker(message.id),
      ),
      if (hasReactions)
        AccordMenuEntry(
          label: 'View Reactions',
          icon: AppIcons.emojiEmotionsOutlined,
          onSelected: () => _showReactors(
            message.id,
            (message.reactions ?? const <AccordReaction>[]).firstOrNull ??
                AccordReaction(),
          ),
        ),
      const AccordMenuEntry.divider(),
      if (widget.isOwn && !system)
        AccordMenuEntry(
          label: 'Edit Message',
          icon: AppIcons.edit,
          onSelected: () => _startEdit(message),
        ),
      AccordMenuEntry(
        label: 'Reply',
        icon: AppIcons.reply,
        onSelected: widget.onReply,
      ),
      AccordMenuEntry(
        label: 'Forward',
        icon: AppIcons.forward,
        onSelected: () => _forward(message),
      ),
      if (widget.spaceId != null)
        AccordMenuEntry(
          label: 'Create Thread',
          icon: AppIcons.forumOutlined,
          onSelected: () => _openThread(message),
        ),
      const AccordMenuEntry.divider(),
      if (content.isNotEmpty)
        AccordMenuEntry(
          label: 'Copy Text',
          icon: AppIcons.copyOutlined,
          onSelected: () => Clipboard.setData(ClipboardData(text: content)),
        ),
      if (widget.canManageMessages)
        AccordMenuEntry(
          label: message.pinned ? 'Unpin Message' : 'Pin Message',
          icon: AppIcons.pushPin,
          onSelected: () => _togglePin(message.id, pinned: message.pinned),
        ),
      AccordMenuEntry(
        label: 'Mark Unread',
        icon: AppIcons.markChatUnreadOutlined,
        onSelected: () => _markUnread(message),
      ),
      if (widget.spaceId case final spaceId?)
        AccordMenuEntry(
          label: 'Copy Message Link',
          icon: AppIcons.link,
          onSelected: () {
            Clipboard.setData(
              ClipboardData(
                text: messageLink(
                  spaceId: spaceId,
                  channelId: widget.channelId,
                  messageId: message.id,
                ),
              ),
            );
            showInfoSnack(context, 'Message link copied');
          },
        ),
      const AccordMenuEntry.divider(),
      if (message.poll case final poll?
          when !poll.closed && (widget.isOwn || widget.canManageMessages))
        AccordMenuEntry(
          label: 'End Poll',
          icon: AppIcons.stopCircleOutlined,
          destructive: true,
          onSelected: () => _endPoll(message.id),
        ),
      if ((widget.canManageMessages || ref.readIsAdmin()) &&
          message.attachments.isNotEmpty &&
          (message.spaceId != null || ref.readIsAdmin()))
        AccordMenuEntry(
          label: 'Block Files and Delete',
          icon: AppIcons.block,
          destructive: true,
          onSelected: () => _blockFiles(message),
        ),
      if (canDelete)
        AccordMenuEntry(
          label: 'Delete Message',
          icon: AppIcons.deleteOutline,
          destructive: true,
          onSelected: () => _delete(message.id),
        ),
      if (canReport)
        AccordMenuEntry(
          label: 'Report Message',
          icon: AppIcons.flagOutlined,
          destructive: true,
          onSelected: () => _report(message),
        ),
      if (widget.onLongPressSelect != null)
        AccordMenuEntry(
          label: 'Select Messages',
          icon: AppIcons.checklist,
          onSelected: widget.onLongPressSelect,
        ),
      const AccordMenuEntry.divider(),
      AccordMenuEntry(
        label: 'Copy Message ID',
        icon: AppIcons.idCard,
        onSelected: () => Clipboard.setData(ClipboardData(text: message.id)),
      ),
    ];

    await showAccordContextMenu(
      context,
      entries: entries,
      globalPosition: position,
      title: _authorName,
    );
  }
}

/// The four quick-reaction emoji at the head of the message menu: 44 px
/// buttons on a 48 px pitch, as the reference client lays them out.
class _QuickReactionRow extends StatelessWidget {
  const _QuickReactionRow({required this.picks, required this.onPick});

  final List<EmojiPick> picks;
  final ValueChanged<EmojiPick> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final pick in picks)
            Tooltip(
              message: pick.name,
              waitDuration: const Duration(milliseconds: 400),
              child: Material(
                color: colors.background,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  hoverColor: colors.hover,
                  onTap: () => onPick(pick),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Text(
                        pick.char,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The message as the confirmation dialogs show it: a raised card with the
/// author's avatar, name and time over the text (or "(attachment)").
class _MessagePreviewCard extends StatelessWidget {
  const _MessagePreviewCard({
    required this.message,
    required this.authorName,
    required this.when,
    required this.avatarUrl,
    this.replyName,
    this.replyText,
  });

  /// The message this one answers, as its reply context shows it.
  final String? replyName;
  final String? replyText;

  final AccordMessage message;
  final String authorName;
  final String when;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final preview = plainMessagePreview(
      accordMessageText(message, authorName: authorName),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: colors.raised,
        borderRadius: BorderRadius.circular(3),
        boxShadow: [
          const BoxShadow(color: Color(0x991E1F22), spreadRadius: 1),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 16),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AccordMemberAvatar(
              avatarUrl: avatarUrl,
              initial: accordInitial(authorName),
              radius: 20,
              backgroundColor: accordAvatarColor(null, message.authorId),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (replyName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$replyName ',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: colors.dirtyWhite,
                            ),
                          ),
                          TextSpan(text: replyText ?? ''),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: colors.interactive,
                      ),
                    ),
                  ),
                MessageAuthorHeader(
                  name: authorName,
                  time: when,
                  ellipsizeName: true,
                ),
                Text(
                  preview.isEmpty
                      ? (message.attachments.isNotEmpty
                            ? '(attachment)'
                            : '(no text)')
                      : preview,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    height: 22 / 16,
                    color: colors.dirtyWhite,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}
