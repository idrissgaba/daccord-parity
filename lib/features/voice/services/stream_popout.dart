/// Pops a stream's video out of the page, where the platform can.
///
/// On the web the browser's own Picture-in-Picture window takes the stream's
/// `<video>` element, so it keeps playing over other tabs and apps. Desktop
/// and mobile have no equivalent for a Flutter view: a second window runs its
/// own engine and cannot show a WebRTC texture from this one, so the in-app
/// floating preview (`VoicePipOverlay`) stands in there.
library;

export 'stream_popout_stub.dart'
    if (dart.library.js_interop) 'stream_popout_web.dart';
