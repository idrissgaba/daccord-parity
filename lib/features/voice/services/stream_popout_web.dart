import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrack;
import 'package:web/web.dart' as web;

/// Whether this browser offers Picture-in-Picture for video elements.
bool get canPopOutStream {
  try {
    final enabled = (web.document as JSObject).getProperty(
      'pictureInPictureEnabled'.toJS,
    );
    return enabled.isA<JSBoolean>() && (enabled as JSBoolean).toDart;
  } catch (_) {
    return false;
  }
}

/// Moves [track]'s playing `<video>` element into the browser's
/// Picture-in-Picture window. Returns false when no element plays the track
/// yet or the browser refused (it needs a user gesture, which the menu click
/// is).
Future<bool> popOutStream(VideoTrack track) async {
  final id = track.mediaStreamTrack.id;
  final videos = web.document.querySelectorAll('video');
  for (var i = 0; i < videos.length; i++) {
    final node = videos.item(i);
    if (node == null || !node.isA<web.HTMLVideoElement>()) continue;
    final video = node as web.HTMLVideoElement;
    final source = video.srcObject;
    if (source == null || !source.isA<web.MediaStream>()) continue;
    final tracks = (source as web.MediaStream).getVideoTracks().toDart;
    if (!tracks.any((t) => t.id == id)) continue;
    try {
      await video.requestPictureInPicture().toDart;
      return true;
    } catch (e) {
      debugPrint('Stream pop-out refused: $e');
      return false;
    }
  }
  return false;
}
