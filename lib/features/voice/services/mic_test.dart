/// Settings › Voice & Video › Mic Test, outside of any call.
///
/// The reference client's Mic Test opens the selected microphone, lights the
/// bar meter as you speak and plays your voice back until you stop it. It
/// needs no voice connection, so it cannot use the call's published track:
///
/// * on the web the browser's Web Audio graph reads the level (an analyser)
///   and plays the input back (to the page's audio output);
/// * elsewhere the microphone is sent over a local loopback pair of WebRTC
///   peer connections; the sender's `media-source` stats give the level —
///   the same counter the call's meter reads — and the receiving end plays
///   through the default output like any remote voice.
///
/// While connected to voice the page shows the call's own level instead and
/// never opens a second capture.
library;

export 'mic_test_io.dart' if (dart.library.js_interop) 'mic_test_web.dart';
