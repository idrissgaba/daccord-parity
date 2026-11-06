import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/settings/models/custom_keybind.dart';
import 'package:bonfire/features/spaces/utils/home_shortcuts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

AccordChannel _channel(String id, {String type = 'text', String? parent}) =>
    AccordChannel.fromJson({
      'id': id,
      'name': id,
      'type': type,
      if (parent != null) 'parent_id': parent,
    });

void main() {
  test('mute and deafen chords map to physical keys for global watching', () {
    expect(
      defaultBindingFor(HomeShortcut.toggleMute).physicalUsage,
      PhysicalKeyboardKey.keyM.usbHidUsage,
    );
    expect(
      defaultBindingFor(HomeShortcut.toggleDeafen).physicalUsage,
      PhysicalKeyboardKey.keyD.usbHidUsage,
    );
    final recorded = bindingFromCustom(
      CustomKeybind(
        action: HomeShortcut.toggleMute.name,
        keyId: LogicalKeyboardKey.f9.keyId,
        physicalKey: PhysicalKeyboardKey.f9.usbHidUsage,
      ),
    );
    expect(recorded!.physicalUsage, PhysicalKeyboardKey.f9.usbHidUsage);
    expect(defaultBindingFor(HomeShortcut.showShortcuts).physicalUsage, isNull);
  });

  group('matchHomeShortcut', () {
    test('maps the chords users know from other chat apps', () {
      expect(
        matchHomeShortcut(
          pressed: LogicalKeyboardKey.keyK,
          control: true,
          shift: false,
          alt: false,
        ),
        HomeShortcut.quickSwitcher,
      );
      expect(
        matchHomeShortcut(
          pressed: LogicalKeyboardKey.arrowDown,
          control: false,
          shift: false,
          alt: true,
        ),
        HomeShortcut.nextChannel,
      );
      expect(
        matchHomeShortcut(
          pressed: LogicalKeyboardKey.arrowUp,
          control: true,
          shift: false,
          alt: true,
        ),
        HomeShortcut.previousSpace,
      );
      expect(
        matchHomeShortcut(
          pressed: LogicalKeyboardKey.keyM,
          control: true,
          shift: true,
          alt: false,
        ),
        HomeShortcut.toggleMute,
      );
    });

    test('a plain or differently modified key is nobody\'s shortcut', () {
      expect(
        matchHomeShortcut(
          pressed: LogicalKeyboardKey.keyK,
          control: false,
          shift: false,
          alt: false,
        ),
        isNull,
      );
      // Ctrl+Shift+K is not Ctrl+K: typing must never jump channels.
      expect(
        matchHomeShortcut(
          pressed: LogicalKeyboardKey.keyK,
          control: true,
          shift: true,
          alt: false,
        ),
        isNull,
      );
    });

    test('describe prints the chord the dialog shows', () {
      final mute = homeShortcutBindings.firstWhere(
        (b) => b.shortcut == HomeShortcut.toggleMute,
      );
      expect(mute.describe(), 'Ctrl+Shift+M');
      expect(mute.describe(mac: true), '⌘+⇧+M');
      final up = homeShortcutBindings.firstWhere(
        (b) => b.shortcut == HomeShortcut.previousChannel,
      );
      expect(up.describe(), 'Alt+↑');
    });
  });

  group('custom keybinds', () {
    test('a recorded keybind triggers its action and wins over a built-in', () {
      final custom = [
        CustomKeybind(
          action: HomeShortcut.toggleMute.name,
          keyId: LogicalKeyboardKey.keyK.keyId,
          keyLabel: 'K',
          control: true,
        ),
      ];
      // Ctrl+K is the built-in quick switcher; the user bound it to mute.
      expect(
        matchHomeShortcut(
          pressed: LogicalKeyboardKey.keyK,
          control: true,
          shift: false,
          alt: false,
          custom: custom,
        ),
        HomeShortcut.toggleMute,
      );
      expect(
        effectiveBindings(custom).first.describe(),
        'Ctrl+K',
      );
    });

    test('a recorded keybind also matches on its physical key', () {
      final custom = [
        CustomKeybind(
          action: HomeShortcut.toggleDeafen.name,
          keyId: LogicalKeyboardKey.keyJ.keyId,
          physicalKey: PhysicalKeyboardKey.keyJ.usbHidUsage,
          keyLabel: 'J',
          control: true,
          shift: true,
        ),
      ];
      // Ctrl held: the platform reported some other logical key for J.
      expect(
        matchHomeShortcut(
          pressed: const LogicalKeyboardKey(0x1100000094),
          control: true,
          shift: true,
          alt: false,
          physicalPressed: PhysicalKeyboardKey.keyJ.usbHidUsage,
          custom: custom,
        ),
        HomeShortcut.toggleDeafen,
      );
    });

    test('a removed built-in no longer fires, a replacement does', () {
      expect(
        matchHomeShortcut(
          pressed: LogicalKeyboardKey.keyK,
          control: true,
          shift: false,
          alt: false,
          disabledDefaults: [HomeShortcut.quickSwitcher.name],
        ),
        isNull,
      );
      final custom = [
        CustomKeybind(
          action: HomeShortcut.quickSwitcher.name,
          keyId: LogicalKeyboardKey.keyP.keyId,
          keyLabel: 'P',
          control: true,
        ),
      ];
      expect(
        matchHomeShortcut(
          pressed: LogicalKeyboardKey.keyP,
          control: true,
          shift: false,
          alt: false,
          custom: custom,
          disabledDefaults: [HomeShortcut.quickSwitcher.name],
        ),
        HomeShortcut.quickSwitcher,
      );
    });

    test('an unrecorded or unknown keybind is ignored', () {
      final custom = [
        CustomKeybind(action: HomeShortcut.toggleMute.name),
        const CustomKeybind(action: 'no-such-action', keyId: 0x61),
      ];
      expect(effectiveBindings(custom).length, homeShortcutBindings.length);
    });

    test('round-trips through json', () {
      const keybind = CustomKeybind(
        action: 'nextChannel',
        keyId: 0x100000301,
        keyLabel: '↓',
        alt: true,
      );
      expect(CustomKeybind.fromJson(keybind.toJson()), keybind);
    });
  });

  group('physicalKeyName', () {
    test('names letters, digits, function and navigation keys', () {
      expect(physicalKeyName(PhysicalKeyboardKey.keyP.usbHidUsage), 'P');
      expect(physicalKeyName(PhysicalKeyboardKey.digit1.usbHidUsage), '1');
      expect(physicalKeyName(PhysicalKeyboardKey.digit0.usbHidUsage), '0');
      expect(physicalKeyName(PhysicalKeyboardKey.f5.usbHidUsage), 'F5');
      expect(physicalKeyName(PhysicalKeyboardKey.arrowUp.usbHidUsage), '↑');
      expect(physicalKeyName(PhysicalKeyboardKey.numpad0.usbHidUsage), 'Numpad 0');
      expect(physicalKeyName(0x1234), isNull);
    });
  });

  group('orderedNavigableChannelIds', () {
    test('walks the list the way the sidebar draws it, skipping categories', () {
      final channels = [
        _channel('cat-a', type: 'category'),
        _channel('a1', parent: 'cat-a'),
        _channel('loose'),
        _channel('cat-b', type: 'category'),
        _channel('b1', type: 'voice', parent: 'cat-b'),
        _channel('a2', parent: 'cat-a'),
      ];
      expect(orderedNavigableChannelIds(channels), [
        'loose',
        'a1',
        'a2',
        'b1',
      ]);
    });
  });

  group('adjacentId', () {
    test('steps forward and back, wrapping at the ends', () {
      const ids = ['a', 'b', 'c'];
      expect(adjacentId(ids, 'a', forward: true), 'b');
      expect(adjacentId(ids, 'c', forward: true), 'a');
      expect(adjacentId(ids, 'a', forward: false), 'c');
    });

    test('starts from an end when nothing is current', () {
      const ids = ['a', 'b'];
      expect(adjacentId(ids, null, forward: true), 'a');
      expect(adjacentId(ids, 'zz', forward: false), 'b');
      expect(adjacentId(const [], 'a', forward: true), isNull);
    });
  });

  group('orderBySavedOrder', () {
    test('saved order first, then the rest as given', () {
      expect(orderBySavedOrder(['x', 'y', 'z'], ['z', 'gone', 'x']), [
        'z',
        'x',
        'y',
      ]);
    });
  });

  group('lot F chords', () {
    HomeShortcut? match(
      LogicalKeyboardKey key, {
      bool control = false,
      bool shift = false,
      bool alt = false,
    }) => matchHomeShortcut(
      pressed: key,
      control: control,
      shift: shift,
      alt: alt,
    );

    test('the reference client\'s chords map to their actions', () {
      expect(
        match(LogicalKeyboardKey.arrowDown, alt: true, shift: true),
        HomeShortcut.nextUnread,
      );
      expect(
        match(
          LogicalKeyboardKey.arrowUp,
          control: true,
          alt: true,
          shift: true,
        ),
        HomeShortcut.previousMention,
      );
      expect(
        match(LogicalKeyboardKey.arrowLeft, alt: true),
        HomeShortcut.historyBack,
      );
      expect(
        match(LogicalKeyboardKey.arrowRight, control: true, alt: true),
        HomeShortcut.toggleDmHome,
      );
      expect(
        match(LogicalKeyboardKey.keyV, control: true, alt: true, shift: true),
        HomeShortcut.currentCall,
      );
      expect(
        match(LogicalKeyboardKey.keyN, control: true, shift: true),
        HomeShortcut.createOrJoinServer,
      );
      expect(
        match(LogicalKeyboardKey.enter, control: true),
        HomeShortcut.answerCall,
      );
      expect(
        match(LogicalKeyboardKey.quote, control: true),
        HomeShortcut.startDmCall,
      );
      expect(
        match(LogicalKeyboardKey.keyB, control: true, shift: true),
        HomeShortcut.toggleSoundboard,
      );
      expect(
        match(LogicalKeyboardKey.escape, shift: true),
        HomeShortcut.markSpaceRead,
      );
      expect(
        match(LogicalKeyboardKey.keyT, control: true, shift: true),
        HomeShortcut.createGroupDm,
      );
      expect(match(LogicalKeyboardKey.keyP, control: true), HomeShortcut.togglePins);
      expect(match(LogicalKeyboardKey.keyI, control: true), HomeShortcut.toggleInbox);
      expect(
        match(LogicalKeyboardKey.keyE, control: true, shift: true),
        HomeShortcut.markTopInboxRead,
      );
      expect(match(LogicalKeyboardKey.keyU, control: true), HomeShortcut.toggleMembers);
      expect(match(LogicalKeyboardKey.keyE, control: true), HomeShortcut.emojiPicker);
      expect(match(LogicalKeyboardKey.keyG, control: true), HomeShortcut.gifPicker);
      expect(match(LogicalKeyboardKey.keyS, control: true), HomeShortcut.stickerPicker);
      expect(
        match(LogicalKeyboardKey.keyU, control: true, shift: true),
        HomeShortcut.uploadFile,
      );
      expect(
        match(LogicalKeyboardKey.keyL, control: true, shift: true),
        HomeShortcut.copyChannelLink,
      );
      expect(
        match(LogicalKeyboardKey.keyH, control: true, shift: true),
        HomeShortcut.getHelp,
      );
      expect(match(LogicalKeyboardKey.keyF, control: true), HomeShortcut.search);
    });

    test('Esc declines a ringing call before it marks the channel read', () {
      expect(
        matchHomeShortcuts(
          pressed: LogicalKeyboardKey.escape,
          control: false,
          shift: false,
          alt: false,
        ),
        [HomeShortcut.declineCall, HomeShortcut.markChannelRead],
      );
      expect(passThroughShortcuts, contains(HomeShortcut.markChannelRead));
      expect(passThroughShortcuts, isNot(contains(HomeShortcut.declineCall)));
    });

    test('every action has a built-in chord and a label', () {
      for (final shortcut in HomeShortcut.values) {
        expect(defaultBindingFor(shortcut).label, isNotEmpty);
      }
    });

    test('key caps spell the chord the dialog draws', () {
      expect(
        defaultBindingFor(HomeShortcut.previousMention).keyCaps(),
        ['CTRL', 'SHIFT', 'ALT', '↑'],
      );
      expect(defaultBindingFor(HomeShortcut.declineCall).keyCaps(), ['ESC']);
      expect(defaultBindingFor(HomeShortcut.startDmCall).keyCaps(), [
        'CTRL',
        "'",
      ]);
      expect(defaultBindingFor(HomeShortcut.quickSwitcher).keyCaps(mac: true), [
        '⌘',
        'K',
      ]);
    });

    test('the combo cards list each section in the reference order', () {
      final sections = <ShortcutSection>[];
      for (final card in keyboardComboCards) {
        if (sections.isEmpty || sections.last != card.section) {
          sections.add(card.section);
        }
      }
      expect(sections, ShortcutSection.values);
      expect(
        keyboardComboCards
            .where((c) => c.section == ShortcutSection.navigation)
            .map((c) => c.label)
            .toList(),
        [
          'Navigate between servers',
          'Navigate between channels',
          'Navigate forward and backward in page history',
          'Navigate between unread channels',
          'Navigate between unread channels with mentions',
          'Navigate to current call',
          'Toggle between last server and DMs',
          'Toggle QuickSwitcher',
          'Create or join a server',
        ],
      );
    });
  });

  group('adjacentMatchingId', () {
    const ids = ['a', 'b', 'c', 'd'];
    test('finds the next match, wrapping, never the current one', () {
      bool unread(String id) => id == 'a' || id == 'c';
      expect(
        adjacentMatchingId(ids, 'a', forward: true, test: unread),
        'c',
      );
      expect(
        adjacentMatchingId(ids, 'c', forward: true, test: unread),
        'a',
      );
      expect(
        adjacentMatchingId(ids, 'b', forward: false, test: unread),
        'a',
      );
      expect(
        adjacentMatchingId(ids, 'a', forward: true, test: (id) => id == 'a'),
        isNull,
      );
      expect(adjacentMatchingId(ids, null, forward: false, test: unread), 'c');
    });
  });
}
