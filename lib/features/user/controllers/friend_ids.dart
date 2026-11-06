import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'friend_ids.g.dart';

/// Relationship types, mirrored from the server.
const int accordFriendRelationship = 1;
const int accordPendingIncomingRelationship = 3;

/// What the rest of the app needs from one connection's relationship list.
class FriendsSummary {
  const FriendsSummary({
    this.friendIds = const <String>{},
    this.pendingIncoming = 0,
  });

  /// The user ids of this connection's friends, for the "Notify me when…"
  /// notifications (a friend comes online, starts streaming).
  final Set<String> friendIds;

  /// Friend requests waiting for an answer: the Home button's badge and the
  /// inbox's "View Friend Requests".
  final int pendingIncoming;

  bool sameAs(FriendsSummary other) =>
      other.pendingIncoming == pendingIncoming &&
      other.friendIds.length == friendIds.length &&
      other.friendIds.every(friendIds.contains);
}

/// One connection's [FriendsSummary].
///
/// Filled from the same relationship list as `BlockedUsersController` (READY,
/// every relationship event, the Friends page).
@Riverpod(keepAlive: true)
class FriendIdsController extends _$FriendIdsController {
  @override
  FriendsSummary build(String serverKey) => const FriendsSummary();

  void set(FriendsSummary summary) {
    if (summary.sameAs(state)) return;
    state = summary;
  }
}
