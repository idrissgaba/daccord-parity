import 'package:bonfire/theme/app_icons.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/shared/components/accord_slider.dart';
import 'package:bonfire/shared/components/color_swatch_chip.dart';
import 'package:bonfire/features/settings/views/settings_sound_row.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/shared/components/escape_to_close.dart';
import 'package:bonfire/shared/components/settings_controls.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/utils/confirm_logout.dart';
import 'package:bonfire/features/developer/views/developer_settings_page.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/messaging/utils/emoji_catalog.dart';
import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/views/settings_anchors.dart';
import 'package:bonfire/features/profiles/views/profiles_page.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/settings/views/connections_settings_page.dart';
import 'package:bonfire/features/settings/views/keybinds_section.dart';
import 'package:bonfire/features/settings/views/privacy_settings_page.dart';
import 'package:bonfire/features/settings/views/settings_backup.dart';
import 'package:bonfire/features/onboarding/views/onboarding_help.dart';
import 'package:bonfire/features/onboarding/views/onboarding_tour.dart';
import 'package:bonfire/features/updates/views/updates_page.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/user/views/accord_account_settings.dart';
import 'package:bonfire/features/user/views/accord_profile_edit.dart';
import 'package:bonfire/features/authentication/views/terms_gate.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/external_url.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/features/voice/views/voice_settings_screen.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

part 'settings_screen/modal.dart';
part 'settings_screen/narrow.dart';
part 'settings_screen/pages.dart';
part 'settings_screen/sections.dart';

/// Opens the user settings on [page] (the reference client's settings modal
/// on desktop, a page list on phones): the `/settings` route when the app
/// routes with go_router, otherwise the same see-through page pushed on the
/// nearest navigator.
Future<void> showUserSettings(BuildContext context, {SettingsPage? page}) {
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    return router.push(
      page == null ? '/settings' : '/settings?page=${page.name}',
    );
  }
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      pageBuilder: (_, _, _) => EscapeToClose(
        child: AccordSettingsScreen(initialPage: page),
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// The headings that group the sidebar ("Experience", "Games & Apps").
enum SettingsGroup {
  user(null),
  experience('Experience'),
  apps('Games & Apps'),
  developer(null);

  const SettingsGroup(this.label);

  final String? label;
}

/// A section of a settings page, reachable from the sidebar.
class SettingsSub {
  const SettingsSub(this.id, this.label);

  final String id;
  final String label;
}

/// The settings pages in the reference client's 2026 sidebar order. Billing,
/// Nitro, Family Centre, Activity Privacy, Messaging Permissions and Language
/// & Time have no Accord counterpart and are left out (DISCORD_PARITY §4).
enum SettingsPage {
  account(
    'Account',
    AppIcons.personOutline,
    SettingsGroup.user,
    [
      SettingsSub('account-info', 'Account Info'),
      SettingsSub('password-security', 'Password & Security'),
    ],
  ),
  dataPrivacy(
    'Data & Privacy',
    AppIcons.shieldOutlined,
    SettingsGroup.user,
    [],
  ),
  notifications(
    'Notifications',
    AppIcons.notificationsNone,
    SettingsGroup.user,
    [
      SettingsSub('notifications-overview', 'Overview'),
      SettingsSub('notifications-sounds', 'Sounds'),
    ],
  ),
  voiceVideo(
    'Voice & Video',
    AppIcons.micNone,
    SettingsGroup.experience,
    [
      SettingsSub('voice', 'Voice'),
      SettingsSub('camera', 'Camera'),
      SettingsSub('streaming', 'Streaming'),
      SettingsSub('voice-sounds', 'Sounds'),
      SettingsSub('soundboard', 'Soundboard'),
      SettingsSub('voice-advanced', 'Advanced'),
    ],
  ),
  appearance(
    'Appearance',
    AppIcons.paletteOutlined,
    SettingsGroup.experience,
    [
      SettingsSub('theme', 'Theme'),
      SettingsSub('messages', 'Messages'),
      SettingsSub('chat-box', 'Chat Box'),
      SettingsSub('streamer-mode', 'Streamer Mode'),
    ],
  ),
  accessibility(
    'Accessibility',
    AppIcons.accessibilityNewOutlined,
    SettingsGroup.experience,
    [
      SettingsSub('text-readability', 'Text Readability'),
      SettingsSub('visual-density', 'Visual Density'),
      SettingsSub('colour-contrast', 'Colour & Contrast'),
      SettingsSub('reduced-motion', 'Reduced Motion'),
    ],
  ),
  system(
    'System',
    AppIcons.keyboardOutlined,
    SettingsGroup.experience,
    [
      SettingsSub('keybinds', 'Keybinds'),
      SettingsSub('desktop', 'Windows Settings'),
      SettingsSub('updates', 'Updates'),
      SettingsSub('backup', 'Backup'),
      SettingsSub('system-advanced', 'Advanced'),
    ],
  ),
  connectedApps(
    'Connected Apps',
    AppIcons.link,
    SettingsGroup.apps,
    [],
  ),
  developer('Developer', AppIcons.code, SettingsGroup.developer, []);

  const SettingsPage(this.label, this.icon, this.group, this.subs);

  final String label;
  final IconData icon;
  final SettingsGroup group;
  final List<SettingsSub> subs;

  static SettingsPage? fromName(String? name) {
    for (final page in values) {
      if (page.name == name) return page;
    }
    return null;
  }
}

/// The pages this build shows, with the sub-sections that apply here: the
/// self-updater and Developer Mode never appear in store builds (#292), the
/// tray setting only on Windows and Linux.
List<SettingsPage> visibleSettingsPages() => [
  for (final page in SettingsPage.values)
    if (page != SettingsPage.developer || isDeveloperModeAvailable) page,
];

List<SettingsSub> visibleSubs(SettingsPage page) => [
  for (final sub in page.subs)
    if (switch (sub.id) {
      'desktop' => UniversalPlatform.isWindows || UniversalPlatform.isLinux,
      'updates' => isSelfUpdateEnabled,
      _ => true,
    })
      sub.id == 'desktop' && UniversalPlatform.isLinux
          ? const SettingsSub('desktop', 'Linux Settings')
          : sub,
];

/// Window width from which the settings open as the centred modal.
const double kSettingsModalBreakpoint = 760;

/// User settings. On desktop-sized windows the reference client's centred
/// modal (sidebar + page, ✕ and Escape close it, sub-sections are anchors);
/// below [kSettingsModalBreakpoint] a list of pages, each opening on its own.
class AccordSettingsScreen extends ConsumerWidget {
  const AccordSettingsScreen({super.key, this.initialPage});

  final SettingsPage? initialPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> logOut() async {
      if (!await confirmLogout(context)) return;
      if (!context.mounted) return;
      ref.read(accordAuthProvider.notifier).logout();
      if (context.mounted) context.go('/');
    }

    void close() {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        GoRouter.maybeOf(context)?.go('/spaces');
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kSettingsModalBreakpoint) {
          return _SettingsModal(
            initialPage: initialPage ?? SettingsPage.account,
            onLogOut: logOut,
            onClose: close,
          );
        }
        return _NarrowSettings(
          initialPage: initialPage,
          onLogOut: logOut,
          onClose: close,
        );
      },
    );
  }
}
