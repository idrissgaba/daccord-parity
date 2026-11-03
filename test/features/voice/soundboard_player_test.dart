import 'package:bonfire/features/voice/services/soundboard_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SoundboardPlayer.shouldPlay', () {
    bool decide({
      String eventServerKey = 'me@server',
      String? spaceId = 'space',
      String? senderId = 'peer',
      String? voiceServerKey = 'me@server',
      String? voiceSpaceId = 'space',
      String? voiceChannelId = 'voice',
      bool deafened = false,
      String? senderChannelId = 'voice',
      bool senderLocallyMuted = false,
    }) => SoundboardPlayer.shouldPlay(
      eventServerKey: eventServerKey,
      spaceId: spaceId,
      senderId: senderId,
      myUserId: 'me',
      voiceServerKey: voiceServerKey,
      voiceSpaceId: voiceSpaceId,
      voiceChannelId: voiceChannelId,
      deafened: deafened,
      senderChannelId: senderChannelId,
      senderLocallyMuted: senderLocallyMuted,
    );

    test('plays a peer sound in our voice channel', () {
      expect(decide(), isTrue);
    });

    test('plays our own sound back to us', () {
      expect(decide(senderId: 'me', senderChannelId: null), isTrue);
    });

    test('is silent when we are not in voice', () {
      expect(decide(voiceChannelId: null), isFalse);
    });

    test('is silent while deafened', () {
      expect(decide(deafened: true), isFalse);
      expect(decide(senderId: 'me', deafened: true), isFalse);
    });

    test('is silent for a sender in another channel of the space', () {
      expect(decide(senderChannelId: 'other'), isFalse);
      expect(decide(senderChannelId: null), isFalse);
    });

    test('is silent for another space or another connection', () {
      expect(decide(spaceId: 'elsewhere'), isFalse);
      expect(decide(eventServerKey: 'me@other'), isFalse);
    });

    test('is silent for a locally muted sender', () {
      expect(decide(senderLocallyMuted: true), isFalse);
    });
  });

  test('mpvVolume scales the clip gain by the soundboard volume', () {
    expect(SoundboardPlayer.mpvVolume(1.0, 1.0), 100);
    expect(SoundboardPlayer.mpvVolume(0.5, 0.5), 25);
    expect(SoundboardPlayer.mpvVolume(2.0, 1.0), 100);
    expect(SoundboardPlayer.mpvVolume(1.0, 0.0), 0);
  });
}
