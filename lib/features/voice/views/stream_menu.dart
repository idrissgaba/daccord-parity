import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/services/stream_popout.dart';
import 'package:bonfire/features/voice/views/screen_share_picker.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrack;
import 'package:universal_platform/universal_platform.dart';

/// The menu of our live screen share, the same one wherever it opens from:
/// the share button while live, the chevron beside it in the call bar, and
/// our stream tile's "…" — Stop Streaming, Change Stream and, where the
/// browser can, Pop Out Stream.
Future<void> showStreamMenu(
  BuildContext context,
  WidgetRef ref, {
  Offset? globalPosition,
  VideoTrack? popOutTrack,
  bool preferAbove = false,
}) {
  final voice = ref.read(voiceControllerProvider.notifier);
  return showAccordContextMenu(
    context,
    globalPosition: globalPosition,
    preferAbove: preferAbove,
    title: 'Stream',
    entries: [
      AccordMenuEntry(
        label: 'Stop Streaming',
        icon: AppIcons.stopScreenShareOutlined,
        destructive: true,
        onSelected: voice.toggleScreenShare,
      ),
      AccordMenuEntry(
        label: 'Change Stream',
        icon: AppIcons.screenShareOutlined,
        onSelected: () => changeStreamWithPicker(context, ref),
      ),
      if (popOutTrack != null && canPopOutStream) ...[
        const AccordMenuEntry.divider(),
        AccordMenuEntry(
          label: 'Pop Out Stream',
          icon: AppIcons.openInNew,
          onSelected: () => popOutStream(popOutTrack),
        ),
      ],
    ],
  );
}

/// Points the live share at another screen or window without ending it. On
/// desktop the source picker chooses; elsewhere the platform prompts again.
Future<void> changeStreamWithPicker(BuildContext context, WidgetRef ref) async {
  final voice = ref.read(voiceControllerProvider.notifier);
  if (UniversalPlatform.isDesktop) {
    final source = await showScreenShareSourcePicker(context, changing: true);
    if (source == null) return;
    await voice.changeScreenShareSource(source.id);
  } else {
    await voice.changeScreenShareSource(null);
  }
}

/// Where a menu opened from the button in [context] anchors: the button's
/// top centre, so the menu stands above or beside it rather than at the
/// pointer.
Offset? menuAnchorOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset(box.size.width / 2, 0));
}
