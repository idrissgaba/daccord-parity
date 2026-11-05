import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/settings/models/custom_keybind.dart';
import 'package:bonfire/features/spaces/utils/home_shortcuts.dart';
import 'package:bonfire/features/spaces/views/keyboard_shortcuts_dialog.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Settings extends SettingsController {
  _Settings(this.initial);
  final AccordSettings initial;
  @override
  AccordSettings build() => initial;
}

Future<void> _pump(WidgetTester tester, AccordSettings settings) async {
  tester.view.physicalSize = const Size(1920, 927);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsControllerProvider.overrideWith(() => _Settings(settings)),
      ],
      child: MaterialApp(
        theme: buildAppTheme(AppThemePreset.dark),
        home: const Scaffold(body: Center(child: KeyboardShortcutsDialog())),
      ),
    ),
  );
}

void main() {
  testWidgets('Keyboard Combos lists the sections in order with their cards', (
    tester,
  ) async {
    await _pump(tester, const AccordSettings());
    expect(find.text('Keyboard Combos'), findsOneWidget);
    expect(
      find.text('Master these to be the greatest Daccord Revolution player'),
      findsOneWidget,
    );
    final titles = ['Navigation', 'Voice and Video', 'Chat', 'Miscellaneous'];
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    for (var i = 1; i < titles.length; i++) {
      await tester.scrollUntilVisible(find.text(titles[i]), 200);
      expect(find.text(titles[i]), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('Search'), 200);
    expect(find.text('Get help'), findsOneWidget);
    // No message section: this client has no focused message.
    expect(find.text('Messages'), findsNothing);
    expect(find.text('Edit Message'), findsNothing);
    expect(top('Get help'), lessThan(top('Search') + 1));
  });

  testWidgets('a recorded keybind replaces the built-in chord', (tester) async {
    await _pump(
      tester,
      AccordSettings(
        keybinds: [
          CustomKeybind(
            action: HomeShortcut.quickSwitcher.name,
            keyId: LogicalKeyboardKey.keyJ.keyId,
            keyLabel: 'J',
            control: true,
            shift: true,
          ),
        ],
      ),
    );
    final card = find.ancestor(
      of: find.text('Toggle QuickSwitcher'),
      matching: find.byType(Container),
    );
    expect(
      find.descendant(of: card.first, matching: find.text('J')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card.first, matching: find.text('K')),
      findsNothing,
    );
  });
}
