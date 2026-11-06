import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'soundboard_activity.g.dart';

/// One soundboard sound someone in our voice channel is playing.
class SoundboardActivity {
  const SoundboardActivity({
    required this.sound,
    required this.until,
    required this.token,
  });

  final AccordSound sound;

  /// When the clip stops playing (an estimate when we don't hear it).
  final DateTime until;

  /// Distinguishes two plays of the same user, so the first one's timer does
  /// not end the second.
  final int token;
}

/// Who in our voice channel is playing a soundboard sound right now, keyed by
/// user ID. Feeds the reference client's cues: the sound's emoji rising over
/// the player's call tile, the speaking ring on the tile and channel row, and
/// the played card's outline in the picker.
@Riverpod(keepAlive: true)
class SoundboardActivityController extends _$SoundboardActivityController {
  final Map<String, Timer> _timers = {};
  int _nextToken = 0;

  /// How long a clip shows when its duration is unknown.
  static const fallbackDuration = Duration(seconds: 2);

  /// Bounds the cue: Discord sounds last at most a few seconds.
  static const maxDuration = Duration(seconds: 6);
  static const minDuration = Duration(milliseconds: 900);

  @override
  Map<String, SoundboardActivity> build() {
    ref.onDispose(() {
      for (final t in _timers.values) {
        t.cancel();
      }
      _timers.clear();
    });
    return const {};
  }

  /// Shows [userId] playing [sound] for [duration] (clamped unless [exact]),
  /// replacing what they were playing.
  void start(
    String userId,
    AccordSound sound, {
    Duration? duration,
    bool exact = false,
  }) {
    final wanted = duration ?? fallbackDuration;
    final length = exact ? wanted : clampDuration(wanted);
    final token = ++_nextToken;
    _timers.remove(userId)?.cancel();
    state = {
      ...state,
      userId: SoundboardActivity(
        sound: sound,
        until: DateTime.now().add(length),
        token: token,
      ),
    };
    _timers[userId] = Timer(length, () => _end(userId, token));
  }

  /// Corrects the length of [userId]'s current clip once playback reports it.
  void setDuration(String userId, AccordSound sound, Duration duration) {
    final current = state[userId];
    if (current == null || current.sound.id != sound.id) return;
    start(userId, sound, duration: duration);
  }

  void _end(String userId, int token) {
    if (!ref.mounted) return;
    if (state[userId]?.token != token) return;
    _timers.remove(userId);
    state = {
      for (final e in state.entries)
        if (e.key != userId) e.key: e.value,
    };
  }

  /// Forgets everything, e.g. when leaving the voice channel.
  void clear() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    if (state.isNotEmpty) state = const {};
  }

  static Duration clampDuration(Duration d) => d < minDuration
      ? minDuration
      : d > maxDuration
      ? maxDuration
      : d;
}
