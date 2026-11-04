part of 'message_pane.dart';

/// The list item's key: the message id, distinct from the row's own
/// `ValueKey(id)` so lookups by that key still find exactly the row.
class MessageRowKey extends LocalKey {
  const MessageRowKey(this.messageId);

  final String messageId;

  @override
  bool operator ==(Object other) =>
      other is MessageRowKey && other.messageId == messageId;

  @override
  int get hashCode => Object.hash(MessageRowKey, messageId);

  @override
  String toString() => '[MessageRowKey $messageId]';
}

/// Which dividers go above a message: a dated line when it starts a new day
/// (or the loaded history), and the red "NEW" line when it is the first
/// message after the read position. Both at once fold into one red, dated
/// line, as in the reference client.
({bool newDay, bool firstUnread, DateTime? day}) messageDividersFor({
  required AccordMessage? previous,
  required AccordMessage message,
  required String? unreadFrom,
}) {
  final day = parseServerTimestamp(message.timestamp)?.toLocal();
  final previousDay = previous == null
      ? null
      : parseServerTimestamp(previous.timestamp)?.toLocal();
  final newDay =
      day != null &&
      (previousDay == null ||
          day.year != previousDay.year ||
          day.month != previousDay.month ||
          day.day != previousDay.day);
  final firstUnread =
      unreadFrom != null &&
      compareMessageIds(message.id, unreadFrom) > 0 &&
      (previous == null || compareMessageIds(previous.id, unreadFrom) <= 0);
  return (newDay: newDay, firstUnread: firstUnread, day: day);
}

/// Wraps [row] with the dividers that go above it (see [messageDividersFor]).
/// The list's keyed element is this wrapper, so the key moves here.
Widget withMessageDividers(
  Widget row, {
  required Key key,
  required AccordMessage? previous,
  required AccordMessage message,
  required String? unreadFrom,
}) {
  final dividers = messageDividersFor(
    previous: previous,
    message: message,
    unreadFrom: unreadFrom,
  );
  if (!dividers.newDay && !dividers.firstUnread) {
    return KeyedSubtree(key: key, child: row);
  }
  return Column(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (dividers.newDay)
        _DayDivider(day: dividers.day!, unread: dividers.firstUnread)
      else
        const _NewMessagesDivider(),
      row,
    ],
  );
}

/// "4 November 2026" — the reference client dates every divider, today
/// included.
String messageDayLabel(DateTime day) => messageDayString(day);

/// The red of the "NEW" line and pill, as the reference client draws it.
const Color _kUnreadRed = Color(0xFFD22D39);

/// A hairline with the date on a pill in the middle, between two days of
/// history. When the first unread message starts the day, the line turns red,
/// the date with it, and the "NEW" pill hangs at its right end.
class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.day, this.unread = false});

  final DateTime day;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final lineColor = unread ? _kUnreadRed : colors.hairline;
    return Padding(
      key: unread ? const Key('new-messages-divider') : null,
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 0),
      child: SizedBox(
        height: 17,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 8,
              height: 1,
              child: ColoredBox(color: lineColor),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                messageDayLabel(day),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 13 / 12,
                  color: unread ? _kUnreadRed : colors.interactive,
                ),
              ),
            ),
            if (unread) const Positioned(right: 0, top: 2, child: _NewPill()),
          ],
        ),
      ),
    );
  }
}

/// The red rule above the first message that arrived since the channel was
/// last read, with the "NEW" pill at its right end.
class _NewMessagesDivider extends StatelessWidget {
  const _NewMessagesDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('new-messages-divider'),
      padding: EdgeInsets.fromLTRB(16, 4, 14, 4),
      child: SizedBox(
        height: 1,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: ColoredBox(color: _kUnreadRed)),
            Positioned(right: 0, top: -6, child: _NewPill()),
          ],
        ),
      ),
    );
  }
}

/// The 27×13 "NEW" tag: a red box with rounded right corners and a pointed
/// left end, white 10 px bold capitals.
class _NewPill extends StatelessWidget {
  const _NewPill();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _NewPillPainter(),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(7, 0, 4, 0),
        child: SizedBox(
          height: 13,
          child: Center(
            child: Text(
              'NEW',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewPillPainter extends CustomPainter {
  const _NewPillPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const r = 4.0;
    final path = Path()
      ..moveTo(0, size.height / 2)
      ..lineTo(4, 0)
      ..lineTo(size.width - r, 0)
      ..arcToPoint(Offset(size.width, r), radius: const Radius.circular(r))
      ..lineTo(size.width, size.height - r)
      ..arcToPoint(
        Offset(size.width - r, size.height),
        radius: const Radius.circular(r),
      )
      ..lineTo(4, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = _kUnreadRed);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
