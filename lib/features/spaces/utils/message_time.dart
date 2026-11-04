import 'package:bonfire/shared/utils/server_timestamp.dart';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Bare `HH:MM` string for a local [DateTime].
String messageClockString(DateTime local) {
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// Date-aware label for a message timestamp shown in the message header.
///
/// | Age      | Result                  |
/// |----------|-------------------------|
/// | Today    | `18:43`                 |
/// | Yesterday| `Yesterday at 18:43`    |
/// | Older    | `12/06/2026, 18:43`     |
///
/// The three forms of the reference client's message header: only today and
/// yesterday are named, everything else carries its calendar date. [now] is
/// injected for testability; callers omit it and the current wall-clock time
/// is used.
String messageTimeString(DateTime local, {DateTime? now}) {
  final clock = messageClockString(local);
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  final thatDay = DateTime(local.year, local.month, local.day);
  // Compare calendar dates in UTC so a 23- or 25-hour daylight-saving day is
  // still exactly one day apart for display purposes.
  final daysAgo = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(thatDay.year, thatDay.month, thatDay.day)).inDays;

  if (daysAgo <= 0) return clock;
  if (daysAgo == 1) return 'Yesterday at $clock';

  final dd = local.day.toString().padLeft(2, '0');
  final mo = local.month.toString().padLeft(2, '0');
  return '$dd/$mo/${local.year}, $clock';
}

/// The day-divider label between two days of history: `4 November 2026`.
/// Never "Today" or "Yesterday" — the reference client dates every divider.
String messageDayString(DateTime local) =>
    '${local.day} ${_months[local.month - 1]} ${local.year}';

/// Compact label for a conversation-list row (the DM list's last activity).
///
/// | Age      | Result       |
/// |----------|--------------|
/// | Today    | `18:43`      |
/// | Yesterday| `Yesterday`  |
/// | 2–6 days | `Mon`        |
/// | Older    | `12/06/2026` |
///
/// Shorter than [messageTimeString] so it fits beside a truncated title.
String conversationTimeString(DateTime local, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  final thatDay = DateTime(local.year, local.month, local.day);
  final daysAgo = today.difference(thatDay).inDays;

  if (daysAgo <= 0) return messageClockString(local);
  if (daysAgo == 1) return 'Yesterday';
  if (daysAgo <= 6) return _weekdays[local.weekday - 1].substring(0, 3);

  final dd = local.day.toString().padLeft(2, '0');
  final mo = local.month.toString().padLeft(2, '0');
  return '$dd/$mo/${local.year}';
}

/// [messageTimeString] for a raw ISO-8601 [iso] timestamp (the form carried on
/// `AccordMessage.timestamp`), converted to local time. Empty when [iso]
/// doesn't parse.
String messageTimeFromIso(String iso, {DateTime? now}) {
  final dt = parseServerTimestamp(iso);
  if (dt == null) return '';
  return messageTimeString(dt.toLocal(), now: now);
}

/// [messageClockString] for a raw ISO-8601 [iso] timestamp, converted to local
/// time. Empty when [iso] doesn't parse.
String messageClockFromIso(String iso) {
  final dt = parseServerTimestamp(iso);
  if (dt == null) return '';
  return messageClockString(dt.toLocal());
}

/// Full, unabbreviated timestamp for tooltips, e.g.
/// `Monday, 5 June 2026 at 14:30`. `intl` isn't a dependency, so the weekday and
/// month names are spelled out by hand here rather than re-inlined per caller.
String messageTimestampString(DateTime local) {
  final weekday = _weekdays[local.weekday - 1];
  final month = _months[local.month - 1];
  return '$weekday, ${local.day} $month ${local.year} at '
      '${messageClockString(local)}';
}

/// [messageTimestampString] for a raw ISO-8601 [iso] timestamp, converted to
/// local time. Empty when [iso] doesn't parse.
String messageTimestampFromIso(String iso) {
  final dt = parseServerTimestamp(iso);
  if (dt == null) return '';
  return messageTimestampString(dt.toLocal());
}
