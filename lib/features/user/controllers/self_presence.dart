import 'dart:async';
import 'dart:math' as math;

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/muted_channels.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/shared/models/server_entity_key.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'self_presence.g.dart';

/// The status choices of the account card's status submenu, with their timed
/// variants ("For 15 Minutes" … "For 3 Days", "Forever").
const List<({String label, Duration? duration})> kStatusDurations = [
  (label: 'For 15 Minutes', duration: Duration(minutes: 15)),
  (label: 'For 1 Hour', duration: Duration(hours: 1)),
  (label: 'For 8 Hours', duration: Duration(hours: 8)),
  (label: 'For 24 Hours', duration: Duration(hours: 24)),
  (label: 'For 3 Days', duration: Duration(days: 3)),
  (label: 'Forever', duration: null),
];

/// The durations of every Mute › submenu (server, category, channel, DM).
const List<({String label, Duration? duration})> kMuteDurations = [
  (label: 'For 15 Minutes', duration: Duration(minutes: 15)),
  (label: 'For 1 Hour', duration: Duration(hours: 1)),
  (label: 'For 3 Hours', duration: Duration(hours: 3)),
  (label: 'For 8 Hours', duration: Duration(hours: 8)),
  (label: 'For 24 Hours', duration: Duration(hours: 24)),
  (label: 'Until I turn it back on', duration: null),
];

/// The signed-in user's own presence: status and custom status, per
/// connection, and the timers that end a timed status, custom status or mute
/// ("For 1 Hour", "Clear after"). Timers live in settings (persisted), so a
/// status or mute that ran out while the app was closed is lifted on the next
/// launch.
@Riverpod(keepAlive: true)
class SelfPresenceController extends _$SelfPresenceController {
  Timer? _timer;

  /// Tests replace the clock.
  DateTime Function() now = DateTime.now;

  @override
  void build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen(
      settingsControllerProvider.select(
        (s) => (s.muteExpiries, s.statusExpiries, s.customStatusExpiries),
      ),
      (_, _) => _schedule(),
      fireImmediately: true,
    );
    // A mute that ran out while its server was unreachable is lifted once
    // the connection is back.
    ref.listen(accordAuthProvider, (_, _) => _schedule());
  }

  /// Sets [status] (`online`, `idle`, `dnd`, `invisible`) on [serverKey],
  /// keeping any custom status. [until] ends it ("For 1 Hour"); null keeps it
  /// until changed.
  void setStatus(String serverKey, String status, {DateTime? until}) {
    _send(serverKey, status: status);
    ref
        .read(settingsControllerProvider.notifier)
        .setStatusExpiry(serverKey, status == 'online' ? null : until);
  }

  /// Sets the custom status [text] ("😀 text", empty clears it) on
  /// [serverKey], keeping the status. [until] clears it at that time.
  void setCustomStatus(String serverKey, String text, {DateTime? until}) {
    final trimmed = text.trim();
    _send(serverKey, custom: trimmed);
    ref
        .read(settingsControllerProvider.notifier)
        .setCustomStatusExpiry(serverKey, trimmed.isEmpty ? null : until);
  }

  void _send(String serverKey, {String? status, String? custom}) {
    final client = ref.read(accordAuthProvider.notifier).clientForKey(serverKey);
    final userId = ref
        .read(connectionsControllerProvider)
        .connectionFor(serverKey)
        ?.session
        .userId;
    if (client == null) return;
    final presences = ref.read(presenceControllerProvider(serverKey));
    final currentStatus = userId == null
        ? 'online'
        : accordPresenceStatus(presences, userId);
    final nextStatus =
        status ?? (currentStatus == 'offline' ? 'online' : currentStatus);
    final nextCustom =
        custom ?? (userId == null ? null : accordCustomStatus(presences, userId));
    final hasCustom = nextCustom != null && nextCustom.isNotEmpty;
    client.gateway.updatePresence(
      nextStatus,
      activity: hasCustom ? {'name': nextCustom, 'type': 'custom'} : const {},
    );
    if (userId != null) {
      ref
          .read(presenceControllerProvider(serverKey).notifier)
          .upsert(
            AccordPresence(
              userId: userId,
              status: nextStatus,
              activities: hasCustom
                  ? [AccordActivity(name: nextCustom, type: 'custom')]
                  : [],
            ),
          );
    }
  }

  /// Lifts every expired timer, then waits for the next one.
  void _schedule() {
    _timer?.cancel();
    final settings = ref.read(settingsControllerProvider);
    final nowMs = now().millisecondsSinceEpoch;
    var next = -1;
    void consider(int ms) {
      if (ms > nowMs) next = next < 0 ? ms : math.min(next, ms);
    }

    final expiredMutes = <String>[];
    settings.muteExpiries.forEach((key, ms) {
      ms <= nowMs ? expiredMutes.add(key) : consider(ms);
    });
    final expiredStatus = <String>[];
    settings.statusExpiries.forEach((key, ms) {
      ms <= nowMs ? expiredStatus.add(key) : consider(ms);
    });
    final expiredCustom = <String>[];
    settings.customStatusExpiries.forEach((key, ms) {
      ms <= nowMs ? expiredCustom.add(key) : consider(ms);
    });

    if (expiredMutes.isNotEmpty ||
        expiredStatus.isNotEmpty ||
        expiredCustom.isNotEmpty) {
      // Applying an expiry writes settings, which reschedules.
      scheduleMicrotask(() {
        for (final key in expiredMutes) {
          _liftMute(settings, key);
        }
        for (final serverKey in expiredStatus) {
          if (_isConnected(serverKey)) {
            setStatus(serverKey, 'online');
          } else {
            ref
                .read(settingsControllerProvider.notifier)
                .setStatusExpiry(serverKey, null);
          }
        }
        for (final serverKey in expiredCustom) {
          if (_isConnected(serverKey)) {
            setCustomStatus(serverKey, '');
          } else {
            ref
                .read(settingsControllerProvider.notifier)
                .setCustomStatusExpiry(serverKey, null);
          }
        }
      });
    }
    if (next > 0) {
      _timer = Timer(
        Duration(milliseconds: next - nowMs + 50),
        _schedule,
      );
    }
  }

  bool _isConnected(String serverKey) =>
      ref.read(accordAuthProvider.notifier).clientForKey(serverKey) != null;

  void _liftMute(AccordSettings settings, String encoded) {
    final key = ServerEntityKey.tryDecode(encoded);
    final settingsCtl = ref.read(settingsControllerProvider.notifier);
    if (key == null) {
      return;
    }
    if (settings.mutedSpaces.contains(encoded)) {
      settingsCtl.setSpaceMuted(key.serverKey, key.entityId, false);
      return;
    }
    // The channel mute lives on the server: keep the timer until it can be
    // lifted there.
    if (!_isConnected(key.serverKey)) return;
    settingsCtl.setMuteExpiry(key.serverKey, key.entityId, null);
    ref
        .read(mutedChannelsControllerProvider(key.serverKey).notifier)
        .setMuted(key.entityId, false);
  }
}

/// The end of a timed choice made [duration] from now, or null for "until
/// changed".
DateTime? untilFrom(Duration? duration) =>
    duration == null ? null : DateTime.now().add(duration);
