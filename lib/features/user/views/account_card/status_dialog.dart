part of '../account_card.dart';

/// The "Clear after" choices of the Set your status dialog.
const List<({String label, Duration? duration})> _kClearAfter = [
  (label: '24 hours', duration: Duration(hours: 24)),
  (label: '4 hours', duration: Duration(hours: 4)),
  (label: '1 hour', duration: Duration(hours: 1)),
  (label: '30 minutes', duration: Duration(minutes: 30)),
  (label: "Don't clear", duration: null),
];

/// Opens "Set your status": a live preview of your card, the status field
/// with its emoji button, "Clear after" and Save.
Future<void> showCustomStatusDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => const _CustomStatusDialog(),
  );
}

class _CustomStatusDialog extends ConsumerStatefulWidget {
  const _CustomStatusDialog();

  @override
  ConsumerState<_CustomStatusDialog> createState() =>
      _CustomStatusDialogState();
}

class _CustomStatusDialogState extends ConsumerState<_CustomStatusDialog> {
  late final TextEditingController _text;
  Duration? _clearAfter = const Duration(hours: 24);
  final String _prompt = statusPromptOfTheDay();

  @override
  void initState() {
    super.initState();
    final userId = ref.read(accordAuthProvider) is AccordAuthLoggedIn
        ? (ref.read(accordAuthProvider) as AccordAuthLoggedIn).session.userId
        : '';
    final current = accordCustomStatus(ref.read(activePresencesProvider), userId);
    _text = TextEditingController(text: current ?? '');
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String _time(DateTime t) => TimeOfDay.fromDateTime(t).format(context);

  /// "24 hours (tomorrow at 22:32)", "1 hour (23:32)".
  String _choiceLabel(({String label, Duration? duration}) c) {
    final d = c.duration;
    if (d == null) return c.label;
    final at = DateTime.now().add(d);
    final today = DateTime.now();
    final sameDay = at.day == today.day && at.month == today.month;
    return '${c.label} (${sameDay ? '' : 'tomorrow at '}${_time(at)})';
  }

  /// "Clear tomorrow at 22:31" / "Clear at 23:31" / "Don't clear".
  String _footerLabel() {
    final d = _clearAfter;
    if (d == null) return "Don't clear";
    final at = DateTime.now().add(d);
    final today = DateTime.now();
    final sameDay = at.day == today.day && at.month == today.month;
    return sameDay ? 'Clear at ${_time(at)}' : 'Clear tomorrow at ${_time(at)}';
  }

  void _save() {
    final serverKey = ref.readActiveServerKey();
    if (serverKey == null) return;
    ref
        .read(selfPresenceControllerProvider.notifier)
        .setCustomStatus(serverKey, _text.text, until: untilFrom(_clearAfter));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final surface = Color.alphaBlend(
      colors.dirtyWhite.withValues(alpha: 0.03),
      colors.raised,
    );
    final serverKey = ref.watchActiveServerKey() ?? '';
    final userId = ref.watchUserId() ?? '';
    final user = ref.watch(
      accordUsersControllerProvider(serverKey).select((u) => u[userId]),
    );
    final status = ref.watch(
      activePresencesProvider.select((p) => accordPresenceStatus(p, userId)),
    );
    final sessionName = ref.watch(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session.username : null,
      ),
    );
    final name = accordUserName(user, fallback: sessionName ?? userId);
    final avatarUrl = user == null ? null : accordAvatarUrl(user, ref.watchCdnUrl());
    final card = profileCardColor(colors);
    final muted = Color.lerp(colors.gray, colors.interactive, 0.5)!;

    return Dialog(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.hairline),
      ),
      child: SizedBox(
        width: 480,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Set your status',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        height: 24 / 20,
                        color: colors.dirtyWhite,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('status-dialog-close'),
                    tooltip: 'Close',
                    iconSize: 20,
                    color: colors.interactive,
                    icon: const Icon(AppIcons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // The live preview of your card.
              Center(
                child: Container(
                  width: 300,
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 105 + 44,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ProfileBanner(
                              height: 105,
                              topRadius: 7,
                              avatarUrl: avatarUrl,
                            ),
                            Positioned(
                              left: 12,
                              top: 57,
                              child: ProfileAvatarCutout(
                                size: 80,
                                ring: 4,
                                avatarUrl: avatarUrl,
                                initial: accordInitial(name),
                                backgroundColor: accordAvatarColor(user, userId),
                                status: status,
                                cardColor: card,
                              ),
                            ),
                            Positioned(
                              left: 106,
                              top: 99,
                              child: CustomStatusBubble(
                                text: _text.text.trim().isEmpty
                                    ? null
                                    : _text.text.trim(),
                                prompt: _prompt,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                height: 24 / 20,
                                color: colors.dirtyWhite,
                              ),
                            ),
                            if ((user?.username ?? '').isNotEmpty)
                              Text(
                                user!.username,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 18 / 14,
                                  color: colors.dirtyWhite,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 42),
              Text(
                'Status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 20 / 16,
                  color: colors.dirtyWhite,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.primary),
                ),
                child: Row(
                  children: [
                    Builder(
                      builder: (buttonContext) => IconButton(
                        key: const Key('status-dialog-emoji'),
                        tooltip: 'Select emoji',
                        iconSize: 22,
                        color: colors.interactive,
                        icon: const Icon(AppIcons.emojiEmotionsOutlined),
                        onPressed: () async {
                          final pick = await showAccordEmojiPicker(
                            buttonContext,
                          );
                          if (pick == null) return;
                          final rest = _text.text.trimLeft();
                          _text.text = '${pick.composerText} $rest'.trimRight();
                        },
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        key: const Key('status-dialog-field'),
                        controller: _text,
                        autofocus: true,
                        maxLength: 128,
                        onSubmitted: (_) => _save(),
                        style: TextStyle(fontSize: 16, color: colors.dirtyWhite),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          counterText: '',
                          border: InputBorder.none,
                          hintText: _prompt,
                          hintStyle: TextStyle(fontSize: 16, color: muted),
                        ),
                      ),
                    ),
                    if (_text.text.isNotEmpty)
                      IconButton(
                        key: const Key('status-dialog-clear'),
                        tooltip: 'Clear',
                        iconSize: 18,
                        color: colors.interactive,
                        icon: const Icon(AppIcons.closeCircle),
                        onPressed: _text.clear,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Row(
                children: [
                  Builder(
                    builder: (buttonContext) => TextButton(
                      key: const Key('status-dialog-clear-after'),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.dirtyWhite,
                        padding: EdgeInsets.zero,
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onPressed: () {
                        final box =
                            buttonContext.findRenderObject() as RenderBox?;
                        showAccordContextMenu(
                          context,
                          globalPosition: box?.localToGlobal(
                            Offset(box.size.width + 24, 0),
                          ),
                          entries: [
                            const AccordMenuEntry(label: 'Clear after'),
                            for (final c in _kClearAfter)
                              AccordMenuEntry(
                                label: _choiceLabel(c),
                                trailing: c.duration == _clearAfter
                                    ? Container(
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color: colors.primary,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          AppIcons.check,
                                          size: 12,
                                          color: Colors.white,
                                        ),
                                      )
                                    : null,
                                onSelected: () =>
                                    setState(() => _clearAfter = c.duration),
                              ),
                          ],
                        );
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_footerLabel()),
                          const SizedBox(width: 4),
                          const Icon(AppIcons.expandMore, size: 16),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 38,
                    child: FilledButton(
                      key: const Key('status-dialog-save'),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(96, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onPressed: _save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
