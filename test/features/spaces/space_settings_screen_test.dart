import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/accord_space_settings.dart';
import 'package:bonfire/shared/components/unsaved_changes_bar.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Lot G: the full-screen server settings — the reference client's sidebar
/// for what the user may open, the shared Server Profile / Engagement /
/// Access draft behind the unsaved-changes bar (leaving only warns), the
/// tabbed role editor, and Create Expressions on the Emoji page.

final _server = AccordServer.fromBaseUrl('https://accord.example.test');
final _session = AccordSession(
  server: _server,
  token: 't',
  userId: 'me',
  username: 'me',
);

class _Spaces extends SpacesController {
  _Spaces(this.spaces);
  final List<AccordSpace> spaces;
  @override
  List<AccordSpace> build() => spaces;
}

class _Settings extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

AccordSpace _space({String owner = 'me', List<String> perms = const []}) =>
    AccordSpace(
      id: 's1',
      name: 'Vale',
      ownerId: owner,
      roles: [
        AccordRole(id: 'everyone', name: '@everyone', permissions: perms),
        AccordRole(id: 'mods', name: 'Mods', position: 1, color: 0x2ECC71),
      ],
    );

class _Host {
  final requests = <http.Request>[];

  late final client = AccordClient(
    token: 't',
    tokenType: 'Bearer',
    baseUrl: _server.baseUrl,
    gatewayUrl: _server.gatewayUrl,
    cdnUrl: _server.cdnUrl,
    httpClient: MockClient((request) async {
      requests.add(request);
      Object body = const <Object>[];
      if (request.method == 'PATCH' &&
          request.url.path.endsWith('/spaces/s1')) {
        final sent = jsonDecode(request.body) as Map<String, dynamic>;
        body = {'id': 's1', 'name': sent['name'], 'owner_id': 'me'};
      }
      return http.Response(
        jsonEncode({'data': body}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );

  Widget wrap(AccordSpace space, {String? page}) => ProviderScope(
    overrides: [
      accordAuthProvider.overrideWithValue(
        AccordAuthLoggedIn(client: client, session: _session),
      ),
      spacesControllerProvider.overrideWith(() => _Spaces([space])),
      settingsControllerProvider.overrideWith(_Settings.new),
    ],
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showAccordSpaceSettings(
                context,
                spaceId: 's1',
                serverKey: '',
                page: page,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<_Host> _open(
  WidgetTester tester,
  AccordSpace space, {
  String? page,
}) async {
  tester.view.physicalSize = const Size(1920, 927);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final host = _Host();
  await tester.pumpWidget(host.wrap(space, page: page));
  await tester.tap(find.text('open'));
  await _settle(tester);
  return host;
}

Finder _nav(String key) => find.byKey(Key('space-settings-nav-$key'));

void main() {
  testWidgets('the owner sees the whole sidebar, Delete Server last', (
    tester,
  ) async {
    await _open(tester, _space());
    for (final key in [
      SpaceSettingsPages.profile,
      SpaceSettingsPages.engagement,
      SpaceSettingsPages.emoji,
      SpaceSettingsPages.stickers,
      SpaceSettingsPages.soundboard,
      SpaceSettingsPages.members,
      SpaceSettingsPages.roles,
      SpaceSettingsPages.invites,
      SpaceSettingsPages.access,
      SpaceSettingsPages.integrations,
      SpaceSettingsPages.auditLog,
      SpaceSettingsPages.bans,
      SpaceSettingsPages.automod,
      SpaceSettingsPages.delete,
    ]) {
      expect(_nav(key), findsOneWidget, reason: key);
    }
    expect(find.text('Server Profile'), findsWidgets);
  });

  testWidgets(
    'a member with Create Expressions only gets the Expression pages',
    (tester) async {
      await _open(
        tester,
        _space(
          owner: 'someone',
          perms: const [AccordPermission.createExpressions],
        ),
      );
      expect(_nav(SpaceSettingsPages.emoji), findsOneWidget);
      expect(_nav(SpaceSettingsPages.stickers), findsOneWidget);
      expect(_nav(SpaceSettingsPages.soundboard), findsOneWidget);
      expect(_nav(SpaceSettingsPages.profile), findsNothing);
      expect(_nav(SpaceSettingsPages.roles), findsNothing);
      expect(_nav(SpaceSettingsPages.delete), findsNothing);
      // They may upload.
      final upload = tester.widget<InkWell>(
        find.descendant(
          of: find.byKey(const Key('emoji-upload')),
          matching: find.byType(InkWell),
        ),
      );
      expect(upload.onTap, isNotNull);
    },
  );

  testWidgets(
    'editing the name brings up the bar; leaving warns; Reset undoes',
    (tester) async {
      await _open(tester, _space());
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('space-settings-name')),
          matching: find.byType(TextField),
        ),
        'Vale 2',
      );
      await _settle(tester);
      expect(find.text('Careful – you have unsaved changes!'), findsOneWidget);
      final bar = tester.widget<UnsavedChangesBar>(
        find.byType(UnsavedChangesBar),
      );
      expect(bar.visible, isTrue);

      // Another page is refused: the bar turns red, the page stays.
      await tester.tap(_nav(SpaceSettingsPages.roles));
      await _settle(tester);
      expect(
        tester
            .widget<UnsavedChangesBar>(find.byType(UnsavedChangesBar))
            .warning,
        isTrue,
      );
      expect(find.byKey(const Key('space-settings-name')), findsOneWidget);

      // So is closing.
      await tester.tap(find.byKey(const Key('space-settings-close')));
      await _settle(tester);
      expect(find.byKey(const Key('space-settings-name')), findsOneWidget);

      await tester.tap(find.byKey(const Key('unsaved-changes-reset')));
      await _settle(tester);
      expect(
        tester
            .widget<UnsavedChangesBar>(find.byType(UnsavedChangesBar))
            .visible,
        isFalse,
      );
      await tester.tap(_nav(SpaceSettingsPages.roles));
      await _settle(tester);
      expect(find.byKey(const Key('roles-create')), findsOneWidget);
    },
  );

  testWidgets('Save Changes sends the draft in one update', (tester) async {
    final host = await _open(tester, _space());
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('space-settings-name')),
        matching: find.byType(TextField),
      ),
      'Vale 2',
    );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('unsaved-changes-save')));
    await _settle(tester);
    final patch = host.requests.lastWhere((r) => r.method == 'PATCH');
    expect(jsonDecode(patch.body)['name'], 'Vale 2');
  });

  testWidgets('the role editor has Display, Permissions and Manage Members', (
    tester,
  ) async {
    await _open(tester, _space(), page: SpaceSettingsPages.roles);
    await tester.tap(find.byKey(const ValueKey('role-row-mods')));
    await _settle(tester);
    expect(find.text('Edit Role – Mods'), findsOneWidget);
    expect(find.byKey(const Key('role-tab-display')), findsOneWidget);
    expect(find.byKey(const Key('role-tab-permissions')), findsOneWidget);
    expect(find.byKey(const Key('role-tab-members')), findsOneWidget);
    expect(find.byKey(const Key('role-name')), findsOneWidget);

    await tester.tap(find.byKey(const Key('role-tab-permissions')));
    await _settle(tester);
    expect(find.text('General Server Permissions'), findsOneWidget);
    await tester.tap(
      find.byKey(Key('role-perm-${AccordPermission.viewChannel}')),
    );
    await _settle(tester);
    expect(find.text('Careful – you have unsaved changes!'), findsOneWidget);

    // Back to the list is refused while the role has edits.
    await tester.tap(find.byKey(const Key('roles-back')));
    await _settle(tester);
    expect(find.text('Edit Role – Mods'), findsOneWidget);
  });

  testWidgets('@everyone opens on Permissions', (tester) async {
    await _open(tester, _space(), page: SpaceSettingsPages.roles);
    await tester.tap(find.byKey(const Key('roles-default-permissions')));
    await _settle(tester);
    expect(find.text('Edit Role – @everyone'), findsOneWidget);
    expect(find.byKey(const Key('role-permission-search')), findsOneWidget);
    expect(find.byKey(const Key('role-name')), findsNothing);
  });
}
