import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/soundboard/controllers/soundboard_activity.dart';
import 'package:bonfire/features/soundboard/controllers/soundboard_sounds.dart';
import 'package:bonfire/features/soundboard/views/soundboard_avatar_cue.dart';
import 'package:bonfire/features/soundboard/views/soundboard_picker.dart';
import 'package:bonfire/features/soundboard/views/soundboard_settings_page.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Lot E of the Discord parity work: the soundboard picker, its sections and
/// cards, the "who is playing" cue and the Soundboard settings page.

final _server = AccordServer.fromBaseUrl('https://accord.example.test');
final _session = AccordSession(
  server: _server,
  token: 't',
  userId: 'me',
  username: 'me',
);

Map<String, dynamic> _sound(String id, String space, String name, String? e) =>
    {
      'id': id,
      'space_id': space,
      'name': name,
      'audio_url': '/sounds/$id.ogg',
      'volume': 1.0,
      'emoji_name': ?e,
      'creator_id': 'me',
    };

final _mine = [
  _sound('q', 's1', 'quack', '\u{1F986}'),
  _sound('a', 's1', 'airhorn', null),
  _sound('c', 's1', 'cricket', '\u{1F997}'),
];
final _theirs = [_sound('j', 's2', 'jellyfish', '\u{1F612}')];

class _Spaces extends SpacesController {
  _Spaces(this.spaces);
  final List<AccordSpace> spaces;
  @override
  List<AccordSpace> build() => spaces;
}

/// Settings without Hive: the soundboard's writes land in memory.
class _Settings extends SettingsController {
  _Settings([this.initial = const AccordSettings()]);
  final AccordSettings initial;
  @override
  AccordSettings build() => initial;
  @override
  void toggleFavoriteSound(String key) {
    final f = state.favoriteSounds;
    state = state.copyWith(
      favoriteSounds: f.contains(key)
          ? [
              for (final k in f)
                if (k != key) k,
            ]
          : [key, ...f],
    );
  }

  @override
  void recordSoundPlayed(String key) {
    state = state.copyWith(
      soundUsage: {...state.soundUsage, key: (state.soundUsage[key] ?? 0) + 1},
    );
  }

  @override
  void setSoundboardVolume(double volume) =>
      state = state.copyWith(soundboardVolume: volume);
}

AccordSpace _space(
  String id,
  String name, {
  String? owner,
  List<String>? perms,
}) => AccordSpace(
  id: id,
  name: name,
  ownerId: owner ?? 'someone-else',
  roles: [
    AccordRole(id: 'everyone-$id', position: 0, permissions: perms ?? []),
  ],
);

class _Host {
  final requests = <String>[];

  late final client = AccordClient(
    token: 't',
    tokenType: 'Bearer',
    baseUrl: _server.baseUrl,
    gatewayUrl: _server.gatewayUrl,
    cdnUrl: _server.cdnUrl,
    httpClient: MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      final path = request.url.path;
      Object body = const <Object>[];
      if (path.endsWith('/spaces/s1/soundboard')) body = _mine;
      if (path.endsWith('/spaces/s2/soundboard')) body = _theirs;
      if (request.method == 'POST') body = const <String, Object>{};
      if (request.method == 'PATCH') body = _mine.first;
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );

  late ProviderContainer container;

  Widget wrap(
    Widget child, {
    required List<AccordSpace> spaces,
    AccordSettings settings = const AccordSettings(),
  }) {
    return ProviderScope(
      overrides: [
        accordAuthProvider.overrideWithValue(
          AccordAuthLoggedIn(client: client, session: _session),
        ),
        spacesControllerProvider.overrideWith(() => _Spaces(spaces)),
        settingsControllerProvider.overrideWith(() => _Settings(settings)),
      ],
      child: MaterialApp(
        theme: buildAppTheme(AppThemePreset.dark),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return child;
            },
          ),
        ),
      ),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  final owned = [_space('s1', 'Vale', owner: 'me'), _space('s2', 'Tide')];

  testWidgets('the picker shows this space, the add card and locked others', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final host = _Host();
    await tester.pumpWidget(
      host.wrap(
        const Center(
          child: SizedBox(
            width: 531,
            height: 520,
            child: SoundboardPickerPanel(serverKey: '', spaceId: 's1'),
          ),
        ),
        spaces: owned,
      ),
    );
    await _settle(tester);

    expect(find.text('Vale'), findsOneWidget);
    expect(find.text('quack'), findsOneWidget);
    expect(find.byKey(const Key('soundboard-add-sound')), findsOneWidget);
    expect(find.text('Tide'), findsOneWidget);
    expect(find.text('jellyfish'), findsOneWidget);
    expect(find.text('Frequently Used'), findsNothing);

    // Another space's sound does not play here.
    await tester.tap(find.byKey(const Key('soundboard-card-j')));
    await _settle(tester);
    expect(host.requests.where((r) => r.startsWith('POST')), isEmpty);

    // Ours plays, and counts for "Frequently Used".
    await tester.tap(find.byKey(const Key('soundboard-card-q')));
    await _settle(tester);
    expect(host.requests, contains('POST /api/v1/spaces/s1/soundboard/q/play'));
    expect(find.text('Frequently Used'), findsOneWidget);
    // The cooldown timer.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('search filters every section by name', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final host = _Host();
    await tester.pumpWidget(
      host.wrap(
        const Center(
          child: SizedBox(
            width: 531,
            height: 520,
            child: SoundboardPickerPanel(serverKey: '', spaceId: 's1'),
          ),
        ),
        spaces: owned,
      ),
    );
    await _settle(tester);
    await tester.enterText(find.byKey(const Key('soundboard-search')), 'CRI');
    await _settle(tester);
    expect(find.text('cricket'), findsOneWidget);
    expect(find.text('quack'), findsNothing);
    expect(find.text('jellyfish'), findsNothing);
    expect(find.byKey(const Key('soundboard-add-sound')), findsNothing);

    await tester.enterText(find.byKey(const Key('soundboard-search')), 'zzz');
    await _settle(tester);
    expect(find.text('No sounds match your search'), findsOneWidget);
  });

  testWidgets('no "Add Sound" without Create Expressions', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final host = _Host();
    await tester.pumpWidget(
      host.wrap(
        const Center(
          child: SizedBox(
            width: 531,
            height: 520,
            child: SoundboardPickerPanel(serverKey: '', spaceId: 's1'),
          ),
        ),
        spaces: [
          _space('s1', 'Vale', perms: [AccordPermission.useSoundboard]),
        ],
      ),
    );
    await _settle(tester);
    expect(find.text('quack'), findsOneWidget);
    expect(find.byKey(const Key('soundboard-add-sound')), findsNothing);
  });

  testWidgets('the hover star adds a sound to Favorites', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final host = _Host();
    await tester.pumpWidget(
      host.wrap(
        const Center(
          child: SizedBox(
            width: 531,
            height: 520,
            child: SoundboardPickerPanel(serverKey: '', spaceId: 's1'),
          ),
        ),
        spaces: owned,
      ),
    );
    await _settle(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const Key('soundboard-card-c'))),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('soundboard-favorite-c')));
    await _settle(tester);
    expect(find.text('Favorites'), findsOneWidget);
    expect(host.container.read(settingsControllerProvider).favoriteSounds, [
      soundSettingsKey('', 'c'),
    ]);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('activity ends when the clip does, a replay restarts it', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final activity = container.read(
      soundboardActivityControllerProvider.notifier,
    );
    final sound = AccordSound(id: 'q', name: 'quack');
    activity.start('u1', sound, duration: const Duration(seconds: 2));
    expect(
      container.read(soundboardActivityControllerProvider),
      contains('u1'),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    activity.start('u1', sound, duration: const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 1000));
    // The first play's timer fired, but the replay is still on.
    expect(
      container.read(soundboardActivityControllerProvider),
      contains('u1'),
    );
    await tester.pump(const Duration(milliseconds: 1100));
    expect(container.read(soundboardActivityControllerProvider), isEmpty);
    // Bounds: a minute-long estimate is cut to the clip ceiling.
    expect(
      SoundboardActivityController.clampDuration(const Duration(minutes: 1)),
      SoundboardActivityController.maxDuration,
    );
  });

  testWidgets('the cue rises over the avatar while the sound plays', (
    tester,
  ) async {
    final host = _Host();
    await tester.pumpWidget(
      host.wrap(
        const Center(child: SoundboardAvatarCue(userId: 'u1', size: 80)),
        spaces: owned,
      ),
    );
    expect(find.byKey(const Key('soundboard-avatar-cue')), findsNothing);
    host.container
        .read(soundboardActivityControllerProvider.notifier)
        .start(
          'u1',
          AccordSound(id: 'q', name: 'quack', emojiName: '\u{1F986}'),
          duration: const Duration(seconds: 1),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('soundboard-avatar-cue')), findsOneWidget);
    expect(find.text('\u{1F986}'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('soundboard-avatar-cue')), findsNothing);
  });

  testWidgets('settings page: rows with preview, upload disabled until valid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 927);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final host = _Host();
    await tester.pumpWidget(
      host.wrap(
        const SoundboardSettingsPage(serverKey: '', spaceId: 's1'),
        spaces: owned,
      ),
    );
    await _settle(tester);
    expect(find.text('Soundboard'), findsWidgets);
    expect(find.byKey(const Key('soundboard-row-q')), findsOneWidget);
    expect(find.byKey(const Key('soundboard-row-preview-q')), findsOneWidget);

    await tester.tap(find.byKey(const Key('soundboard-upload')));
    await _settle(tester);
    expect(find.text('Upload a Sound'), findsOneWidget);
    final upload = tester.widget<TextButton>(
      find.byKey(const Key('accord-dialog-primary')),
    );
    expect(upload.onPressed, isNull, reason: 'no file and no name yet');
    await tester.tap(find.byKey(const Key('accord-dialog-secondary')));
    await _settle(tester);
    expect(find.text('Upload a Sound'), findsNothing);
  });

  testWidgets('editing a sound sends its emoji and volume', (tester) async {
    tester.view.physicalSize = const Size(1920, 927);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final host = _Host();
    await tester.pumpWidget(
      host.wrap(
        const SoundboardSettingsPage(serverKey: '', spaceId: 's1'),
        spaces: owned,
      ),
    );
    await _settle(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const Key('soundboard-row-q'))),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('soundboard-row-edit-q')));
    await _settle(tester);
    expect(find.text('Edit Sound'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('sound-dialog-name')),
      'quack!',
    );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('accord-dialog-primary')));
    await _settle(tester);
    expect(host.requests, contains('PATCH /api/v1/spaces/s1/soundboard/q'));
  });

  testWidgets('settings page empty state', (tester) async {
    tester.view.physicalSize = const Size(1920, 927);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final host = _Host();
    await tester.pumpWidget(
      host.wrap(
        const SoundboardSettingsPage(serverKey: '', spaceId: 's2'),
        spaces: [_space('s2', 'Tide', owner: 'me')],
      ),
    );
    await _settle(tester);
    // s2 has one sound in the fixture; drop it to see the empty state.
    host.container
        .read(soundboardSoundsControllerProvider('', 's2').notifier)
        .remove('j');
    await _settle(tester);
    expect(find.text('No Sounds'), findsOneWidget);
    expect(
      find.text('Get the party started by uploading a sound'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('soundboard-upload')), findsOneWidget);
  });
}
