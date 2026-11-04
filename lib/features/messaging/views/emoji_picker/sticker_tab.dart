part of '../emoji_picker.dart';

/// The Stickers tab: every space's sticker pack — the current space first —
/// in one scrolling grid of 4 columns, a rail of the packs at the left, and
/// the hovered sticker named ("from the pack") along the bottom.
class _StickerTab extends ConsumerStatefulWidget {
  const _StickerTab({required this.spaceId, required this.onPick});

  final String? spaceId;
  final ValueChanged<AccordSticker> onPick;

  @override
  ConsumerState<_StickerTab> createState() => _StickerTabState();
}

class _StickerTabState extends ConsumerState<_StickerTab> {
  String _query = '';
  final _scroll = ScrollController();
  final _hovered = ValueNotifier<(AccordSticker, AccordSpace)?>(null);
  final Map<String, GlobalKey> _sectionKeys = {};

  @override
  void dispose() {
    _scroll.dispose();
    _hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final serverKey = ref.watchActiveServerKey() ?? '';
    final cdnUrl = ref.watchCdnUrl();
    final spaces = [...?ref.watch(spacesControllerProvider)]
      ..sort(
        (a, b) =>
            a.id == widget.spaceId ? -1 : (b.id == widget.spaceId ? 1 : 0),
      );
    final packs = <(AccordSpace, List<AccordSticker>?)>[
      for (final space in spaces)
        (
          space,
          ref.watch(spaceStickersControllerProvider(serverKey, space.id)),
        ),
    ];
    final loading = packs.every((p) => p.$2 == null) && packs.isNotEmpty;
    final shown = [
      for (final (space, stickers) in packs)
        (
          space,
          [
            for (final s in stickers ?? const <AccordSticker>[])
              if (_query.isEmpty || s.name.toLowerCase().contains(_query)) s,
          ],
        ),
    ];
    final current = shown.firstWhereOrNull((p) => p.$1.id == widget.spaceId);
    final nonEmpty = shown.where((p) => p.$2.isNotEmpty).toList();
    final slivers = <Widget>[];
    // The current space's pack shows its empty state, as the reference
    // client's "Your server is waiting for you to upload some stickers!".
    if (current != null && current.$2.isEmpty && _query.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(child: _packHeader(colors, current.$1, cdnUrl)),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _pickerInset(colors),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(AppIcons.sticker, size: 20, color: colors.interactive),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your server is waiting for you to upload some stickers!',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: colors.dirtyWhite,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('sticker-manage'),
                  onPressed: () =>
                      showStickerManagement(context, spaceId: current.$1.id),
                  child: const Text(
                    'Manage Stickers',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF7289F5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    for (final (space, stickers) in nonEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          key: _sectionKeys.putIfAbsent(space.id, GlobalKey.new),
          child: _packHeader(colors, space, cdnUrl),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          sliver: SliverGrid.count(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final sticker in stickers)
                _StickerCell(
                  sticker: sticker,
                  url: stickerUrl(sticker, cdnUrl),
                  onHover: () => _hovered.value = (sticker, space),
                  onTap: () => widget.onPick(sticker),
                ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _PickerSearchField(
            hint: 'Find the perfect sticker',
            autofocus: true,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: _kRail,
                decoration: BoxDecoration(
                  color: _pickerInset(colors),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                  ),
                ),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final (space, _) in shown)
                      Tooltip(
                        message: space.name,
                        child: InkWell(
                          onTap: () {
                            final ctx = _sectionKeys[space.id]?.currentContext;
                            if (ctx != null) {
                              Scrollable.ensureVisible(
                                ctx,
                                duration: const Duration(milliseconds: 180),
                              );
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Center(
                              child: _SpaceGlyph(
                                space: space,
                                cdnUrl: cdnUrl,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: loading
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : slivers.isEmpty
                          ? Center(
                              child: Text(
                                _query.isEmpty
                                    ? 'No stickers yet.'
                                    : 'No sticker matches "$_query"',
                                style: TextStyle(color: colors.gray),
                              ),
                            )
                          : CustomScrollView(
                              controller: _scroll,
                              slivers: [
                                ...slivers,
                                const SliverToBoxAdapter(
                                  child: SizedBox(height: 8),
                                ),
                              ],
                            ),
                    ),
                    if (nonEmpty.isNotEmpty)
                      Container(
                        height: 48,
                        color: _pickerInset(colors),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ValueListenableBuilder(
                          valueListenable: _hovered,
                          builder: (context, hovered, _) {
                            if (hovered == null) return const SizedBox.shrink();
                            final (sticker, space) = hovered;
                            final url = stickerUrl(sticker, cdnUrl);
                            return Row(
                              children: [
                                if (url != null)
                                  CachedNetworkImage(
                                    imageUrl: url,
                                    width: 28,
                                    height: 28,
                                    fit: BoxFit.contain,
                                  ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        sticker.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          height: 1.1,
                                          color: colors.dirtyWhite,
                                        ),
                                      ),
                                      Text(
                                        'from ${space.name}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: colors.interactive,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _packHeader(
    BonfireThemeExtension colors,
    AccordSpace space,
    String? cdnUrl,
  ) {
    return SizedBox(
      height: _kHeader,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
        child: Row(
          children: [
            _SpaceGlyph(space: space, cdnUrl: cdnUrl, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                space.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.dirtyWhite,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(AppIcons.expandMore, size: 12, color: colors.interactive),
          ],
        ),
      ),
    );
  }
}

class _StickerCell extends StatelessWidget {
  const _StickerCell({
    required this.sticker,
    required this.url,
    required this.onHover,
    required this.onTap,
  });

  final AccordSticker sticker;
  final String? url;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Tooltip(
        message: sticker.name,
        waitDuration: const Duration(seconds: 2),
        child: InkWell(
          key: ValueKey('sticker-${sticker.id}'),
          borderRadius: BorderRadius.circular(8),
          hoverColor: colors.selection,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: url == null
                ? Center(child: Text(sticker.name))
                : CachedNetworkImage(
                    imageUrl: url!,
                    fit: BoxFit.contain,
                    errorWidget: (_, _, _) => Center(child: Text(sticker.name)),
                  ),
          ),
        ),
      ),
    );
  }
}
