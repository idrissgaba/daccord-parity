import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_prism/flutter_prism.dart';
import 'package:markdown_viewer/markdown_viewer.dart';

/// The message text colour: the theme's text a shade toward the pane
/// (`#EFEFF1` on the Dark preset's `#1A1A1E`).
Color messageTextColor(BonfireThemeExtension palette) => Color.alphaBlend(
  palette.dirtyWhite.withValues(alpha: 0.95),
  palette.background,
);

/// The reference client's chat typography: 16 px text on 22 px lines, h1–h3
/// at 24 / 20 / 16 bold, the link blue, strikethrough in the text colour,
/// quotes behind a 4 px bar, code on the accent wash.
MarkdownStyle getMarkdownStyleSheet(BuildContext context) {
  final palette = BonfireThemeExtension.of(context);
  final textColor = messageTextColor(palette);
  final paragraph = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 22 / 16,
    color: textColor,
  );
  final codeStyle = TextStyle(
    fontFamily: 'RobotoMono',
    fontSize: 14,
    height: 18 / 14,
    fontWeight: FontWeight.w400,
    color: textColor,
  );
  TextStyle heading(double size, double lineHeight) => TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w700,
    height: lineHeight / size,
    color: palette.dirtyWhite,
  );
  return MarkdownStyle(
    paragraph: paragraph,
    paragraphPadding: EdgeInsets.zero,
    blockSpacing: 0,
    codeBlock: codeStyle,
    codeblockPadding: const EdgeInsets.all(8),
    codeblockDecoration: BoxDecoration(
      color: Color.alphaBlend(
        palette.primary.withValues(alpha: 0.05),
        palette.background,
      ),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: palette.hairline),
    ),
    codeSpan: codeStyle.copyWith(
      backgroundColor: palette.primary.withValues(alpha: 0.08),
    ),
    strikethrough: TextStyle(color: textColor, decorationColor: textColor),
    link: const TextStyle(color: Color(0xFF4D96EE)),
    blockquote: TextStyle(color: palette.interactive),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: Color.alphaBlend(
            palette.interactive.withValues(alpha: 0.3),
            palette.background,
          ),
          width: 4,
        ),
      ),
    ),
    blockquoteContentPadding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
    list: paragraph,
    listItem: paragraph,
    listItemMarker: paragraph,
    listItemMinIndent: 16,
    headline1: heading(24, 33),
    headline2: heading(20, 27.5),
    headline3: heading(16, 22),
    h1Padding: const EdgeInsets.only(top: 16, bottom: 8),
    h2Padding: const EdgeInsets.only(top: 16, bottom: 8),
    h3Padding: const EdgeInsets.only(top: 16, bottom: 8),
    headline4: paragraph,
    headline5: paragraph,
    headline6: paragraph,
  );
}

/// Syntax colors with at least 4.5:1 contrast on each preset's code surface.
PrismStyle getMarkdownPrismStyle(BuildContext context) {
  final palette = BonfireThemeExtension.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  final text = TextStyle(color: palette.dirtyWhite);
  final comment = TextStyle(color: palette.gray);
  final purple = TextStyle(
    color: dark ? const Color(0xFFC4B5FD) : const Color(0xFF6D28D9),
  );
  final cyan = TextStyle(
    color: dark ? const Color(0xFF8BD5E5) : const Color(0xFF086779),
  );
  final green = TextStyle(
    color: dark ? const Color(0xFFA6DA95) : const Color(0xFF356A24),
  );
  final orange = TextStyle(
    color: dark ? const Color(0xFFF5C285) : const Color(0xFF925000),
  );
  final red = TextStyle(
    color: dark ? const Color(0xFFF5A0A9) : const Color(0xFFA1263D),
  );
  return PrismStyle(
    token: text,
    atrule: purple,
    attrName: cyan,
    attrValue: green,
    boolean: purple,
    builtin: cyan,
    cdata: comment,
    char: green,
    className: cyan,
    comment: comment,
    constant: purple,
    deleted: red,
    doctype: comment,
    entity: orange,
    function: orange,
    important: purple.copyWith(fontWeight: FontWeight.bold),
    inserted: green,
    keyword: purple,
    namespace: text,
    number: orange,
    operator: cyan,
    prolog: comment,
    property: cyan,
    punctuation: text,
    regex: orange,
    selector: green,
    string: green,
    symbol: purple,
    tag: red,
    url: cyan,
  );
}
