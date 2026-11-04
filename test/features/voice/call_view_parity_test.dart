import 'package:accordkit/accordkit.dart'
    show AccordClient, AccordMember, AccordUser, AccordVoiceState;
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/services/voice_session.dart';
import 'package:bonfire/features/voice/views/voice_view.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lot C of the Discord parity work: the call view's control bar, the
/// "alone" panel, the participant menu and the deafen-mutes rule.

class _RecordingSession extends VoiceSession {
  final micToggles = <bool>[];
  final deafens = <bool>[];

  @override
  Future<String?> setMicEnabled(bool enabled) async {
    micToggles.add(enabled);
    return null;
  }

  @override
  Future<void> setDeafened(bool deafened) async {
    deafens.add(deafened);
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}
}

class _ConnectedVoice extends VoiceController {
  _ConnectedVoice(this._session, {this.selfMute = false});

  final _RecordingSession _session;
  final bool selfMute;

  @override
  VoiceConnection build() {
    debugSession = _session;
    return VoiceConnection(
      channelId: 'c1',
      spaceId: 's1',
      selfMute: selfMute,
    );
  }
}

class _States extends VoiceStatesController {
  _States(this.states);
  final Map<String, AccordVoiceState> states;

  @override
  Map<String, Map<String, AccordVoiceState>> build(String serverKey) => {
    'c1': states,
  };
}

class _FakeSettings extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

/// Logged in as `u1` on the active server `''`, so the view knows who we are
/// and the participant menu has a server to key its settings on.
class _LoggedInAuth extends AccordAuth {
  _LoggedInAuth(this._client);
  final AccordClient _client;

  @override
  AccordAuthState build() => AccordAuthLoggedIn(
    client: _client,
    session: AccordSession(
      server: AccordServer.fromBaseUrl('https://accord.example.test'),
      token: 'test-token',
      userId: 'u1',
      username: 'u1',
    ),
  );

  @override
  AccordClient? clientForKey(String key) => _client;
}

class _ActiveConnections extends ConnectionsController {
  @override
  ConnectionsState build() => const ConnectionsState(activeKey: '');
}

/// Empty caches that never fetch (a fetch would leave a timer pending).
class _Users extends AccordUsersController {
  @override
  Map<String, AccordUser> build(String serverKey) => const {};
  @override
  void ensure(String userId) {}
}

class _Members extends AccordMembersController {
  @override
  Map<String, AccordMember>? build(String serverKey, String spaceId) =>
      const {};
}

Widget _host(
  VoiceController voice, {
  required Map<String, AccordVoiceState> states,
  Size size = const Size(1400, 900),
  AccordClient? loggedIn,
}) => ProviderScope(
  overrides: [
    if (loggedIn == null)
      accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut())
    else ...[
      accordAuthProvider.overrideWith(() => _LoggedInAuth(loggedIn)),
      connectionsControllerProvider.overrideWith(_ActiveConnections.new),
      accordUsersControllerProvider('').overrideWith(_Users.new),
      accordMembersControllerProvider('', 's1').overrideWith(_Members.new),
    ],
    settingsControllerProvider.overrideWith(_FakeSettings.new),
    voiceControllerProvider.overrideWith(() => voice),
    voiceStatesControllerProvider('').overrideWith(() => _States(states)),
  ],
  child: MaterialApp(
    theme: buildAppTheme(AppThemePreset.dark),
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: const Scaffold(
        body: VoiceChannelView(
          channelId: 'c1',
          spaceId: 's1',
          channelName: 'General',
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];
  setUp(() {
    soundManager.debugPlayed.clear();
    for (final channel in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
    }
  });
  tearDown(() {
    soundManager.voiceSessionActive = false;
    for (final channel in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  group('control bar', () {
    testWidgets('carries the reference layout, without deafen or settings', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _ConnectedVoice(_RecordingSession()),
          states: {'u1': AccordVoiceState(userId: 'u1', channelId: 'c1')},
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('voice-mic')), findsOneWidget);
      expect(find.byKey(const Key('voice-mic-devices')), findsOneWidget);
      expect(find.byKey(const Key('voice-camera')), findsOneWidget);
      expect(find.byKey(const Key('voice-camera-devices')), findsOneWidget);
      expect(find.byKey(const Key('voice-arcade')), findsOneWidget);
      expect(find.byKey(const Key('voice-more')), findsOneWidget);
      expect(find.byTooltip('Disconnect'), findsOneWidget);
      expect(find.byKey(const Key('voice-full-screen')), findsOneWidget);
      // Deafen and the gear left the bar (user panel and "…" menu).
      expect(find.byTooltip('Deafen'), findsNothing);
      expect(find.byTooltip('Voice settings'), findsNothing);
      expect(find.byIcon(AppIcons.headset), findsNothing);

      // The bar's order, left to right.
      double x(Key key) => tester.getCenter(find.byKey(key)).dx;
      expect(x(const Key('voice-mic')), lessThan(x(const Key('voice-camera'))));
      expect(
        x(const Key('voice-camera')),
        lessThan(x(const Key('voice-arcade'))),
      );
      expect(x(const Key('voice-arcade')), lessThan(x(const Key('voice-more'))));
      expect(
        x(const Key('voice-more')),
        lessThan(tester.getCenter(find.byTooltip('Disconnect')).dx),
      );
      expect(
        tester.getCenter(find.byTooltip('Disconnect')).dx,
        lessThan(x(const Key('voice-full-screen'))),
      );
      // The hang-up is the wide one.
      expect(tester.getSize(find.byTooltip('Disconnect')).width, 68);
    });

    testWidgets('"…" offers Voice Settings', (tester) async {
      await tester.pumpWidget(
        _host(
          _ConnectedVoice(_RecordingSession()),
          states: {'u1': AccordVoiceState(userId: 'u1', channelId: 'c1')},
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('voice-more')));
      await tester.pumpAndSettle();
      expect(find.text('Voice Settings'), findsOneWidget);
    });
  });

  group('call body', () {
    testWidgets('alone: our tile plus the invite / activity panel', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _ConnectedVoice(_RecordingSession()),
          states: {'u1': AccordVoiceState(userId: 'u1', channelId: 'c1')},
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('voice-alone-panel')), findsOneWidget);
      expect(find.text('Choose Activity'), findsOneWidget);
      // Both cells are 16:9 and the same size.
      final tile = tester.getSize(find.byKey(const Key('voice-tile-u1:camera')));
      final panel = tester.getSize(find.byKey(const Key('voice-alone-panel')));
      expect(panel, tile);
      expect(panel.width / panel.height, closeTo(16 / 9, 0.01));
    });

    testWidgets('the panel leaves when someone else is in', (tester) async {
      await tester.pumpWidget(
        _host(
          _ConnectedVoice(_RecordingSession()),
          states: {
            'u1': AccordVoiceState(userId: 'u1', channelId: 'c1'),
            'u2': AccordVoiceState(userId: 'u2', channelId: 'c1'),
          },
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('voice-alone-panel')), findsNothing);
    });

    testWidgets('a resting tile shows only the status square; hover adds '
        'the name', (tester) async {
      await tester.pumpWidget(
        _host(
          _ConnectedVoice(_RecordingSession()),
          states: {
            'u1': AccordVoiceState(
              userId: 'u1',
              channelId: 'c1',
              selfMute: true,
            ),
            'u2': AccordVoiceState(
              userId: 'u2',
              channelId: 'c1',
              selfDeaf: true,
            ),
          },
        ),
      );
      await tester.pump();
      // No name until the pointer rests on the tile (desktop layout).
      expect(find.text('u1'), findsNothing);
      expect(find.byKey(const Key('tile-status-u1')), findsOneWidget);
      // Deafened shows the crossed headset, muted the crossed mic.
      expect(
        find.descendant(
          of: find.byKey(const Key('tile-status-u2')),
          matching: find.byIcon(AppIcons.headsetOff),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('tile-status-u1')),
          matching: find.byIcon(AppIcons.micOff),
        ),
        findsOneWidget,
      );
    });

    testWidgets('right-clicking a tile opens the participant menu', (
      tester,
    ) async {
      final client = AccordClient(
        token: 'test-token',
        tokenType: 'Bearer',
        baseUrl: 'https://accord.example.test',
        gatewayUrl: 'wss://accord.example.test/ws',
      );
      addTearDown(client.dispose);
      await tester.pumpWidget(
        _host(
          _ConnectedVoice(_RecordingSession()),
          loggedIn: client,
          states: {
            'u1': AccordVoiceState(userId: 'u1', channelId: 'c1'),
            'u2': AccordVoiceState(userId: 'u2', channelId: 'c1'),
          },
        ),
      );
      await tester.pump();
      await tester.longPress(find.byKey(const Key('voice-tile-u2:camera')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('voice-menu-profile')), findsOneWidget);
      expect(find.byKey(const Key('voice-menu-mention')), findsOneWidget);
      expect(find.byKey(const Key('voice-menu-message')), findsOneWidget);
      expect(find.byKey(const Key('voice-menu-mute')), findsOneWidget);
      expect(find.byKey(const Key('user-volume-slider')), findsOneWidget);
      expect(find.byKey(const Key('voice-menu-non-video')), findsOneWidget);
      expect(find.byKey(const Key('voice-menu-copy-id')), findsOneWidget);
      // No permissions on this space, so no moderation rows.
      expect(find.byKey(const Key('voice-mod-mute')), findsNothing);
      // Close the sheet before the tree goes away.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    });
  });

  group('deafen', () {
    test('deafening mutes the mic; undeafening restores it', () async {
      final session = _RecordingSession();
      final container = ProviderContainer(
        overrides: [
          accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut()),
          settingsControllerProvider.overrideWith(_FakeSettings.new),
          voiceControllerProvider.overrideWith(() => _ConnectedVoice(session)),
          voiceStatesControllerProvider('').overrideWith(() => _States({})),
        ],
      );
      addTearDown(container.dispose);
      final voice = container.read(voiceControllerProvider.notifier);

      voice.setDeafen(true);
      await Future<void>.delayed(Duration.zero);
      var state = container.read(voiceControllerProvider);
      expect(state.selfDeaf, isTrue);
      expect(state.selfMute, isTrue, reason: 'deafen mutes too');
      expect(session.deafens, [true]);
      expect(session.micToggles, [false]);
      expect(soundManager.debugPlayed, ['deafen']);

      voice.setDeafen(false);
      await Future<void>.delayed(Duration.zero);
      state = container.read(voiceControllerProvider);
      expect(state.selfDeaf, isFalse);
      expect(state.selfMute, isFalse, reason: 'the mute came from the deafen');
      expect(session.micToggles, [false, true]);
    });

    test('a mic muted beforehand stays muted after undeafening', () async {
      final session = _RecordingSession();
      final container = ProviderContainer(
        overrides: [
          accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut()),
          settingsControllerProvider.overrideWith(_FakeSettings.new),
          voiceControllerProvider.overrideWith(
            () => _ConnectedVoice(session, selfMute: true),
          ),
          voiceStatesControllerProvider('').overrideWith(() => _States({})),
        ],
      );
      addTearDown(container.dispose);
      final voice = container.read(voiceControllerProvider.notifier);

      voice.setDeafen(true);
      voice.setDeafen(false);
      await Future<void>.delayed(Duration.zero);
      final state = container.read(voiceControllerProvider);
      expect(state.selfDeaf, isFalse);
      expect(state.selfMute, isTrue);
      expect(session.micToggles, isEmpty);
    });
  });

  test('a forced disconnect sounds like leaving', () async {
    final session = _RecordingSession();
    final container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut()),
        settingsControllerProvider.overrideWith(_FakeSettings.new),
        voiceControllerProvider.overrideWith(() => _ConnectedVoice(session)),
        voiceStatesControllerProvider('').overrideWith(() => _States({})),
      ],
    );
    addTearDown(container.dispose);
    final voice = container.read(voiceControllerProvider.notifier);
    voice.handleForcedDisconnect('c1');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(voiceControllerProvider).isConnected, isFalse);
    expect(soundManager.debugPlayed, contains('voice_leave'));
  });
}
