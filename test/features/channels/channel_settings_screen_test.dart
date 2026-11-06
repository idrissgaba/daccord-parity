import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/views/channel_management.dart';
import 'package:bonfire/shared/components/unsaved_changes_bar.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lot G: Edit Channel is the reference client's full-screen channel settings
/// — Overview / Permissions / Invites / Integrations / Delete Channel — and
/// Overview edits wait behind the unsaved-changes bar.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  testWidgets('Edit Channel: pages, the bar, a refused close, Reset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 927);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final channel = AccordChannel(
      id: 'c1',
      spaceId: 's1',
      name: 'general',
      type: 'text',
      topic: 'hello',
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showEditChannelDialog(
                  context,
                  spaceId: 's1',
                  channel: channel,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);

    for (final key in [
      'overview',
      'permissions',
      'invites',
      'integrations',
      'delete',
    ]) {
      expect(
        find.byKey(Key('space-settings-nav-$key')),
        findsOneWidget,
        reason: key,
      );
    }
    expect(find.text('Delete Channel'), findsOneWidget);
    expect(find.byKey(const Key('channel-topic-toolbar')), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('channel-name')),
        matching: find.byType(TextField),
      ),
      'generalx',
    );
    await _settle(tester);
    expect(
      tester.widget<UnsavedChangesBar>(find.byType(UnsavedChangesBar)).visible,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('space-settings-close')));
    await _settle(tester);
    expect(find.byKey(const Key('channel-name')), findsOneWidget);
    expect(
      tester.widget<UnsavedChangesBar>(find.byType(UnsavedChangesBar)).warning,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('unsaved-changes-reset')));
    await _settle(tester);
    expect(find.text('generalx'), findsNothing);
    await tester.tap(find.byKey(const Key('space-settings-close')));
    await _settle(tester);
    expect(find.byKey(const Key('channel-name')), findsNothing);
  });
}
