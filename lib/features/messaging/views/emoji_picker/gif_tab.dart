part of '../emoji_picker.dart';

/// The GIF tab. Accord has no GIF provider (the reference client's comes from
/// a proprietary service), so the tab offers the free equivalents: the user's
/// Favourites, "Upload a GIF" from disk, and the GIFs already posted in this
/// channel — each starrable — searchable by file name. Picking one sends its
/// link, which clients render inline.
class _GifTab extends ConsumerStatefulWidget {
  const _GifTab({required this.channelId, required this.onPick});

  final String? channelId;
  final ValueChanged<ExpressionPick> onPick;

  @override
  ConsumerState<_GifTab> createState() => _GifTabState();
}

class _GifTabState extends ConsumerState<_GifTab> {
  String _query = '';
  bool _favourites = false;

  /// The GIFs posted in the channel's loaded history, newest first.
  List<String> _channelGifs() {
    final channelId = widget.channelId;
    if (channelId == null) return const [];
    final messages =
        ref.watch(
          accordMessagesControllerProvider(
            ref.readActiveServerKey() ?? '',
            channelId,
          ),
        ) ??
        const <AccordMessage>[];
    final cdnUrl = ref.watchCdnUrl();
    final out = <String>[];
    for (final m in messages.reversed) {
      for (final a in m.attachments) {
        final isGif =
            a.contentType == 'image/gif' ||
            a.filename.toLowerCase().endsWith('.gif');
        if (!isGif || a.encryption != null) continue;
        final url = AccordCDN.resolvePath(a.url, cdnUrl: cdnUrl ?? '');
        if (!out.contains(url)) out.add(url);
      }
      final lone = loneGifUrl(m.content);
      if (lone != null && !out.contains(lone)) out.add(lone);
    }
    return out;
  }

  bool _matches(String url) =>
      _query.isEmpty || Uri.decodeComponent(url).toLowerCase().contains(_query);

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final favourites = ref.watch(
      settingsControllerProvider.select((s) => s.favoriteGifs),
    );
    final posted = _channelGifs();
    final shown = [
      for (final url in _favourites ? favourites : posted)
        if (_matches(url)) url,
    ];
    final tiles = <Widget>[
      if (!_favourites && _query.isEmpty) ...[
        _GifCategoryTile(
          key: const Key('gif-favourites'),
          label: 'Favourites',
          icon: AppIcons.star,
          color: colors.primary,
          onTap: () => setState(() => _favourites = true),
        ),
        _GifCategoryTile(
          key: const Key('gif-upload'),
          label: 'Upload a GIF',
          icon: AppIcons.upload,
          color: colors.selection.withValues(alpha: 0.24),
          onTap: () => widget.onPick(const ExpressionPick.uploadGif()),
        ),
      ],
      for (final url in shown)
        _GifTile(
          url: url,
          favourite: favourites.contains(url),
          onTap: () => widget.onPick(ExpressionPick.gif(url)),
          onToggleFavourite: () => ref
              .read(settingsControllerProvider.notifier)
              .toggleFavoriteGif(url),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _PickerSearchField(
            hint: _favourites ? 'Search Favourites' : 'Search GIFs',
            autofocus: true,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        if (_favourites)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _favourites = false),
                  icon: Icon(
                    AppIcons.arrowBack,
                    size: 18,
                    color: colors.interactive,
                  ),
                ),
                Text(
                  'Favourites',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.dirtyWhite,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: tiles.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _favourites
                          ? 'Star a GIF to keep it here.'
                          : 'No GIFs in this channel yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.gray),
                    ),
                  ),
                )
              : GridView.count(
                  crossAxisCount: 2,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 230 / 110,
                  children: tiles,
                ),
        ),
      ],
    );
  }
}

/// A 230×110 category tile: a solid colour with its label (and icon) in the
/// middle, as the reference client's Favourites / Trending tiles.
class _GifCategoryTile extends StatelessWidget {
  const _GifCategoryTile({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One GIF of the grid, with the favourite star at its top right on hover.
class _GifTile extends StatefulWidget {
  const _GifTile({
    required this.url,
    required this.favourite,
    required this.onTap,
    required this.onToggleFavourite,
  });

  final String url;
  final bool favourite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavourite;

  @override
  State<_GifTile> createState() => _GifTileState();
}

class _GifTileState extends State<_GifTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: colors.background,
        borderRadius: BorderRadius.circular(4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: widget.url,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) =>
                    Icon(AppIcons.brokenImageOutlined, color: colors.gray),
              ),
              if (_hover || widget.favourite)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Tooltip(
                    message: widget.favourite
                        ? 'Remove from Favourites'
                        : 'Add to Favourites',
                    child: InkWell(
                      onTap: widget.onToggleFavourite,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          AppIcons.star,
                          size: 18,
                          color: widget.favourite
                              ? const Color(0xFFF0B232)
                              : Colors.white,
                        ),
                      ),
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

/// The URL when [content] is nothing but a link to a `.gif` — a GIF picked
/// in the composer — so the message can show the image alone, as the
/// reference client does.
String? loneGifUrl(String content) {
  final text = content.trim();
  if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
    return null;
  }
  return uri.path.toLowerCase().endsWith('.gif') ? text : null;
}
