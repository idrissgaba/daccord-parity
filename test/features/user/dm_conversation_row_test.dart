import 'package:bonfire/theme/app_icons.dart';
import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'dm_home_host.dart';

/// A [DmChannelsController] exposing a fixed conversation list, so the DM
/// home renders without a server.
class _FakeDmChannels extends DmChannelsController {
  _FakeDmChannels(this._channels);

  final List<AccordChannel> _channels;

  @override
  List<AccordChannel>? build(String serverKey) => _channels;
}

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

AccordMessage _message(String author, String content, DateTime sentAt) =>
    AccordMessage(
      id: 'm-$content',
      channelId: 'dm1',
      authorId: author,
      content: content,
      timestamp: sentAt.toUtc().toIso8601String(),
    );

/// Signed in as [userId], with a client that answers every request with an
/// empty list so nothing reaches the network.
AccordAuthLoggedIn _loggedIn(String userId) {
  final server = AccordServer.fromBaseUrl('https://accord.example.test');
  final client = AccordClient(
    token: 'test-token',
    tokenType: 'Bearer',
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
    httpClient: MockClient((_) async => http.Response('[]', 200)),
  );
  addTearDown(client.dispose);
  return AccordAuthLoggedIn(
    client: client,
    session: AccordSession(
      server: server,
      token: 'test-token',
      userId: userId,
      username: 'me',
    ),
  );
}

void main() {
  late ProviderContainer container;

  /// Recreates [container] with bob (`u2`) at the given presence and name,
  /// signed in as [selfId] when given.
  void useConversation({
    String name = 'bob',
    String? status,
    String? selfId,
    String? origin,
  }) {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        if (selfId != null)
          accordAuthProvider.overrideWithValue(_loggedIn(selfId)),
        settingsControllerProvider.overrideWith(_FakeSettingsController.new),
        if (status != null)
          activePresencesProvider.overrideWithValue(
            PresenceMap(
              byUser: {'u2': AccordPresence(userId: 'u2', status: status)},
            ),
          ),
        dmChannelsControllerProvider('').overrideWith(
          () => _FakeDmChannels([
            AccordChannel(
              id: 'dm1',
              type: 'dm',
              recipients: [
                AccordUser(id: 'u2', username: name, origin: origin),
              ],
            ),
          ]),
        ),
      ],
    );
  }

  /// Renders the app at a phone-sized logical [width].
  void useWidth(WidgetTester tester, double width) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 740);
    addTearDown(tester.view.reset);
  }

  Future<void> openHome(WidgetTester tester, {bool sidebarOnly = false}) async {
    resetDmHomeAfter();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: DmHomeHost(sidebarOnly: sidebarOnly),
        ),
      ),
    );
    await tester.tap(find.text('open dms'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    container = ProviderContainer();
    useConversation();
  });

  tearDown(() => container.dispose());

  testWidgets('a row shows the name, not the last message', (tester) async {
    // The reference client's DM list carries the name and the status line;
    // the last message is only in the conversation.
    container
        .read(dmChannelsControllerProvider('').notifier)
        .setPreview('dm1', _message('u2', 'Near the beach', DateTime.now()));

    await openHome(tester);

    expect(find.text('bob'), findsOneWidget);
    expect(find.text('Near the beach'), findsNothing);
  });

  testWidgets('a remote row carries the origin badge', (tester) async {
    useConversation(origin: 'remote.example');

    await openHome(tester);

    expect(find.byIcon(AppIcons.public), findsOneWidget);
  });

  testWidgets('the column offers Find or start and Create DM', (tester) async {
    await openHome(tester);

    expect(find.text('Find or start a conversation'), findsOneWidget);
    expect(find.byTooltip('Create DM'), findsOneWidget);
    expect(find.text('Friends'), findsWidgets);
  });

  group('row semantics', () {
    testWidgets('an unread row with mentions announces them and presence', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      useConversation(status: 'online');
      final readState = container.read(
        readStateControllerProvider('').notifier,
      );
      readState.markUnread('dm1', isMention: true);
      readState.markUnread('dm1', isMention: true);

      await openHome(tester);

      expect(
        find.bySemanticsLabel('bob, online, Unread, 2 mentions'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('a single mention is singular', (tester) async {
      final semantics = tester.ensureSemantics();
      container
          .read(readStateControllerProvider('').notifier)
          .markUnread('dm1', isMention: true);

      await openHome(tester);

      expect(
        find.bySemanticsLabel(RegExp(r'Unread, 1 mention$')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('an unread row without mentions says Unread only', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      useConversation(status: 'dnd');
      container
          .read(readStateControllerProvider('').notifier)
          .markUnread('dm1');

      await openHome(tester);

      expect(
        find.bySemanticsLabel('bob, do not disturb, Unread'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('a read row is not announced as unread', (tester) async {
      final semantics = tester.ensureSemantics();
      useConversation(status: 'idle');

      await openHome(tester);

      expect(find.bySemanticsLabel('bob, idle'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Unread')), findsNothing);
      semantics.dispose();
    });

    testWidgets('a user with no presence is announced offline', (tester) async {
      final semantics = tester.ensureSemantics();

      await openHome(tester);

      expect(find.bySemanticsLabel('bob, offline'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a remote user is announced with their home domain', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      useConversation(origin: 'remote.example', status: 'online');

      await openHome(tester);

      expect(
        find.bySemanticsLabel('bob, homed on remote.example, online'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('the row stays tappable for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();

      await openHome(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('bob, offline')),
        matchesSemantics(
          label: 'bob, offline',
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      semantics.dispose();
    });
  });

  group('narrow mobile widths', () {
    const longName =
        'a_really_quite_remarkably_long_username_that_cannot_possibly_fit';

    for (final width in [320.0, 375.0]) {
      testWidgets('a long remote name truncates before the badge at '
          '${width.toInt()}px', (tester) async {
        useWidth(tester, width);
        useConversation(
          name: longName,
          status: 'online',
          origin: 'remote.example',
        );

        await openHome(tester, sidebarOnly: true);

        expect(tester.takeException(), isNull);
        final titleRect = tester.getRect(find.text(longName));
        final originRect = tester.getRect(find.byIcon(AppIcons.public));
        expect(titleRect.right, lessThanOrEqualTo(originRect.left));
        expect(originRect.right, lessThanOrEqualTo(width));
      });
    }
  });
}
