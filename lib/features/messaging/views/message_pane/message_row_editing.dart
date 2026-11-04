part of 'message_pane.dart';

/// The inline editor: opening it (also from the ↑ shortcut), Enter/Shift+Enter/Escape, saving. Split from [_MessageRowState] for size.
mixin _MessageRowEditing on ConsumerState<_MessageRow> {
  AccordClient? get _client;
  AccordMessage get _message;

  bool _busy = false;
  bool _editing = false;

  TextEditingController? _editController;

  /// Focus of the inline editor, so Enter saves, Shift+Enter breaks the line
  /// and Escape cancels — a multi-line field's own `onSubmitted` never fires.
  FocusNode? _editFocus;

  void _onEditRequest() {
    final message = _message;
    if (widget.editRequest?.value != message.id) return;
    if (_editing || !widget.isOwn || widget.selecting) return;
    _startEdit(message);
  }

  /// The message the inline editor was opened on. The edit is committed against
  /// this id rather than the currently-bound one, so an in-progress edit can
  /// never be saved onto a neighbouring message.
  String? _editingMessageId;

  void _startEdit(AccordMessage message) {
    setState(() {
      _editing = true;
      _editingMessageId = message.id;
      _editController = TextEditingController(text: message.content)
        // Caret at the end, where an edit usually continues.
        ..selection = TextSelection.collapsed(offset: message.content.length);
      _editFocus?.dispose();
      _editFocus = FocusNode(onKeyEvent: _onEditKey);
    });
    // `autofocus` yields when something else (the composer, after ↑) already
    // holds focus; take it once the field exists, so Enter/Escape and typing
    // go to the editor and not to the composer underneath.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _editFocus?.requestFocus();
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _editingMessageId = null;
      _editController?.dispose();
      _editController = null;
      _editFocus?.dispose();
      _editFocus = null;
    });
  }

  /// Enter saves, Shift+Enter inserts a newline, Escape cancels. On Linux
  /// Shift+Enter is left to GTK, which inserts the newline itself (see
  /// [composerUsesNativeNewlines]).
  KeyEventResult _onEditKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final controller = _editController;
    if (controller == null) return KeyEventResult.ignored;
    final mods = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent && !_busy) _cancelEdit();
      return KeyEventResult.handled;
    }
    final composing = controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (isShiftEnterChord(event, mods)) {
      if (composerUsesNativeNewlines) return KeyEventResult.ignored;
      controller.value = insertAtSelection(controller.value, '\n');
      return KeyEventResult.handled;
    }
    if (isPlainEnter(event, mods)) {
      if (event is KeyDownEvent) _saveEdit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// What an emptied editor does on Enter; the handlers mixin deletes with
  /// confirmation.
  void _onEmptyEdit(String messageId);

  Future<void> _saveEdit() async {
    final client = _client;
    final raw = _editController?.text ?? '';
    // Edits convert emoticons too, matching the send path — otherwise fixing a
    // typo would silently downgrade an already-converted glyph back to ASCII.
    final text =
        ref.read(settingsControllerProvider.select((s) => s.convertEmoticons))
        ? applyEmoticons(raw)
        : raw;
    // Commit against the message the editor was opened on, captured before the
    // round-trip.
    final messageId = _editingMessageId ?? _message.id;
    if (client == null || _busy) return;
    if (text.trim().isEmpty) {
      // Enter on an emptied editor: the reference client asks whether to
      // delete the message instead of saving nothing.
      _cancelEdit();
      _onEmptyEdit(messageId);
      return;
    }
    setState(() => _busy = true);
    final ok = await ref
        .read(
          accordMessagesControllerProvider(
            ref.readActiveServerKey() ?? '',
            widget.channelId,
          ).notifier,
        )
        .edit(client, messageId, text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) _cancelEdit();
  }

  /// The reference client's inline editor: the message text in a composer
  /// box (56 px, 16 px text, emoji button at the right) under the header, and
  /// the "escape to cancel • enter to save" line beneath it.
  Widget _buildEditor(ThemeData theme, BonfireThemeExtension colors) {
    const link = Color(0xFF4D96EE);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
          decoration: BoxDecoration(
            color: composerSurfaceColor(colors),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('inline-message-editor'),
                  controller: _editController,
                  focusNode: _editFocus,
                  autofocus: true,
                  enabled: !_busy,
                  minLines: 1,
                  maxLines: 12,
                  style: const TextStyle(fontSize: 16, height: 22 / 16),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 17),
                  ),
                  onSubmitted: (_) => _saveEdit(),
                ),
              ),
              IconButton(
                tooltip: 'Emoji',
                onPressed: _busy ? null : _pickEditorEmoji,
                icon: Icon(
                  AppIcons.emojiEmotionsOutlined,
                  size: 24,
                  color: colors.interactive,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: 12,
                height: 1,
                color: colors.dirtyWhite,
              ),
              children: [
                const TextSpan(text: 'escape to '),
                TextSpan(
                  text: 'cancel',
                  style: const TextStyle(color: link),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      if (!_busy) _cancelEdit();
                    },
                ),
                const TextSpan(text: ' • enter to '),
                TextSpan(
                  text: 'save',
                  style: const TextStyle(color: link),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      if (!_busy) _saveEdit();
                    },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Inserts an emoji at the editor's caret.
  Future<void> _pickEditorEmoji() async {
    final controller = _editController;
    if (controller == null) return;
    final pick = await showAccordEmojiPicker(context, spaceId: widget.spaceId);
    if (pick == null || !mounted || _editController != controller) return;
    controller.value = insertAtSelection(controller.value, pick.composerText);
    _editFocus?.requestFocus();
  }
}
