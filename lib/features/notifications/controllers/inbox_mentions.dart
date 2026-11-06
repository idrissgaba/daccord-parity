import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/utils/message_position.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'inbox_mentions.g.dart';

/// How a message reached the user: their own `@name`, one of their roles, or
/// `@everyone` / `@here`. The inbox's Mentions filter hides the last two on
/// request.
enum InboxMentionKind { direct, role, everyone }

/// One message of the inbox's Mentions tab.
class InboxMention {
  const InboxMention({
    required this.message,
    required this.kind,
    required this.receivedAt,
  });

  final AccordMessage message;
  final InboxMentionKind kind;
  final DateTime receivedAt;
}

/// The reference client clears a mention from its inbox after a week.
const Duration kInboxMentionLifetime = Duration(days: 7);

/// Keeps at most this many mentions per connection.
const int kInboxMentionCap = 200;

/// The messages that mentioned the user on one connection, newest first.
///
/// Accord has no "recent mentions" endpoint, so the list is what this client
/// saw: every mention delivered over the gateway while it ran, plus those the
/// inbox finds in unread channels when it opens. Dismissed messages stay
/// dismissed for the session.
@Riverpod(keepAlive: true)
class InboxMentionsController extends _$InboxMentionsController {
  final _dismissed = <String>{};

  @override
  List<InboxMention> build(String serverKey) => const [];

  /// Adds [message] (once), dropping mentions older than a week.
  void record(
    AccordMessage message,
    InboxMentionKind kind, {
    DateTime? now,
  }) {
    if (message.id.isEmpty || _dismissed.contains(message.id)) return;
    if (state.any((m) => m.message.id == message.id)) return;
    final at = now ?? DateTime.now();
    final next = [
      InboxMention(message: message, kind: kind, receivedAt: at),
      ...state.where((m) => at.difference(m.receivedAt) < kInboxMentionLifetime),
    ]..sort((a, b) => compareMessageIds(b.message.id, a.message.id));
    state = next.length > kInboxMentionCap
        ? next.sublist(0, kInboxMentionCap)
        : next;
  }

  /// Removes one mention (its ✓ / ✕).
  void dismiss(String messageId) {
    _dismissed.add(messageId);
    state = [
      for (final m in state)
        if (m.message.id != messageId) m,
    ];
  }

  /// Drops a deleted message.
  void remove(String messageId) {
    if (!state.any((m) => m.message.id == messageId)) return;
    state = [
      for (final m in state)
        if (m.message.id != messageId) m,
    ];
  }
}

/// How [message] mentions [userId], or null when it doesn't.
/// [memberRoles] are the user's roles in the message's space.
InboxMentionKind? inboxMentionKind(
  AccordMessage message, {
  required bool Function(String id) isSelf,
  Iterable<String> memberRoles = const [],
}) {
  if (message.mentions.any(isSelf)) return InboxMentionKind.direct;
  if (message.mentionRoles.any(memberRoles.contains)) {
    return InboxMentionKind.role;
  }
  if (message.mentionEveryone) return InboxMentionKind.everyone;
  return null;
}
