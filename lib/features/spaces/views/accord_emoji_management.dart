import 'package:bonfire/theme/app_icons.dart';
import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/text_prompt_dialog.dart';
import 'package:bonfire/features/messaging/controllers/accord_emojis.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/accord_space_settings.dart';
import 'package:bonfire/features/spaces/views/space_settings_frame.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/shared/components/settings_controls.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens Server Settings › Emoji for [spaceId].
Future<void> showAccordEmojiManagement(
  BuildContext context, {
  required String spaceId,
}) => showAccordSpaceSettings(
  context,
  spaceId: spaceId,
  page: SpaceSettingsPages.emoji,
);

/// Server Settings › Emoji: "Upload Emoji", then the space's emoji (image,
/// name, who uploaded it) or "No Emoji". Uploading needs Create Expressions
/// (or Manage Expressions); renaming and deleting your own emoji needs Create
/// Expressions, anyone else's Manage Expressions — as the server enforces.
class EmojiSettingsPage extends ConsumerStatefulWidget {
  const EmojiSettingsPage({super.key, required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<EmojiSettingsPage> createState() => _EmojiSettingsPageState();
}

class _EmojiSettingsPageState extends ConsumerState<EmojiSettingsPage> {
  bool _busy = false;
  String? _error;

  AccordClient? get _client => ref.accordClient;

  Future<void> _pickAndUpload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file?.bytes == null) return;
    final client = _client;
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final dataUri = AccordCDN.buildDataUri(file!.bytes!, file.name);
    // Drop the extension for a sensible default name; user can rename inline.
    final defaultName = _sanitizeName(file.name.split('.').first);
    final result = await client.emojis.create(widget.spaceId, {
      'name': defaultName,
      'image': dataUri,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() => _error = result.errorOr('Failed to upload emoji'));
      return;
    }
    final emoji = result.data;
    if (emoji is AccordEmoji) {
      ref
          .read(
            accordEmojisControllerProvider(
              ref.readActiveServerKey() ?? '',
              widget.spaceId,
            ).notifier,
          )
          .upsert(emoji);
    }
  }

  Future<void> _rename(AccordEmoji emoji) async {
    final client = _client;
    if (client == null) return;
    final id = emoji.id;
    if (id == null) return;
    final next = await _promptForName(emoji.name);
    if (next == null || next == emoji.name) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.emojis.update(widget.spaceId, id, {
      'name': _sanitizeName(next),
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() => _error = result.errorOr('Failed to rename emoji'));
      return;
    }
    final updated = result.data;
    if (updated is AccordEmoji) {
      ref
          .read(
            accordEmojisControllerProvider(
              ref.readActiveServerKey() ?? '',
              widget.spaceId,
            ).notifier,
          )
          .upsert(updated);
    }
  }

  Future<void> _delete(AccordEmoji emoji) async {
    final client = _client;
    if (client == null) return;
    final id = emoji.id;
    if (id == null) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete emoji?',
      message: ':${emoji.name}: will be removed from this space.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.emojis.delete(widget.spaceId, id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() => _error = result.errorOr('Failed to delete emoji'));
      return;
    }
    ref
        .read(
          accordEmojisControllerProvider(
            ref.readActiveServerKey() ?? '',
            widget.spaceId,
          ).notifier,
        )
        .remove(id);
  }

  Future<String?> _promptForName(String initial) async {
    final name = await showTextPromptDialog(
      context,
      title: 'Rename emoji',
      label: 'Name',
      helperText: 'Letters, numbers, and underscores',
      initial: initial,
    );
    return name?.trim();
  }

  static String _sanitizeName(String raw) {
    // Server-side rules typically require [a-z0-9_]; lowercase + replace
    // anything else with underscores so a freshly-uploaded emoji has a valid
    // default name. Falls back to "emoji" if everything got stripped.
    final cleaned = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'emoji' : cleaned;
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final serverKey = ref.watchActiveServerKey() ?? '';
    final emojis = ref.watch(
      accordEmojisControllerProvider(serverKey, widget.spaceId),
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
    final members = ref.watch(
      accordMembersControllerProvider(serverKey, widget.spaceId),
    );
    final users = ref.watch(accordUsersControllerProvider(serverKey));
    final head = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 16 / 12,
      color: colors.interactive,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsPageHeader(
          title: 'Emoji',
          description:
              'Add custom emojis that anyone can use in this server.',
          bottom: 16,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: AccordButton(
            key: const Key('emoji-upload'),
            label: 'Upload Emoji',
            onPressed: _busy || !create ? null : _pickAndUpload,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'The emoji is named after its file; rename it here afterwards.',
          style: TextStyle(fontSize: 12, height: 16 / 12, color: colors.dirtyWhite),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          InlineError(_error!, centered: false),
        ],
        const SettingsDivider(top: 24, bottom: 40),
        if (emojis == null)
          const LoadingView()
        else if (emojis.isEmpty)
          Column(
            key: const Key('emoji-empty'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No Emoji',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 20 / 16,
                  color: colors.interactive,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Get the party started by uploading an emoji',
                style: SettingsText.description(colors),
              ),
            ],
          )
        else ...[
          Text(
            'Emoji — ${emojis.length}',
            style: SettingsText.label(colors),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(width: 72, child: Text('IMAGE', style: head)),
              Expanded(flex: 3, child: Text('NAME', style: head)),
              Expanded(flex: 3, child: Text('UPLOADED BY', style: head)),
              const SizedBox(width: 64),
            ],
          ),
          const SizedBox(height: 8),
          for (final emoji in emojis)
            _EmojiRow(
              key: ValueKey('emoji-${emoji.id}'),
              imageUrl: _emojiUrl(emoji, cdnUrl),
              name: emoji.name,
              uploader: emoji.creatorId == null
                  ? null
                  : accordAuthorName(
                      emoji.creatorId!,
                      members: members,
                      users: users,
                    ),
              editable:
                  !_busy &&
                  (manage || (create && emoji.creatorId == me && me != null)),
              onRename: () => _rename(emoji),
              onDelete: () => _delete(emoji),
            ),
        ],
      ],
    );
  }

  String? _emojiUrl(AccordEmoji emoji, String? cdnUrl) =>
      accordEmojiUrl(emoji, cdnUrl);
}

/// One emoji row; rename and the delete ✕ show on hover.
class _EmojiRow extends StatefulWidget {
  const _EmojiRow({
    super.key,
    required this.imageUrl,
    required this.name,
    required this.uploader,
    required this.editable,
    required this.onRename,
    required this.onDelete,
  });

  final String? imageUrl;
  final String name;
  final String? uploader;
  final bool editable;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  State<_EmojiRow> createState() => _EmojiRowState();
}

class _EmojiRowState extends State<_EmojiRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final text = TextStyle(fontSize: 14, height: 18 / 14, color: colors.dirtyWhite);
    final url = widget.imageUrl;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.hairline)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Align(
                alignment: Alignment.centerLeft,
                child: url == null
                    ? Icon(AppIcons.imageOutlined, color: colors.gray)
                    : CachedNetworkImage(
                        imageUrl: url,
                        width: 32,
                        height: 32,
                        errorWidget: (_, _, _) =>
                            Icon(AppIcons.brokenImage, color: colors.gray),
                      ),
              ),
            ),
            Expanded(flex: 3, child: Text(widget.name, style: text)),
            Expanded(
              flex: 3,
              child: Text(widget.uploader ?? '—', style: text),
            ),
            SizedBox(
              width: 64,
              child: _hover && widget.editable
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Rename',
                          visualDensity: VisualDensity.compact,
                          onPressed: widget.onRename,
                          icon: Icon(
                            AppIcons.edit,
                            size: 16,
                            color: colors.interactive,
                          ),
                        ),
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
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
