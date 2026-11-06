part of '../soundboard_settings_page.dart';

/// Opens the reference client's "Upload a Sound" dialog (File, Sound Name,
/// Related Emoji, Sound Volume; "Never mind" / "Upload"), or — for an
/// [existing] sound — the same form without the file, to edit it.
Future<void> showSoundDialog(
  BuildContext context, {
  required String serverKey,
  required String spaceId,
  AccordSound? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SoundDialog(
      serverKey: serverKey,
      spaceId: spaceId,
      existing: existing,
    ),
  );
}

/// Sound names: 2 to 32 characters, as on the reference client and server.
const int _kMinSoundName = 2;
const int _kMaxSoundName = 32;

class _SoundDialog extends ConsumerStatefulWidget {
  const _SoundDialog({
    required this.serverKey,
    required this.spaceId,
    this.existing,
  });

  final String serverKey;
  final String spaceId;
  final AccordSound? existing;

  @override
  ConsumerState<_SoundDialog> createState() => _SoundDialogState();
}

class _SoundDialogState extends ConsumerState<_SoundDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  PlatformFile? _file;
  late String? _emojiId = widget.existing?.emojiId;
  late String? _emojiName = widget.existing?.emojiName;
  late double _volume = (widget.existing?.volume ?? 1.0).clamp(0.0, 1.0);
  bool _busy = false;
  String? _error;

  bool get _editing => widget.existing != null;

  bool get _valid {
    final n = _name.text.trim().characters.length;
    return (_editing || _file?.bytes != null) &&
        n >= _kMinSoundName &&
        n <= _kMaxSoundName &&
        !_busy;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file?.bytes == null || !mounted) return;
    setState(() {
      _file = file;
      _error = null;
      if (_name.text.trim().isEmpty) {
        final base = file!.name.contains('.')
            ? file.name.substring(0, file.name.lastIndexOf('.'))
            : file.name;
        _name.text = base.characters.take(_kMaxSoundName).toString();
      }
    });
  }

  Future<void> _pickEmoji() async {
    final pick = await showAccordEmojiPicker(context, spaceId: widget.spaceId);
    if (pick == null || !mounted) return;
    setState(() {
      if (pick.isCustom) {
        _emojiId = pick.id;
        _emojiName = pick.name;
      } else {
        _emojiId = null;
        _emojiName = pick.char;
      }
    });
  }

  Future<void> _submit() async {
    if (!_valid) return;
    final client = ref.accordClient;
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final name = _name.text.trim();
    final RestResult result;
    if (_editing) {
      result = await client.soundboard.update(
        widget.spaceId,
        widget.existing!.id!,
        {
          'name': name,
          'volume': _volume,
          'emoji_id': _emojiId,
          'emoji_name': _emojiName,
        },
      );
    } else {
      final file = _file!;
      result = await client.soundboard.create(widget.spaceId, {
        'name': name,
        'audio': AccordCDN.buildDataUri(file.bytes!, file.name),
        'volume': _volume,
        if (_emojiId != null) 'emoji_id': _emojiId,
        if (_emojiName != null) 'emoji_name': _emojiName,
      });
    }
    if (!mounted) return;
    if (result.ok && result.data is AccordSound) {
      ref
          .read(
            soundboardSoundsControllerProvider(
              widget.serverKey,
              widget.spaceId,
            ).notifier,
          )
          .upsert(result.data as AccordSound);
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = result.errorOr(
        _editing ? 'Failed to save sound' : 'Failed to upload sound',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final labelStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 20 / 16,
      color: colors.dirtyWhite,
    );
    Widget label(String text, {bool required = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          text: text,
          children: [
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(
                  fontWeight: FontWeight.w400,
                  color: Color(0xFFF87E7A),
                ),
              ),
          ],
        ),
        style: labelStyle,
      ),
    );
    BoxDecoration box() => BoxDecoration(
      color: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: colors.hairline),
    );
    const hint = Color(0xFF96979E);
    final emojiPreview = AccordSound(
      spaceId: widget.spaceId,
      emojiId: _emojiId,
      emojiName: _emojiName,
    );
    final hasEmoji = SoundEmoji.hasEmoji(emojiPreview);

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_editing) ...[
          label('File', required: true),
          Container(
            height: 40,
            decoration: box(),
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(
              children: [
                Icon(AppIcons.upload, size: 16, color: colors.interactive),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _file?.name ?? 'Choose a file',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      color: _file == null ? hint : colors.dirtyWhite,
                    ),
                  ),
                ),
                SizedBox(
                  height: 32,
                  child: TextButton(
                    key: const Key('sound-dialog-browse'),
                    onPressed: _busy ? null : _browse,
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0x1F97979F),
                      foregroundColor: colors.dirtyWhite,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Browse',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 266,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  label('Sound Name', required: true),
                  Container(
                    height: 40,
                    decoration: box(),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    child: TextField(
                      key: const Key('sound-dialog-name'),
                      controller: _name,
                      maxLength: _kMaxSoundName,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                      style: TextStyle(fontSize: 16, color: colors.dirtyWhite),
                      decoration: const InputDecoration(
                        isDense: true,
                        counterText: '',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Sound Name',
                        hintStyle: TextStyle(fontSize: 16, color: hint),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 156,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  label('Related Emoji'),
                  InkWell(
                    key: const Key('sound-dialog-emoji'),
                    onTap: _busy ? null : _pickEmoji,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 40,
                      decoration: box(),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          if (hasEmoji)
                            SoundEmoji(
                              sound: emojiPreview,
                              serverKey: widget.serverKey,
                              size: 20,
                            )
                          else
                            Icon(
                              AppIcons.addReactionOutlined,
                              size: 16,
                              color: colors.interactive,
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              hasEmoji
                                  ? (_emojiId != null
                                        ? ':${_emojiName ?? ''}:'
                                        : 'Change')
                                  : 'Click to select',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                color: hasEmoji ? colors.dirtyWhite : hint,
                              ),
                            ),
                          ),
                          if (hasEmoji)
                            InkResponse(
                              key: const Key('sound-dialog-emoji-clear'),
                              onTap: () => setState(() {
                                _emojiId = null;
                                _emojiName = null;
                              }),
                              radius: 12,
                              child: Icon(
                                AppIcons.close,
                                size: 14,
                                color: colors.interactive,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        label('Sound Volume'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: AccordSlider(
            key: const Key('sound-dialog-volume'),
            value: _volume,
            onChanged: _busy ? null : (v) => setState(() => _volume = v),
            semanticLabel: 'Sound volume',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(fontSize: 14, color: colors.red)),
        ],
      ],
    );
    return AccordDialog(
      title: _editing ? 'Edit Sound' : 'Upload a Sound',
      body: body,
      secondaryLabel: 'Never mind',
      primaryLabel: _editing ? 'Save' : 'Upload',
      primaryEnabled: _valid,
      onPrimary: _submit,
    );
  }
}
