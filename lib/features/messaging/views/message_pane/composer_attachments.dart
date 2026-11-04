part of 'message_pane.dart';

/// Attachments: file picking and drops, voice messages, polls, stickers and the emoji picker. Split from [_ComposerState] for size.
mixin _ComposerAttachments on ConsumerState<_Composer> {
  String? get _error;
  set _error(String? value);
  FocusNode get _focusNode;
  TextEditingController get _controller;
  void _insertAtCursor(String text);
  Future<void> _send();
  bool get _sending;

  /// Files the user has attached but not yet sent.
  final List<PendingAttachment> _attachments = [];

  /// True while a voice message is being recorded: the recorder replaces the
  /// text field and its buttons.
  bool _recordingVoice = false;

  /// Opens the system file picker.
  ///
  /// No `allowedExtensions` filter: the Accord server enforces no type
  /// allow-list on message attachments (only size and count — see
  /// `AccordServerLimits`), so filtering here would hide legitimate files.
  /// Unrecognised types attach and upload; they just don't preview inline.
  ///
  /// The picker can throw rather than return null (Windows' legacy
  /// `GetOpenFileNameW` fails on a cloud placeholder or an over-MAX_PATH
  /// selection); unguarded, that escapes the unawaited `onPressed` and the
  /// attach button appears to do nothing.
  Future<void> _pickFiles({bool gifOnly = false}) async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: gifOnly ? FileType.custom : FileType.any,
        allowedExtensions: gifOnly ? const ['gif'] : null,
      );
    } catch (e) {
      debugPrint('File picker failed: $e');
      if (mounted) {
        setState(() => _error = "Couldn't open the file picker: $e");
      }
      return;
    }
    if (result == null || !mounted) return;
    _addFiles([for (final file in result.files) PendingAttachment(file)]);
  }

  /// A drop on the message pane (see `_MessagePaneState._wrapDrop`).
  Future<void> _onDrop(DropDoneDetails details) async {
    if (_sending) return;
    final dropped = await readDroppedFiles(
      details.files,
      maxBytes: ref.read(serverLimitsControllerProvider).maxAttachmentBytes,
    );
    if (!mounted) return;
    _addFiles(dropped.accepted, alsoRejected: dropped.rejections);
  }

  /// Attaches every file in [files] that passes the connected server's
  /// limits, and reports the ones that don't, along with any [alsoRejected]
  /// lines the caller screened out itself. A file dropped in silence would
  /// look like the attach button doing nothing.
  void _addFiles(
    Iterable<PendingAttachment> files, {
    List<String> alsoRejected = const [],
  }) {
    final limits = ref.read(serverLimitsControllerProvider);
    final screened = screenAttachments(
      files,
      maxBytes: limits.maxAttachmentBytes,
      maxCount: limits.maxAttachmentsPerMessage,
      alreadyAttached: _attachments.length,
    );
    final rejections = [...alsoRejected, ...screened.rejections];
    setState(() {
      _attachments.addAll(screened.accepted);
      _error = rejections.isEmpty ? null : rejections.join('\n');
    });
  }

  void _startVoiceMessage() {
    setState(() {
      _recordingVoice = true;
      _error = null;
    });
  }

  /// A finished voice message is sent straight away, like any attachment.
  void _onVoiceMessageRecorded(PendingAttachment file) {
    setState(() => _recordingVoice = false);
    _addFiles([file]);
    if (_attachments.contains(file)) unawaited(_send());
  }

  void _onVoiceMessageClosed(String? error) {
    if (!mounted) return;
    setState(() {
      _recordingVoice = false;
      _error = error;
    });
  }

  void _createPoll() {
    final client = ref.accordClient;
    if (client == null) return;
    final controller = ref.read(
      accordMessagesControllerProvider(
        ref.readActiveServerKey() ?? '',
        widget.channelId,
      ).notifier,
    );
    showCreatePollDialog(
      context,
      create:
          ({
            required question,
            required answers,
            required allowMultiselect,
            required durationHours,
          }) => controller.createPoll(
            client,
            question: question,
            answers: answers,
            allowMultiselect: allowMultiselect,
            durationHours: durationHours,
          ),
    );
  }

  void _removeAttachment(PendingAttachment file) {
    setState(() => _attachments.remove(file));
  }

  /// Swaps [file] for [replacement] in place, keeping its slot.
  void _replaceAttachment(
    PendingAttachment file,
    PendingAttachment replacement,
  ) {
    final index = _attachments.indexOf(file);
    if (index < 0) return;
    setState(() => _attachments[index] = replacement);
  }

  /// "Modify Attachment": a new file name, keeping the extension sensible.
  Future<void> _renameAttachment(PendingAttachment file) async {
    final name = await showTextPromptDialog(
      context,
      title: 'Edit Attachment',
      label: 'Filename',
      initial: file.name,
      confirmLabel: 'Save',
    );
    if (name == null || !mounted) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == file.name) return;
    _replaceAttachment(file, file.renamed(trimmed));
  }

  /// "Spoiler Attachment": toggles the `SPOILER_` prefix that marks an
  /// attachment as hidden until clicked.
  void _toggleSpoiler(PendingAttachment file) {
    final name = file.isSpoiler
        ? file.name.substring(kSpoilerPrefix.length)
        : '$kSpoilerPrefix${file.name}';
    _replaceAttachment(file, file.renamed(name));
  }

  /// The "+" menu: Upload a File, Create Poll (in a space). Opens above the
  /// button, its left edge on the button's.
  void _openAttachMenu(Offset buttonOrigin) {
    showAccordContextMenu(
      context,
      globalPosition: buttonOrigin,
      preferAbove: true,
      anchorLeft: true,
      width: 148,
      title: 'Attach',
      entries: [
        AccordMenuEntry(
          label: 'Upload a File',
          icon: AppIcons.uploadFile,
          onSelected: _pickFiles,
        ),
        if (widget.spaceId != null)
          AccordMenuEntry(
            key: const Key('poll-create'),
            label: 'Create Poll',
            icon: AppIcons.pollOutlined,
            onSelected: _createPoll,
          ),
      ],
    );
  }

  /// Where the expression picker stands: above this composer's box.
  Rect? _composerRect() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    // The box sits 8 px in from the composer's edges (see _ComposerView).
    return Rect.fromLTWH(
      origin.dx + 8,
      origin.dy,
      box.size.width - 16,
      box.size.height - 8,
    );
  }

  Future<void> _pickEmoji() => _openExpressions(ExpressionTab.emoji);
  Future<void> _pickGif() => _openExpressions(ExpressionTab.gifs);
  Future<void> _pickSticker() => _openExpressions(ExpressionTab.stickers);

  /// Opens the GIFs / Stickers / Emoji popover on [tab] and acts on the pick.
  Future<void> _openExpressions(ExpressionTab tab) async {
    final pick = await showExpressionPicker(
      context,
      spaceId: widget.spaceId,
      channelId: widget.channelId,
      initialTab: tab,
      anchorRect: _composerRect(),
    );
    if (pick == null || !mounted) return;
    if (pick.emoji case final emoji?) {
      _insertAtCursor(emoji.composerText);
    } else if (pick.sticker case final sticker?) {
      await _sendSticker(sticker);
    } else if (pick.gifUrl case final url?) {
      _controller.text = url;
      await _send();
    } else if (pick.uploadGif) {
      await _pickFiles(gifOnly: true);
    }
    if (mounted) _focusNode.requestFocus();
  }

  /// Sends [sticker] to the channel.
  Future<void> _sendSticker(AccordSticker sticker) async {
    final client = ref.accordClient;
    if (client == null || !mounted) return;
    final result = await client.stickers.send(widget.channelId, sticker.id);
    if (!mounted) return;
    final message = result.data;
    if (result.ok && message is AccordMessage) {
      ref
          .read(
            accordMessagesControllerProvider(
              ref.readActiveServerKey() ?? '',
              widget.channelId,
            ).notifier,
          )
          .addMessage(message);
    } else {
      setState(
        () => _error = result.errorMessageOr('Could not send the sticker'),
      );
    }
  }
}
