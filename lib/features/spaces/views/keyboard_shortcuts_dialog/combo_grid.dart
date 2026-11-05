part of '../keyboard_shortcuts_dialog.dart';

/// Key caps and cards sit on white at 8 % over the modal (`#999999` 8 %
/// measured on the reference).
Color _capFill(BonfireThemeExtension colors) =>
    colors.dirtyWhite.withValues(alpha: 0.08);

const TextStyle _capText = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  height: 1,
  color: Colors.white,
);

/// The modal's header: "Keyboard Combos" with its own chord, the subtitle,
/// and four arrow keys at the right.
class _ComboHeader extends StatelessWidget {
  const _ComboHeader({required this.mac});

  final bool mac;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return SizedBox(
      height: 100,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 20, 40, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Keyboard Combos',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w400,
                            height: 34 / 26,
                            color: colors.dirtyWhite,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _KeyCaps([mac ? '⌘' : 'CTRL', '/']),
                    ],
                  ),
                  Text(
                    'Master these to be the greatest Daccord Revolution player',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      height: 20 / 16,
                      color: colors.dirtyWhite,
                    ),
                  ),
                ],
              ),
            ),
            for (final icon in const [
              AppIcons.arrowBack,
              AppIcons.arrowDownward,
              AppIcons.arrowUpward,
              AppIcons.arrowForwardRounded,
            ])
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 8),
                child: Icon(icon, size: 44, color: colors.dirtyWhite),
              ),
          ],
        ),
      ),
    );
  }
}

typedef _CardData = ({String label, List<List<String>> chords});

/// One section: its title, then its cards in a four-column grid; a hairline
/// separates it from the section above.
class _ComboSection extends StatelessWidget {
  const _ComboSection({
    super.key,
    required this.first,
    required this.title,
    required this.cards,
  });

  final bool first;
  final String title;
  final List<_CardData> cards;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!first)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 32, 0, 24),
            child: Container(height: 1, color: colors.hairline),
          ),
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 24 / 20,
            color: colors.dirtyWhite,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) =>
              _ComboGrid(cards: cards, maxWidth: constraints.maxWidth),
        ),
      ],
    );
  }
}

/// Four columns, each as wide as its widest card (at least 180), shrunk
/// evenly when they would overflow — the reference's grid. Each row is as
/// tall as its tallest card; 24 px between cards both ways.
class _ComboGrid extends StatelessWidget {
  const _ComboGrid({required this.cards, required this.maxWidth});

  final List<_CardData> cards;
  final double maxWidth;

  static const int columns = 4;
  static const double gap = 24;
  static const double minColumn = 180;

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      // The app's font, or the columns measure narrower than they paint.
      text: TextSpan(
        text: text,
        style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
            .merge(style),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }

  double _naturalWidth(BuildContext context, _CardData card) {
    var widest = _textWidth(context, card.label, _ComboCard.labelStyle);
    for (final chord in card.chords) {
      var w = 0.0;
      for (final cap in chord) {
        w += _textWidth(context, cap, _capText) + 14;
      }
      w += 4 * (chord.length - 1);
      widest = math.max(widest, w);
    }
    // 24 px of padding, and a little slack so a label measured to the pixel
    // never wraps when painted.
    return (widest + 24 + 8).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final used = math.min(columns, cards.length);
    final available = maxWidth - gap * (used - 1);
    // A window too narrow for four 180 px columns shares what there is.
    final floor = math.min(minColumn, available / used);
    final widths = List<double>.filled(columns, floor);
    for (var i = 0; i < cards.length; i++) {
      final c = i % columns;
      widths[c] = math.max(widths[c], _naturalWidth(context, cards[i]));
    }
    final total = widths.take(used).sum;
    if (total > available) {
      final excess = widths.take(used).map((w) => w - floor).sum;
      final over = total - available;
      for (var c = 0; c < used; c++) {
        final share = excess <= 0 ? 0.0 : (widths[c] - floor) / excess;
        widths[c] = math.max(floor, widths[c] - over * share);
      }
    }
    final rows = <Widget>[];
    for (var start = 0; start < cards.length; start += columns) {
      final row = cards.sublist(start, math.min(start + columns, cards.length));
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: start == 0 ? 0 : gap),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (c, card) in row.indexed) ...[
                  if (c > 0) const SizedBox(width: gap),
                  SizedBox(
                    width: widths[c],
                    child: _ComboCard(card: card),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

/// A card: the action's name, then one line of key caps per chord.
class _ComboCard extends StatelessWidget {
  const _ComboCard({required this.card});

  final _CardData card;

  static const TextStyle labelStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 18 / 14,
  );

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: _capFill(colors),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.label,
            style: labelStyle.copyWith(color: colors.dirtyWhite),
          ),
          const SizedBox(height: 8),
          for (final chord in card.chords)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _KeyCaps(chord),
            ),
        ],
      ),
    );
  }
}

/// A chord as key caps: 23 px tall, 4 px apart.
class _KeyCaps extends StatelessWidget {
  const _KeyCaps(this.caps);

  final List<String> caps;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final cap in caps)
          Container(
            height: 23,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: _capFill(colors),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colors.hairline),
            ),
            // widthFactor 1: a cap is as wide as its label, not the card.
            child: Center(widthFactor: 1, child: Text(cap, style: _capText)),
          ),
      ],
    );
  }
}
