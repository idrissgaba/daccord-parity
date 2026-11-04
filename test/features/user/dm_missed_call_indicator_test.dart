import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/voice/controllers/missed_calls.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dm_home_host.dart';

/// A [DmChannelsController] exposing a fixed conversation list, so the DM
/// dialog renders without a server.
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

AccordChannel _dm(String id, String withName) => AccordChannel(
  id: id,
  type: 'dm',
  recipients: [AccordUser(id: 'u2', username: withName)],
);

void main() {
  late ProviderContainer container;

  Future<void> openDialog(WidgetTester tester) async {
    resetDmHomeAfter();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: const DmHomeHost(),
        ),
      ),
    );
    await tester.tap(find.text('open dms'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    container = ProviderContainer(
      overrides: [
        settingsControllerProvider.overrideWith(_FakeSettingsController.new),
        dmChannelsControllerProvider(
          '',
        ).overrideWith(() => _FakeDmChannels([_dm('dm1', 'bob')])),
      ],
    );
  });

  tearDown(() => container.dispose());

  testWidgets('no missed call means no indicator', (tester) async {
    await openDialog(tester);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('Missed call'), findsNothing);
  });

  testWidgets('a missed call labels the conversation in the DM list', (
    tester,
  ) async {
    container
        .read(missedCallsControllerProvider.notifier)
        .record(channelId: 'dm1', callerId: 'u2');

    await openDialog(tester);

    expect(find.text('Missed call'), findsOneWidget);
  });

  testWidgets('repeat misses show the count', (tester) async {
    final missed = container.read(missedCallsControllerProvider.notifier);
    missed.record(channelId: 'dm1', callerId: 'u2', video: true);
    missed.record(channelId: 'dm1', callerId: 'u2', video: true);

    await openDialog(tester);

    expect(find.text('Missed call (2)'), findsOneWidget);
  });

  testWidgets('opening the conversation clears the indicator', (tester) async {
    container
        .read(missedCallsControllerProvider.notifier)
        .record(channelId: 'dm1', callerId: 'u2');

    await openDialog(tester);
    expect(find.text('Missed call'), findsOneWidget);

    // Open the conversation, then go back to the Friends page. There is no
    // client in this harness, so the shared message pane remains in its
    // loading state; pump explicit frames rather than waiting for it to settle.
    await tester.tap(find.text('bob').first);
    await tester.pump();
    await tester.pump();
    expect(container.read(missedCallsControllerProvider), isEmpty);

    await tester.tap(find.byKey(const Key('dm-home-friends')));
    await tester.pump();

    expect(find.text('bob'), findsOneWidget);
    expect(find.text('Missed call'), findsNothing);
  });

  testWidgets('conversation uses the shared channel message controls', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.tap(find.text('bob'));
    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('Pinned Messages'), findsOneWidget);
    // The attach tooltip now carries the server's limits after the label
    // (#330), so match on its prefix rather than the exact string.
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message?.startsWith('Attach files') == true,
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Emoji'), findsOneWidget);
    expect(find.byTooltip('Start Voice Call'), findsOneWidget);
    expect(find.byTooltip('Start Video Call'), findsOneWidget);
  });

  testWidgets('long-pressing a DM user opens their context menu', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.longPress(find.text('bob'));
    await tester.pumpAndSettle();

    expect(find.text('View profile'), findsOneWidget);
    expect(find.text('Copy user ID'), findsOneWidget);
    expect(find.text('Close DM'), findsOneWidget);
  });

  testWidgets('opening a different conversation keeps the indicator', (
    tester,
  ) async {
    container.updateOverrides([
      settingsControllerProvider.overrideWith(_FakeSettingsController.new),
      dmChannelsControllerProvider('').overrideWith(
        () => _FakeDmChannels([_dm('dm1', 'bob'), _dm('dm2', 'carol')]),
      ),
    ]);
    container
        .read(missedCallsControllerProvider.notifier)
        .record(channelId: 'dm1', callerId: 'u2');

    await openDialog(tester);
    await tester.tap(find.text('carol'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('dm-home-friends')));
    await tester.pump();

    expect(container.read(missedCallsControllerProvider).keys, ['dm1']);
    expect(find.text('Missed call'), findsOneWidget);
  });
}
