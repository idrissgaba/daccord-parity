import 'dart:math' as math;

import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/spaces/utils/home_shortcuts.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'keyboard_shortcuts_dialog/combo_grid.dart';

/// The scrim behind the dialog (black at 72 %, as the reference client's
/// modals).
const Color _kScrim = Color(0xB8000000);

/// Lists every keyboard shortcut in force (Ctrl+/ and Settings › Keybinds),
/// laid out as the reference client's "Keyboard Combos" modal. An action the
/// user recorded a keybind for shows that chord in place of the built-in one.
Future<void> showKeyboardShortcutsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: _kScrim,
    builder: (_) => const KeyboardShortcutsDialog(),
  );
}

class KeyboardShortcutsDialog extends ConsumerWidget {
  const KeyboardShortcutsDialog({super.key});

  /// The modal's size: 950 × 741 at the reference viewport.
  static const double width = 950;
  static const double height = 741;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final mac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    final settings = ref.watch(settingsControllerProvider);
    final effective = effectiveBindings(
      settings.keybinds,
      disabledDefaults: settings.disabledDefaultKeybinds,
    );
    // One line of key caps per action: the first binding in force for it.
    List<List<String>> chordsOf(KeyboardComboCard card) => [
      ...card.fixed,
      for (final action in card.actions)
        if (effective.firstWhereOrNull((b) => b.shortcut == action)
            case final binding?)
          binding.keyCaps(mac: mac),
    ];
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: colors.background,
      insetPadding: const EdgeInsets.all(16),
      // Material caps dialogs at 560 px; this modal is wider.
      constraints: const BoxConstraints(),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        key: const Key('keyboard-combos'),
        width: math.min(width, screen.width - 32),
        height: math.min(height, screen.height - 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ComboHeader(mac: mac),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, section) in ShortcutSection.values.indexed)
                      if (keyboardComboCards.any((c) => c.section == section))
                        _ComboSection(
                          key: Key('keyboard-combos-${section.name}'),
                          first: i == 0,
                          title: shortcutSectionTitle(section),
                          cards: [
                            for (final card in keyboardComboCards)
                              if (card.section == section)
                                (label: card.label, chords: chordsOf(card)),
                          ],
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
