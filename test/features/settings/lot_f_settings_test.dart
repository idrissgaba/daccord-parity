import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/shared/models/server_entity_key.dart';
import 'package:flutter_test/flutter_test.dart';

/// The lot F preferences: timed mutes and statuses, space and category
/// notification levels, pinned channels, hidden muted channels and voice
/// names — all persisted locally until the server stores them.
void main() {
  String key(String id) => ServerEntityKey('s', id).encoded;

  test('the new preferences survive a JSON round trip', () {
    final settings = AccordSettings(
      muteExpiries: {key('c1'): 1000},
      spaceNotifications: {key('sp'): 'mentions'},
      spaceSuppressEveryone: [key('sp')],
      spaceSuppressRoles: [key('sp')],
      pinnedChannels: [key('c2')],
      hideMutedChannels: [key('sp')],
      hiddenVoiceNames: [key('v1')],
      statusExpiries: const {'s': 2000},
      customStatusExpiries: const {'s': 3000},
    );
    final back = AccordSettings.fromJson(settings.toJson());
    expect(
      back.muteExpiry('s', 'c1'),
      DateTime.fromMillisecondsSinceEpoch(1000),
    );
    expect(back.spaceNotificationLevel('s', 'sp'), 'mentions');
    expect(back.suppressesEveryoneIn('s', 'sp'), isTrue);
    expect(back.suppressesRolesIn('s', 'sp'), isTrue);
    expect(back.isChannelPinned('s', 'c2'), isTrue);
    expect(back.hidesMutedChannels('s', 'sp'), isTrue);
    expect(back.hidesVoiceNames('s', 'v1'), isTrue);
    expect(back.statusExpiries, {'s': 2000});
    expect(back.customStatusExpiries, {'s': 3000});
  });

  test('a channel inherits its category, then its space', () {
    final settings = AccordSettings(
      channelNotifications: {key('cat'): 'nothing'},
      spaceNotifications: {key('sp'): 'all'},
    );
    expect(
      settings.effectiveNotificationLevel(
        's',
        'c1',
        categoryId: 'cat',
        spaceId: 'sp',
      ),
      'nothing',
    );
    expect(
      settings.effectiveNotificationLevel('s', 'c1', spaceId: 'sp'),
      'all',
    );
    expect(settings.effectiveNotificationLevel('s', 'c1'), isNull);
    final own = AccordSettings(
      channelNotifications: {key('c1'): 'mentions', key('cat'): 'nothing'},
    );
    expect(
      own.effectiveNotificationLevel('s', 'c1', categoryId: 'cat'),
      'mentions',
    );
  });

  test('older settings without the new keys load with empty defaults', () {
    final back = AccordSettings.fromJson(const {});
    expect(back.muteExpiries, isEmpty);
    expect(back.pinnedChannels, isEmpty);
    expect(back.statusExpiries, isEmpty);
  });
}
