import 'dart:math' as math;

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/utils/space_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'quick_switcher/switcher_view.dart';

/// What a quick-switcher row leads to.
enum QuickSwitchKind { textChannel, voiceChannel, space, dm, user }

/// One row of the quick switcher: a channel, a server, a DM conversation or
/// a user, on the connection [serverKey].
@immutable
class QuickSwitchItem {
  const QuickSwitchItem({
    required this.kind,
    required this.serverKey,
    required this.id,
    required this.name,
    this.secondary,
    this.category,
    this.spaceId,
    this.spaceName,
    this.imageUrl,
    this.channel,
    this.user,
    this.unread = false,
  });

  final QuickSwitchKind kind;
  final String serverKey;

  /// The channel id (channels and DMs), the space id or the user id.
  final String id;
  final String name;

  /// A user's username, shown after the name.
  final String? secondary;

  /// The small label after the name: a channel's category, or "Server".
  final String? category;

  /// The space a channel belongs to (and the space itself for servers).
  final String? spaceId;

  /// The server name at the row's right edge.
  final String? spaceName;

  /// A server icon or an avatar.
  final String? imageUrl;

  /// The DM conversation, for [QuickSwitchKind.dm].
  final AccordChannel? channel;

  /// The user (users and 1:1 DMs).
  final AccordUser? user;

  /// Unread channels and servers are drawn in the bright text colour.
  final bool unread;

  /// Identity across connections, shared with [QuickSwitcherHistory].
  String get key => quickSwitchKey(kind, serverKey, id);
}

/// The identity of a switcher target.
String quickSwitchKey(QuickSwitchKind kind, String serverKey, String id) {
  // A DM and its 1:1 user are one place to the history, as channels are.
  final family = switch (kind) {
    QuickSwitchKind.textChannel ||
    QuickSwitchKind.voiceChannel ||
    QuickSwitchKind.dm => 'channel',
    QuickSwitchKind.space => 'space',
    QuickSwitchKind.user => 'user',
  };
  return '$family $serverKey $id';
}

/// What a switcher query searches and the header shown above its results.
@immutable
class QuickSwitchResult {
  const QuickSwitchResult(this.header, this.items);

  /// "Previous Channels", "Searching All Users", … or null for a plain query.
  final String? header;
  final List<QuickSwitchItem> items;
}

/// The search prefixes of the Protip line, and what each narrows to. The
/// reference's `$` (game profiles) has no equivalent here.
const Map<String, ({String header, Set<QuickSwitchKind> kinds})>
quickSwitchPrefixes = {
  '@': (
    header: 'Searching All Users',
    kinds: {QuickSwitchKind.user, QuickSwitchKind.dm},
  ),
  '#': (
    header: 'Searching Text Channels',
    kinds: {QuickSwitchKind.textChannel},
  ),
  '!': (
    header: 'Searching Voice Channels',
    kinds: {QuickSwitchKind.voiceChannel},
  ),
  '*': (header: 'Searching Servers', kinds: {QuickSwitchKind.space}),
};

const String _kPreviousChannels = 'Previous Channels';

/// Plain queries list channels, then servers, then people.
int _kindOrder(QuickSwitchKind kind) => switch (kind) {
  QuickSwitchKind.textChannel || QuickSwitchKind.voiceChannel => 0,
  QuickSwitchKind.space => 1,
  QuickSwitchKind.dm || QuickSwitchKind.user => 2,
};

/// [text] lower-cased with common Latin accents folded ("général" matches
/// "gen").
String foldForSearch(String text) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    out.write(i < 0 ? ch : to[i]);
  }
  return out.toString();
}

/// How well [query] matches [text]: 0 prefix, 1 word prefix, 2 substring,
/// 3 the query's letters in order, or null for no match.
int? quickSwitchRank(String text, String query) {
  final t = foldForSearch(text);
  final q = foldForSearch(query);
  if (q.isEmpty) return 0;
  if (t.startsWith(q)) return 0;
  final words = t.split(RegExp(r'[\s\-_.]+'));
  if (words.any((w) => w.startsWith(q))) return 1;
  if (t.contains(q)) return 2;
  var i = 0;
  for (final rune in t.runes) {
    if (i < q.length && q.codeUnitAt(i) == rune) i++;
  }
  return i == q.length ? 3 : null;
}

/// The rows for [raw] (what was typed) among [items]. An empty query shows
/// [recent] as "Previous Channels"; a leading `@ # ! *` narrows to users,
/// text channels, voice channels or servers ("@" alone lists nobody, as the
/// reference); otherwise channels come first, then servers, then people,
/// each ranked by [quickSwitchRank].
QuickSwitchResult filterQuickSwitch(
  List<QuickSwitchItem> items,
  String raw, {
  List<QuickSwitchItem> recent = const [],
  int limit = 50,
}) {
  final typed = raw.trimLeft();
  if (typed.isEmpty) {
    return QuickSwitchResult(
      recent.isEmpty ? null : _kPreviousChannels,
      recent.take(limit).toList(),
    );
  }
  final prefix = quickSwitchPrefixes[typed[0]];
  final query = (prefix == null ? typed : typed.substring(1)).trim();
  if (prefix != null && query.isEmpty) {
    if (typed[0] == '@') return QuickSwitchResult(prefix.header, const []);
    return QuickSwitchResult(
      prefix.header,
      [
        for (final item in items)
          if (prefix.kinds.contains(item.kind)) item,
      ].take(limit).toList(),
    );
  }
  final ranked = <(int, int, int, QuickSwitchItem)>[];
  for (final (index, item) in items.indexed) {
    if (prefix != null && !prefix.kinds.contains(item.kind)) continue;
    var rank = quickSwitchRank(item.name, query);
    final secondary = item.secondary;
    if (secondary != null) {
      final r = quickSwitchRank(secondary, query);
      if (r != null && (rank == null || r < rank)) rank = r;
    }
    if (rank == null) continue;
    ranked.add((prefix == null ? _kindOrder(item.kind) : 0, rank, index, item));
  }
  ranked.sort((a, b) {
    final byKind = a.$1.compareTo(b.$1);
    if (byKind != 0) return byKind;
    final byRank = a.$2.compareTo(b.$2);
    return byRank != 0 ? byRank : a.$3.compareTo(b.$3);
  });
  return QuickSwitchResult(
    prefix?.header,
    [for (final r in ranked) r.$4].take(limit).toList(),
  );
}

/// The places visited most recently, newest first — the switcher's "Previous
/// Channels". Fed by navigation (open tabs, the DM home) and by the
/// switcher's own picks; kept for the session.
class QuickSwitcherHistory {
  QuickSwitcherHistory._();

  static const int capacity = 10;
  static final List<String> _keys = [];

  static List<String> get keys => List.unmodifiable(_keys);

  /// Records a visit to the place [key] (see [quickSwitchKey]).
  static void visit(String key) {
    _keys
      ..remove(key)
      ..insert(0, key);
    if (_keys.length > capacity) _keys.removeRange(capacity, _keys.length);
  }

  @visibleForTesting
  static void clear() => _keys.clear();
}

/// Opens the switcher from places that cannot reach the home screen's
/// navigation (the DM home's "Find or start a conversation"): the home
/// screen registers how it opens the switcher and handles the pick.
class QuickSwitcherLauncher {
  QuickSwitcherLauncher._();

  static Future<void> Function()? _open;

  static void register(Future<void> Function() open) => _open = open;

  static void unregister(Future<void> Function() open) {
    if (_open == open) _open = null;
  }

  /// Opens the switcher; false when no home screen is mounted.
  static Future<bool> open() async {
    final open = _open;
    if (open == null) return false;
    await open();
    return true;
  }
}

/// The Ctrl+K dialog — "Search for servers, channels or DMs": type to find a
/// channel, server, conversation or person on any connection; ↑/↓ to move,
/// Enter to jump. Resolves to the pick, or null when dismissed. [current]
/// (the place on screen) is left out of "Previous Channels".
Future<QuickSwitchItem?> showQuickSwitcher(
  BuildContext context, {
  String? current,
}) {
  return showGeneralDialog<QuickSwitchItem>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close the quick switcher',
    barrierColor: _kSwitcherScrim,
    transitionDuration: const Duration(milliseconds: 100),
    pageBuilder: (_, _, _) => _QuickSwitcherDialog(current: current),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// The scrim behind the switcher (black at 72 %, as the reference's modals).
const Color _kSwitcherScrim = Color(0xB8000000);

/// Everything the switcher can reach, gathered from the loaded caches of
/// every connection (spaces, their channels, DMs, friends and members).
/// Nothing is fetched here except through providers the active connection
/// already builds.
List<QuickSwitchItem> gatherQuickSwitchItems(
  WidgetRef ref, {
  List<AccordRelationship> friends = const [],
}) {
  final connections = ref.watch(connectionsControllerProvider);
  final liveSpaces = ref.watch(spacesControllerProvider);
  final channels = <QuickSwitchItem>[];
  final spaces = <QuickSwitchItem>[];
  final people = <QuickSwitchItem>[];
  final seenUsers = <String>{};

  for (final conn in connections.connections) {
    final key = conn.key;
    final active = key == connections.activeKey;
    final cdn = conn.session.server.cdnUrl;
    final selfId = conn.session.userId;
    final readState = ref.watch(readStateControllerProvider(key));
    final connSpaces = active ? (liveSpaces ?? conn.spaces) : conn.spaces;
    for (final space in connSpaces) {
      final provider = accordChannelsControllerProvider(key, space.id);
      final list = active || ref.exists(provider)
          ? (ref.watch(provider) ?? const <AccordChannel>[])
          : const <AccordChannel>[];
      final categories = {
        for (final c in list)
          if (c.type == 'category') c.id: c.name ?? '',
      };
      var spaceUnread = false;
      for (final channel in list) {
        if (channel.type == 'category') continue;
        final voice = channel.type == 'voice' || channel.type == 'stage';
        final unread = readState.isUnread(channel.id);
        spaceUnread |= unread;
        channels.add(
          QuickSwitchItem(
            kind: voice
                ? QuickSwitchKind.voiceChannel
                : QuickSwitchKind.textChannel,
            serverKey: key,
            id: channel.id,
            name: channel.name ?? channel.id,
            category: voice ? null : categories[channel.parentId],
            spaceId: space.id,
            spaceName: space.name,
            channel: channel,
            unread: unread,
          ),
        );
      }
      spaces.add(
        QuickSwitchItem(
          kind: QuickSwitchKind.space,
          serverKey: key,
          id: space.id,
          name: space.name,
          category: 'Server',
          spaceId: space.id,
          imageUrl: accordSpaceIconUrl(space, cdn),
          unread: spaceUnread,
        ),
      );
    }

    final users = ref.watch(accordUsersControllerProvider(key));
    final dmProvider = dmChannelsControllerProvider(key);
    final dms = active || ref.exists(dmProvider)
        ? (ref.watch(dmProvider) ?? const <AccordChannel>[])
        : const <AccordChannel>[];
    for (final dm in dms) {
      final others = (dm.recipients ?? const <AccordUser>[])
          .where((u) => u.id != selfId)
          .toList();
      final one = dm.type == 'dm' && others.length == 1
          ? (users[others.first.id] ?? others.first)
          : null;
      if (one != null) seenUsers.add('$key ${one.id}');
      people.add(
        QuickSwitchItem(
          kind: QuickSwitchKind.dm,
          serverKey: key,
          id: dm.id,
          name: dmChannelTitle(
            dm,
            selfId,
            fallback: 'Conversation',
            users: users,
          ),
          secondary: one?.username,
          imageUrl: one == null ? null : accordAvatarUrl(one, cdn),
          channel: dm,
          user: one,
          unread: readState.isUnread(dm.id),
        ),
      );
    }

    void addUser(AccordUser user, {String? avatarUrl}) {
      if (user.id == selfId || !seenUsers.add('$key ${user.id}')) return;
      people.add(
        QuickSwitchItem(
          kind: QuickSwitchKind.user,
          serverKey: key,
          id: user.id,
          name: accordUserName(user, fallback: user.id),
          secondary: user.username,
          imageUrl: avatarUrl ?? accordAvatarUrl(user, cdn),
          user: user,
        ),
      );
    }

    if (active) {
      for (final relationship in friends) {
        if (relationship.type == 1 && relationship.user != null) {
          addUser(users[relationship.user!.id] ?? relationship.user!);
        }
      }
    }
    for (final space in connSpaces) {
      final provider = accordMembersControllerProvider(key, space.id);
      if (!ref.exists(provider)) continue;
      for (final member in (ref.watch(provider) ?? const {}).values) {
        final user = member.user;
        if (user == null) continue;
        addUser(user, avatarUrl: accordMemberAvatarUrl(member, cdn));
      }
    }
  }
  return [...channels, ...spaces, ...people];
}

/// [QuickSwitcherHistory] resolved against [items], minus [current].
List<QuickSwitchItem> recentQuickSwitchItems(
  List<QuickSwitchItem> items, {
  String? current,
}) {
  final byKey = <String, QuickSwitchItem>{};
  for (final item in items) {
    byKey.putIfAbsent(item.key, () => item);
  }
  return [
    for (final key in QuickSwitcherHistory.keys)
      if (key != current)
        if (byKey[key] case final item?) item,
  ];
}

/// The widest the switcher's box grows (it shrinks on narrow windows).
const double kQuickSwitcherWidth = 680;
const double kQuickSwitcherHeight = 398;

double _boxWidth(Size screen) =>
    math.min(kQuickSwitcherWidth, screen.width - 32);
