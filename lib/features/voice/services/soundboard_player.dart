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
  }) {
    if (voiceChannelId == null || deafened) return false;
    if (voiceServerKey != eventServerKey) return false;
    if (spaceId == null || spaceId != voiceSpaceId) return false;
    if (senderId == null) return false;
    if (senderId == myUserId) return true;
    return senderChannelId == voiceChannelId && !senderLocallyMuted;
  }

  /// Plays the clip at [url] with its own [gain], scaled by [volume].
  Future<void> play(String url, {double gain = 1.0}) async {
    if (SoundManager.silent || url.isEmpty) return;
    final level = mpvVolume(gain, volume);
    if (level <= 0) return;
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
    } catch (e) {
      debugPrint('SoundboardPlayer: playback failed: $e');
    }
  }
}

/// App-wide soundboard player, configured by `MainWindow`.
final soundboardPlayer = SoundboardPlayer._();
