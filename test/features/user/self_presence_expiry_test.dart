import 'dart:io';

import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/user/controllers/self_presence.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Timed mutes and statuses ("For 1 Hour", "Clear after") are lifted when
/// their time comes — also on the next launch when it passed meanwhile.
void main() {
  const server = 'me@https://server.example';
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('accord-expiry-test');
    Hive.init(tempDir.path);
    await Hive.openBox('accord-settings');
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk('accord-settings');
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('a timed server mute ends at its time', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final settings = container.read(settingsControllerProvider.notifier);
    settings.setSpaceMuted(
      server,
      'sp',
      true,
      until: DateTime.now().add(const Duration(milliseconds: 150)),
    );
    expect(
      container.read(settingsControllerProvider).isSpaceMuted(server, 'sp'),
      isTrue,
    );

    container.read(selfPresenceControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final state = container.read(settingsControllerProvider);
    expect(state.isSpaceMuted(server, 'sp'), isFalse);
    expect(state.muteExpiries, isEmpty);
  });

  test('an already expired server mute is lifted at start-up', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(settingsControllerProvider.notifier)
        .setSpaceMuted(
          server,
          'sp',
          true,
          until: DateTime.now().subtract(const Duration(minutes: 1)),
        );
    container.read(selfPresenceControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      container.read(settingsControllerProvider).isSpaceMuted(server, 'sp'),
      isFalse,
    );
  });

  test('a mute until turned back on has no timer and stays', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(settingsControllerProvider.notifier)
        .setSpaceMuted(server, 'sp', true);
    container.read(selfPresenceControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final state = container.read(settingsControllerProvider);
    expect(state.isSpaceMuted(server, 'sp'), isTrue);
    expect(state.muteExpiry(server, 'sp'), isNull);
  });

  test('a timed status of a disconnected server drops its timer', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(settingsControllerProvider.notifier)
        .setStatusExpiry(
          server,
          DateTime.now().subtract(const Duration(seconds: 1)),
        );
    container.read(selfPresenceControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(settingsControllerProvider).statusExpiries, isEmpty);
  });
}
