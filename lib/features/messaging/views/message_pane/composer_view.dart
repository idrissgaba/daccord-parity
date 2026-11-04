part of 'message_pane.dart';

/// The longest message the server accepts; the composer counts down to it.
const int kMaxMessageLength = 2000;

/// The composer's widget tree. Split from [_ComposerState] for size; the state keeps the behaviour, this keeps the layout.
///
/// Desktop follows the reference client: one 56 px box on a lifted surface
/// (8 px in from the pane's edges), "+" at the left opening the attach menu,
/// the text in the middle, GIF · Sticker · Emoji at the right and nothing to
/// press to send — Enter does. Replies, attachments and warnings stack inside
/// the same box above the text. Touch layouts keep a Send / voice-message
/// button, since there is no Enter to speak of.
mixin _ComposerView
    on
        ConsumerState<_Composer>,
        _ComposerMentions,
        _ComposerEmojiSuggest,
        _ComposerCommands,
        _ComposerAttachments {
  SendCooldown? get _cooldown;
  void _onChanged(String value);
  void _onSubmitted();

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    // Desktop clients (and the web on a desktop OS) send with Enter and have
    // no voice messages, as in the reference client; touch platforms keep
    // the send / record slot.
    final desktop = switch (Theme.of(context).platform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    };
    // Watched, not read: the limits arrive a round-trip after connect, and the
    // attach button's enabled state depends on the count limit.
    final limits = ref.watch(serverLimitsControllerProvider);
    final atAttachmentLimit =
        _attachments.length >= limits.maxAttachmentsPerMessage;
    final name = widget.channelName;
    // DMs have no `#`: the pane passes the conversation's title, and the
    // placeholder reads "Message @name". A nameless channel stays "Message"
    // rather than a dangling "Message #".
    final hint = !widget.canSend
        ? 'You do not have permission to send messages in this channel.'
        : name == null || name.isEmpty
        ? 'Message'
        : widget.spaceId == null
        ? 'Message @$name'
        : 'Message #$name';
    final now = DateTime.now();
    final cooldown = _cooldown != null && _cooldown!.isActive(now)
        ? _cooldown
        : null;
    final sendBlocked = sendBlockedByCooldown(
      cooldown: cooldown,
      now: now,
      hasAttachments: _attachments.isNotEmpty,
    );
    // A voice message is an upload, so an upload budget holds it back too.
    final voiceBlocked = sendBlockedByCooldown(
      cooldown: cooldown,
      now: now,
      hasAttachments: true,
    );
    // Configured capacity, shown as guidance beside the per-message limits;
    // only the server knows what's left this minute.
    final budgetHint = uploadBudgetHint(
      requestsPerMinute: limits.uploadRequestsPerMinute,
      bytesPerMinute: limits.uploadBytesPerMinute,
    );
    final String? cooldownLine = cooldown != null
        ? [
            sendCooldownLabel(cooldown, now),
            if (cooldown.kind == SendCooldownKind.rateLimited &&
                budgetHint != null)
              budgetHint,
          ].join(' ')
        : widget.slowmodeSeconds > 0
        ? slowmodeHint(widget.slowmodeSeconds)
        : null;
    final placeholderColor = Color.alphaBlend(
      colors.gray.withValues(alpha: 0.8),
      colors.background,
    );
    final textStyle = TextStyle(
      fontSize: 16,
      height: 22 / 16,
      color: colors.dirtyWhite,
    );
    final iconColor = colors.interactive;

    Widget iconButton({
      required String tooltip,
      required IconData icon,
      required VoidCallback? onPressed,
      Key? key,
      GlobalKey? anchorKey,
      double size = 24,
    }) => Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(8),
        hoverColor: colors.hover,
        onTap: onPressed,
        child: SizedBox(
          key: anchorKey,
          width: 32,
          height: 32,
          child: Icon(
            icon,
            size: size,
            color: onPressed == null ? colors.gray : iconColor,
          ),
        ),
      ),
    );

    final attachTooltip = atAttachmentLimit
        ? 'Attachment limit reached '
              '(${limits.maxAttachmentsPerMessage} per message)'
        : [
            'Attach files '
                '(${attachmentLimitsHint(maxBytes: limits.maxAttachmentBytes, maxCount: limits.maxAttachmentsPerMessage)})',
            if (budgetHint != null) budgetHint,
          ].join('\n');

    final field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      // Deliberately never disabled while sending: a disabled TextField
      // gives up focus (and the mobile keyboard) for the whole round-trip.
      // The buttons and the guard in _send() are what stop a double-send.
      enabled: widget.canSend,
      minLines: 1,
      maxLines: 12,
      textInputAction: composerUsesNativeNewlines
          ? TextInputAction.newline
          : TextInputAction.send,
      onChanged: _onChanged,
      onSubmitted: (_) => _onSubmitted(),
      style: textStyle,
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: hint,
        hintStyle: textStyle.copyWith(color: placeholderColor),
        hintMaxLines: 1,
        contentPadding: const EdgeInsets.symmetric(vertical: 17),
      ),
    );

    // Characters left, shown from 199 down; negative (over the limit) in red.
    final counter = ValueListenableBuilder(
      valueListenable: _controller,
      builder: (context, value, _) {
        final remaining = kMaxMessageLength - value.text.characters.length;
        if (remaining > 199) return const SizedBox.shrink();
        return Text(
          '$remaining',
          key: const Key('composer-counter'),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 18 / 14,
            color: remaining < 0 ? const Color(0xFFF87E7A) : colors.dirtyWhite,
          ),
        );
      },
    );

    final mainRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(width: 11),
        Builder(
          builder: (context) => iconButton(
            key: const Key('composer-attach'),
            tooltip: attachTooltip,
            icon: AppIcons.add,
            onPressed: !widget.canSend || _sending || atAttachmentLimit
                ? null
                : () {
                    final box = context.findRenderObject() as RenderBox?;
                    final origin =
                        box?.localToGlobal(Offset.zero) ?? Offset.zero;
                    _openAttachMenu(origin);
                  },
          ),
        ),
        const SizedBox(width: 20),
        Expanded(child: field),
        if (widget.canSend) ...[
          iconButton(
            key: const Key('gif-pick'),
            tooltip: 'GIF',
            icon: AppIcons.gif,
            onPressed: _sending ? null : _pickGif,
          ),
          const SizedBox(width: 8),
          iconButton(
            key: const Key('sticker-pick'),
            tooltip: 'Sticker',
            icon: AppIcons.sticker,
            onPressed: _sending ? null : _pickSticker,
          ),
          const SizedBox(width: 8),
          iconButton(
            key: const Key('emoji-pick'),
            tooltip: 'Emoji',
            icon: AppIcons.emojiEmotionsOutlined,
            onPressed: _sending ? null : _pickEmoji,
          ),
          if (!desktop) ...[
            const SizedBox(width: 8),
            ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, value, _) {
                // Nothing typed or attached: the send slot records a voice
                // message instead.
                if (value.text.trim().isEmpty && _attachments.isEmpty) {
                  return iconButton(
                    key: const Key('voice-message-record'),
                    tooltip: voiceBlocked && cooldown != null
                        ? sendCooldownLabel(cooldown, now)
                        : 'Record a voice message',
                    icon: AppIcons.micNone,
                    onPressed: _sending || voiceBlocked
                        ? null
                        : _startVoiceMessage,
                  );
                }
                return iconButton(
                  tooltip: sendBlocked && cooldown != null
                      ? sendCooldownLabel(cooldown, now)
                      : 'Send',
                  icon: AppIcons.send,
                  onPressed: _sending || sendBlocked ? null : _send,
                );
              },
            ),
          ],
          const SizedBox(width: 12),
        ] else
          const SizedBox(width: 16),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Container(
        key: const Key('composer-box'),
        decoration: BoxDecoration(
          color: composerSurfaceColor(colors),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.replyingTo != null)
              _ReplyBar(
                name: widget.replyName ?? 'message',
                onCancel: widget.onCancelReply,
              ),
            if (_attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 20, 10, 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final file in _attachments) ...[
                        _AttachmentChip(
                          attachment: file,
                          onRemove: _sending
                              ? null
                              : () => _removeAttachment(file),
                          onRename: _sending
                              ? null
                              : () => _renameAttachment(file),
                          onToggleSpoiler: _sending
                              ? null
                              : () => _toggleSpoiler(file),
                        ),
                        const SizedBox(width: 24),
                      ],
                    ],
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: InlineError(_error!, centered: false)),
                    IconButton(
                      tooltip: 'Dismiss',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _error = null),
                      icon: Icon(AppIcons.close, size: 14, color: colors.gray),
                    ),
                  ],
                ),
              ),
            if (!widget.canMentionEveryone)
              // Follows the text itself: pastes and programmatic edits don't
              // otherwise rebuild the composer.
              ValueListenableBuilder(
                valueListenable: _controller,
                builder: (context, value, _) =>
                    _broadcastMention.hasMatch(value.text)
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "You don't have permission to mention @everyone or @here in this channel.",
                            style: Theme.of(context).textTheme.bodySmall!
                                .copyWith(color: colors.yellow),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            if (cooldownLine != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Icon(
                      AppIcons.timerOutlined,
                      size: 14,
                      color: cooldown != null ? colors.yellow : colors.gray,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        cooldownLine,
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: cooldown != null ? colors.yellow : colors.gray,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_mention != null && widget.spaceId != null)
              _MentionPopup(
                spaceId: widget.spaceId!,
                query: _mention!.query,
                allowBroadcast: widget.canMentionEveryone,
                onPick: _pickMention,
                highlighted: _mentionIndex,
              ),
            if (_channelRef != null && widget.spaceId != null)
              _MentionPopup(
                spaceId: widget.spaceId!,
                query: _channelRef!.query,
                allowBroadcast: false,
                channels: true,
                onPick: _pickMention,
                highlighted: _mentionIndex,
              ),
            if (_emojiSuggest != null && _mention == null)
              _EmojiSuggestPopup(
                entries: _emojiSuggestions(),
                query: _emojiSuggest!.query,
                onPick: _pickEmojiSuggestion,
                highlighted: _emojiIndex,
              ),
            if (_slashQuery != null &&
                _command == null &&
                widget.spaceId != null)
              CommandPopup(
                serverKey: _serverKey,
                spaceId: widget.spaceId!,
                query: _slashQuery!,
                onPick: _pickCommand,
              ),
            InteractionStatusLine(channelId: widget.channelId),
            if (_recordingVoice)
              VoiceMessageRecorder(
                onRecorded: _onVoiceMessageRecorded,
                onClosed: _onVoiceMessageClosed,
              )
            else if (_command != null && widget.spaceId != null)
              CommandForm(
                key: ValueKey('command-form-${_command!.id}'),
                serverKey: _serverKey,
                spaceId: widget.spaceId!,
                command: _command!,
                onRun: (options) => _runCommand(_command!, options),
                onCancel: _cancelCommand,
              )
            else
              Stack(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 54),
                    child: mainRow,
                  ),
                  Positioned(right: 14, bottom: 6, child: counter),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// "Replying to **Name**" across the top of the composer box, with the ✕ at
/// the right, as the reference client lays it out.
class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.name, required this.onCancel});

  final String name;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      key: const Key('composer-reply-bar'),
      height: 32,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'Replying to ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 18 / 14,
                  color: colors.interactive,
                ),
                children: [
                  TextSpan(
                    text: name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.dirtyWhite,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Tooltip(
            message: 'Cancel reply',
            child: InkWell(
              onTap: onCancel,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Icon(
                  AppIcons.closeCircle,
                  size: 16,
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

/// The full-pane prompt while a file drag hovers the channel: the reference
/// client's dark veil and the "Upload to #channel" card.
class _UploadOverlay extends StatelessWidget {
  const _UploadOverlay({required this.channelLabel});

  final String channelLabel;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return IgnorePointer(
      child: ColoredBox(
        key: const Key('upload-overlay'),
        color: Colors.black.withValues(alpha: 0.8),
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 330,
                height: 190,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              SizedBox(
                width: 310,
                height: 170,
                child: CustomPaint(
                  painter: _DashedBorderPainter(
                    color: Colors.white.withValues(alpha: 0.4),
                    radius: 6,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        height: 60,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Icon(
                              AppIcons.insertDriveFileOutlined,
                              size: 44,
                              color: Colors.white70,
                            ),
                            Icon(
                              AppIcons.imageOutlined,
                              size: 56,
                              color: Colors.white,
                            ),
                            Icon(
                              AppIcons.code,
                              size: 44,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text.rich(
                        TextSpan(
                          text: 'Upload to ',
                          children: [
                            TextSpan(
                              text: channelLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'You can add comments before uploading.\n'
                        'Hold shift to upload directly.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 16 / 12,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 2 px dashed rounded rectangle along the edge of its box.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rect.deflate(1));
    const dash = 6.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
