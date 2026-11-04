part of 'message_pane.dart';

/// Resolves an attachment's server-returned URL/path to an absolute CDN URL.
String _attachmentUrl(AccordAttachment attachment, String? cdnUrl) =>
    AccordCDN.resolvePath(attachment.url, cdnUrl: cdnUrl ?? '');

/// How an attachment renders inline, resolved through the shared extension →
/// MIME → preview table so it can't drift from the type we upload it with.
///
/// Notably `image/*` is not enough on its own: it matches SVG and TIFF, which
/// Flutter can't decode and which therefore render as a broken image.
AttachmentPreview _previewOf(AccordAttachment attachment) =>
    attachmentPreviewFor(
      contentType: attachment.contentType,
      filename: attachment.filename,
    );

/// Best-effort conversion of an attachment's loosely-typed width/height to a
/// double for sizing hints.
double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// The file icon the reference client draws for [name]: a text page, an
/// archive, an image, else a plain file.
IconData fileKindIcon(String name, AttachmentPreview preview) {
  final lower = name.toLowerCase();
  if (RegExp(r'\.(zip|rar|7z|tar|gz|bz2|xz)$').hasMatch(lower)) {
    return AppIcons.fileArchive;
  }
  if (RegExp(
    r'\.(txt|md|log|csv|json|ya?ml|xml|ini|cfg|dart|js|ts|py|rs|go|c|h|cpp|java|kt|swift|html|css)$',
  ).hasMatch(lower)) {
    return AppIcons.fileText;
  }
  return switch (preview) {
    AttachmentPreview.image => AppIcons.imageOutlined,
    AttachmentPreview.video => AppIcons.movieOutlined,
    AttachmentPreview.audio => AppIcons.audiotrackOutlined,
    AttachmentPreview.none => AppIcons.insertDriveFileOutlined,
  };
}

/// Stands in for an attachment on a *sent* message that AutoMod hasn't
/// published: processing, held for a moderator, or finally refused. The copy
/// keeps the three apart — a file that's merely still being scanned must not
/// read like one that was rejected — and a refusal shows the server's reason
/// once it has been fetched for this (our own) upload.
class _PendingAttachmentTile extends StatelessWidget {
  const _PendingAttachmentTile({required this.upload});

  final PendingUpload upload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final (icon, title, detail) = switch (upload.status) {
      AutomodUploadStatus.quarantined => (
        AppIcons.visibilityOffOutlined,
        'Attachment under review',
        upload.reason ?? 'Held for a moderator to check before it is shown.',
      ),
      AutomodUploadStatus.rejected => (
        AppIcons.blockOutlined,
        'Attachment removed by AutoMod',
        upload.reason ?? "This file didn't pass the server's upload rules.",
      ),
      AutomodUploadStatus.removed => (
        AppIcons.blockOutlined,
        'Attachment removed by AutoMod',
        upload.reason ?? 'A moderator or server policy withdrew this file.',
      ),
      _ => (
        AppIcons.hourglassTopOutlined,
        'Attachment processing',
        'Being checked by AutoMod before it is shown to others.',
      ),
    };
    final refused = upload.isRefused;
    return Semantics(
      label: '$title. $detail',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.darkGray,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: refused
                ? colors.red.withValues(alpha: 0.5)
                : colors.gray.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: refused ? colors.red : colors.gray),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyMedium),
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.gray,
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

/// One pending attachment in the composer, as the reference client's card:
/// 218 px square on a lifted surface, the image (or a file icon) above the
/// name, and Spoiler · Modify · Remove in a small bar at the top right.
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    this.onRemove,
    this.onRename,
    this.onToggleSpoiler,
  });

  final PendingAttachment attachment;
  final VoidCallback? onRemove;
  final VoidCallback? onRename;
  final VoidCallback? onToggleSpoiler;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final unknown = attachment.isUnrecognised;
    final bytes = attachment.bytes;
    final isImage =
        attachment.preview == AttachmentPreview.image && bytes != null;
    final spoiler = attachment.isSpoiler;
    Widget media;
    if (isImage) {
      media = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          width: 200,
          height: 125,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) =>
              Icon(AppIcons.brokenImageOutlined, size: 48, color: colors.gray),
        ),
      );
      if (spoiler) {
        media = Stack(
          alignment: Alignment.center,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: media,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'SPOILER',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      }
      media = Padding(
        padding: const EdgeInsets.only(top: 25),
        child: SizedBox(width: 200, height: 125, child: media),
      );
    } else {
      media = SizedBox(
        width: 200,
        height: 144,
        child: Icon(
          fileKindIcon(attachment.name, attachment.preview),
          size: 96,
          color: const Color(0xFFC6CAF7),
        ),
      );
    }
    final name = spoiler
        ? attachment.name.substring(kSpoilerPrefix.length)
        : attachment.name;
    return Tooltip(
      message:
          '${attachment.name}\n'
          '${unknown ? 'Unrecognised type' : attachment.contentType} · '
          '${formatFileSize(attachment.size)}',
      waitDuration: const Duration(milliseconds: 600),
      child: Container(
        key: Key('attachment-chip-${attachment.name}'),
        width: 218,
        height: 218,
        decoration: BoxDecoration(
          color: popoverSurfaceColor(colors),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.selection),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 9,
              top: 9,
              width: 200,
              height: 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  media,
                  const Spacer(),
                  SizedBox(
                    height: 26,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 18 / 14,
                          color: colors.dirtyWhite,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: -15,
              top: 1,
              child: Material(
                color: Color.alphaBlend(
                  colors.dirtyWhite.withValues(alpha: 0.08),
                  colors.background,
                ),
                borderRadius: BorderRadius.circular(4),
                elevation: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ChipAction(
                      tooltip: 'Spoiler Attachment',
                      icon: spoiler
                          ? AppIcons.visibilityOff
                          : AppIcons.visibility,
                      onPressed: onToggleSpoiler,
                    ),
                    _ChipAction(
                      tooltip: 'Modify Attachment',
                      icon: AppIcons.edit,
                      onPressed: onRename,
                    ),
                    _ChipAction(
                      tooltip: 'Remove Attachment',
                      icon: AppIcons.deleteOutline,
                      color: const Color(0xFFF87E7A),
                      onPressed: onRemove,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One 32 px button of the attachment card's action bar.
class _ChipAction extends StatelessWidget {
  const _ChipAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onPressed,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            icon,
            size: 20,
            color: onPressed == null
                ? colors.gray
                : (color ?? colors.interactive),
          ),
        ),
      ),
    );
  }
}

/// An inline image attachment, constrained to a readable size and preserving
/// the server-provided aspect ratio when available.
class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({required this.url, this.width, this.height});

  final String url;
  final double? width;
  final double? height;

  static const _maxWidth = 400.0;
  static const _maxHeight = 350.0;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    double? renderWidth = width;
    double? renderHeight = height;
    if (renderWidth != null && renderWidth > _maxWidth) {
      final scale = _maxWidth / renderWidth;
      renderWidth = _maxWidth;
      if (renderHeight != null) renderHeight *= scale;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _maxWidth,
          maxHeight: _maxHeight,
        ),
        child: CachedNetworkImage(
          imageUrl: url,
          width: renderWidth,
          height: renderHeight,
          fit: BoxFit.cover,
          placeholder: (_, _) => Container(
            width: renderWidth ?? 200,
            height: renderHeight ?? 150,
            color: colors.darkGray,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (_, _, _) => Container(
            padding: const EdgeInsets.all(8),
            color: colors.darkGray,
            child: Icon(AppIcons.brokenImageOutlined, color: colors.gray),
          ),
        ),
      ),
    );
  }
}

/// A "loading older" / "beginning of channel" header rendered above the
/// message list. Watches the messages controller so the spinner and end-of-
/// history hint reflect [AccordMessagesController.isLoadingOlder]/
/// [hasMoreOlder] as they change.
class _OlderHistoryHeader extends ConsumerWidget {
  const _OlderHistoryHeader({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild whenever the message list mutates (which also covers the
    // controller bumping state at the start/end of loadOlder).
    ref.watch(
      accordMessagesControllerProvider(
        ref.readActiveServerKey() ?? '',
        channelId,
      ),
    );
    final notifier = ref.read(
      accordMessagesControllerProvider(
        ref.readActiveServerKey() ?? '',
        channelId,
      ).notifier,
    );
    if (notifier.isLoadingOlder) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!notifier.hasMoreOlder) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            "Beginning of channel",
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      );
    }
    return const SizedBox(height: 12);
  }
}
