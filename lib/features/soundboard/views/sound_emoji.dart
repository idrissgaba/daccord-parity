import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/messaging/controllers/accord_emojis.dart';
import 'package:bonfire/features/messaging/views/message_media_gate.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The emoji of a soundboard [sound] at [size]: its Unicode emoji, the image
/// of its custom emoji (looked up in the sound's space), or — for a sound
/// without one — a speaker glyph in [fallbackColor], like the reference
/// client's sounds without an emoji.
class SoundEmoji extends ConsumerWidget {
  const SoundEmoji({
    super.key,
    required this.sound,
    required this.serverKey,
    this.size = 20,
    this.fallbackColor,
  });

  final AccordSound sound;
  final String serverKey;
  final double size;
  final Color? fallbackColor;

  /// Whether [sound] has an emoji to show (custom or Unicode).
  static bool hasEmoji(AccordSound sound) =>
      sound.emojiId != null || (sound.emojiName ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emojiId = sound.emojiId;
    final spaceId = sound.spaceId;
    if (emojiId != null && spaceId != null) {
      final emoji = ref
          .watch(accordEmojisControllerProvider(serverKey, spaceId))
          ?.firstWhereOrNull((e) => e.id == emojiId);
      final cdnUrl = ref.watchCdnUrl();
      final url = emoji == null ? null : accordEmojiUrl(emoji, cdnUrl);
      if (url != null) {
        return SizedBox.square(
          dimension: size,
          child: MessageMediaGate(
            source: url,
            trustedBaseUrl: cdnUrl,
            allowExternalConsent: false,
            blockedPlaceholder: _fallback(context),
            builder: (_, safeUrl) => CachedNetworkImage(
              imageUrl: safeUrl,
              width: size,
              height: size,
              fit: BoxFit.contain,
              errorWidget: (_, _, _) => _fallback(context),
            ),
          ),
        );
      }
    }
    final char = sound.emojiName;
    if (char != null && char.isNotEmpty && emojiId == null) {
      return SizedBox.square(
        dimension: size,
        child: Center(
          child: Text(
            char,
            maxLines: 1,
            textScaler: TextScaler.noScaling,
            overflow: TextOverflow.clip,
            style: TextStyle(fontSize: size * 0.86, height: 1.0),
          ),
        ),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Icon(
      AppIcons.volumeUp,
      size: size * 0.9,
      color: fallbackColor ?? Colors.white,
    ),
  );
}
