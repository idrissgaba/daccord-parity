part of '../emoji_picker.dart';

/// A pseudo-category selected by the rail in addition to the standard
/// [EmojiCategory] values and the spaces' custom sets.
enum _Tab { recent }

/// Size of one emoji cell (40 px glyph + 4 px padding), the section header
/// and the rail, as the reference client draws them.
const double _kCell = 48;
const double _kHeader = 32;
const double _kRail = 48;

/// Skin-tone modifiers, so a toned recent/reaction glyph can be traced back
/// to its catalogue entry.
const _kToneModifiers = ['🏻', '🏼', '🏽', '🏾', '🏿'];

/// The emoji tab: search, skin tone and "Add Emoji" (or, for reactions, the
/// Super Reaction toggle) across the top; a rail of sections at the left —
/// Frequently Used, every space's custom emoji, the unicode categories — one
/// grid scrolling through them, and the hovered emoji named along the bottom.
/// Emoji of spaces other than [spaceId] are shown locked, as the reference
/// client shows another server's emoji. Shared by the composer popover, the
/// reaction picker and the touch bottom sheet.
class EmojiPickerPanel extends ConsumerStatefulWidget {
  const EmojiPickerPanel({
    super.key,
    required this.onPick,
    this.spaceId,
    this.compact = false,
    this.autofocusSearch = false,
    this.reaction = false,
    this.embedded = false,
  });

  final ValueChanged<EmojiPick> onPick;
  final String? spaceId;

  /// Touch layout: the category rail runs horizontally above the grid.
  final bool compact;
  final bool autofocusSearch;

  /// Picking a reaction: offers the Super Reaction toggle.
  final bool reaction;

  /// Inside the composer popover, under its tab row (no top padding).
  final bool embedded;

  @override
  ConsumerState<EmojiPickerPanel> createState() => _EmojiPickerPanelState();
}

class _CustomSet {
  const _CustomSet(this.space, this.emoji, {required this.locked});

  final AccordSpace space;
  final List<AccordEmoji> emoji;
  final bool locked;
}

class _EmojiPickerPanelState extends ConsumerState<EmojiPickerPanel> {
  final _scroll = ScrollController();
  final _hovered = ValueNotifier<EmojiPick?>(null);
  String _query = '';
  bool _super = false;

  /// Sections folded by a click on their header.
  final Set<Object> _collapsed = {};

  /// The rail entry highlighted: follows the scroll position, or the search.
  Object _active = _Tab.recent;
  List<_Section> _sections = const [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_followScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _hovered.dispose();
    super.dispose();
  }

  String? get _cdnUrl => ref.readCdnUrl();
  String get _serverKey => ref.readActiveServerKey() ?? '';

  /// Every space's custom emoji: the current space first and usable, the
  /// others after it, locked.
  List<_CustomSet> _customSets() {
    final spaces = ref.watch(spacesControllerProvider) ?? const <AccordSpace>[];
    final sets = <_CustomSet>[];
    final ordered = [
      ...spaces.where((s) => s.id == widget.spaceId),
      ...spaces.where((s) => s.id != widget.spaceId),
    ];
    for (final space in ordered) {
      final emoji =
          ref.watch(accordEmojisControllerProvider(_serverKey, space.id)) ??
          const <AccordEmoji>[];
      if (emoji.isEmpty) continue;
      sets.add(_CustomSet(space, emoji, locked: space.id != widget.spaceId));
    }
    return sets;
  }

  List<AccordEmoji> get _usableCustom {
    final spaceId = widget.spaceId;
    if (spaceId == null) return const [];
    return ref.watch(accordEmojisControllerProvider(_serverKey, spaceId)) ??
        const [];
  }

  int get _tone =>
      ref.watch(settingsControllerProvider.select((s) => s.emojiSkinTone));

  void _pick(EmojiPick pick) {
    if (widget.spaceId != null || !pick.isCustom) {
      ref
          .read(settingsControllerProvider.notifier)
          .addRecentEmoji(pick.recentToken);
    }
    widget.onPick(_super ? pick.asSuper() : pick);
  }

  void _followScroll() {
    if (!_scroll.hasClients || _query.isNotEmpty) return;
    final offset = _scroll.offset + 1;
    Object? current;
    for (final s in _sections) {
      if (s.start <= offset) current = s.id;
    }
    if (current != null && current != _active) {
      setState(() => _active = current!);
    }
  }

  void _jumpTo(Object id) {
    setState(() => _active = id);
    final section = _sections.where((s) => s.id == id).firstOrNull;
    if (section == null || !_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    _scroll.animateTo(
      section.start.clamp(0, max),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  /// Reconstructs an [EmojiPick] from a stored recent token, resolving custom
  /// tokens (`name:id`) against the current space's emoji.
  EmojiPick? _pickFromRecent(String token, List<AccordEmoji> custom) {
    final sep = token.lastIndexOf(':');
    if (sep > 0 && sep < token.length - 1) {
      final id = token.substring(sep + 1);
      final match = custom.firstWhereOrNull((e) => e.id == id);
      if (match == null) return null; // not usable here
      return EmojiPick(
        name: match.name,
        id: match.id,
        imageUrl: _emojiImageUrl(match),
      );
    }
    var base = token;
    for (final m in _kToneModifiers) {
      base = base.replaceAll(m, '');
    }
    final entry = kEmojiCatalog.firstWhere(
      (e) => e.char == token || e.char == base,
      orElse: () => EmojiEntry(token, token, EmojiCategory.smileys),
    );
    return EmojiPick(name: entry.name, char: token);
  }

  String? _emojiImageUrl(AccordEmoji emoji) => accordEmojiUrl(emoji, _cdnUrl);

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final usable = _usableCustom;
    final sets = _customSets();
    final recents = ref.watch(
      settingsControllerProvider.select((s) => s.recentEmoji),
    );
    final tone = _tone;
    final rail = _CategoryRail(
      hasRecent: recents.isNotEmpty,
      spaces: [for (final set in sets) (set.space, set.locked)],
      cdnUrl: _cdnUrl,
      selected: _query.isEmpty ? _active : null,
      horizontal: widget.compact,
      onSelect: _jumpTo,
    );
    final canAddEmoji = widget.spaceId != null && !widget.reaction;
    final header = Padding(
      padding: EdgeInsets.fromLTRB(16, widget.embedded ? 0 : 16, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _PickerSearchField(
              fieldKey: const Key('emoji-picker-search'),
              hint: 'Find the perfect emoji',
              autofocus: widget.autofocusSearch,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              onSubmitted: () => _pickFirstResult(usable, tone),
            ),
          ),
          const SizedBox(width: 12),
          _SkinToneButton(
            tone: tone,
            onChanged: (t) => ref
                .read(settingsControllerProvider.notifier)
                .setEmojiSkinTone(t),
          ),
          if (widget.reaction) ...[
            const SizedBox(width: 12),
            _SuperToggle(
              on: _super,
              onChanged: (v) => setState(() => _super = v),
            ),
          ] else if (canAddEmoji) ...[
            const SizedBox(width: 12),
            SizedBox(
              height: 40,
              child: TextButton(
                key: const Key('emoji-picker-add'),
                style: TextButton.styleFrom(
                  backgroundColor: colors.selection.withValues(alpha: 0.12),
                  foregroundColor: colors.dirtyWhite,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                  ),
                ),
                onPressed: () => showAccordEmojiManagement(
                  context,
                  spaceId: widget.spaceId!,
                ),
                child: const Text(
                  'Add Emoji',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    final grid = _query.isNotEmpty
        ? _buildSearchGrid(colors, usable, tone)
        : _buildSections(colors, sets, recents, tone);
    return Column(
      children: [
        header,
        if (widget.compact) rail,
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.compact) rail,
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: grid),
                    _PreviewBar(hovered: _hovered),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<EmojiEntry> _unicodeHits() => [
    for (final e in kEmojiCatalog)
      if (e.matches(_query)) e,
  ];

  List<AccordEmoji> _customHits(List<AccordEmoji> custom) => [
    for (final e in custom)
      if (e.name.toLowerCase().contains(_query)) e,
  ];

  void _pickFirstResult(List<AccordEmoji> custom, int tone) {
    if (_query.isEmpty) return;
    final customHits = _customHits(custom);
    if (customHits.isNotEmpty) {
      final e = customHits.first;
      _pick(EmojiPick(name: e.name, id: e.id, imageUrl: _emojiImageUrl(e)));
      return;
    }
    final hits = _unicodeHits();
    if (hits.isNotEmpty) _pick(_unicodePick(hits.first, tone));
  }

  Widget _buildSearchGrid(
    BonfireThemeExtension colors,
    List<AccordEmoji> custom,
    int tone,
  ) {
    final unicodeHits = _unicodeHits();
    final customHits = _customHits(custom);
    if (unicodeHits.isEmpty && customHits.isEmpty) {
      return Center(
        child: Text(
          'No emoji match "$_query"',
          style: TextStyle(color: colors.gray),
        ),
      );
    }
    final cells = [
      for (final e in customHits) _customCell(e),
      for (final e in unicodeHits) _unicodeCell(e, tone),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _columns(constraints.maxWidth),
          mainAxisExtent: _kCell,
        ),
        itemCount: cells.length,
        itemBuilder: (context, i) => cells[i],
      ),
    );
  }

  int _columns(double width) => ((width - 16) / _kCell).floor().clamp(1, 20);

  Widget _buildSections(
    BonfireThemeExtension colors,
    List<_CustomSet> sets,
    List<String> recents,
    int tone,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columns(constraints.maxWidth);
        final sections = <_Section>[];
        var offset = 0.0;
        void add(
          Object id,
          String title,
          Widget icon,
          List<Widget> cells, {
          bool locked = false,
        }) {
          if (cells.isEmpty) return;
          final collapsed = _collapsed.contains(id);
          final rows = collapsed ? 0 : (cells.length / columns).ceil();
          sections.add(
            _Section(id, title, icon, cells, offset, locked: locked),
          );
          offset += _kHeader + rows * _kCell;
        }

        final usable = _usableCustom;
        final recentPicks = [
          for (final token in recents)
            if (_pickFromRecent(token, usable) case final p?) p,
        ];
        add(
          _Tab.recent,
          'Frequently Used',
          Icon(AppIcons.schedule, size: 16, color: colors.interactive),
          [for (final p in recentPicks) _pickCell(p)],
        );
        for (final set in sets) {
          add(
            set.space.id,
            set.space.name,
            _SpaceGlyph(space: set.space, cdnUrl: _cdnUrl, size: 16),
            [
              for (final e in set.emoji)
                set.locked ? _lockedCell(e) : _customCell(e),
            ],
            locked: set.locked,
          );
        }
        for (final category in EmojiCategory.values) {
          add(
            category,
            category.label,
            Icon(category.icon, size: 16, color: colors.interactive),
            [
              for (final e in kEmojiCatalog)
                if (e.category == category) _unicodeCell(e, tone),
            ],
          );
        }
        _sections = sections;
        // The inspector names the first emoji until something is hovered.
        if (_hovered.value == null) {
          final first =
              recentPicks.firstOrNull ??
              kEmojiCatalog
                  .where((e) => e.category == EmojiCategory.values.first)
                  .map((e) => _unicodePick(e, tone))
                  .firstOrNull;
          if (first != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _hovered.value == null) _hovered.value = first;
            });
          }
        }
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            for (final s in sections) ...[
              SliverPersistentHeader(
                pinned: true,
                delegate: _SectionHeaderDelegate(
                  title: s.title,
                  icon: s.icon,
                  collapsed: _collapsed.contains(s.id),
                  background: _pickerSurface(colors),
                  onToggle: () => setState(() {
                    if (!_collapsed.remove(s.id)) _collapsed.add(s.id);
                  }),
                ),
              ),
              if (!_collapsed.contains(s.id))
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: _kCell,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => s.cells[i],
                      childCount: s.cells.length,
                    ),
                  ),
                ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],
        );
      },
    );
  }

  EmojiPick _unicodePick(EmojiEntry entry, int tone) =>
      EmojiPick(name: entry.name, char: entry.withTone(tone));

  Widget _unicodeCell(EmojiEntry entry, int tone) {
    final pick = _unicodePick(entry, tone);
    return _cell(pick: pick, child: _glyph(pick));
  }

  Widget _customCell(AccordEmoji emoji) {
    final url = _emojiImageUrl(emoji);
    return _pickCell(EmojiPick(name: emoji.name, id: emoji.id, imageUrl: url));
  }

  /// Another space's emoji: visible, dimmed under a lock, not pickable.
  Widget _lockedCell(AccordEmoji emoji) {
    final colors = BonfireThemeExtension.of(context);
    final pick = EmojiPick(
      name: emoji.name,
      id: emoji.id,
      imageUrl: _emojiImageUrl(emoji),
    );
    return Tooltip(
      message: ':${emoji.name}: is from another server',
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => _hovered.value = pick,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(opacity: 0.35, child: _glyph(pick)),
            Icon(AppIcons.lock, size: 16, color: colors.dirtyWhite),
          ],
        ),
      ),
    );
  }

  Widget _pickCell(EmojiPick pick) => _cell(pick: pick, child: _glyph(pick));

  Widget _glyph(EmojiPick pick, {double size = 40}) {
    if (!pick.isCustom) {
      return Text(
        pick.char,
        style: TextStyle(fontSize: size * 0.95, height: 1.1),
      );
    }
    if (pick.imageUrl == null) {
      return Text(':${pick.name}:', style: const TextStyle(fontSize: 9));
    }
    return MessageMediaGate(
      source: pick.imageUrl,
      trustedBaseUrl: _cdnUrl,
      allowExternalConsent: false,
      blockedPlaceholder: Text(
        ':${pick.name}:',
        style: const TextStyle(fontSize: 9),
      ),
      builder: (_, safeUrl) => CachedNetworkImage(
        imageUrl: safeUrl,
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _cell({required EmojiPick pick, required Widget child}) {
    final colors = BonfireThemeExtension.of(context);
    return MouseRegion(
      onEnter: (_) => _hovered.value = pick,
      // The preview bar names the hovered emoji; the tooltip is for screen
      // readers and tests, so it waits long enough not to double up.
      child: Tooltip(
        message: pick.name,
        waitDuration: const Duration(seconds: 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          hoverColor: colors.selection,
          onTap: () => _pick(pick),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// One category block of the continuous grid and where it starts, in
/// scroll offset, for the rail to jump to and to follow.
class _Section {
  const _Section(
    this.id,
    this.title,
    this.icon,
    this.cells,
    this.start, {
    this.locked = false,
  });

  final Object id;
  final String title;
  final Widget icon;
  final List<Widget> cells;
  final double start;
  final bool locked;
}

/// A section's sticky 32 px header: its icon, its name, and a chevron that
/// folds it.
class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _SectionHeaderDelegate({
    required this.title,
    required this.icon,
    required this.collapsed,
    required this.background,
    required this.onToggle,
  });

  final String title;
  final Widget icon;
  final bool collapsed;
  final Color background;
  final VoidCallback onToggle;

  @override
  double get minExtent => _kHeader;
  @override
  double get maxExtent => _kHeader;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colors = BonfireThemeExtension.of(context);
    return ColoredBox(
      color: background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: onToggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 18 / 14,
                      color: colors.dirtyWhite,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  collapsed ? AppIcons.chevronRight : AppIcons.expandMore,
                  size: 12,
                  color: colors.interactive,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SectionHeaderDelegate old) =>
      old.title != title ||
      old.collapsed != collapsed ||
      old.background != background;
}

/// A space's icon (or initial) at [size], for the rail and section headers.
class _SpaceGlyph extends StatelessWidget {
  const _SpaceGlyph({
    required this.space,
    required this.cdnUrl,
    required this.size,
  });

  final AccordSpace space;
  final String? cdnUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final url = accordSpaceIconUrl(space, cdnUrl);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? ColoredBox(
                color: colors.primary,
                child: Center(
                  child: Text(
                    space.name.isEmpty ? '?' : space.name.characters.first,
                    style: TextStyle(
                      fontSize: size * 0.55,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
      ),
    );
  }
}

/// The section selector: Frequently Used, one entry per space with custom
/// emoji, then the unicode categories — a 48 px column on desktop, a strip
/// on touch layouts.
class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.hasRecent,
    required this.spaces,
    required this.cdnUrl,
    required this.selected,
    required this.horizontal,
    required this.onSelect,
  });

  final bool hasRecent;
  final List<(AccordSpace, bool)> spaces;
  final String? cdnUrl;
  final Object? selected;
  final bool horizontal;
  final ValueChanged<Object> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final tabs = <Widget>[
      if (hasRecent)
        _tab(
          colors,
          _Tab.recent,
          'Frequently Used',
          Icon(
            AppIcons.schedule,
            size: 24,
            color: selected == _Tab.recent
                ? colors.dirtyWhite
                : colors.interactive,
          ),
        ),
      for (final (space, locked) in spaces)
        _tab(
          colors,
          space.id,
          space.name,
          Stack(
            clipBehavior: Clip.none,
            children: [
              _SpaceGlyph(space: space, cdnUrl: cdnUrl, size: 28),
              if (locked)
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: _pickerInset(colors),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      AppIcons.lock,
                      size: 10,
                      color: colors.dirtyWhite,
                    ),
                  ),
                ),
            ],
          ),
        ),
      if (spaces.isNotEmpty || hasRecent)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Divider(height: 1, thickness: 1, color: colors.hairline),
        ),
      for (final c in EmojiCategory.values)
        _tab(
          colors,
          c,
          c.label,
          Icon(
            c.icon,
            size: 20,
            color: selected == c ? colors.dirtyWhite : colors.interactive,
          ),
        ),
    ];
    if (horizontal) {
      return SizedBox(
        height: 40,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: HorizontalWheelScroll(
            builder: (context, controller) => ListView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: tabs,
            ),
          ),
        ),
      );
    }
    return Container(
      width: _kRail,
      decoration: BoxDecoration(
        color: _pickerInset(colors),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8)),
      ),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: tabs,
        ),
      ),
    );
  }

  Widget _tab(
    BonfireThemeExtension colors,
    Object value,
    String label,
    Widget glyph,
  ) {
    final active = selected == value;
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 400),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Material(
          color: active ? colors.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => onSelect(value),
            child: SizedBox(width: 36, height: 32, child: Center(child: glyph)),
          ),
        ),
      ),
    );
  }
}

/// The hovered emoji, large, with its `:name:` along the bottom of the panel.
class _PreviewBar extends StatelessWidget {
  const _PreviewBar({required this.hovered});

  final ValueNotifier<EmojiPick?> hovered;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      height: 48,
      color: _pickerInset(colors),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ValueListenableBuilder<EmojiPick?>(
        valueListenable: hovered,
        builder: (context, pick, _) {
          if (pick == null) {
            return Row(
              children: [
                Icon(
                  AppIcons.emojiEmotionsOutlined,
                  size: 28,
                  color: colors.gray,
                ),
                const SizedBox(width: 8),
                Text(
                  'Pick an emoji',
                  style: TextStyle(fontSize: 16, color: colors.gray),
                ),
              ],
            );
          }
          return Row(
            children: [
              if (pick.isCustom && pick.imageUrl != null)
                CachedNetworkImage(
                  imageUrl: pick.imageUrl!,
                  width: 28,
                  height: 28,
                  fit: BoxFit.contain,
                )
              else
                Text(pick.char, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ':${pick.name}:',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.dirtyWhite,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The reaction picker's "Super Reaction" toggle: a sparkle that lights up in
/// the super-reaction accent while on.
class _SuperToggle extends StatelessWidget {
  const _SuperToggle({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final accent = Color.lerp(colors.primary, const Color(0xFFFFC857), 0.5)!;
    return Tooltip(
      message: on ? 'Super Reaction: on' : 'Super Reaction',
      child: Material(
        color: on ? accent.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: const Key('emoji-picker-super'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => onChanged(!on),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              AppIcons.autoAwesome,
              size: 22,
              color: on ? accent : colors.interactive,
            ),
          ),
        ),
      ),
    );
  }
}

/// The skin-tone chooser: a hand in the current tone that opens the six
/// options.
class _SkinToneButton extends StatelessWidget {
  const _SkinToneButton({required this.tone, required this.onChanged});

  final int tone;
  final ValueChanged<int> onChanged;

  static const _hand = EmojiEntry('👏', 'clap', EmojiCategory.people, '', [
    '👏🏻',
    '👏🏼',
    '👏🏽',
    '👏🏾',
    '👏🏿',
  ]);
  static const _labels = [
    'No skin tone',
    'Light skin tone',
    'Medium-light skin tone',
    'Medium skin tone',
    'Medium-dark skin tone',
    'Dark skin tone',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return PopupMenuButton<int>(
      key: const Key('emoji-skin-tone'),
      tooltip: 'Skin tone',
      color: _pickerSurface(colors),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (var t = 0; t <= 5; t++)
          PopupMenuItem<int>(
            value: t,
            height: 36,
            child: Row(
              children: [
                Text(_hand.withTone(t), style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Text(_labels[t]),
                if (t == tone) ...[
                  const Spacer(),
                  Icon(AppIcons.check, size: 16, color: colors.primary),
                ],
              ],
            ),
          ),
      ],
      child: SizedBox(
        width: 38,
        height: 38,
        child: Center(
          child: Text(
            _hand.withTone(tone),
            style: const TextStyle(fontSize: 24),
          ),
        ),
      ),
    );
  }
}
