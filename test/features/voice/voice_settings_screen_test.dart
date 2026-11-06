import 'dart:io';

import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/utils/audio_output_support.dart';
import 'package:bonfire/features/voice/views/voice_settings_screen.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:bonfire/shared/components/settings_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Settings held in memory rather than Hive, so the page can be pumped without
/// opening a box.
class _MemorySettingsController extends SettingsController {
  _MemorySettingsController(this._initial);
  final AccordSettings _initial;

  @override
  AccordSettings build() => _initial;
}

/// Never joined, so the page renders its disconnected mic-test copy.
class _IdleVoiceController extends VoiceController {
  @override
  VoiceConnection build() => const VoiceConnection();
}

Widget _host(AccordSettings settings) => ProviderScope(
  overrides: [
    settingsControllerProvider.overrideWith(
      () => _MemorySettingsController(settings),
    ),
    voiceControllerProvider.overrideWith(_IdleVoiceController.new),
  ],
  child: MaterialApp(
    theme: buildAppTheme(AppThemePreset.dark),
    home: const Scaffold(
      body: SingleChildScrollView(child: VoiceVideoSettingsPage()),
    ),
  ),
);

/// Lays the whole page out at once so a `findsNothing` means the control is
/// absent rather than merely unbuilt.
Future<void> _pumpTall(
  WidgetTester tester, [
  AccordSettings settings = const AccordSettings(),
]) async {
  tester.view.physicalSize = const Size(900, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(settings));
  await tester.pump();
}

void main() {
  group('output device picker (#306)', () {
    tearDown(() => debugCanPickAudioOutputDevice = null);

    testWidgets('sits beside the microphone where the platform honours it', (
      tester,
    ) async {
      debugCanPickAudioOutputDevice = true;
      await _pumpTall(tester);

      expect(find.text('Speaker'), findsOneWidget);
      final mic = tester.getTopLeft(find.byKey(const Key('audio-input-dropdown')));
      final speaker = tester.getTopLeft(
        find.byKey(const Key('audio-output-dropdown')),
      );
      expect(speaker.dy, mic.dy, reason: 'side by side');
      expect(speaker.dx, greaterThan(mic.dx));
    });

    testWidgets('is not offered where the write would be swallowed (iOS)', (
      tester,
    ) async {
      debugCanPickAudioOutputDevice = false;
      await _pumpTall(tester);

      expect(find.byKey(const Key('audio-output-dropdown')), findsNothing);
      // The rest of the voice stack is untouched — only the one dead control
      // goes, never the feature.
      expect(find.byKey(const Key('audio-input-dropdown')), findsOneWidget);
      expect(find.text('Speaker Volume'), findsOneWidget);
      expect(find.text('Camera'), findsWidgets);
    });
  });

  testWidgets('the page has the reference sections in order', (tester) async {
    await _pumpTall(tester);
    final titles = ['Voice', 'Camera', 'Streaming', 'Sounds', 'Soundboard',
      'Advanced'];
    double top(String t) => tester
        .getTopLeft(
          find.byWidgetPredicate(
            (w) => w is SettingsSectionTitle && w.text == t,
          ),
        )
        .dy;
    for (var i = 1; i < titles.length; i++) {
      expect(top(titles[i]), greaterThan(top(titles[i - 1])), reason: titles[i]);
    }
    expect(find.byKey(const Key('mic-test-button')), findsOneWidget);
    expect(find.byKey(const Key('mic-test-meter')), findsOneWidget);
    expect(find.byKey(const Key('input-sensitivity-slider')), findsOneWidget);
    expect(find.byKey(const Key('camera-test-button')), findsOneWidget);
  });

  testWidgets('Custom shows the per-filter controls', (
    tester,
  ) async {
    await _pumpTall(tester);
    expect(find.byKey(const Key('echo-cancellation-switch')), findsOneWidget);
    expect(find.byKey(const Key('noise-suppression-select')), findsOneWidget);
  });

  testWidgets('Studio hides the per-filter controls', (tester) async {
    await _pumpTall(
      tester,
      const AccordSettings(voiceInputProfile: VoiceInputProfile.studio),
    );
    expect(find.byKey(const Key('echo-cancellation-switch')), findsNothing);
    expect(find.byKey(const Key('noise-suppression-select')), findsNothing);
  });

  group('the input profile drives the three filters', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('accord-profile-test');
      Hive.init(tempDir.path);
      await Hive.openBox('accord-settings');
    });

    tearDown(() async {
      await Hive.deleteBoxFromDisk('accord-settings');
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('Studio turns them off, Voice Isolation on, Custom leaves them', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(settingsControllerProvider.notifier);

      controller.setVoiceInputProfile(VoiceInputProfile.studio);
      var s = container.read(settingsControllerProvider);
      expect(s.voiceInputProfile, VoiceInputProfile.studio);
      expect(
        [s.voiceNoiseSuppression, s.voiceEchoCancellation,
          s.voiceAutoGainControl],
        [false, false, false],
      );

      controller.setVoiceInputProfile(VoiceInputProfile.custom);
      s = container.read(settingsControllerProvider);
      expect(s.voiceNoiseSuppression, isFalse, reason: 'Custom keeps them');

      controller.setVoiceInputProfile(VoiceInputProfile.voiceIsolation);
      s = container.read(settingsControllerProvider);
      expect(
        [s.voiceNoiseSuppression, s.voiceEchoCancellation,
          s.voiceAutoGainControl],
        [true, true, true],
      );
      // Persisted, as a restart would read it.
      expect(
        Hive.box('accord-settings').get('settings'),
        containsPair('voiceInputProfile', 'voiceIsolation'),
      );
    });
  });

  testWidgets('camera and stream quality each keep their own value', (
    tester,
  ) async {
    await _pumpTall(
      tester,
      const AccordSettings(videoFps: 30, screenShareFps: 60),
    );
    final camera = tester.widget<AccordSelect<int>>(
      find.byKey(const Key('camera-fps-dropdown')),
    );
    final stream = tester.widget<AccordSelect<int>>(
      find.byKey(const Key('screen-share-fps-dropdown')),
    );
    expect(camera.value, 30);
    expect(stream.value, 60);
    expect(find.byKey(const Key('screen-share-motion-switch')), findsOneWidget);
  });

  testWidgets('the soundboard volume has its own section', (tester) async {
    await _pumpTall(tester, const AccordSettings(soundboardVolume: 0.4));
    expect(find.byKey(const Key('soundboard-volume-setting')), findsOneWidget);
    final slider = tester.widget<Slider>(
      find.descendant(
        of: find.byKey(const Key('soundboard-volume-setting')),
        matching: find.byType(Slider),
      ),
    );
    expect(slider.value, 0.4);
  });
}
