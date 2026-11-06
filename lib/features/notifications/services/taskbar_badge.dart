import 'package:bonfire/features/channels/controllers/global_unread.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:universal_platform/universal_platform.dart';

part 'taskbar_badge.g.dart';

/// Method channel to the desktop runners' badge implementations:
///
///  * macOS   — `NSApp.dockTile.badgeLabel` (`macos/Runner/MainFlutterWindow.swift`)
///  * Windows — `ITaskbarList3::SetOverlayIcon` (`windows/runner/taskbar_badge.cpp`)
///  * Linux   — `com.canonical.Unity.LauncherEntry` D-Bus signal
///              (`linux/taskbar_badge.cc`)
///
/// One `setBadge` method, `{count: int, visible: bool}`; each runner picks the
/// native presentation (numeral vs dot) so the Dart side stays platform-blind.
const MethodChannel taskbarBadgeChannel = MethodChannel(
  'com.daccord.app/taskbar_badge',
);

/// Whether this platform has a taskbar/dock badge at all. Web and mobile
/// no-op: mobile app-icon badges need background delivery to be useful.
bool get taskbarBadgeSupported =>
    !UniversalPlatform.isWeb &&
    (UniversalPlatform.isMacOS ||
        UniversalPlatform.isWindows ||
        UniversalPlatform.isLinux);

/// Pushes one badge state to the platform. Safe to call anywhere: a no-op off
/// desktop, and failures (an old runner without the channel, no D-Bus session
/// bus, no taskbar) are swallowed — a badge is never worth an error dialog.
Future<void> pushTaskbarBadge(GlobalUnread unread) async {
  if (!taskbarBadgeSupported) return;
  try {
    await taskbarBadgeChannel.invokeMethod<void>('setBadge', {
      'count': unread.mentionCount,
      'visible': !unread.isEmpty,
    });
  } on MissingPluginException {
    // Runner predates the badge channel (e.g. a stale incremental build).
  } catch (e) {
    debugPrint('Taskbar badge update failed: $e');
  }
}

/// Mirrors [globalUnreadProvider] onto the OS taskbar/dock icon, live —
/// including while the window is minimised or backgrounded. Kept alive by a
/// `ref.watch` in `MainWindow`.
@Riverpod(keepAlive: true)
class TaskbarBadgeController extends _$TaskbarBadgeController {
  GlobalUnread? _pushed;

  @override
  void build() {
    if (!taskbarBadgeSupported) return;
    // Deliberately no `ref.onDispose` clear: Riverpod runs those before every
    // *rebuild* too, which would clear-then-reset the badge on each new
    // message (a visible flicker on Windows, an extra bus round-trip on Linux).
    // The startup push below covers the case it would have handled — a badge
    // outliving the state that produced it.
    // Notifications › Badges › Enable Unread Message Badge.
    final badgeOn = ref.watch(
      settingsControllerProvider.select((s) => s.unreadBadgeEnabled),
    );
    final unread = badgeOn
        ? ref.watch(globalUnreadProvider)
        : const GlobalUnread();
    // Rebuilds are cheap but platform round-trips aren't (Windows redraws an
    // icon; Linux hits the session bus), and the fold can re-emit an identical
    // value whenever an unrelated connection changes.
    //
    // The very first build always pushes, even when there's nothing unread:
    // Linux launchers remember the last count they were told *across restarts*,
    // so a startup with no unread has to say so explicitly.
    if (_pushed == unread) return;
    _pushed = unread;
    pushTaskbarBadge(unread);
  }
}

/// The tab title's unread prefix on the web, as the reference client's web
/// app writes it: "(3) " with mentions, "• " with unread messages only.
String unreadTitlePrefix(GlobalUnread unread) {
  if (unread.mentionCount > 0) return '(${unread.mentionCount}) ';
  if (unread.hasUnread) return '• ';
  return '';
}
