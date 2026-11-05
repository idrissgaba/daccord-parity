import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/quick_switcher.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = 'me@https://switch.test';

QuickSwitchItem _item(
  QuickSwitchKind kind,
  String id,
  String name, {
  String? secondary,
}) => QuickSwitchItem(
  kind: kind,
  serverKey: _key,
  id: id,
  name: name,
  secondary: secondary,
);

class _Auth extends AccordAuth {
  @override
  AccordAuthState build() => const AccordAuthLoggedOut();
  @override
  AccordClient? clientForKey(String key) => null;
}

class _Connections extends ConnectionsController {
  _Connections(this.session);
  final AccordSession session;
  @override
  ConnectionsState build() => ConnectionsState(
    activeKey: session.key,
    connections: [
      AccordConnection(session: session, status: ConnectionStatus.ready),
    ],
  );
}

class _Settings extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

void main() {
  group('filterQuickSwitch', () {
    final items = [
      _item(QuickSwitchKind.textChannel, 'c1', 'general'),
      _item(QuickSwitchKind.textChannel, 'c2', 'général'),
      _item(QuickSwitchKind.voiceChannel, 'v1', 'Gaming Lounge'),
      _item(QuickSwitchKind.space, 's1', 'Gaming Zone'),
      _item(QuickSwitchKind.dm, 'd1', 'Alice', secondary: 'alice'),
      _item(QuickSwitchKind.user, 'u1', 'Gerard', secondary: 'gege'),
    ];

    List<String> ids(QuickSwitchResult r) => [for (final i in r.items) i.id];

    test('channels first, then servers, then people, best match first', () {
      final result = filterQuickSwitch(items, 'ge');
      expect(result.header, isNull);
      // "général" folds its accent; "Gaming Lounge" / "Gaming Zone" match
      // the letters in order.
      expect(ids(result), ['c1', 'c2', 'v1', 's1', 'u1']);
    });

    test('prefixes narrow the search and name it', () {
      expect(filterQuickSwitch(items, '#').header, 'Searching Text Channels');
      expect(ids(filterQuickSwitch(items, '#')), ['c1', 'c2']);
      expect(ids(filterQuickSwitch(items, '!')), ['v1']);
      expect(filterQuickSwitch(items, '*').header, 'Searching Servers');
      expect(ids(filterQuickSwitch(items, '*gam')), ['s1']);
      // "@" alone lists nobody, as the reference does.
      final at = filterQuickSwitch(items, '@');
      expect(at.header, 'Searching All Users');
      expect(at.items, isEmpty);
      expect(ids(filterQuickSwitch(items, '@ali')), ['d1']);
      // Usernames match too.
      expect(ids(filterQuickSwitch(items, '@gege')), ['u1']);
    });

    test('an empty query shows the previous channels', () {
      final recent = [items[1], items[4]];
      final result = filterQuickSwitch(items, '', recent: recent);
      expect(result.header, 'Previous Channels');
      expect(ids(result), ['c2', 'd1']);
      expect(filterQuickSwitch(items, '  ').header, isNull);
    });

    test('there is no game-profile prefix', () {
      expect(quickSwitchPrefixes.keys, ['@', '#', '!', '*']);
      expect(ids(filterQuickSwitch(items, r'$')), isEmpty);
    });
  });

  group('QuickSwitcherHistory', () {
    setUp(QuickSwitcherHistory.clear);

    test('keeps the newest first, once each, capped', () {
      for (var i = 0; i < QuickSwitcherHistory.capacity + 3; i++) {
        QuickSwitcherHistory.visit('k$i');
      }
      QuickSwitcherHistory.visit('k5');
      expect(QuickSwitcherHistory.keys.first, 'k5');
      expect(QuickSwitcherHistory.keys.length, QuickSwitcherHistory.capacity);
      expect(QuickSwitcherHistory.keys.where((k) => k == 'k5').length, 1);
    });

    test(
      'a channel and its DM share one place; the current one is left out',
      () {
        final items = [
          _item(QuickSwitchKind.textChannel, 'c1', 'general'),
          _item(QuickSwitchKind.dm, 'd1', 'Alice'),
        ];
        QuickSwitcherHistory.visit(
          quickSwitchKey(QuickSwitchKind.textChannel, _key, 'c1'),
        );
        QuickSwitcherHistory.visit(
          quickSwitchKey(QuickSwitchKind.textChannel, _key, 'd1'),
        );
        expect(recentQuickSwitchItems(items).map((i) => i.id), ['d1', 'c1']);
        expect(
          recentQuickSwitchItems(items, current: items[1].key).map((i) => i.id),
          ['c1'],
        );
      },
    );
  });

  group('the switcher dialog', () {
    final session = AccordSession(
      server: AccordServer.fromBaseUrl('https://switch.test'),
      token: 'test-only',
      tokenType: 'Bearer',
      userId: 'me',
      username: 'me',
    );

    Future<(ProviderContainer, ValueNotifier<QuickSwitchItem?>)> pump(
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 927);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          accordAuthProvider.overrideWith(_Auth.new),
          connectionsControllerProvider.overrideWith(
            () => _Connections(session),
          ),
          settingsControllerProvider.overrideWith(_Settings.new),
        ],
      );
      addTearDown(container.dispose);
      final space = AccordSpace.fromJson({'id': 's1', 'name': 'Maison'});
      container.read(spacesControllerProvider.notifier).setSpaces([space]);
      container
          .read(accordChannelsControllerProvider(session.key, 's1').notifier)
          .setChannels([
            AccordChannel.fromJson({
              'id': 'cat',
              'name': 'Text Channels',
              'type': 'category',
            }),
            AccordChannel.fromJson({
              'id': 'gen',
              'name': 'general',
              'type': 'text',
              'parent_id': 'cat',
            }),
            AccordChannel.fromJson({
              'id': 'lounge',
              'name': 'Lounge',
              'type': 'voice',
            }),
          ]);
      container
          .read(dmChannelsControllerProvider(session.key).notifier)
          .setChannels([
            AccordChannel.fromJson({
              'id': 'dm1',
              'type': 'dm',
              'recipients': [
                {'id': 'ali', 'username': 'alice', 'display_name': 'Alice'},
              ],
            }),
          ]);
      final picked = ValueNotifier<QuickSwitchItem?>(null);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(AppThemePreset.dark),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async =>
                      picked.value = await showQuickSwitcher(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (container, picked);
    }

    setUp(QuickSwitcherHistory.clear);

    testWidgets('titles, prefixes and the protip', (tester) async {
      await pump(tester);
      expect(find.text('Search for servers, channels or DMs'), findsOneWidget);
      expect(find.text('Where would you like to go?'), findsOneWidget);
      final protip = tester.widget<Text>(
        find.byKey(const Key('quick-switcher-protip')),
      );
      expect(
        protip.textSpan!.toPlainText(includePlaceholders: false),
        'Protip: Start searches with  to narrow results.',
      );
      for (final symbol in ['@', '#', '!', '*']) {
        expect(find.text(symbol), findsOneWidget);
      }
      expect(find.text(r'$'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('quick-switcher-field')),
        '!',
      );
      await tester.pump();
      expect(
        find.text('Select a result and press ENTER to jump to it'),
        findsOneWidget,
      );
      expect(find.text('Searching Voice Channels'), findsOneWidget);
      expect(find.text('Lounge'), findsOneWidget);
      expect(find.text('general'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('quick-switcher-field')),
        '@al',
      );
      await tester.pump();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
    });

    testWidgets('Enter jumps to the highlighted row; ↓ moves', (tester) async {
      final (_, picked) = await pump(tester);
      await tester.enterText(
        find.byKey(const Key('quick-switcher-field')),
        'l',
      );
      await tester.pump();
      // "Lounge" (prefix) ranks before "general" (letters in order).
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(picked.value?.kind, QuickSwitchKind.textChannel);
      expect(picked.value?.id, 'gen');
      expect(picked.value?.spaceId, 's1');
      expect(picked.value?.category, 'Text Channels');
    });

    testWidgets('previous channels list the places visited', (tester) async {
      QuickSwitcherHistory.visit(
        quickSwitchKey(QuickSwitchKind.textChannel, session.key, 'dm1'),
      );
      await pump(tester);
      expect(find.text('Previous Channels'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });
  });
}
