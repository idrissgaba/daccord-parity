import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// A running microphone test (see `mic_test.dart`). [level] is the input
/// level, 0–1, updated about ten times a second.
class MicTest {
  MicTest._();

  final ValueNotifier<double> level = ValueNotifier(0);

  web.MediaStream? _stream;
  web.AudioContext? _context;
  web.AnalyserNode? _analyser;
  Timer? _timer;
  bool _stopped = false;

  /// Opens [deviceId] (empty = system default) with the given processing,
  /// plays it back and starts measuring. Throws when the microphone cannot be
  /// opened (no permission, no device).
  static Future<MicTest> start({
    required String deviceId,
    required bool noiseSuppression,
    required bool echoCancellation,
    required bool autoGainControl,
  }) async {
    final test = MicTest._();
    try {
      final audio = web.MediaTrackConstraints(
        echoCancellation: echoCancellation.toJS,
        noiseSuppression: noiseSuppression.toJS,
        autoGainControl: autoGainControl.toJS,
      );
      if (deviceId.isNotEmpty) audio.deviceId = deviceId.toJS;
      final stream = test._stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(audio: audio))
          .toDart;
      final context = test._context = web.AudioContext();
      final source = context.createMediaStreamSource(stream);
      final analyser = test._analyser = context.createAnalyser()
        ..fftSize = 1024;
      source.connect(analyser);
      // Playback: the reference client lets you hear yourself.
      source.connect(context.destination);
      test._timer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => test._poll(),
      );
    } catch (_) {
      await test.stop();
      rethrow;
    }
    return test;
  }

  void _poll() {
    final analyser = _analyser;
    if (analyser == null || _stopped) return;
    final samples = Float32List(analyser.fftSize);
    analyser.getFloatTimeDomainData(samples.toJS);
    var sum = 0.0;
    for (final s in samples) {
      sum += s * s;
    }
    // RMS amplitude, the scale WebRTC's `audioLevel` reports.
    level.value = math.sqrt(sum / samples.length).clamp(0.0, 1.0);
  }

  /// Releases the microphone and the audio graph.
  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    level.value = 0;
    final tracks =
        _stream?.getTracks().toDart ?? const <web.MediaStreamTrack>[];
    for (final track in tracks) {
      track.stop();
    }
    try {
      await _context?.close().toDart;
    } catch (_) {}
    _stream = null;
    _context = null;
    _analyser = null;
  }
}
