import 'package:livekit_client/livekit_client.dart' show VideoTrack;

/// No pop-out window on this platform (see `stream_popout.dart`).
bool get canPopOutStream => false;

/// Never pops out here; returns false.
Future<bool> popOutStream(VideoTrack track) async => false;
