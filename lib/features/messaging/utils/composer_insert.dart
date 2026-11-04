/// Lets anything outside the message pane (the voice participant menu's
/// "Mention", say) put text into the composer of the channel in view.
library;

import 'package:flutter/foundation.dart';

/// Text waiting to be inserted at the composer's cursor. The composer takes
/// it when it arrives, or when the composer itself mounts (the voice chat
/// panel may be closed when a mention is asked for), and clears it.
final composerInsertRequest = ValueNotifier<String?>(null);

/// Asks the visible composer to insert [text] at its cursor (with a trailing
/// space) and focus itself.
void requestComposerInsert(String text) {
  // Re-posting the same text must still notify, so clear first.
  composerInsertRequest.value = null;
  composerInsertRequest.value = text;
}

/// Takes the pending insert, if any, leaving none behind.
String? takeComposerInsert() {
  final text = composerInsertRequest.value;
  composerInsertRequest.value = null;
  return text;
}
