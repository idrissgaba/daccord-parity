part of '../soundboard_settings_page.dart';

/// One sound of the Soundboard settings page, after the reference client's
/// row: the emoji, the name with a speaker that previews it, who uploaded it
/// (avatar + name), and — on hover, for those who may change it — a pencil
/// (edit) over a red ✕ (delete) at the right edge.
class _SoundRow extends ConsumerStatefulWidget {
  const _SoundRow({
    super.key,
    required this.sound,
    required this.serverKey,
    required this.spaceId,
    required this.canEdit,
  });

  final AccordSound sound;
  final String serverKey;
  final String spaceId;
  final bool canEdit;

  @override
  ConsumerState<_SoundRow> createState() => _SoundRowState();
}

class _SoundRowState extends ConsumerState<_SoundRow> {
  bool _hover = false;

  void _preview() {
    final client = ref.accordClient;
    if (client == null) return;
    soundboardPlayer.play(
      AccordCDN.resolvePath(
        widget.sound.audioUrl,
        cdnUrl: client.config.cdnUrl,
      ),
      gain: widget.sound.volume,
    );
  }

  Future<void> _delete() async {
    final sound = widget.sound;
    final id = sound.id;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AccordDialog(
        title: 'Delete Sound',
        subtitle: 'Are you sure you want to delete ${sound.name}?',
        primaryLabel: 'Delete',
        tone: AccordDialogTone.danger,
      ),
    );
    if (ok != true || !mounted) return;
    final client = ref.accordClient;
    if (client == null) return;
    final result = await client.soundboard.delete(widget.spaceId, id);
    if (!mounted) return;
    if (result.ok) {
      ref
          .read(
            soundboardSoundsControllerProvider(
              widget.serverKey,
              widget.spaceId,
            ).notifier,
          )
          .remove(id);
    } else {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(result.errorOr('Failed to delete sound'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final sound = widget.sound;
    final creatorId = sound.creatorId;
    final member = creatorId == null
        ? null
        : ref.watch(
            accordMembersControllerProvider(
              widget.serverKey,
              widget.spaceId,
            ).select((m) => m?[creatorId]),
          );
    final cdnUrl = ref.watchCdnUrl();
    final creatorName = creatorId == null
        ? ''
        : accordMemberName(member, fallback: 'Unknown');
    Widget roundButton(
      IconData icon,
      Color color,
      String tooltip,
      VoidCallback onTap,
      Key key,
    ) => Tooltip(
      message: tooltip,
      child: InkResponse(
        key: key,
        onTap: onTap,
        radius: 14,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: colors.foreground,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: 59,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.hairline)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            SoundEmoji(
              sound: sound,
              serverKey: widget.serverKey,
              size: 24,
              fallbackColor: colors.interactive,
            ),
            const SizedBox(width: 43),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      sound.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        height: 20 / 16,
                        color: colors.dirtyWhite,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Preview',
                    child: InkResponse(
                      key: Key('soundboard-row-preview-${sound.id}'),
                      onTap: _preview,
                      radius: 12,
                      child: Icon(
                        AppIcons.volumeUp,
                        size: 16,
                        color: colors.interactive,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 210,
              child: creatorId == null
                  ? const SizedBox.shrink()
                  : Row(
                      children: [
                        AccordMemberAvatar(
                          avatarUrl: accordMemberAvatarUrl(member, cdnUrl),
                          initial: accordInitial(creatorName),
                          radius: 12,
                          backgroundColor: accordAvatarColor(
                            member?.user,
                            creatorId,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            creatorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              height: 20 / 16,
                              color: colors.dirtyWhite,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            SizedBox(
              width: 40,
              child: widget.canEdit && _hover
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        roundButton(
                          AppIcons.edit,
                          colors.interactive,
                          'Edit',
                          () => showSoundDialog(
                            context,
                            serverKey: widget.serverKey,
                            spaceId: widget.spaceId,
                            existing: sound,
                          ),
                          Key('soundboard-row-edit-${sound.id}'),
                        ),
                        const SizedBox(height: 4),
                        roundButton(
                          AppIcons.close,
                          colors.red,
                          'Delete',
                          _delete,
                          Key('soundboard-row-delete-${sound.id}'),
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
