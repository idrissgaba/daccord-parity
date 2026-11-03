import 'dart:typed_data';

import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/views/screen_share_picker.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

/// A capturable window or screen without the native plugin.
class _FakeSource extends rtc.DesktopCapturerSource {
  _FakeSource(this.id, this.name, this.type, {this.thumbnail});

  @override
  final String id;
  @override
  final String name;
  @override
  final rtc.SourceType type;
  @override
  final Uint8List? thumbnail;
  @override
  rtc.ThumbnailSize get thumbnailSize => rtc.ThumbnailSize(160, 90);
}

class _Settings extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
  @override
  void setScreenShareResolution(int index) =>
      state = state.copyWith(screenShareResolution: index);
  @override
  void setScreenShareFps(int fps) =>
      state = state.copyWith(screenShareFps: fps);
  @override
  void setScreenShareMotionPriority(bool enabled) =>
      state = state.copyWith(screenShareMotionPriority: enabled);
}

Future<List<rtc.DesktopCapturerSource>> _sources(rtc.SourceType type) async =>
    type == rtc.SourceType.Window
    ? [
        _FakeSource('w1', 'Code editor', type),
        _FakeSource('w2', 'Browser', type),
        _FakeSource('w3', 'Game', type),
      ]
    : [
        _FakeSource('s1', 'Screen 1', type),
        _FakeSource('s2', 'Screen 2', type),
      ];

Widget _host({String? channelName, bool changing = false}) => ProviderScope(
  overrides: [settingsControllerProvider.overrideWith(_Settings.new)],
  child: MaterialApp(
    theme: buildAppTheme(AppThemePreset.dark),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showScreenShareSourcePicker(
              context,
              channelName: channelName,
              changing: changing,
              sourceLoader: _sources,
            ),
            child: const Text('share'),
          ),
        ),
      ),
    ),
  ),
);

/// The source tiles spin until a thumbnail arrives, so the tree never
/// settles; fixed pumps stand in for `pumpAndSettle`.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('applications first, screens second, Go Live waits for a pick', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1568, 711);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(channelName: 'Chill'));
    await tester.tap(find.text('share'));
    await _settle(tester);

    expect(find.text('Screen Share'), findsOneWidget);
    expect(find.text('Applications'), findsOneWidget);
    expect(find.text('Screens'), findsOneWidget);
    expect(find.text('Code editor'), findsOneWidget);
    expect(find.text('Screen 1'), findsNothing);
    final goLive = tester.widget<FilledButton>(
      find.byKey(const Key('share-go-live')),
    );
    expect(goLive.onPressed, isNull);

    await tester.tap(find.text('Screens'));
    await _settle(tester);
    expect(find.text('Screen 1'), findsOneWidget);
    expect(find.text('Code editor'), findsNothing);
  });

  testWidgets('picking a source opens the quality step, Go Live returns it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1568, 711);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(channelName: 'Chill'));
    await tester.tap(find.text('share'));
    await _settle(tester);

    await tester.tap(find.text('Browser'));
    await _settle(tester);

    // Step two: what is streamed, where, and the quality.
    expect(find.text("WHAT YOU'RE STREAMING"), findsOneWidget);
    expect(find.text('Browser'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('STREAMING CHANNEL'), findsOneWidget);
    expect(find.text('Chill'), findsOneWidget);
    expect(find.text('STREAM QUALITY'), findsOneWidget);
    expect(find.text('Smoother Video'), findsOneWidget);
    for (final label in ['720', '1080', '1440', 'SOURCE', '15', '30', '60']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Back'), findsOneWidget);

    // "Change" goes back to the sources; a new pick comes back here.
    await tester.tap(find.byKey(const Key('share-change-source')));
    await _settle(tester);
    expect(find.text('Applications'), findsOneWidget);
    await tester.tap(find.text('Game'));
    await _settle(tester);
    expect(find.text('Game'), findsOneWidget);

    await tester.tap(find.text('1080'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('share-go-live')));
    await _settle(tester);
    expect(find.text('Screen Share'), findsNothing);
  });

  testWidgets('changing a live stream picks a source without a quality step', (
    tester,
  ) async {
    await tester.pumpWidget(_host(changing: true));
    await tester.tap(find.text('share'));
    await _settle(tester);
    await tester.tap(find.text('Browser'));
    await _settle(tester);
    expect(find.text('Screen Share'), findsNothing);
    expect(find.text("WHAT YOU'RE STREAMING"), findsNothing);
  });
}
