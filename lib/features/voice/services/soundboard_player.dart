import 'dart:async';

import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Plays soundboard clips locally. The server only broadcasts
/// `soundboard.play`; every client in the voice channel plays the clip itself,
/// which is how everyone (the sender included) hears it, like Discord.
///
/// media_kit (libmpv) rather than audioplayers: Windows' Media Foundation
/// backend can't decode Ogg on editions without the Web Media Extensions, and
/// soundboard clips are usually Ogg. Players are reused round-robin so a few
/// clips can overlap without creating one per play.
class SoundboardPlayer {
  SoundboardPlayer._();

  static const _poolSize = 3;

  final List<Player> _pool = [];
  int _next = 0;

  /// Mirrors `AccordSettings.soundboardVolume` (0.0–1.0).
  double volume = 1.0;

  /// Effective mpv volume (0–100) for a clip with its own [gain] (0.0–2.0)
  /// at the user's soundboard [volume]. Pure so it can be unit-tested.
  static double mpvVolume(double gain, double volume) =>
      (gain * volume * 100).clamp(0.0, 100.0).toDouble();

  /// Whether a `soundboard.play` from [senderId] is shown here (the emoji on
  /// their tile): while we sit in that voice channel of that space on that
  /// connection. [eventChannelId] is the channel the server names (newer
  /// servers); otherwise the sender's channel from the voice states.
  static bool shouldShow({
    required String eventServerKey,
    required String? spaceId,
    required String? senderId,
    required String myUserId,
    required String? voiceServerKey,
    required String? voiceSpaceId,
    required String? voiceChannelId,
    required String? eventChannelId,
    required String? senderChannelId,
  }) {
    if (voiceChannelId == null) return false;
    if (voiceServerKey != eventServerKey) return false;
    if (spaceId == null || spaceId != voiceSpaceId) return false;
    if (senderId == null) return false;
    if (eventChannelId != null) return eventChannelId == voiceChannelId;
    if (senderId == myUserId) return true;
    return senderChannelId == voiceChannelId;
  }

  /// Whether a `soundboard.play` from [senderId] in [spaceId] is heard here:
  /// only while we sit in a voice channel of that space on that connection,
  /// not deafened, the sender is in the same channel (or is us), and we
  /// haven't muted the sender locally — Discord's rules.
  static bool shouldPlay({
    required String eventServerKey,
    required String? spaceId,
    required String? senderId,
    required String myUserId,
    required String? voiceServerKey,
    required String? voiceSpaceId,
    required String? voiceChannelId,
    required bool deafened,
    required String? senderChannelId,
    required bool senderLocallyMuted,
    String? eventChannelId,
  }) {
    if (deafened) return false;
    final shown = shouldShow(
      eventServerKey: eventServerKey,
      spaceId: spaceId,
      senderId: senderId,
      myUserId: myUserId,
      voiceServerKey: voiceServerKey,
      voiceSpaceId: voiceSpaceId,
      voiceChannelId: voiceChannelId,
      eventChannelId: eventChannelId,
      senderChannelId: senderChannelId,
    );
    return shown && (senderId == myUserId || !senderLocallyMuted);
  }

  /// Plays the clip at [url] with its own [gain], scaled by [volume].
  /// Completes with the clip's length once the player knows it (null when
  /// nothing plays or it can't tell within a moment), so the "who is playing"
  /// cue can last as long as the sound.
  Future<Duration?> play(String url, {double gain = 1.0}) async {
    if (SoundManager.silent || url.isEmpty) return null;
    final level = mpvVolume(gain, volume);
    if (level <= 0) return null;
    try {
      final Player player;
      if (_pool.length < _poolSize) {
        player = Player();
        _pool.add(player);
      } else {
        player = _pool[_next];
        _next = (_next + 1) % _poolSize;
      }
      await player.setVolume(level);
      await player.open(Media(url));
      final known = player.state.duration;
      if (known > Duration.zero) return known;
      return await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(milliseconds: 1500));
    } catch (e) {
      if (e is! TimeoutException && e is! StateError) {
        debugPrint('SoundboardPlayer: playback failed: $e');
      }
      return null;
    }
  }
}

/// App-wide soundboard player, configured by `MainWindow`.
final soundboardPlayer = SoundboardPlayer._();
