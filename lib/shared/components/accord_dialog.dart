import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// How the confirming button of an [AccordDialog] is coloured.
enum AccordDialogTone { primary, danger }

/// The reference client's confirmation modal: 480 px wide on the raised
/// surface, 12 px corners and a hairline border, the ✕ in the top-right
/// corner, a 20/600 title over a muted 16 px subtitle, an optional [body], and
/// two equal 40 px buttons along the bottom — the secondary on the left, the
/// confirming one on the right. The secondary button (and the ✕) pop `false`;
/// [onPrimary] defaults to popping `true`.
class AccordDialog extends StatelessWidget {
  const AccordDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.body,
    required this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel = 'Cancel',
    this.tone = AccordDialogTone.primary,
    this.primaryEnabled = true,
  });

  final String title;
  final String? subtitle;
  final Widget? body;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String secondaryLabel;
  final AccordDialogTone tone;

  /// When false the confirming button is dimmed and inert (a form that is
  /// not complete yet, like "Upload a Sound" before a file and a name).
  final bool primaryEnabled;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final surface = Color.alphaBlend(
      colors.dirtyWhite.withValues(alpha: 0.045),
      colors.background,
    );
    final confirmColor = tone == AccordDialogTone.danger
        ? const Color(0xFFD22D39)
        : colors.primary;
    Widget button(
      String label, {
      required Color background,
      required Color foreground,
      required Color border,
      required VoidCallback? onPressed,
      Key? key,
    }) => Expanded(
      child: SizedBox(
        height: 40,
        child: TextButton(
          key: key,
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            disabledBackgroundColor: background.withValues(alpha: 0.5),
            disabledForegroundColor: foreground.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: border),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
    return Dialog(
      backgroundColor: surface,
      insetPadding: const EdgeInsets.all(16),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.hairline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 32),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        height: 24 / 20,
                        color: colors.dirtyWhite,
                      ),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 16,
                        height: 20 / 16,
                        color: colors.interactive,
                      ),
                    ),
                  ],
                  if (body != null) ...[const SizedBox(height: 24), body!],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      button(
                        secondaryLabel,
                        key: const Key('accord-dialog-secondary'),
                        background: colors.selection.withValues(alpha: 0.12),
                        foreground: colors.dirtyWhite,
                        border: Colors.white.withValues(alpha: 0.04),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      const SizedBox(width: 8),
                      button(
                        primaryLabel,
                        key: const Key('accord-dialog-primary'),
                        background: confirmColor,
                        foreground: Colors.white,
                        border: Colors.white.withValues(alpha: 0.08),
                        onPressed: !primaryEnabled
                            ? null
                            : onPrimary ??
                                  () => Navigator.of(context).pop(true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(false),
                icon: Icon(AppIcons.close, size: 20, color: colors.interactive),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
