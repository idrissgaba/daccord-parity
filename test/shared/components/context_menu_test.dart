import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The single Accord menu (lot F): anchored rows, cascading submenus,
/// disabled rows kept in place, the keyboard.
void main() {
  Future<void> open(WidgetTester tester, List<AccordMenuEntry> entries) async {
    // Landscape: the anchored (desktop) form.
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemePreset.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAccordContextMenu(
                  context,
                  entries: entries,
                  globalPosition: const Offset(200, 200),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<TestGesture> hover(WidgetTester tester, Finder finder) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(finder));
    await tester.pumpAndSettle();
    return gesture;
  }

  testWidgets('a submenu opens beside its row on hover and acts on pick', (
    tester,
  ) async {
    String? picked;
    await open(tester, [
      AccordMenuEntry(label: 'Invite to Server', onSelected: () {}),
      AccordMenuEntry(
        label: 'Mute Server',
        submenu: [
          AccordMenuEntry(label: 'For 1 Hour', onSelected: () => picked = '1h'),
        ],
      ),
    ]);
    expect(find.text('For 1 Hour'), findsNothing);

    await hover(tester, find.text('Mute Server'));
    expect(find.text('For 1 Hour'), findsOneWidget);
    // Beside its row, overlapping the parent by a few pixels.
    final row = tester.getRect(find.text('Mute Server'));
    final sub = tester.getRect(find.text('For 1 Hour'));
    expect(sub.left, greaterThan(row.right));
    expect((sub.center.dy - row.center.dy).abs(), lessThan(4));

    await tester.tap(find.text('For 1 Hour'));
    await tester.pumpAndSettle();
    expect(picked, '1h');
    expect(find.text('Invite to Server'), findsNothing);
  });

  testWidgets('a row without an action stays, greyed, and does nothing', (
    tester,
  ) async {
    await open(tester, const [
      AccordMenuEntry(label: 'Mark as Read'),
      AccordMenuEntry.divider(),
      AccordMenuEntry.divider(),
      AccordMenuEntry(label: 'Copy Server ID'),
    ]);
    expect(find.text('Mark as Read'), findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.text('Mark as Read'),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(opacity.opacity, 0.5);
    await tester.tap(find.text('Mark as Read'));
    await tester.pumpAndSettle();
    // Still open: the row is disabled.
    expect(find.text('Copy Server ID'), findsOneWidget);
  });

  testWidgets('the keyboard walks rows, opens a submenu with → and picks', (
    tester,
  ) async {
    String? picked;
    await open(tester, [
      AccordMenuEntry(label: 'Profile', onSelected: () => picked = 'profile'),
      AccordMenuEntry(
        label: 'Roles',
        submenu: [
          AccordMenuEntry(
            label: 'Makers',
            checked: false,
            onSelected: () => picked = 'makers',
          ),
        ],
      ),
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Makers'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, 'makers');
  });

  testWidgets('Escape closes a submenu first, then the menu', (tester) async {
    await open(tester, [
      AccordMenuEntry(
        label: 'Move to…',
        submenu: [AccordMenuEntry(label: 'First in List', onSelected: () {})],
      ),
    ]);
    await hover(tester, find.text('Move to…'));
    expect(find.text('First in List'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('First in List'), findsNothing);
    expect(find.text('Move to…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Move to…'), findsNothing);
  });

  testWidgets('a menu is as wide as its widest row, at least 144 px', (
    tester,
  ) async {
    await open(tester, [AccordMenuEntry(label: 'Pin', onSelected: () {})]);
    final panel = tester.getRect(
      find
          .ancestor(of: find.text('Pin'), matching: find.byType(Positioned))
          .first,
    );
    expect(panel.width, kAccordMenuMinWidth);
  });
}
