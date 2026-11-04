// A throwaway entry point for the Discord-parity capture loop: it boots the
// real app against an offline fixture (the store-capture space, with a
// `#general` built to show every message shape lot B covers — markdown,
// replies, reactions, a pin, a file, a mention, unread history, someone
// typing — and one direct message), so the screens can be photographed at
// 1920×927 and compared with the reference captures without posting anything
// to a live server.
//
// Build: `flutter build web -t tool/parity_capture/parity_app.dart
// --no-tree-shake-icons -o build/parity`, serve `build/parity`, open
// `/?scene=messages` or `/?scene=dm`. Nothing here is shipped.

import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/utils/hive.dart';
import 'package:bonfire/features/channels/controllers/open_tabs.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/channels/models/open_tab.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/messaging/controllers/typing.dart';
import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/accord_home.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/shared/components/app_shell.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../store_capture/seeded_space.dart';

const _dmChannelId = 'dm-hana';

Map<String, dynamic> _msg(
  String id,
  String author,
  String at,
  String content, {
  String? replyTo,
  String type = 'default',
  List<String> mentions = const [],
  List<(String, int, bool)> reactions = const [],
  List<Map<String, dynamic>> attachments = const [],
  String? editedAt,
  String channelId = seedGeneralChannelId,
}) => {
  'id': id,
  'channel_id': channelId,
  'author_id': author,
  'content': content,
  'type': type,
  'timestamp': at,
  if (editedAt != null) 'edited_at': editedAt,
  if (replyTo != null) 'reply_to': replyTo,
  if (mentions.isNotEmpty) 'mentions': mentions,
  if (attachments.isNotEmpty) 'attachments': attachments,
  if (reactions.isNotEmpty)
    'reactions': [
      for (final (emoji, count, me) in reactions)
        {
          'emoji': {'id': null, 'name': emoji},
          'count': count,
          'me': me,
        },
    ],
};

/// `#general` for lot B, oldest first (reversed for the API below).
final List<Map<String, dynamic>> _general = [
  _msg(
    '101',
    'u-hana',
    '2026-11-03T20:40:00Z',
    'hello one',
    reactions: [('👍', 2, true), ('😂', 1, false)],
  ),
  _msg(
    '102',
    'u-hana',
    '2026-11-03T20:42:00Z',
    'second message in the same group',
  ),
  _msg(
    '103',
    seedSelfId,
    '2026-11-04T09:10:00Z',
    '**bold** *italic* ~~strike~~ __underline__ ||spoiler|| `inline code` '
        '[masked link](https://example.com) https://example.org\n'
        '# Heading 1\n## Heading 2\n### Heading 3\n-# subtext line\n'
        '- item one\n- item two\n1. first\n2. second\n'
        '> quote line\n>>> block quote\nsecond quoted line',
    editedAt: '2026-11-04T09:12:00Z',
  ),
  _msg(
    '104',
    seedSelfId,
    '2026-11-04T09:11:00Z',
    'code block:\n```js\nconst x = 1;\nconsole.log(x);\n```',
  ),
  _msg(
    '105',
    'u-june',
    '2026-11-04T09:20:00Z',
    'mention @mira and channel #general at <t:1700000000:R> or <t:1700000000:F>',
    mentions: [seedSelfId],
  ),
  _msg(
    '106',
    seedSelfId,
    '2026-11-04T09:25:00Z',
    'a reply with preview',
    replyTo: '101',
  ),
  _msg(
    '107',
    seedSelfId,
    '2026-11-04T09:26:00Z',
    '',
    type: 'pin',
    replyTo: '106',
  ),
  _msg(
    '108',
    'u-omar',
    '2026-11-04T09:30:00Z',
    'attachments test',
    attachments: [
      {
        'id': 'a1',
        'filename': 'archive-parity.zip',
        'size': 5000,
        'content_type': 'application/zip',
        'url': '/attachments/c-general/a1/archive-parity.zip',
      },
    ],
  ),
  _msg(
    '109',
    'u-hana',
    '2026-11-04T09:40:00Z',
    'new message after the read line',
  ),
  _msg('110', 'u-hana', '2026-11-04T09:41:00Z', 'and another one'),
];

final List<Map<String, dynamic>> _dmMessages = [
  _msg(
    'd1',
    'u-hana',
    '2026-11-03T18:20:00Z',
    'are you coming to open night?',
    channelId: _dmChannelId,
  ),
  _msg(
    'd2',
    seedSelfId,
    '2026-11-03T18:21:00Z',
    'yes, bringing the rover',
    channelId: _dmChannelId,
  ),
];

final Map<String, dynamic> _dm = {
  'id': _dmChannelId,
  'type': 'dm',
  'recipients': [
    {
      'id': 'u-hana',
      'username': 'hana',
      'display_name': 'Hana',
      'created_at': '2025-03-14T10:00:00Z',
    },
    {'id': seedSelfId, 'username': seedSelfName},
  ],
};

MockClient _transport() {
  final seeded = buildSeededTransport();
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' &&
        path.endsWith('/channels/$seedGeneralChannelId/messages')) {
      return _json(_general.reversed.toList());
    }
    if (request.method == 'GET' &&
        path.endsWith('/channels/$_dmChannelId/messages')) {
      return _json(_dmMessages.reversed.toList());
    }
    if (path.endsWith('/users/@me/channels')) return _json([_dm]);
    if (path.endsWith('/users/@me/relationships')) {
      return _json([
        {
          'id': 'u-hana',
          'type': 1,
          'user': {'id': 'u-hana', 'username': 'hana', 'display_name': 'Hana'},
        },
        {
          'id': 'u-june',
          'type': 1,
          'user': {'id': 'u-june', 'username': 'june', 'display_name': 'June'},
        },
      ]);
    }
    // A handled request is finalized; the seeded client needs its own copy.
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = request.bodyBytes;
    return seeded.send(copy).then(http.Response.fromStream);
  });
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupHive();
  await ProfileStore.settingsBox.put(
    'settings',
    const AccordSettings().toJson(),
  );
  await ProfileStore.settingsBox.delete('open-tabs');
  final scene = Uri.base.queryParameters['scene'] ?? 'messages';
  final server = AccordServer.fromBaseUrl('https://vale.example');
  final client = AccordClient(
    token: 'parity-token',
    tokenType: 'Bearer',
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
    httpClient: _transport(),
  );
  final session = AccordSession(
    server: server,
    token: 'parity-token',
    userId: seedSelfId,
    username: seedSelfName,
  );
  final container = ProviderContainer(
    overrides: [
      accordAuthProvider.overrideWithValue(
        AccordAuthLoggedIn(client: client, session: session),
      ),
    ],
  );
  final key = session.key;
  final spaces = [for (final s in seedSpaces) AccordSpace.fromJson(s)];
  container.read(connectionsControllerProvider.notifier)
    ..register(session, status: ConnectionStatus.connected)
    ..setSpaces(key, spaces, authoritative: true)
    ..setActive(key);
  container.read(spacesControllerProvider.notifier).setSpaces(spaces);
  container.read(presenceControllerProvider(key).notifier).seed([
    for (final m in seedValeMembers)
      if (m.status != 'offline') AccordPresence(userId: m.id, status: m.status),
  ]);
  container.read(readStateControllerProvider(key).notifier).hydrate(const [
    ReadEntry(
      channelId: seedGeneralChannelId,
      spaceId: seedSpaceId,
      lastMessageId: '110',
      lastReadMessageId: '108',
    ),
  ]);
  // Opening the channel acknowledges it; the cursor it leaves behind is what
  // draws the NEW line and the unread bar.
  container
      .read(readStateControllerProvider(key).notifier)
      .markRead(seedGeneralChannelId, messageId: '110');
  container
      .read(openTabsControllerProvider.notifier)
      .open(
        OpenTab(
          channelId: seedGeneralChannelId,
          spaceId: seedSpaceId,
          serverKey: key,
          name: 'general',
        ),
      );
  if (Uri.base.queryParameters['typing'] == '1') {
    Future<void>.delayed(const Duration(seconds: 2), () {
      container
          .read(typingControllerProvider(key, seedGeneralChannelId).notifier)
          .userTyping('u-june');
    });
  }
  if (scene == 'dm' || scene == 'friends') {
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      dmHome.open(scene == 'dm' ? AccordChannel.fromJson(_dm) : null);
    });
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(AppThemePreset.dark),
        builder: (context, child) =>
            buildAppShell(context, child, uiScale: 1, reducedMotion: false),
        home: Builder(
          builder: (context) => Scaffold(
            backgroundColor: BonfireThemeExtension.of(context).background,
            body: const AccordHomeScreen(),
          ),
        ),
      ),
    ),
  );
}
