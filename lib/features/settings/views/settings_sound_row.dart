import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/shared/components/settings_controls.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The link colour of "Preview Sound".
const Color _kLinkColor = Color(0xFF4D96EE);

/// One sound effect as the reference client lists it: its name, a "Preview
/// Sound" link under it, and a switch.
class SettingsSoundRow extends ConsumerWidget {
  const SettingsSoundRow({
    super.key,
    required this.name,
    required this.label,
    this.value,
    this.onChanged,
  });

  final String name;
  final String label;

  /// A switch other than the sound's own on/off (with [onChanged]): "New
  /// Message in the channel I'm currently reading" previews the message
  /// sound but switches a separate preference.
  final bool? value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final enabled = settings.soundsEnabled;
    return SettingsRow(
      key: Key('settings-sound-$name'),
      label: label,
      enabled: enabled,
      descriptionWidget: GestureDetector(
        onTap: enabled ? () => soundManager.preview(name) : null,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: const Text(
            'Preview Sound',
            style: TextStyle(color: _kLinkColor),
          ),
        ),
      ),
      trailing: AccordSwitch(
        value: value ?? !settings.disabledSounds.contains(name),
        onChanged: enabled
            ? (onChanged ?? (on) => controller.setSoundEnabled(name, on))
            : null,
      ),
    );
  }
}

/// A row that unfolds more rows ("Show 18 more sounds ⌄"), as the reference
/// client tucks away its long lists.
class SettingsExpander extends StatefulWidget {
  const SettingsExpander({
    super.key,
    required this.label,
    this.description,
    required this.children,
  });

  final String label;
  final String? description;
  final List<Widget> children;

  @override
  State<SettingsExpander> createState() => _SettingsExpanderState();
}

class _SettingsExpanderState extends State<SettingsExpander> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = !_open),
          child: SettingsRow(
            label: widget.label,
            description: widget.description,
            trailing: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF94949C).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  AppIcons.expandMore,
                  size: 20,
                  color: colors.dirtyWhite,
                ),
              ),
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 32),
          SettingsRows(children: widget.children),
        ],
      ],
    );
  }
}
