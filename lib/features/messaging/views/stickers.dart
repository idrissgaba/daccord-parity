import 'package:bonfire/theme/app_icons.dart';
import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/controllers/space_stickers.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:collection/collection.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/text_prompt_dialog.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/accord_space_settings.dart';
import 'package:bonfire/features/spaces/views/space_settings_frame.dart';
import 'package:bonfire/shared/components/settings_controls.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The absolute URL of a sticker's image, or null for a deleted sticker.
String? stickerUrl(AccordSticker sticker, String? cdnUrl) {
  final image = sticker.image;
  if (image == null || image.isEmpty) return null;
  return AccordCDN.resolvePath(image, cdnUrl: cdnUrl ?? '');
}

/// A sticker as a message shows it: up to 160 px, or its name once deleted.
class MessageSticker extends ConsumerWidget {
  const MessageSticker({super.key, required this.sticker});

  final AccordSticker sticker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = stickerUrl(sticker, ref.watchCdnUrl());
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      key: ValueKey('message-sticker-${sticker.id}'),
      padding: const EdgeInsets.only(top: 4),
      child: Tooltip(
        message: sticker.name,
        child: url == null
            ? Text('🏷️ ${sticker.name}', style: TextStyle(color: colors.gray))
            : CachedNetworkImage(
                imageUrl: url,
                width: 160,
                height: 160,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                errorWidget: (_, _, _) => Text('🏷️ ${sticker.name}'),
              ),
      ),
    );
  }
}

/// Upload, rename and delete a space's stickers (needs `manage_emojis`).
/// Opens Server Settings › Stickers for [spaceId].
Future<void> showStickerManagement(
  BuildContext context, {
  required String spaceId,
}) => showAccordSpaceSettings(
  context,
  spaceId: spaceId,
  page: SpaceSettingsPages.stickers,
);

/// Server Settings › Stickers: the space's stickers as the reference
/// client's slot grid, with "Upload Sticker". Uploading needs Create
/// Expressions (or Manage Expressions); renaming and deleting your own
/// stickers needs Create Expressions, anyone else's Manage Expressions.
class StickerSettingsPage extends ConsumerStatefulWidget {
  const StickerSettingsPage({super.key, required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<StickerSettingsPage> createState() =>
      _StickerSettingsPageState();
}

class _StickerSettingsPageState extends ConsumerState<StickerSettingsPage> {
  bool _busy = false;
  String? _error;

  SpaceStickersController get _controller => ref.read(
    spaceStickersControllerProvider(
      ref.readActiveServerKey() ?? '',
      widget.spaceId,
    ).notifier,
  );

  Future<void> _run(
    Future<RestResult> Function(AccordClient client) action,
    String failure,
    void Function(Object? data) onDone,
  ) async {
    final client = ref.accordClient;
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await action(client);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!result.ok) _error = result.errorMessageOr(failure);
    });
    if (result.ok) onDone(result.data);
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'gif', 'webp'],
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file?.bytes == null || !mounted) return;
    final base = file!.name.split('.').first.replaceAll(RegExp(r'[_-]+'), ' ');
    final name = base.trim().length >= 2 ? base.trim() : 'Sticker';
    await _run(
      (client) => client.stickers.create(
        widget.spaceId,
        name: name.length > 30 ? name.substring(0, 30) : name,
        image: AccordCDN.buildDataUri(file.bytes!, file.name),
      ),
      'Could not upload the sticker',
      (data) {
        if (data is AccordSticker) _controller.upsert(data);
      },
    );
  }

  Future<void> _rename(AccordSticker sticker) async {
    final name = (await showTextPromptDialog(
      context,
      title: 'Rename sticker',
      label: 'Name',
      helperText: '2–30 characters',
      initial: sticker.name,
    ))?.trim();
    if (name == null || name == sticker.name) return;
    await _run(
      (client) =>
          client.stickers.update(widget.spaceId, sticker.id, name: name),
      'Could not rename the sticker',
      (data) {
        if (data is AccordSticker) _controller.upsert(data);
      },
    );
  }

  Future<void> _delete(AccordSticker sticker) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${sticker.name}?',
      message: 'Messages that used it will show its name instead.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok != true || !mounted) return;
    await _run(
      (client) => client.stickers.delete(widget.spaceId, sticker.id),
      'Could not delete the sticker',
      (_) => _controller.remove(sticker.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final stickers = ref.watch(
      spaceStickersControllerProvider(
        ref.watchActiveServerKey() ?? '',
        widget.spaceId,
      ),
    );
    final cdnUrl = ref.watchCdnUrl();
    final space = ref.watch(
      spacesControllerProvider.select(
        (s) => s?.firstWhereOrNull((sp) => sp.id == widget.spaceId),
      ),
    );
    final perms = ref.watchAccordPermissions(space, widget.spaceId);
    final manage = accordHasPermission(perms, AccordPermission.manageEmojis);
    final create =
        manage ||
        accordHasPermission(perms, AccordPermission.createExpressions);
    final me = ref.watchUserId();
    final count = stickers?.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsPageHeader(
          title: 'Stickers',
          description:
              'Upload custom stickers that anyone in this server can send. '
              'PNG, GIF or WebP, up to 60 per server.',
          bottom: 24,
        ),
        if (_error != null) ...[
          InlineError(_error!, centered: false),
          const SizedBox(height: 12),
        ],
        Container(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stickers',
                            style: SettingsText.label(
                              colors,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '$count of 60 slots used',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colors.dirtyWhite,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AccordButton(
                      key: const Key('sticker-upload'),
                      label: 'Upload Sticker',
                      small: true,
                      onPressed: _busy || !create ? null : _upload,
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: colors.hairline),
              Padding(
                padding: const EdgeInsets.all(16),
                child: stickers == null
                    ? const LoadingView()
                    : GridView.count(
                        crossAxisCount: 5,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 92 / 111,
                        children: [
                          for (final sticker in stickers)
                            _StickerSlot(
                              key: ValueKey('manage-sticker-${sticker.id}'),
                              url: stickerUrl(sticker, cdnUrl),
                              name: sticker.name,
                              editable:
                                  !_busy &&
                                  (manage ||
                                      (create &&
                                          me != null &&
                                          sticker.creatorId == me)),
                              onRename: () => _rename(sticker),
                              onDelete: () => _delete(sticker),
                            ),
                          // Empty slots up to a full row, as the reference
                          // client shows its free slots.
                          for (var i = count; i < ((count ~/ 5) + 1) * 5; i++)
                            const _StickerSlot(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One sticker slot: the sticker and its name, or an empty dashed slot.
/// Rename and delete show on hover.
class _StickerSlot extends StatefulWidget {
  const _StickerSlot({
    super.key,
    this.url,
    this.name,
    this.editable = false,
    this.onRename,
    this.onDelete,
  });

  final String? url;
  final String? name;
  final bool editable;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  State<_StickerSlot> createState() => _StickerSlotState();
}

class _StickerSlotState extends State<_StickerSlot> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final name = widget.name;
    final url = widget.url;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: name == null ? 0.0 : 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x339696A0)),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: name == null
                          ? Icon(
                              AppIcons.stickyNote2Outlined,
                              size: 40,
                              color: colors.darkGray,
                            )
                          : url == null
                          ? Icon(AppIcons.imageOutlined, color: colors.gray)
                          : CachedNetworkImage(
                              imageUrl: url,
                              width: 64,
                              height: 64,
                              errorWidget: (_, _, _) => Icon(
                                AppIcons.brokenImage,
                                color: colors.gray,
                              ),
                            ),
                    ),
                  ),
                  if (name != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.dirtyWhite,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_hover && widget.editable)
              Positioned(
                top: 4,
                right: 4,
                child: Row(
                  children: [
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: widget.onRename,
                      child: Tooltip(
                        message: 'Rename',
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: colors.raised,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            AppIcons.edit,
                            size: 13,
                            color: colors.dirtyWhite,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: widget.onDelete,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          AppIcons.close,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
