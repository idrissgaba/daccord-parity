import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// A running microphone test (see `mic_test.dart`). [level] is the input
/// level, 0–1, updated about ten times a second.
class MicTest {
  MicTest._();

  final ValueNotifier<double> level = ValueNotifier(0);

  MediaStream? _stream;
  RTCPeerConnection? _sender;
  RTCPeerConnection? _receiver;
  Timer? _timer;
  bool _polling = false;
  bool _stopped = false;

  /// Opens [deviceId] (empty = system default) with the given processing and
  /// starts the loopback. Throws when the microphone cannot be opened.
  static Future<MicTest> start({
    required String deviceId,
    required bool noiseSuppression,
    required bool echoCancellation,
    required bool autoGainControl,
  }) async {
    final test = MicTest._();
    try {
      await test._open(
        deviceId: deviceId,
        noiseSuppression: noiseSuppression,
        echoCancellation: echoCancellation,
        autoGainControl: autoGainControl,
      );
    } catch (_) {
      await test.stop();
      rethrow;
    }
    return test;
  }

  Future<void> _open({
    required String deviceId,
    required bool noiseSuppression,
    required bool echoCancellation,
    required bool autoGainControl,
  }) async {
    final audio = <String, dynamic>{
      'echoCancellation': echoCancellation,
      'noiseSuppression': noiseSuppression,
      'autoGainControl': autoGainControl,
      if (deviceId.isNotEmpty) 'deviceId': deviceId,
    };
    final stream = _stream = await navigator.mediaDevices.getUserMedia({
      'audio': audio,
      'video': false,
    });
    final sender = _sender = await createPeerConnection({});
    final receiver = _receiver = await createPeerConnection({});
    sender.onIceCandidate = (c) => receiver.addCandidate(c);
    receiver.onIceCandidate = (c) => sender.addCandidate(c);
    for (final track in stream.getAudioTracks()) {
      await sender.addTrack(track, stream);
    }
    final offer = await sender.createOffer();
    await sender.setLocalDescription(offer);
    await receiver.setRemoteDescription(offer);
    final answer = await receiver.createAnswer();
    await receiver.setLocalDescription(answer);
    await sender.setRemoteDescription(answer);
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _poll());
  }

  Future<void> _poll() async {
    final sender = _sender;
    if (_polling || sender == null || _stopped) return;
    _polling = true;
    try {
      final reports = await sender.getStats();
      for (final report in reports) {
        if (report.type != 'media-source') continue;
        final value = report.values['audioLevel'];
        if (value is num && !_stopped) level.value = value.toDouble();
      }
    } catch (_) {
      // A transient stats failure leaves the last level showing.
    } finally {
      _polling = false;
    }
  }

  /// Releases the microphone and the loopback.
  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    level.value = 0;
    try {
      await _sender?.close();
      await _receiver?.close();
    } catch (_) {}
    try {
      for (final track in _stream?.getTracks() ?? const <MediaStreamTrack>[]) {
        await track.stop();
      }
      await _stream?.dispose();
    } catch (_) {}
    _sender = null;
    _receiver = null;
    _stream = null;
  }
}
