import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/member/views/full_profile.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Settings extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

void main() {
  testWidgets('a full profile can send a friend request', (tester) async {
    final requests = <http.Request>[];
    final server = AccordServer.fromBaseUrl('https://accord.example.test');
    final client = AccordClient(
      token: 't',
      baseUrl: server.baseUrl,
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'data': request.method == 'GET' ? [] : null}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(_Settings.new),
          accordAuthProvider.overrideWithValue(
            AccordAuthLoggedIn(
              client: client,
              session: AccordSession(
                server: server,
                token: 't',
                userId: 'me',
                username: 'me',
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showFullProfile(context, userId: 'u2'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // The full profile's add-friend button.
    expect(find.byTooltip('Add Friend'), findsOneWidget);

    await tester.tap(find.byKey(const Key('full-profile-friend')));
    await tester.pumpAndSettle();
    final put = requests.firstWhere((r) => r.method == 'PUT');
    expect(put.url.path, endsWith('/users/@me/relationships/u2'));
    expect(jsonDecode(put.body), {'type': 1});
  });
}
