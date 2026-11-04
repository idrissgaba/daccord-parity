import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/messaging/utils/composer_input.dart';
import 'package:bonfire/features/messaging/utils/message_timestamp.dart';
import 'package:bonfire/features/messaging/views/message_media_gate.dart';
import 'package:bonfire/features/spaces/utils/message_time.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_markdown/dart_markdown.dart' as md;
import 'package:flutter/material.dart';
import 'package:markdown_viewer/markdown_viewer.dart';
import 'package:source_span/source_span.dart';

/// Resolved lookup tables for Accord's inline tokens (`@user` / `@role` /
/// `@everyone` / `#channel` chips, custom `:emoji:`, `||spoiler||`,
/// `__underline__`, `<t:…>` timestamps) and the `-# subtext` block.
///
/// All maps are keyed by the **lowercased** handle/name so resolution is
/// case-insensitive. Anything not present here simply renders as plain text —
/// an unresolved `#channel` or `@user` is left verbatim rather than chipped.
/// Without a space (e.g. DMs) the maps stay empty; the protocol-agnostic
/// tokens (`@everyone`/`@here`, spoiler, underline, markdown) still apply.
class AccordMarkupContext {
  const AccordMarkupContext({
    this.userByHandle = const {},
    this.roleByName = const {},
    this.channelByName = const {},
    this.emojiByName = const {},
    this.cdnUrl,
  });

  final Map<String, AccordMember> userByHandle;
  final Map<String, AccordRole> roleByName;
  final Map<String, AccordChannel> channelByName;
  final Map<String, AccordEmoji> emojiByName;
  final String? cdnUrl;
}

/// The syntax extensions that teach [AccordMarkdownBox]'s `markdown_viewer`
/// stack to render Accord's inline tokens *alongside* standard markdown.
///
/// Custom inline syntaxes are evaluated before the built-in emphasis syntaxes,
/// so `__text__` becomes an underline (matching the reference client) instead
/// of bold, and `:emoji:` / `@mention` / `#channel` chip up when they resolve.
List<md.Syntax> accordMarkupSyntaxes([
  AccordMarkupContext ctx = const AccordMarkupContext(),
]) => [
  const _SubtextSyntax(),
  _EditedSyntax(),
  _TimestampSyntax(),
  _DeepLinkSyntax(),
  _SpoilerSyntax(),
  _UnderlineSyntax(),
  _EmojiSyntax(ctx),
  _MentionSyntax(ctx),
  _ChannelSyntax(ctx),
];

/// The element builders for [accordMarkupSyntaxes]' elements. Mention and
/// channel chips are tappable when [onTapUser] / [onTapChannel] are given.
List<MarkdownElementBuilder> accordMarkupBuilders({
  String? cdnUrl,
  void Function(String userId)? onTapUser,
  void Function(String channelId)? onTapChannel,
}) => [
  _CodeSpanBuilder(),
  _EditedBuilder(),
  _SubtextBuilder(),
  _TimestampBuilder(),
  _SpoilerBuilder(),
  _UnderlineBuilder(),
  _EmojiBuilder(cdnUrl),
  _MentionBuilder(onTapUser),
  _ChannelBuilder(onTapChannel),
];

// ---------------------------------------------------------------------------
// Syntaxes
// ---------------------------------------------------------------------------

/// A line starting `-# ` → an `accordSubtext` block: smaller, muted text for
/// footnotes and fine print. Its content still gets inline markdown.
class _SubtextSyntax extends md.BlockSyntax {
  const _SubtextSyntax();

  static final _pattern = RegExp(r'^-# +\S');

  @override
  RegExp get pattern => _pattern;

  @override
  md.BlockElement parse(md.BlockParser parser) {
    final content = parser.current.content;
    final text = content.text;
    final markerStart = text.indexOf('-#');
    final bodyStart = text.indexOf(RegExp(r'\S'), markerStart + 2);
    final marker = content.subspan(markerStart, markerStart + 2);
    final body = content.subspan(bodyStart, text.trimRight().length);
    parser.advance();
    return md.BlockElement(
      'accordSubtext',
      markers: [marker],
      children: [md.UnparsedContent.fromSpan(body)],
      start: marker.start,
      end: body.end,
    );
  }
}

/// `<t:SECONDS>` / `<t:SECONDS:STYLE>` → an `accordTimestamp` element shown in
/// the reader's time zone. An out-of-range value is left as literal text.
class _TimestampSyntax extends md.InlineSyntax {
  _TimestampSyntax() : super(messageTimestampPattern);

  @override
  md.InlineObject? parse(md.InlineParser parser, Match match) {
    if (messageTimestampInstant(match[1]!) == null) return null;
    final markers = parser.consumeBy(match[0]!.length);
    return md.InlineElement(
      'accordTimestamp',
      markers: markers,
      attributes: {
        'seconds': match[1]!,
        'style': match[2] ?? defaultMessageTimestampStyle,
      },
      start: markers.first.start,
      end: markers.last.end,
    );
  }
}

/// A bare `daccord://…` link (e.g. a pasted message link) → a regular link.
/// Standard autolinking only knows http(s)/www; tapping it opens the
/// destination in the app.
class _DeepLinkSyntax extends md.InlineSyntax {
  _DeepLinkSyntax() : super(_pattern);

  static final _pattern = RegExp(r'daccord://[^\s<>()\[\]]+');

  @override
  md.InlineObject? parse(md.InlineParser parser, Match match) {
    final span = parser.consumeBy(match[0]!.length).first;
    final content = md.Text.fromSpan(span);
    return md.InlineElement(
      'autolinkExtension',
      children: [content],
      start: content.start,
      end: content.end,
      attributes: {'destination': span.text},
    );
  }
}

/// `||text||` → an `accordSpoiler` element carrying the hidden text.
class _SpoilerSyntax extends md.InlineSyntax {
  _SpoilerSyntax() : super(_pattern);

  static final _pattern = RegExp(r'\|\|(.+?)\|\|', dotAll: true);

  @override
  md.InlineObject? parse(md.InlineParser parser, Match match) {
    final markers = parser.consumeBy(match[0]!.length);
    return md.InlineElement(
      'accordSpoiler',
      markers: markers,
      attributes: {'text': match[1] ?? ''},
      start: markers.first.start,
      end: markers.last.end,
    );
  }
}

/// `__text__` → an `accordUnderline` element. Unlike standard markdown (which
/// treats `__` as bold) the reference client maps this to an underline. The
/// inner text is preserved as a child [md.Text] so it renders with the parent
/// style merged.
class _UnderlineSyntax extends md.InlineSyntax {
  _UnderlineSyntax() : super(_pattern);

  static final _pattern = RegExp(r'__(.+?)__', dotAll: true);

  @override
  md.InlineObject? parse(md.InlineParser parser, Match match) {
    final start = parser.position;
    final full = match[0]!;
    final innerSpans = parser.subspan(start + 2, start + full.length - 2);
    final markers = parser.consumeBy(full.length);
    return md.InlineElement(
      'accordUnderline',
      markers: markers,
      children: innerSpans
          .map<md.InlineObject>((span) => md.Text.fromSpan(span))
          .toList(),
      start: markers.first.start,
      end: markers.last.end,
    );
  }
}

/// `:name:` → an `accordEmoji` element, but only when the name resolves to a
/// space emoji. Otherwise it regrets the match (returns `null` without
/// consuming) so the literal `:name:` is left for other syntaxes / plain text.
class _EmojiSyntax extends md.InlineSyntax {
  _EmojiSyntax(this.ctx) : super(_pattern);

  static final _pattern = RegExp(r':([A-Za-z0-9_]+):');

  final AccordMarkupContext ctx;

  @override
  md.InlineObject? parse(md.InlineParser parser, Match match) {
    final emoji = ctx.emojiByName[match[1]!.toLowerCase()];
    if (emoji == null) return null;
    final url = accordEmojiUrl(emoji, ctx.cdnUrl);
    final markers = parser.consumeBy(match[0]!.length);
    return md.InlineElement(
      'accordEmoji',
      markers: markers,
      attributes: {'name': match[1]!, if (url != null) 'url': url},
      start: markers.first.start,
      end: markers.last.end,
    );
  }
}

/// `@everyone` / `@here` / `@handle` → an `accordMention` chip. `@everyone` and
/// `@here` always chip up; a `@handle` chips only when it resolves to a
/// mentionable role or a member (else it regrets). A leading word character
/// (e.g. the `@` in `email@host`) suppresses the match.
class _MentionSyntax extends md.InlineSyntax {
  _MentionSyntax(this.ctx) : super(_pattern);

  static final _pattern = RegExp(r'@(everyone|here)\b|@(\w+)');

  final AccordMarkupContext ctx;

  @override
  md.InlineObject? parse(md.InlineParser parser, Match match) {
    final pos = parser.position;
    if (pos > 0 && isMentionWordChar(parser.charAt(pos - 1))) return null;

    String label;
    Color color;
    String? userId;

    final broadcast = match[1];
    if (broadcast != null) {
      label = '@$broadcast';
      color = _mentionColor;
    } else {
      final handle = match[2]!;
      final lower = handle.toLowerCase();
      final role = ctx.roleByName[lower];
      if (role != null) {
        label = '@${role.name}';
        color = accordRoleColor(role.color) ?? _mentionColor;
      } else {
        final member = ctx.userByHandle[lower];
        if (member == null) return null;
        label = '@${accordUserName(member.user, fallback: handle)}';
        color = _mentionColor;
        userId = member.user?.id;
      }
    }

    final markers = parser.consumeBy(match[0]!.length);
    return md.InlineElement(
      'accordMention',
      markers: markers,
      attributes: {
        'label': label,
        'color': _encodeColor(color),
        if (userId != null) 'userId': userId,
      },
      start: markers.first.start,
      end: markers.last.end,
    );
  }
}

/// `#name` → an `accordChannel` chip, only when it resolves to a real channel
/// (else it regrets). A leading word character suppresses the match.
class _ChannelSyntax extends md.InlineSyntax {
  _ChannelSyntax(this.ctx) : super(_pattern);

  static final _pattern = RegExp(r'#([A-Za-z0-9_\-]+)');

  final AccordMarkupContext ctx;

  @override
  md.InlineObject? parse(md.InlineParser parser, Match match) {
    final pos = parser.position;
    if (pos > 0 && isMentionWordChar(parser.charAt(pos - 1))) return null;

    final channel = ctx.channelByName[match[1]!.toLowerCase()];
    if (channel == null) return null;

    final markers = parser.consumeBy(match[0]!.length);
    return md.InlineElement(
      'accordChannel',
      markers: markers,
      attributes: {
        'label': '# ${channel.name}',
        'color': _encodeColor(_mentionColor),
        'channelId': channel.id,
      },
      start: markers.first.start,
      end: markers.last.end,
    );
  }
}

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

class _MentionBuilder extends MarkdownElementBuilder {
  _MentionBuilder(this.onTapUser);

  final void Function(String userId)? onTapUser;

  @override
  List<String> get matchTypes => const ['accordMention'];

  @override
  bool isBlock(element) => false;

  @override
  Widget? buildWidget(element, parent) {
    final a = element.attributes;
    final userId = a['userId'];
    final tap = (userId != null && onTapUser != null)
        ? () => onTapUser!(userId)
        : null;
    return _inlineWidget(
      _Chip(
        label: a['label'] ?? '',
        color: _decodeColor(a['color']),
        onTap: tap,
      ),
    );
  }
}

class _ChannelBuilder extends MarkdownElementBuilder {
  _ChannelBuilder(this.onTapChannel);

  final void Function(String channelId)? onTapChannel;

  @override
  List<String> get matchTypes => const ['accordChannel'];

  @override
  bool isBlock(element) => false;

  @override
  Widget? buildWidget(element, parent) {
    final a = element.attributes;
    final channelId = a['channelId'];
    final tap = (channelId != null && onTapChannel != null)
        ? () => onTapChannel!(channelId)
        : null;
    return _inlineWidget(
      _Chip(
        label: a['label'] ?? '',
        color: _decodeColor(a['color']),
        onTap: tap,
      ),
    );
  }
}

class _EmojiBuilder extends MarkdownElementBuilder {
  _EmojiBuilder(this.trustedMediaBaseUrl);

  final String? trustedMediaBaseUrl;

  @override
  List<String> get matchTypes => const ['accordEmoji'];

  @override
  bool isBlock(element) => false;

  @override
  Widget? buildWidget(element, parent) {
    final a = element.attributes;
    return _inlineWidget(
      _EmojiImage(
        url: a['url'],
        name: a['name'] ?? '',
        trustedMediaBaseUrl: trustedMediaBaseUrl,
      ),
    );
  }
}

/// Private-use delimiters around the edit time appended to an edited
/// message's text by [withEditedMarker]; never typed by a user.
const String _kEditedOpen = '';
const String _kEditedClose = '';

/// Appends the edited marker to [content], so the "(edited)" tag renders at
/// the end of the last line, as the reference client places it.
String withEditedMarker(String content, String editedAt) =>
    '$content $_kEditedOpen$editedAt$_kEditedClose';

/// `<edit time>` → an `accordEdited` element.
class _EditedSyntax extends md.InlineSyntax {
  _EditedSyntax() : super(_pattern);

  static final _pattern = RegExp(
    '$_kEditedOpen([^$_kEditedClose]*)$_kEditedClose',
  );

  @override
  md.InlineObject? parse(md.InlineParser parser, Match match) {
    final markers = parser.consumeBy(match[0]!.length);
    return md.InlineElement(
      'accordEdited',
      markers: markers,
      attributes: {'at': match[1] ?? ''},
      start: markers.first.start,
      end: markers.last.end,
    );
  }
}

/// The small muted "(edited)" after the text, with the edit time on hover.
class _EditedBuilder extends MarkdownElementBuilder {
  @override
  List<String> get matchTypes => const ['accordEdited'];

  @override
  bool isBlock(element) => false;

  @override
  Widget? buildWidget(element, parent) {
    return _baselineWidget(
      MessageEditedTag(at: element.attributes['at'] ?? ''),
    );
  }
}

/// The small muted "(edited)" with the edit time in its tooltip.
class MessageEditedTag extends StatelessWidget {
  const MessageEditedTag({super.key, required this.at});

  final String at;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Tooltip(
      message: at,
      waitDuration: const Duration(milliseconds: 300),
      child: Text(
        '(edited)',
        style: TextStyle(fontSize: 10, height: 1, color: colors.gray),
      ),
    );
  }
}

/// Inline `code` as the reference client draws it: monospace on the accent
/// wash, a 1 px border and 4 px corners.
class _CodeSpanBuilder extends MarkdownElementBuilder {
  @override
  List<String> get matchTypes => const ['codeSpan'];

  @override
  bool isBlock(element) => false;

  @override
  Widget? buildWidget(element, parent) {
    final text = element.children
        .whereType<RichText>()
        .map((r) => r.text.toPlainText())
        .join();
    return _baselineWidget(_InlineCode(text: text));
  }
}

class _InlineCode extends StatelessWidget {
  const _InlineCode({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2.7),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.selection.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'RobotoMono',
          fontSize: 13.6,
          height: 18 / 13.6,
          color: colors.dirtyWhite,
        ),
      ),
    );
  }
}

/// `-# subtext`: the paragraph style, shrunk and dimmed.
class _SubtextBuilder extends MarkdownElementBuilder {
  @override
  List<String> get matchTypes => const ['accordSubtext'];

  @override
  bool isBlock(element) => true;

  @override
  TextStyle? buildTextStyle(element, defaultStyle) {
    final base = defaultStyle.merge(parentStyle);
    // The reference client's subtext: 14 px in the muted text colour.
    return base.copyWith(
      fontSize: 14,
      height: 19.25 / 14,
      color: const Color(0xFFABACB2),
    );
  }
}

class _TimestampBuilder extends MarkdownElementBuilder {
  @override
  List<String> get matchTypes => const ['accordTimestamp'];

  @override
  bool isBlock(element) => false;

  @override
  Widget? buildWidget(element, parent) {
    final at = messageTimestampInstant(element.attributes['seconds'] ?? '');
    if (at == null) return null;
    return _inlineWidget(
      _Timestamp(
        at: at.toLocal(),
        style: element.attributes['style'] ?? defaultMessageTimestampStyle,
      ),
    );
  }
}

class _SpoilerBuilder extends MarkdownElementBuilder {
  @override
  List<String> get matchTypes => const ['accordSpoiler'];

  @override
  bool isBlock(element) => false;

  @override
  Widget? buildWidget(element, parent) {
    return _inlineWidget(_Spoiler(text: element.attributes['text'] ?? ''));
  }
}

/// Underline relies on the default (children-merging) [buildWidget]; supplying
/// a [textStyle] with an underline decoration is enough.
class _UnderlineBuilder extends MarkdownElementBuilder {
  _UnderlineBuilder()
    : super(textStyle: const TextStyle(decoration: TextDecoration.underline));

  @override
  List<String> get matchTypes => const ['accordUnderline'];
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

/// Wraps an arbitrary [child] widget into a [RichText] whose root span is a
/// [WidgetSpan]. The renderer only permits `RichText`/`Text`/`DefaultTextStyle`
/// /`Consumer` from an inline `buildWidget`; returning the widget *inside* a
/// `RichText` (with a `WidgetSpan` root) keeps it a discrete inline item — the
/// merge pass detects the `WidgetSpan` and lays these out in a `Wrap` rather
/// than trying to cast it into a `List<TextSpan>` (which would throw).
Widget _inlineWidget(Widget child) => RichText(
  text: WidgetSpan(alignment: PlaceholderAlignment.middle, child: child),
);

/// [_inlineWidget] for inline text (code, the edited tag): on the line's
/// alphabetic baseline rather than centred.
Widget _baselineWidget(Widget child) => RichText(
  text: WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: child,
  ),
);

/// A mention / channel pill: the accent wash with light-blue text, solid
/// accent with white text under the pointer, as the reference client draws
/// them. A coloured role mention takes its role's colour instead.
class _Chip extends StatefulWidget {
  const _Chip({required this.label, required this.color, this.onTap});

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.color == _mentionColor;
    final background = _hover && widget.onTap != null
        ? widget.color
        : widget.color.withValues(alpha: accent ? 0.24 : 0.1);
    final foreground = _hover && widget.onTap != null
        ? Colors.white
        : accent
        ? const Color(0xFFA9BBFF)
        : widget.color;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        widget.label,
        style: TextStyle(
          fontSize: 16,
          height: 22 / 16,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
      ),
    );
    if (widget.onTap == null) return chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: chip),
    );
  }
}

/// An inline custom-emoji image (~20px). Falls back to the literal `:name:`
/// text when there's no URL or the image fails to load.
class _EmojiImage extends StatelessWidget {
  const _EmojiImage({
    required this.url,
    required this.name,
    required this.trustedMediaBaseUrl,
  });

  final String? url;
  final String name;
  final String? trustedMediaBaseUrl;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Text(':$name:', style: Theme.of(context).textTheme.bodyLarge);
    }
    return Tooltip(
      message: ':$name:',
      child: MessageMediaGate(
        source: url,
        trustedBaseUrl: trustedMediaBaseUrl,
        allowExternalConsent: false,
        blockedPlaceholder: Text(
          ':$name:',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        builder: (_, safeUrl) => CachedNetworkImage(
          imageUrl: safeUrl,
          width: 20,
          height: 20,
          fit: BoxFit.contain,
          errorWidget: (context, _, _) =>
              Text(':$name:', style: Theme.of(context).textTheme.bodyLarge),
        ),
      ),
    );
  }
}

/// A dynamic timestamp: formatted in the reader's locale and time zone, with
/// the full date in a tooltip. Relative (`R`) ones keep themselves current.
class _Timestamp extends StatefulWidget {
  const _Timestamp({required this.at, required this.style});

  final DateTime at;
  final String style;

  @override
  State<_Timestamp> createState() => _TimestampState();
}

class _TimestampState extends State<_Timestamp> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_Timestamp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.at != widget.at || oldWidget.style != widget.style) {
      _schedule();
    }
  }

  void _schedule() {
    _refresh?.cancel();
    _refresh = null;
    if (widget.style != 'R') return;
    _refresh = Timer(relativeTimeRefresh(widget.at, DateTime.now()), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  String _time(
    MaterialLocalizations l10n,
    bool use24h, {
    bool seconds = false,
  }) {
    final time = l10n.formatTimeOfDay(
      TimeOfDay.fromDateTime(widget.at),
      alwaysUse24HourFormat: use24h,
    );
    if (!seconds) return time;
    final ss = widget.at.second.toString().padLeft(2, '0');
    // Insert the seconds after the minutes ("9:05 AM" -> "9:05:07 AM").
    final minutes = widget.at.minute.toString().padLeft(2, '0');
    final index = time.indexOf(':$minutes');
    if (index < 0) return time;
    final end = index + minutes.length + 1;
    return '${time.substring(0, end)}:$ss${time.substring(end)}';
  }

  String _format(MaterialLocalizations l10n, bool use24h, String style) =>
      switch (style) {
        't' => _time(l10n, use24h),
        'T' => _time(l10n, use24h, seconds: true),
        'd' => l10n.formatCompactDate(widget.at),
        'D' => l10n.formatShortDate(widget.at),
        'F' => messageTimestampString(widget.at),
        'R' => relativeTimeLabel(widget.at, DateTime.now()),
        _ => '${messageDayString(widget.at)} at ${_time(l10n, use24h)}',
      };

  @override
  Widget build(BuildContext context) {
    final l10n = MaterialLocalizations.of(context);
    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
    final colors = BonfireThemeExtension.of(context);
    return Tooltip(
      message: _format(l10n, use24h, 'F'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: colors.selection.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          _format(l10n, use24h, widget.style),
          style: const TextStyle(fontSize: 16, height: 22 / 16),
        ),
      ),
    );
  }
}

class _Spoiler extends StatefulWidget {
  const _Spoiler({required this.text});

  final String text;

  @override
  State<_Spoiler> createState() => _SpoilerState();
}

class _SpoilerState extends State<_Spoiler> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    const style = TextStyle(fontSize: 16, height: 22 / 16);
    return GestureDetector(
      onTap: _revealed ? null : () => setState(() => _revealed = true),
      child: MouseRegion(
        cursor: _revealed ? MouseCursor.defer : SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            // The pane is drawn in `background`, so a hidden spoiler needs a
            // shade of its own to be seen at all.
            color: _revealed
                ? colors.hover
                : Color.lerp(colors.background, colors.dirtyWhite, 0.32),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            widget.text,
            style: style.copyWith(color: _revealed ? null : Colors.transparent),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _mentionColor = Color(0xFF5865F2);

String _encodeColor(Color color) => color.toARGB32().toString();

Color _decodeColor(String? encoded) {
  if (encoded == null) return _mentionColor;
  return Color(int.tryParse(encoded) ?? _mentionColor.toARGB32());
}
