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
// `/?scene=messages`, `/?scene=dm` or `/?scene=friends`; add
// `&preview=r-everyone` to see the menus of a plain member, `&open=shortcuts`
// or `&open=switcher` for Ctrl+/ and Ctrl+K. Lot E: `/?scene=voice` sits in
// the `Workbench` voice channel with `#general` open, `/?scene=call` shows its
// call view; the space has soundboard sounds (and the second space a few,
// which show locked), `&crowd=1` seats three more people in the call and
// `&play=<user id>` makes that person play a sound (the emoji rising over
// their tile), held for a minute; `&sounds=0` empties the space's soundboard.
// Lot G: `&open=settings&page=voiceVideo` (any `SettingsPage` name) opens the
// user settings modal on that page; `&open=space-settings&page=roles` (any
// `SpaceSettingsPages` key) the server settings, whose lists start empty;
// `&open=profile` the Edit Profile modal, `&open=channel-settings` Edit
// Channel on #general.
// Lot H: `/?scene=unread` leaves #introductions, #show-and-tell (a mention),
// #build-log (two) and Tidepool's #lobby unread, mutes #off-topic (unread,
// one mention), and leaves Hana's DM unread (a rail tile); `&open=inbox`
// opens the inbox (`&tab=mentions` its Mentions tab), whose Mentions list is
// seeded with three messages.
// Nothing here is shipped.

import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/utils/hive.dart';
import 'package:bonfire/features/channels/controllers/open_tabs.dart';
import 'package:bonfire/features/channels/controllers/muted_channels.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/channels/models/open_tab.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/messaging/controllers/typing.dart';
import 'package:bonfire/features/notifications/controllers/inbox_mentions.dart';
import 'package:bonfire/features/notifications/views/inbox_popover.dart';
import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/settings/views/accord_settings_screen.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/channels/views/channel_management.dart';
import 'package:bonfire/features/user/views/accord_profile_edit.dart';
import 'package:bonfire/features/soundboard/controllers/soundboard_activity.dart';
import 'package:bonfire/features/soundboard/controllers/soundboard_sounds.dart';
import 'package:bonfire/features/spaces/controllers/role_preview.dart';
import 'package:bonfire/features/spaces/views/accord_space_settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/accord_home.dart';
import 'package:bonfire/features/spaces/views/keyboard_shortcuts_dialog.dart';
import 'package:bonfire/features/spaces/views/quick_switcher.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/services/voice_session.dart';
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

/// Lot H: what follows the read line in the unread channels.
final Map<String, List<Map<String, dynamic>>> _unreadMessages = {
  'c-introductions': [
    _msg(
      'i1',
      'u-hana',
      '2026-11-05T18:02:00Z',
      'hi all, Hana here, I build little robots',
      channelId: 'c-introductions',
    ),
    _msg(
      'i2',
      'u-hana',
      '2026-11-05T18:03:00Z',
      'mostly from old printer parts',
      channelId: 'c-introductions',
    ),
  ],
  'c-show-and-tell': [
    _msg(
      's1',
      'u-june',
      '2026-11-06T09:12:00Z',
      'finished the walnut lamp, @mira what do you think?',
      mentions: [seedSelfId],
      reactions: [('🔥', 2, false)],
      channelId: 'c-show-and-tell',
    ),
  ],
  'c-build-log': [
    _msg(
      'b1',
      'u-omar',
      '2026-11-06T10:30:00Z',
      '@mira the CNC bed is levelled',
      mentions: [seedSelfId],
      channelId: 'c-build-log',
    ),
    _msg(
      'b2',
      'u-omar',
      '2026-11-06T10:31:00Z',
      '@mira and the spindle runs true now',
      mentions: [seedSelfId],
      channelId: 'c-build-log',
    ),
  ],
  'c-off-topic': [
    _msg(
      'o1',
      'u-nadia',
      '2026-11-06T08:00:00Z',
      'anyone tried the new bakery? @mira',
      mentions: [seedSelfId],
      channelId: 'c-off-topic',
    ),
  ],
  't-lobby': [
    _msg(
      'l1',
      'u-hana',
      '2026-11-06T11:00:00Z',
      '@mira tournament tonight!',
      mentions: [seedSelfId],
      channelId: 't-lobby',
    ),
  ],
  _dmChannelId: [
    _msg(
      'd3',
      'u-hana',
      '2026-11-06T11:20:00Z',
      'see you at the workshop?',
      channelId: _dmChannelId,
    ),
    _msg(
      'd4',
      'u-hana',
      '2026-11-06T11:21:00Z',
      'bring the calipers',
      channelId: _dmChannelId,
    ),
  ],
};

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

Map<String, dynamic> _sound(
  String id,
  String spaceId,
  String name,
  String? emoji,
) => {
  'id': id,
  'space_id': spaceId,
  'name': name,
  'audio_url': '/sounds/$spaceId/$id.ogg',
  'volume': 1.0,
  'emoji_name': ?emoji,
  'creator_id': seedSelfId,
  'created_at': '2026-11-01 10:00:00',
  'updated_at': '2026-11-01 10:00:00',
};

/// The space's soundboard, named like the reference client's built-in sounds
/// so the two pickers line up card for card.
final List<Map<String, dynamic>> _valeSounds = [
  _sound('snd-quack', seedSpaceId, 'quack', '\u{1F986}'),
  _sound('snd-airhorn', seedSpaceId, 'airhorn', '\u{1F4E2}'),
  _sound('snd-cricket', seedSpaceId, 'cricket', '\u{1F997}'),
  _sound('snd-golfclap', seedSpaceId, 'golf clap', '\u{1F44F}'),
  _sound('snd-sadhorn', seedSpaceId, 'sad horn', '\u{1F3BA}'),
  _sound('snd-badumtss', seedSpaceId, 'ba dum tss', '\u{1F941}'),
];

final List<Map<String, dynamic>> _tideSounds = [
  _sound('snd-boing', seedSecondSpaceId, 'boing', null),
  _sound('snd-cap', seedSecondSpaceId, 'cap', '\u{1F611}'),
  _sound('snd-jellyfish', seedSecondSpaceId, 'jellyfish', '\u{1F612}'),
];

/// Set once the app is up: a play request makes us the one playing.
ProviderContainer? _container;

MockClient _transport() {
  final seeded = buildSeededTransport();
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' &&
        path.endsWith('/spaces/$seedSpaceId/soundboard')) {
      // `&sounds=0`: an empty soundboard (its settings page's empty state).
      if (Uri.base.queryParameters['sounds'] == '0') return _json([]);
      return _json(_valeSounds);
    }
    if (request.method == 'GET' &&
        path.endsWith('/spaces/$seedSecondSpaceId/soundboard')) {
      return _json(_tideSounds);
    }
    if (request.method == 'POST' && path.endsWith('/play')) {
      final soundId = request.url.pathSegments.reversed.elementAt(1);
      final sound = _valeSounds.firstWhere(
        (s) => s['id'] == soundId,
        orElse: () => _valeSounds.first,
      );
      _container
          ?.read(soundboardActivityControllerProvider.notifier)
          .start(seedSelfId, AccordSound.fromJson(sound));
      return _json(const <String, dynamic>{});
    }
    if (request.method == 'GET' &&
        path.endsWith('/channels/$seedGeneralChannelId/messages')) {
      return _json(_general.reversed.toList());
    }
    if (request.method == 'GET' &&
        path.endsWith('/channels/$_dmChannelId/messages')) {
      return _json(_dmMessages.reversed.toList());
    }
    // Lot G: the server settings' lists start empty (their empty states).
    if (request.method == 'GET' &&
        path.contains('/spaces/$seedSpaceId/') &&
        const [
          '/bans',
          '/invites',
          '/audit-log',
          '/audit-logs',
          '/webhooks',
          '/emojis',
          '/stickers',
        ].any(path.endsWith)) {
      return _json([]);
    }
    if (request.method == 'GET' && path.contains('/channels/')) {
      final channelId = request.url.pathSegments.reversed.elementAt(1);
      final unread = _unreadMessages[channelId];
      if (unread != null && path.endsWith('/messages')) {
        return _json(unread.reversed.toList());
      }
    }
    if (path.endsWith('/users/@me/channels')) return _json([_dm]);
    if (path.endsWith('/users/@me/mutes')) {
      return _json([
        if (Uri.base.queryParameters['scene'] == 'unread')
          {'channel_id': 'c-off-topic'},
      ]);
    }
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

/// The mounted element carrying [key], if any.
BuildContext? _findKeyed(Key key) {
  BuildContext? found;
  void visit(Element element) {
    if (found != null) return;
    if (element.widget.key == key) {
      found = element;
      return;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

/// Connected to `Workbench` without a LiveKit session: the tiles fall back to
/// avatars, which is what a camera-off call shows.
class _InVoice extends VoiceController {
  _InVoice(this.serverKey);
  final String serverKey;

  @override
  VoiceConnection build() => VoiceConnection(
    channelId: seedVoiceChannelId,
    spaceId: seedSpaceId,
    serverKey: serverKey,
    sessionState: VoiceSessionState.connected,
  );
}

/// Logged in on the fixture; [clientForKey] serves the panes that look a
/// client up by connection (the inbox, the mutes, the user cache).
class _Auth extends AccordAuth {
  _Auth(this._client, this._session);
  final AccordClient _client;
  final AccordSession _session;

  @override
  AccordAuthState build() =>
      AccordAuthLoggedIn(client: _client, session: _session);

  @override
  AccordClient? clientForKey(String key) =>
      key == _session.key ? _client : null;
}

/// Lot H: `#off-topic` is muted in the unread scene.
class _Mutes extends MutedChannelsController {
  _Mutes(this.scene);
  final String scene;

  @override
  Future<Set<String>> build(String serverKey) async =>
      scene == 'unread' ? const {'c-off-topic'} : const <String>{};
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupHive();
  final scene = Uri.base.queryParameters['scene'] ?? 'messages';
  final server = AccordServer.fromBaseUrl('https://vale.example');
  final voiceScene = scene == 'voice' || scene == 'call';
  final settingsKey = '$seedSelfId@${server.baseUrl}';
  await ProfileStore.settingsBox.put(
    'settings',
    AccordSettings(
      // Three sounds already played, for the picker's "Frequently Used".
      soundUsage: voiceScene
          ? {
              for (final (i, id) in const [
                'snd-quack',
                'snd-airhorn',
                'snd-cricket',
              ].indexed)
                soundSettingsKey(settingsKey, id): 3 - i,
            }
          : const {},
    ).toJson(),
  );
  await ProfileStore.settingsBox.delete('open-tabs');
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
      accordAuthProvider.overrideWith(() => _Auth(client, session)),
      if (voiceScene)
        voiceControllerProvider.overrideWith(() => _InVoice(session.key)),
      // The real controller reaches the client through the auth notifier,
      // which a value override doesn't have.
      mutedChannelsControllerProvider.overrideWith2((_) => _Mutes(scene)),
    ],
  );
  _container = container;
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
  container.read(readStateControllerProvider(key).notifier).hydrate([
    const ReadEntry(
      channelId: seedGeneralChannelId,
      spaceId: seedSpaceId,
      lastMessageId: '110',
      lastReadMessageId: '108',
    ),
    if (scene == 'unread') ...const [
      ReadEntry(
        channelId: 'c-introductions',
        spaceId: seedSpaceId,
        lastMessageId: 'i2',
        lastReadMessageId: 'i0',
      ),
      ReadEntry(
        channelId: 'c-show-and-tell',
        spaceId: seedSpaceId,
        mentions: 1,
        lastMessageId: 's1',
        lastReadMessageId: 's0',
      ),
      ReadEntry(
        channelId: 'c-build-log',
        spaceId: seedSpaceId,
        mentions: 2,
        lastMessageId: 'b2',
        lastReadMessageId: 'b0',
      ),
      ReadEntry(
        channelId: 'c-off-topic',
        spaceId: seedSpaceId,
        mentions: 1,
        lastMessageId: 'o1',
        lastReadMessageId: 'o0',
      ),
      ReadEntry(
        channelId: 't-lobby',
        spaceId: seedSecondSpaceId,
        mentions: 1,
        lastMessageId: 'l1',
        lastReadMessageId: 'l0',
      ),
      ReadEntry(
        channelId: _dmChannelId,
        mentions: 2,
        lastMessageId: 'd4',
        lastReadMessageId: 'd2',
      ),
    ],
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
  if (voiceScene) {
    final crowd = Uri.base.queryParameters['crowd'] == '1';
    container
        .read(voiceStatesControllerProvider(key).notifier)
        .seedChannel(seedVoiceChannelId, [
          for (final entry in seedVoiceParticipants.entries)
            if (crowd || entry.key == seedSelfId)
              AccordVoiceState(
                userId: entry.key,
                spaceId: seedSpaceId,
                channelId: seedVoiceChannelId,
                selfMute: entry.value['self_mute'] ?? false,
              ),
        ]);
    if (scene == 'call') {
      container
          .read(openTabsControllerProvider.notifier)
          .open(
            OpenTab(
              channelId: seedVoiceChannelId,
              spaceId: seedSpaceId,
              serverKey: key,
              name: 'Workbench',
            ),
          );
    }
    final player = Uri.base.queryParameters['play'];
    if (player != null) {
      Future<void>.delayed(const Duration(milliseconds: 2500), () {
        container
            .read(soundboardActivityControllerProvider.notifier)
            .start(
              player,
              AccordSound.fromJson(_valeSounds.first),
              duration: const Duration(minutes: 1),
              exact: true,
            );
      });
    }
  }
  if (Uri.base.queryParameters['typing'] == '1') {
    Future<void>.delayed(const Duration(seconds: 2), () {
      container
          .read(typingControllerProvider(key, seedGeneralChannelId).notifier)
          .userTyping('u-june');
    });
  }
  // `&preview=r-everyone` views the space as that role (the owner's "View
  // Server As Role"), for the menus a plain member gets.
  final previewRole = Uri.base.queryParameters['preview'];
  if (previewRole != null) {
    container
        .read(rolePreviewControllerProvider.notifier)
        .enter(
          RolePreview(
            spaceId: seedSpaceId,
            roleId: previewRole,
            roleName: previewRole,
          ),
        );
  }
  if (scene == 'unread') {
    // The Mentions tab: what the gateway would have delivered this session.
    final mentions = container.read(
      inboxMentionsControllerProvider(key).notifier,
    );
    for (final (channel, id, kind) in const [
      ('c-show-and-tell', 's1', InboxMentionKind.direct),
      ('c-build-log', 'b2', InboxMentionKind.direct),
      ('t-lobby', 'l1', InboxMentionKind.direct),
    ]) {
      final raw = _unreadMessages[channel]!.firstWhere((m) => m['id'] == id);
      mentions.record(
        AccordMessage.fromJson({
          ...raw,
          'space_id': channel.startsWith('t-') ? seedSecondSpaceId : seedSpaceId,
        }),
        kind,
      );
    }
  }
  if (scene == 'dm' || scene == 'friends') {
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      dmHome.open(scene == 'dm' ? AccordChannel.fromJson(_dm) : null);
    });
  }
  // `&open=shortcuts` / `&open=switcher` opens Ctrl+/ or Ctrl+K once the
  // home is up (synthetic keyboard events don't reach Flutter's shortcuts).
  final navigatorKey = GlobalKey<NavigatorState>();
  final open = Uri.base.queryParameters['open'];
  if (open != null) {
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      if (open == 'shortcuts') showKeyboardShortcutsDialog(context);
      if (open == 'switcher') showQuickSwitcher(context);
      // Lot G: `&open=profile` (Edit Profile) and `&open=channel-settings`
      // (Edit Channel on #general).
      if (open == 'profile') showAccordProfileEdit(context);
      if (open == 'channel-settings') {
        final general = container
            .read(accordChannelsControllerProvider(key, seedSpaceId))
            ?.where((c) => c.id == seedGeneralChannelId)
            .firstOrNull;
        if (general != null) {
          showEditChannelDialog(
            context,
            spaceId: seedSpaceId,
            channel: general,
          );
        }
      }
      // Lot G: `&open=space-settings&page=<SpaceSettingsPages key>`.
      if (open == 'space-settings') {
        showAccordSpaceSettings(
          context,
          spaceId: seedSpaceId,
          page: Uri.base.queryParameters['page'],
        );
      }
      // Lot H: `&open=inbox` (`&tab=mentions`), from the title bar's button.
      if (open == 'inbox') {
        final button = _findKeyed(const Key('home-title-bar-inbox'));
        showInboxPopover(
          button ?? context,
          tab: Uri.base.queryParameters['tab'] == 'mentions'
              ? InboxTab.mentions
              : InboxTab.unread,
        );
      }
      // Lot G: `&open=settings&page=<SettingsPage name>`.
      if (open == 'settings') {
        showUserSettings(
          context,
          page: SettingsPage.fromName(Uri.base.queryParameters['page']),
        );
      }
    });
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: navigatorKey,
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
