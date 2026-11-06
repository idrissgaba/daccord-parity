import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/messaging/views/emoji_picker.dart';
import 'package:bonfire/features/soundboard/controllers/soundboard_sounds.dart';
import 'package:bonfire/features/soundboard/views/sound_emoji.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/space_settings_frame.dart';
import 'package:bonfire/features/voice/services/soundboard_player.dart';
import 'package:bonfire/shared/components/accord_dialog.dart';
import 'package:bonfire/shared/components/accord_slider.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'soundboard_settings_page/sound_row.dart';
part 'soundboard_settings_page/sound_dialog.dart';

/// Opens the space's Soundboard settings page — the reference client's
/// Server Settings › Soundboard, full screen with the ✕ / ESC close — and,
/// with [openUpload], its "Upload a Sound" dialog straight away (the
/// soundboard's "Add Sound" card does that).
Future<void> showSpaceSoundboardSettings(
  BuildContext context, {
  required String serverKey,
  required String spaceId,
  bool openUpload = false,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'space-soundboard-settings'),
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (_, _, _) => SoundboardSettingsPage(
        serverKey: serverKey,
        spaceId: spaceId,
        openUpload: openUpload,
      ),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 1.04, end: 1.0).animate(animation),
          child: child,
        ),
      ),
    ),
  );
}

/// What the active user may do with a space's sounds.
({bool create, bool manage, String? userId}) _rights(
  WidgetRef ref,
  String spaceId,
) {
  final space = ref.watch(
    spacesControllerProvider.select(
      (s) => s?.firstWhereOrNull((sp) => sp.id == spaceId),
    ),
  );
  final perms = ref.watchAccordPermissions(space, spaceId);
  final manage = accordHasPermission(perms, AccordPermission.manageSoundboard);
  return (
    create:
        manage ||
        accordHasPermission(perms, AccordPermission.createExpressions),
    manage: manage,
    userId: ref.watchUserId(),
  );
}

class SoundboardSettingsPage extends ConsumerStatefulWidget {
  const SoundboardSettingsPage({
    super.key,
    required this.serverKey,
    required this.spaceId,
    this.openUpload = false,
  });

  final String serverKey;
  final String spaceId;
  final bool openUpload;

  @override
  ConsumerState<SoundboardSettingsPage> createState() =>
      _SoundboardSettingsPageState();
}

class _SoundboardSettingsPageState
    extends ConsumerState<SoundboardSettingsPage> {
  @override
  void initState() {
    super.initState();
    if (widget.openUpload) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _upload();
      });
    }
  }

  Future<void> _upload() => showSoundDialog(
    context,
    serverKey: widget.serverKey,
    spaceId: widget.spaceId,
  );

  @override
  Widget build(BuildContext context) {
    final spaceName = ref.watch(
      spacesControllerProvider.select(
        (s) => s?.firstWhereOrNull((sp) => sp.id == widget.spaceId)?.name,
      ),
    );
    return SpaceSettingsFrame(
      spaceName: spaceName ?? '',
      groups: const [
        SpaceSettingsGroup(
          title: 'Expression',
          items: [SpaceSettingsItem(key: 'soundboard', label: 'Soundboard')],
        ),
      ],
      selected: 'soundboard',
      onSelect: (_) {},
      child: SoundboardSettingsView(
        serverKey: widget.serverKey,
        spaceId: widget.spaceId,
        onUpload: _upload,
      ),
    );
  }
}

/// The page body: title, description, then either the empty state ("No
/// Sounds" + Upload Sound) or the Upload Sound button and one row per sound.
class SoundboardSettingsView extends ConsumerWidget {
  const SoundboardSettingsView({
    super.key,
    required this.serverKey,
    required this.spaceId,
    required this.onUpload,
  });

  final String serverKey;
  final String spaceId;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final sounds = ref.watch(
      soundboardSoundsControllerProvider(serverKey, spaceId),
    );
    final rights = _rights(ref, spaceId);
    final uploadButton = _UploadButton(
      onPressed: rights.create ? onUpload : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Soundboard',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 24 / 20,
            color: colors.dirtyWhite,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Upload custom sound reactions that anyone in this server can use.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 18 / 14,
            color: colors.dirtyWhite.withValues(alpha: 0.94),
          ),
        ),
        if (sounds == null)
          const Padding(
            padding: EdgeInsets.only(top: 64),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (sounds.isEmpty) ...[
          const SizedBox(height: 64),
          const Text(
            'No Sounds',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 24 / 20,
              color: Color(0xFF96979E),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Get the party started by uploading a sound',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              height: 20 / 16,
              color: Color(0xFF96979E),
            ),
          ),
          const SizedBox(height: 38),
          Center(child: uploadButton),
        ] else ...[
          const SizedBox(height: 24),
          Align(alignment: Alignment.centerLeft, child: uploadButton),
          const SizedBox(height: 24),
          for (final sound in sounds)
            _SoundRow(
              key: Key('soundboard-row-${sound.id}'),
              sound: sound,
              serverKey: serverKey,
              spaceId: spaceId,
              canEdit:
                  rights.manage ||
                  (rights.create &&
                      sound.creatorId != null &&
                      sound.creatorId == rights.userId),
            ),
        ],
      ],
    );
  }
}

class _UploadButton extends StatelessWidget {
  const _UploadButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return SizedBox(
      height: 40,
      child: TextButton(
        key: const Key('soundboard-upload'),
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: colors.primary.withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text(
          'Upload Sound',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
