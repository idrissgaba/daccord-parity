import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/utils/message_display.dart';
import 'package:bonfire/features/messaging/views/box/accord_message_content.dart';
import 'package:bonfire/features/messaging/views/box/accord_message_markup.dart';
import 'package:bonfire/features/messaging/views/emoji_picker.dart';
import 'package:bonfire/features/messaging/views/message_media_gate.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bonfire/shared/utils/style/markdown/stylesheet.dart';
import 'package:flutter/material.dart';

/// System join text uses the resolved author name as literal text, so names
/// cannot become Markdown links or mentions. Regular messages keep Markdown.
class MessageBody extends StatelessWidget {
  const MessageBody({
    super.key,
    required this.message,
    required this.authorName,
    this.spaceId,
    this.editedTooltip,
  });

  final AccordMessage message;
  final String authorName;
  final String? spaceId;

  /// When set, the message was edited: a small "(edited)" follows the last
  /// line of text, with this (the edit time) as its tooltip.
  final String? editedTooltip;

  @override
  Widget build(BuildContext context) {
    final content = accordMessageText(message, authorName: authorName);
    if (isSystemMessage(message)) {
      return Text(content, style: getMarkdownStyleSheet(context).paragraph);
    }
    if (loneGifUrl(content) case final gif?) {
      return LoneGif(url: gif);
    }
    final edited = editedTooltip;
    if (edited == null) {
      return AccordMessageContent(content: content, spaceId: spaceId);
    }
    // After a plain last line the tag runs on inline; after a closing block
    // (quote, list, heading, code) it starts the next line.
    final last = content.trimRight().split('\n').last;
    final inline =
        !content.trimRight().endsWith('```') &&
        !RegExp(r'^(>|\s*[-*+] |\s*\d+\. |#|-# )').hasMatch(last) &&
        !content.contains('>>> ');
    if (inline) {
      return AccordMessageContent(
        content: withEditedMarker(content, edited),
        spaceId: spaceId,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccordMessageContent(content: content, spaceId: spaceId),
        MessageEditedTag(at: edited),
      ],
    );
  }
}

/// A message that is only a GIF link: the GIF, up to 400 px wide, behind the
/// media consent gate like any external image.
class LoneGif extends ConsumerWidget {
  const LoneGif({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: MessageMediaGate(
        source: url,
        trustedBaseUrl: ref.watchCdnUrl(),
        builder: (_, safeUrl) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
            child: CachedNetworkImage(imageUrl: safeUrl, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
