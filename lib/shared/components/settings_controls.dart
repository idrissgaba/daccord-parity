import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// The reference client's settings-form primitives, shared by the user
/// settings modal, the full-screen server and channel settings, and the
/// editors they open. Measured on the 2025 dark theme at 1920×927: section
/// titles 24/500, row labels 16/500, descriptions 14/400 in the interactive
/// grey, 48×24 switches, 40 px fields with a 12 % black fill and a 20 % border.

/// The fill and border every settings field (input, select, search) shares.
BoxDecoration settingsFieldDecoration(
  BonfireThemeExtension colors, {
  bool focused = false,
}) => BoxDecoration(
  color: Colors.black.withValues(alpha: 0.12),
  borderRadius: BorderRadius.circular(8),
  border: Border.all(
    color: focused
        ? colors.primary
        : const Color(0xFF9696A0).withValues(alpha: 0.2),
  ),
);

/// Text styles of the settings forms.
abstract final class SettingsText {
  static TextStyle title(BonfireThemeExtension colors) => TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 32 / 24,
    color: colors.dirtyWhite,
  );

  /// A page heading inside the full-screen server settings (20/600).
  static TextStyle pageTitle(BonfireThemeExtension colors) => TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 24 / 20,
    color: colors.dirtyWhite,
  );

  static TextStyle label(BonfireThemeExtension colors) => TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 20 / 16,
    color: colors.dirtyWhite,
  );

  static TextStyle description(BonfireThemeExtension colors) => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 18 / 14,
    color: colors.interactive,
  );

  static TextStyle body(BonfireThemeExtension colors) => TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 20 / 16,
    color: colors.dirtyWhite,
  );
}

/// A 24/500 section title ("Voice", "Camera", "Theme" …). [anchorKey] lets the
/// sidebar's sub-items scroll the page to it.
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.text, {super.key, this.bottom = 32});

  final String text;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Text(
        text,
        style: SettingsText.title(colors),
        semanticsLabel: text,
      ),
    );
  }
}

/// The hairline that closes a section: 56 px under its last row, 40 above
/// the next title.
class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key, this.top = 56, this.bottom = 40});

  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      height: 1,
      margin: EdgeInsets.only(top: top, bottom: bottom),
      color: colors.hairline,
    );
  }
}

/// A 16/500 label above a field ("Microphone", "Camera"), 8 px over it.
class SettingsFieldLabel extends StatelessWidget {
  const SettingsFieldLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Flexible(child: Text(text, style: SettingsText.label(colors))),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
    );
  }
}

/// A label with an optional description on the left and a control on the
/// right. Rows sit 32 px apart (see [SettingsRows]).
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.description,
    this.descriptionWidget,
    this.trailing,
    this.enabled = true,
  });

  final String label;
  final String? description;
  final Widget? descriptionWidget;
  final Widget? trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final alone = description == null && descriptionWidget == null;
    final row = Row(
      crossAxisAlignment: alone
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: SettingsText.label(colors)),
              if (description != null) ...[
                const SizedBox(height: 4),
                Text(description!, style: SettingsText.description(colors)),
              ],
              if (descriptionWidget != null) ...[
                const SizedBox(height: 4),
                DefaultTextStyle.merge(
                  style: SettingsText.description(colors),
                  child: descriptionWidget!,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 16), trailing!],
      ],
    );
    return enabled ? row : Opacity(opacity: 0.5, child: row);
  }
}

/// A [SettingsRow] whose control is an [AccordSwitch]; the whole row toggles.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return MergeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged(!value),
        child: SettingsRow(
          label: label,
          description: description,
          enabled: onChanged != null,
          trailing: AccordSwitch(value: value, onChanged: onChanged),
        ),
      ),
    );
  }
}

/// Lays [children] out 32 px apart — the reference client's row rhythm.
class SettingsRows extends StatelessWidget {
  const SettingsRows({super.key, required this.children, this.gap = 32});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) SizedBox(height: gap),
          child,
        ],
      ],
    );
  }
}

/// The reference client's 48×24 pill switch: accent when on, a 12 % black
/// well with a 20 % border when off, a white 16 px knob.
class AccordSwitch extends StatelessWidget {
  const AccordSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final onChanged = this.onChanged;
    final track = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 48,
      height: 24,
      decoration: BoxDecoration(
        color: value ? colors.primary : Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? const Color(0xFF94949C).withValues(alpha: 0.12)
              : const Color(0xFF9696A0).withValues(alpha: 0.2),
        ),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      child: MouseRegion(
        cursor: onChanged == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged(!value),
          child: Opacity(opacity: onChanged == null ? 0.5 : 1, child: track),
        ),
      ),
    );
  }
}

/// One option of an [AccordSelect].
class AccordSelectOption<T> {
  const AccordSelectOption(this.value, this.label);

  final T value;
  final String label;
}

/// A 40 px dropdown field whose list opens in the single Accord menu, as
/// wide as the field and right under it.
class AccordSelect<T> extends StatelessWidget {
  const AccordSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.leadingIcon,
    this.placeholder,
  });

  final T value;
  final List<AccordSelectOption<T>> options;
  final ValueChanged<T>? onChanged;
  final IconData? leadingIcon;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final onChanged = this.onChanged;
    String? label;
    for (final option in options) {
      if (option.value == value) label = option.label;
    }
    label ??= placeholder ?? '';
    final field = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: settingsFieldDecoration(colors),
      child: Row(
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 16, color: colors.dirtyWhite),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SettingsText.label(colors),
            ),
          ),
          Icon(AppIcons.expandMore, size: 18, color: colors.dirtyWhite),
        ],
      ),
    );
    return Builder(
      builder: (context) => MouseRegion(
        cursor: onChanged == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onChanged == null
              ? null
              : () {
                  final box = context.findRenderObject() as RenderBox?;
                  final origin = box?.localToGlobal(
                    Offset(0, box.size.height + 4),
                  );
                  showAccordContextMenu(
                    context,
                    globalPosition: origin,
                    width: box?.size.width,
                    title: placeholder,
                    entries: [
                      for (final option in options)
                        AccordMenuEntry(
                          label: option.label,
                          radio: option.value == value,
                          onSelected: () => onChanged(option.value),
                        ),
                    ],
                  );
                },
          child: Opacity(opacity: onChanged == null ? 0.5 : 1, child: field),
        ),
      ),
    );
  }
}

/// A 20 px radio row: an accent disc with a white 8 px dot when selected, a
/// grey ring otherwise, then the label and an optional description.
class AccordRadioRow extends StatelessWidget {
  const AccordRadioRow({
    super.key,
    required this.label,
    this.description,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? description;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final disc = Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.primary : Colors.transparent,
        border: selected
            ? null
            : Border.all(color: colors.interactive, width: 2),
      ),
      child: selected
          ? Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              disc,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: SettingsText.body(colors).copyWith(
                        fontWeight: selected
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        description!,
                        style: SettingsText.description(colors),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How an [AccordButton] is coloured.
enum AccordButtonTone { primary, secondary, danger, success }

/// The reference client's filled button: 40 px (or 32 when [small]), 8 px
/// corners, 16/500 (14/500 small) white label.
class AccordButton extends StatelessWidget {
  const AccordButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = AccordButtonTone.primary,
    this.small = false,
    this.icon,
    this.minWidth = 0,
  });

  final String label;
  final VoidCallback? onPressed;
  final AccordButtonTone tone;
  final bool small;
  final IconData? icon;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final background = switch (tone) {
      AccordButtonTone.primary => colors.primary,
      AccordButtonTone.secondary => const Color(
        0xFF94949C,
      ).withValues(alpha: 0.12),
      AccordButtonTone.danger => const Color(0xFFD22D39),
      AccordButtonTone.success => const Color(0xFF008545),
    };
    final foreground = tone == AccordButtonTone.secondary
        ? colors.dirtyWhite
        : Colors.white;
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.black.withValues(alpha: 0.1),
          child: Container(
            height: small ? 32 : 40,
            constraints: BoxConstraints(minWidth: minWidth),
            padding: EdgeInsets.symmetric(horizontal: small ? 12 : 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: small ? 16 : 18, color: foreground),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: small ? 14 : 16,
                      fontWeight: FontWeight.w500,
                      height: (small ? 18 : 20) / (small ? 14 : 16),
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row that links to another settings page ("Related Settings" cards): a
/// 40 px icon tile, title and description, chevron at the right.
class SettingsLinkCard extends StatelessWidget {
  const SettingsLinkCard({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? description;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF94949C).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: colors.dirtyWhite),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SettingsText.label(colors)),
                  if (description != null) ...[
                    const SizedBox(height: 2),
                    Text(description!, style: SettingsText.description(colors)),
                  ],
                ],
              ),
            ),
            trailing ??
                Icon(AppIcons.chevronRight, size: 20, color: colors.dirtyWhite),
          ],
        ),
      ),
    );
  }
}
