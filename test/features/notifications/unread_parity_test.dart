import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/global_unread.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/notifications/controllers/inbox_mentions.dart';
import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:bonfire/features/notifications/services/taskbar_badge.dart';
import 'package:bonfire/features/notifications/utils/notification_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AccordMessage _message(
  String id, {
  List<String> mentions = const [],
  List<String> roles = const [],
  bool everyone = false,
}) => AccordMessage.fromJson({
  'id': id,
  'channel_id': 'c',
  'space_id': 's',
  'author_id': 'u-other',
  'content': 'hi',
  'timestamp': '2026-11-06T10:00:00Z',
  'mentions': mentions,
  'mention_roles': roles,
  'mention_everyone': everyone,
});

void main() {
  group('muted channels', () {
    const snapshot = ReadStateSnapshot(
      entries: {
        'muted': ReadEntry(channelId: 'muted', spaceId: 's', mentions: 1),
        'quiet': ReadEntry(channelId: 'quiet', spaceId: 's'),
      },
    );

    test('lose their pill but keep their mentions', () {
      expect(
        snapshot.isUnreadVisible('muted', mutedChannels: {'muted'}),
        isFalse,
      );
      expect(snapshot.visibleMentionCount('muted'), 1);
      expect(snapshot.isUnreadVisible('quiet'), isTrue);
    });

    test('never light the rail, but their mentions badge it', () {
      const onlyMuted = ReadStateSnapshot(
        entries: {
          'muted': ReadEntry(channelId: 'muted', spaceId: 's', mentions: 2),
        },
      );
      expect(
        onlyMuted.spaceShowsUnread(
          's',
          spaceMuted: false,
          mutedChannels: {'muted'},
        ),
        isFalse,
      );
      expect(onlyMuted.visibleMentionsInSpace('s', spaceMuted: false), 2);
    });

    test('a muted category mutes its channels', () {
      final channels = [
        AccordChannel.fromJson({'id': 'cat', 'type': 'category'}),
        AccordChannel.fromJson({'id': 'a', 'type': 'text', 'parent_id': 'cat'}),
        AccordChannel.fromJson({'id': 'b', 'type': 'text'}),
      ];
      expect(effectiveMutedChannels({'cat'}, channels), {'cat', 'a'});
      expect(effectiveMutedChannels(const {}, channels), isEmpty);
    });

    test('the taskbar counts their mentions only', () {
      final unread = foldGlobalUnread([
        const ReadStateSnapshot(
          entries: {
            'muted': ReadEntry(channelId: 'muted', spaceId: 's'),
          },
        ),
      ], mutedChannels: {'muted'});
      expect(unread.isEmpty, isTrue);

      final mentioned = foldGlobalUnread([snapshot], mutedChannels: {'muted'});
      expect(mentioned.mentionCount, 1);
      expect(mentioned.hasUnread, isTrue);
    });
  });

  group('web tab title', () {
    test('mentions as a count, unread as a dot, nothing when read', () {
      expect(
        unreadTitlePrefix(const GlobalUnread(hasUnread: true, mentionCount: 3)),
        '(3) ',
      );
      expect(unreadTitlePrefix(const GlobalUnread(hasUnread: true)), '• ');
      expect(unreadTitlePrefix(const GlobalUnread()), '');
    });
  });

  group('New Message in the channel I am currently reading', () {
    String? sound({required bool chime}) => SoundManager.soundForMessage(
      isMention: false,
      isVisibleChannel: true,
      focused: true,
      enabled: true,
      volume: 1,
      chimeInVisibleChannel: chime,
    );

    test('chimes the open channel only when switched on', () {
      expect(sound(chime: false), isNull);
      expect(sound(chime: true), 'message_received');
    });
  });

  group('friend activity', () {
    test('coming online means leaving offline', () {
      expect(FriendActivityNotificationGate.cameOnline('offline', 'online'), isTrue);
      expect(FriendActivityNotificationGate.cameOnline('offline', 'idle'), isTrue);
      expect(FriendActivityNotificationGate.cameOnline('idle', 'online'), isFalse);
      expect(
        FriendActivityNotificationGate.cameOnline('online', 'offline'),
        isFalse,
      );
    });

    bool notify({
      bool optedIn = true,
      bool enabled = true,
      bool streamer = false,
      bool dnd = false,
      bool friend = true,
      bool self = false,
    }) => FriendActivityNotificationGate.shouldNotify(
      optedIn: optedIn,
      notificationsEnabled: enabled,
      streamerMode: streamer,
      selfDnd: dnd,
      isFriend: friend,
      isSelf: self,
    );

    test('needs a friend, the switch and no silencing', () {
      expect(notify(), isTrue);
      expect(notify(optedIn: false), isFalse);
      expect(notify(enabled: false), isFalse);
      expect(notify(streamer: true), isFalse);
      expect(notify(dnd: true), isFalse);
      expect(notify(friend: false), isFalse);
      expect(notify(self: true), isFalse);
    });
  });

  group('inbox mentions', () {
    test('records once, newest first, and forgets dismissed ones', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(
        inboxMentionsControllerProvider('k').notifier,
      );
      controller.record(_message('10'), InboxMentionKind.direct);
      controller.record(_message('12'), InboxMentionKind.role);
      controller.record(_message('10'), InboxMentionKind.direct);
      expect(
        container.read(inboxMentionsControllerProvider('k')).map(
          (m) => m.message.id,
        ),
        ['12', '10'],
      );

      controller.dismiss('12');
      controller.record(_message('12'), InboxMentionKind.role);
      expect(
        container.read(inboxMentionsControllerProvider('k')).map(
          (m) => m.message.id,
        ),
        ['10'],
      );
    });

    test('drops mentions older than a week', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(
        inboxMentionsControllerProvider('k').notifier,
      );
      final start = DateTime(2026, 11, 1);
      controller.record(_message('1'), InboxMentionKind.direct, now: start);
      controller.record(
        _message('2'),
        InboxMentionKind.direct,
        now: start.add(const Duration(days: 8)),
      );
      expect(
        container.read(inboxMentionsControllerProvider('k')).map(
          (m) => m.message.id,
        ),
        ['2'],
      );
    });

    test('tells a direct, role and @everyone mention apart', () {
      bool self(String id) => id == 'me';
      expect(
        inboxMentionKind(_message('1', mentions: ['me']), isSelf: self),
        InboxMentionKind.direct,
      );
      expect(
        inboxMentionKind(
          _message('2', roles: ['r1']),
          isSelf: self,
          memberRoles: ['r1'],
        ),
        InboxMentionKind.role,
      );
      expect(
        inboxMentionKind(_message('3', everyone: true), isSelf: self),
        InboxMentionKind.everyone,
      );
      expect(inboxMentionKind(_message('4'), isSelf: self), isNull);
    });
  });
}
