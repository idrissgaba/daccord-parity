part of '../quick_switcher.dart';

/// The selected row's wash: the muted grey halfway to the secondary icons
/// (`#96969E`) at 20 %, as measured.
Color _rowSelected(BonfireThemeExtension colors) =>
    Color.lerp(colors.gray, colors.interactive, 0.5)!.withValues(alpha: 0.2);

/// The small grey of category labels and the section header (`#96979E`).
Color _labelGrey(BonfireThemeExtension colors) =>
    Color.lerp(colors.gray, colors.interactive, 0.5)!;

/// The box: the modal surface (`#242429`), white at 4.5 % over the pane
/// background like every other dialog.
Color _boxColor(BonfireThemeExtension colors) => Color.alphaBlend(
  colors.dirtyWhite.withValues(alpha: 0.045),
  colors.background,
);

class _QuickSwitcherDialog extends ConsumerStatefulWidget {
  const _QuickSwitcherDialog({this.current});

  final String? current;

  @override
  ConsumerState<_QuickSwitcherDialog> createState() =>
      _QuickSwitcherDialogState();
}

class _QuickSwitcherDialogState extends ConsumerState<_QuickSwitcherDialog> {
  final _controller = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final _scroll = ScrollController();
  String _query = '';
  int _highlighted = 0;
  List<AccordRelationship> _friends = const [];
  List<QuickSwitchItem> _rows = const [];

  static const double _rowHeight = 34;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  /// Friends are not cached app-wide; the switcher asks once per opening.
  Future<void> _loadFriends() async {
    final key = ref.read(connectionsControllerProvider).activeKey;
    final client = key == null
        ? null
        : ref.read(accordAuthProvider.notifier).clientForKey(key);
    if (client == null) return;
    final result = await client.users.listRelationships();
    final data = result.data;
    if (!mounted || data is! List) return;
    setState(() => _friends = data.whereType<AccordRelationship>().toList());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _pick(QuickSwitchItem item) => Navigator.of(context).pop(item);

  void _move(int step) {
    if (_rows.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + step) % _rows.length;
      if (_highlighted < 0) _highlighted += _rows.length;
    });
    // Keep the highlighted row in view.
    if (!_scroll.hasClients) return;
    final top = _highlighted * _rowHeight;
    final viewport = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + _rowHeight > _scroll.offset + viewport) {
      _scroll.jumpTo(top + _rowHeight - viewport);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent && _rows.isNotEmpty) {
        _pick(_rows[_highlighted.clamp(0, _rows.length - 1)]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final items = gatherQuickSwitchItems(ref, friends: _friends);
    final result = filterQuickSwitch(
      items,
      _query,
      recent: recentQuickSwitchItems(items, current: widget.current),
    );
    _rows = result.items;
    final highlighted = _rows.isEmpty
        ? -1
        : _highlighted.clamp(0, _rows.length - 1);
    final screen = MediaQuery.sizeOf(context);
    final width = _boxWidth(screen);
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: width,
          child: Padding(
            // The box is centred on screen, its title (24 + 7 px) above it.
            padding: const EdgeInsets.only(bottom: 31),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Just above the box, 7 px clear of it.
                SizedBox(
                  height: 24,
                  child: Text(
                    _query.trim().isEmpty
                        ? 'Search for servers, channels or DMs'
                        : 'Select a result and press ENTER to jump to it',
                    key: const Key('quick-switcher-title'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      height: 24 / 18,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  key: const Key('quick-switcher'),
                  height: kQuickSwitcherHeight,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  decoration: BoxDecoration(
                    color: _boxColor(colors),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SearchField(
                        controller: _controller,
                        focusNode: _focus,
                        onChanged: (value) => setState(() {
                          _query = value;
                          _highlighted = 0;
                          if (_scroll.hasClients) _scroll.jumpTo(0);
                        }),
                      ),
                      const SizedBox(height: 16),
                      if (result.header case final header?)
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: SizedBox(
                            height: 30,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                header,
                                key: const Key('quick-switcher-header'),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: colors.interactive,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: ListView.builder(
                          controller: _scroll,
                          padding: EdgeInsets.zero,
                          itemExtent: _rowHeight,
                          itemCount: _rows.length,
                          itemBuilder: (context, index) => _SwitcherRow(
                            item: _rows[index],
                            selected: index == highlighted,
                            onHover: () => setState(() => _highlighted = index),
                            onTap: () => _pick(_rows[index]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 11),
                      Container(height: 1, color: colors.hairline),
                      const SizedBox(height: 11),
                      const _Protip(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 70 px search field: black at 12 % with a 20 % grey border.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    const style = TextStyle(fontSize: 22, fontWeight: FontWeight.w400);
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _labelGrey(colors).withValues(alpha: 0.2)),
      ),
      child: TextField(
        key: const Key('quick-switcher-field'),
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        style: style.copyWith(color: colors.dirtyWhite),
        cursorColor: colors.dirtyWhite,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          hintText: 'Where would you like to go?',
          hintStyle: style.copyWith(color: colors.gray),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _SwitcherRow extends ConsumerWidget {
  const _SwitcherRow({
    required this.item,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  final QuickSwitchItem item;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final person =
        item.kind == QuickSwitchKind.dm || item.kind == QuickSwitchKind.user;
    final bright = person || item.unread;
    final nameColor = bright ? colors.dirtyWhite : colors.interactive;
    final Widget leading;
    switch (item.kind) {
      case QuickSwitchKind.textChannel:
      case QuickSwitchKind.voiceChannel:
        leading = SizedBox(
          width: 24,
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Icon(
              item.kind == QuickSwitchKind.voiceChannel
                  ? AppIcons.volumeUp
                  : AppIcons.tag,
              size: 16,
              color: colors.interactive,
            ),
          ),
        );
      case QuickSwitchKind.space:
        leading = SizedBox(
          width: 25,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _SpaceGlyph(item: item),
          ),
        );
      case QuickSwitchKind.dm:
      case QuickSwitchKind.user:
        final status = item.user == null
            ? null
            : ref.watch(
                presenceControllerProvider(
                  item.serverKey,
                ).select((p) => accordPresenceStatus(p, item.user!.id)),
              );
        leading = SizedBox(
          width: 25,
          child: Align(
            alignment: Alignment.centerLeft,
            child: item.user == null
                ? Icon(AppIcons.group, size: 20, color: colors.interactive)
                : AccordMemberAvatar(
                    avatarUrl: item.imageUrl,
                    initial: item.name.isEmpty ? '?' : item.name[0],
                    status: status,
                    radius: 10,
                    backgroundColor: accordAvatarColor(item.user, item.id),
                    statusRingColor: selected
                        ? Color.alphaBlend(
                            _rowSelected(colors),
                            _boxColor(colors),
                          )
                        : _boxColor(colors),
                    initialStyle: const TextStyle(fontSize: 10),
                  ),
          ),
        );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(),
      child: GestureDetector(
        key: Key('quick-switcher-${item.key}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? _rowSelected(colors) : null,
            borderRadius: BorderRadius.circular(3),
          ),
          padding: const EdgeInsets.only(left: 10, right: 11),
          child: Row(
            children: [
              // Name, nickname and category take the room; the space's name
              // sits at the row's right end.
              Expanded(
                child: Row(
                  children: [
                    leading,
                    Flexible(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: nameColor,
                        ),
                      ),
                    ),
                    if (item.secondary case final secondary?
                        when secondary.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          secondary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: colors.interactive,
                          ),
                        ),
                      ),
                    ],
                    if (item.category case final category?
                        when category.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          category,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _labelGrey(colors),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (item.kind != QuickSwitchKind.space && item.spaceName != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    item.spaceName!,
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.interactive,
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

/// A server's 20 px icon, or nothing when it has none (the reference leaves
/// the slot empty).
class _SpaceGlyph extends StatelessWidget {
  const _SpaceGlyph({required this.item});

  final QuickSwitchItem item;

  @override
  Widget build(BuildContext context) {
    final url = item.imageUrl;
    if (url == null) return const SizedBox(width: 20, height: 20);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 20,
        height: 20,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => const SizedBox(width: 20, height: 20),
      ),
    );
  }
}

/// "Protip: Start searches with @ # ! * to narrow results."
class _Protip extends StatelessWidget {
  const _Protip();

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final text = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 16 / 12,
      color: colors.dirtyWhite,
    );
    WidgetSpan chip(String symbol) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: colors.foreground,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(symbol, style: text.copyWith(fontWeight: FontWeight.w400)),
      ),
    );
    return Text.rich(
      key: const Key('quick-switcher-protip'),
      maxLines: 1,
      overflow: TextOverflow.clip,
      TextSpan(
        style: text,
        children: [
          TextSpan(
            text: 'Protip:',
            style: text.copyWith(color: const Color(0xFF5EB479)),
          ),
          const TextSpan(text: ' Start searches with '),
          for (final symbol in quickSwitchPrefixes.keys) chip(symbol),
          const TextSpan(text: ' to narrow results.'),
        ],
      ),
    );
  }
}
