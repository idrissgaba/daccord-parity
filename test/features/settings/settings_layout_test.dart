import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/settings/views/accord_settings_screen.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps the screen off Hive (the real controller reads the `accord-settings`
/// box in `build`).
class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

Widget _host({double textScale = 1.0, SettingsPage? page}) => ProviderScope(
  overrides: [
    settingsControllerProvider.overrideWith(_FakeSettingsController.new),
  ],
  child: MaterialApp(
    theme: buildAppTheme(AppThemePreset.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(body: AccordSettingsScreen(initialPage: page)),
  ),
);

Future<void> _pumpAt(
  WidgetTester tester,
  Size size, {
  double textScale = 1.0,
  SettingsPage? page,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(textScale: textScale, page: page));
  await tester.pumpAndSettle();
}

Finder _modal() => find.byKey(const ValueKey('settings-modal'));
Finder _sidebar() => find.byKey(const ValueKey('settings-sidebar'));
Finder _nav(SettingsPage page) =>
    find.byKey(ValueKey('settings-nav-${page.name}'));
Finder _title(String text) => find.text(text);

Future<void> _open(WidgetTester tester, SettingsPage page) async {
  await tester.ensureVisible(_nav(page));
  await tester.tap(_nav(page));
  await tester.pumpAndSettle();
}

void main() {
  group('desktop: the reference client\'s settings modal', () {
    testWidgets('a centred 1400 px modal clear of the window edges', (
      tester,
    ) async {
      await _pumpAt(tester, const Size(1920, 927));

      expect(_modal(), findsOneWidget);
      final rect = tester.getRect(_modal());
      expect(rect.width, 1400);
      expect(rect.top, 72);
      expect(rect.bottom, 927 - 72);
      expect(rect.center.dx, 960);
      expect(find.byKey(const Key('settings-close')), findsOneWidget);
    });

    testWidgets(
      'the sidebar lists every page in the 2026 order, Log Out last',
      (tester) async {
        await _pumpAt(tester, const Size(1920, 1600));

        final pages = visibleSettingsPages();
        for (var i = 1; i < pages.length; i++) {
          expect(
            tester.getTopLeft(_nav(pages[i])).dy,
            greaterThan(tester.getTopLeft(_nav(pages[i - 1])).dy),
            reason: '${pages[i - 1].name} before ${pages[i].name}',
          );
        }
        expect(find.text('Experience'), findsOneWidget);
        expect(find.text('Games & Apps'), findsOneWidget);
        final logOut = find.byKey(const ValueKey('settings-nav-logout'));
        expect(
          tester.getTopLeft(logOut).dy,
          greaterThan(tester.getTopLeft(_nav(pages.last)).dy),
        );
      },
    );

    testWidgets(
      'the selected page shows its sub-sections, anchored on the page',
      (tester) async {
        await _pumpAt(tester, const Size(1920, 927));
        await _open(tester, SettingsPage.appearance);

        expect(find.byKey(const Key('settings-page-title')), findsOneWidget);
        for (final sub in visibleSubs(SettingsPage.appearance)) {
          expect(
            find.byKey(ValueKey('settings-sub-${sub.id}')),
            findsOneWidget,
            reason: sub.id,
          );
        }
        // Another page's sections stay folded.
        expect(find.byKey(const ValueKey('settings-sub-camera')), findsNothing);

        await tester.tap(
          find.byKey(const ValueKey('settings-sub-streamer-mode')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('settings-streamer-mode')).hitTestable(),
          findsOneWidget,
        );
      },
    );

    testWidgets('every page renders', (tester) async {
      await _pumpAt(tester, const Size(1920, 927));
      for (final page in visibleSettingsPages()) {
        await _open(tester, page);
        expect(tester.takeException(), isNull, reason: page.name);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('settings-page-title')))
              .data,
          page.label,
          reason: page.name,
        );
      }
    });

    testWidgets('search narrows the sidebar to matching pages and sections', (
      tester,
    ) async {
      await _pumpAt(tester, const Size(1920, 927));
      await tester.enterText(find.byKey(const Key('settings-search')), 'cam');
      await tester.pumpAndSettle();

      expect(_nav(SettingsPage.voiceVideo), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-sub-camera')), findsOneWidget);
      expect(_nav(SettingsPage.appearance), findsNothing);
    });

    testWidgets('opens on the page it was asked for', (tester) async {
      await _pumpAt(tester, const Size(1920, 927), page: SettingsPage.system);
      expect(
        tester.widget<Text>(find.byKey(const Key('settings-page-title'))).data,
        'System',
      );
    });

    testWidgets('holds up at 150% text scale', (tester) async {
      await _pumpAt(tester, const Size(1200, 900), textScale: 1.5);
      expect(_sidebar(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _open(tester, SettingsPage.appearance);
      expect(tester.takeException(), isNull);
    });
  });

  group('phones: a page list', () {
    testWidgets('lists the pages and opens one on its own screen', (
      tester,
    ) async {
      await _pumpAt(tester, const Size(400, 1600));

      expect(_modal(), findsNothing);
      expect(find.byKey(const ValueKey('settings-page-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-nav-logout')), findsOneWidget);

      await tester.tap(_nav(SettingsPage.accessibility));
      await tester.pumpAndSettle();
      expect(_title('Text Readability'), findsOneWidget);
      expect(_title('Reduced Motion'), findsWidgets);
    });
  });

  // Apple rejected 0.2.16 under guideline 2.2 partly because the store build
  // shipped a live GitHub self-updater and a Developer Mode / local MCP server
  // toggle — both of which read as an unfinished, non-store build (#292).
  group('app store builds', () {
    setUp(() => debugAppStoreBuild = true);
    tearDown(() => debugAppStoreBuild = null);

    testWidgets('hide Updates under System', (tester) async {
      await _pumpAt(tester, const Size(1920, 1600));
      await _open(tester, SettingsPage.system);

      expect(find.byKey(const ValueKey('settings-sub-updates')), findsNothing);
      expect(find.text('Check for Updates'), findsNothing);
      // The rest of System is untouched.
      expect(find.byKey(const ValueKey('settings-sub-backup')), findsOneWidget);
    });

    testWidgets('hide the Developer page', (tester) async {
      await _pumpAt(tester, const Size(1920, 927));
      expect(_nav(SettingsPage.developer), findsNothing);
      expect(find.text('Developer Mode'), findsNothing);
    });
  });

  group('platforms without a local MCP server (mobile / web)', () {
    setUp(() => debugDeveloperModeAvailable = false);
    tearDown(() => debugDeveloperModeAvailable = null);

    testWidgets('hide the Developer page, keep Updates', (tester) async {
      await _pumpAt(tester, const Size(1920, 1600));
      expect(_nav(SettingsPage.developer), findsNothing);

      await _open(tester, SettingsPage.system);
      expect(
        find.byKey(const ValueKey('settings-sub-updates')),
        findsOneWidget,
      );
    });
  });
}
