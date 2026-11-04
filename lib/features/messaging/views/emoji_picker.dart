import 'package:bonfire/theme/app_icons.dart';
import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/messaging/controllers/accord_emojis.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/controllers/space_stickers.dart';
import 'package:bonfire/features/messaging/utils/emoji_catalog.dart';
import 'package:bonfire/features/messaging/views/message_media_gate.dart';
import 'package:bonfire/features/messaging/views/stickers.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/utils/space_display.dart';
import 'package:bonfire/features/spaces/views/accord_emoji_management.dart';
import 'package:bonfire/shared/components/horizontal_wheel_scroll.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/platform.dart';
import 'package:bonfire/shared/utils/pointer_anchor.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'emoji_picker/panel.dart';
part 'emoji_picker/gif_tab.dart';
part 'emoji_picker/sticker_tab.dart';

/// The user's selection from the emoji picker. [id] is null for built-in
/// unicode emoji (where [char] is the character to insert/react with — with
/// the chosen skin tone applied); for a custom space emoji [id] is set,
/// [char] is empty, and [imageUrl] points at the rendered glyph.
class EmojiPick {
  const EmojiPick({
    required this.name,
    this.char = '',
    this.id,
    this.imageUrl,
    this.superReaction = false,
  });

  final String name;
  final String char;
  final String? id;
  final String? imageUrl;

  /// Picked with the reaction picker's "Super Reaction" toggle on.
  final bool superReaction;

  bool get isCustom => id != null;

  /// The text inserted into the composer: the char for built-ins, or a
  /// `:name:` shortcode for custom emoji.
  String get composerText => isCustom ? ':$name:' : char;

  /// What a reaction toggle is given: the glyph itself for built-ins (so a
  /// skin tone survives), the name for custom emoji (paired with [id]).
  String get reactionName => isCustom ? name : char;

  /// The token stored in the recents list, from which [_pickFromRecent] can
  /// reconstruct this pick.
  String get recentToken => isCustom ? '$name:$id' : char;

  /// The token a super reaction is sent with.
  String get superToken => isCustom ? '$name:$id' : char;

  EmojiPick asSuper() => EmojiPick(
    name: name,
    char: char,
    id: id,
    imageUrl: imageUrl,
    superReaction: true,
  );
}

/// The three tabs of the composer's expression picker, in the reference
/// client's order.
enum ExpressionTab { gifs, stickers, emoji }

/// What the composer's picker resolved to: one emoji to insert, one sticker
/// to send, a GIF (by URL) to send, or a request to upload a GIF from disk.
class ExpressionPick {
  const ExpressionPick.emoji(EmojiPick this.emoji)
    : sticker = null,
      gifUrl = null,
      uploadGif = false;
  const ExpressionPick.sticker(AccordSticker this.sticker)
    : emoji = null,
      gifUrl = null,
      uploadGif = false;
  const ExpressionPick.gif(String this.gifUrl)
    : emoji = null,
      sticker = null,
      uploadGif = false;
  const ExpressionPick.uploadGif()
    : emoji = null,
      sticker = null,
      gifUrl = null,
      uploadGif = true;

  final EmojiPick? emoji;
  final AccordSticker? sticker;
  final String? gifUrl;
  final bool uploadGif;
}

/// Width and height of the desktop popover, as measured on the reference
/// client at 1920×927.
const Size _kPopoverSize = Size(496, 485);

/// The composer's GIFs / Stickers / Emoji popover. On desktop it stands 8 px
/// above [anchorRect] (the composer box) with its right edge 24 px in from the
/// box's; without an anchor it follows the click that opened it. On touch
/// layouts it is a bottom sheet. [channelId] feeds the GIF tab with the GIFs
/// already posted there.
Future<ExpressionPick?> showExpressionPicker(
  BuildContext context, {
  String? spaceId,
  String? channelId,
  ExpressionTab initialTab = ExpressionTab.emoji,
  Rect? anchorRect,
}) {
  return _showPopover<ExpressionPick>(
    context,
    anchorRect: anchorRect,
    builder: (ctx, compact) => ExpressionPickerPanel(
      spaceId: spaceId,
      channelId: channelId,
      initialTab: initialTab,
      compact: compact,
      onPick: (pick) => Navigator.of(ctx).pop(pick),
    ),
  );
}

/// The emoji-only picker used for reactions and the inline editor. With
/// [reaction] the header offers the "Super Reaction" toggle in place of
/// "Add Emoji".
Future<EmojiPick?> showAccordEmojiPicker(
  BuildContext context, {
  String? spaceId,
  bool reaction = false,
}) {
  return _showPopover<EmojiPick>(
    context,
    builder: (ctx, compact) => EmojiPickerPanel(
      spaceId: spaceId,
      compact: compact,
      autofocusSearch: !compact,
      reaction: reaction,
      onPick: (pick) => Navigator.of(ctx).pop(pick),
    ),
  );
}

Future<T?> _showPopover<T>(
  BuildContext context, {
  Rect? anchorRect,
  required Widget Function(BuildContext ctx, bool compact) builder,
}) {
  final desktop = shouldUseDesktopLayout(context);
  final anchor = !desktop
      ? null
      : anchorRect != null
      ? _PopoverAnchor.box(anchorRect)
      : switch (recentPointerAnchor()) {
          final Offset point => _PopoverAnchor.point(point),
          null => null,
        };
  final colors = BonfireThemeExtension.of(context);
  if (anchor == null) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          height: MediaQuery.of(ctx).size.height * 0.6,
          decoration: BoxDecoration(
            color: _pickerSurface(colors),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.gray,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(child: builder(ctx, true)),
            ],
          ),
        ),
      ),
    );
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close picker',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (ctx, _, _) => CustomSingleChildLayout(
      delegate: _PickerPopoverLayout(anchor),
      child: Material(
        color: _pickerSurface(colors),
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox.fromSize(
          size: _kPopoverSize,
          child: builder(ctx, false),
        ),
      ),
    ),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// The picker's surface (`#242429` on the Dark preset).
Color _pickerSurface(BonfireThemeExtension colors) => Color.alphaBlend(
  colors.dirtyWhite.withValues(alpha: 0.045),
  colors.background,
);

/// The rail and preview strip behind the grid (`#1A1A1E`: the pane colour).
Color _pickerInset(BonfireThemeExtension colors) => colors.background;

class _PopoverAnchor {
  const _PopoverAnchor.point(Offset this.point) : box = null;
  const _PopoverAnchor.box(Rect this.box) : point = null;

  final Offset? point;
  final Rect? box;
}

/// Places the panel above the composer box (8 px clear, right edge 24 px in)
/// or, for a click anchor, above the click with its right edge on it —
/// falling back to below when there is no room, always kept on screen.
class _PickerPopoverLayout extends SingleChildLayoutDelegate {
  const _PickerPopoverLayout(this.anchor);

  final _PopoverAnchor anchor;
  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          _kPopoverSize.width.clamp(0, constraints.maxWidth - 2 * _margin),
          _kPopoverSize.height.clamp(0, constraints.maxHeight - 2 * _margin),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x, y;
    if (anchor.box case final box?) {
      x = box.right - 24 - childSize.width;
      y = box.top - 8 - childSize.height;
    } else {
      final p = anchor.point!;
      x = p.dx + 20 - childSize.width;
      y = p.dy - 34 - childSize.height;
      if (y < _margin) y = p.dy + 34;
    }
    x = x.clamp(
      _margin,
      (size.width - childSize.width - _margin).clamp(_margin, size.width),
    );
    y = y.clamp(
      _margin,
      (size.height - childSize.height - _margin).clamp(_margin, size.height),
    );
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PickerPopoverLayout oldDelegate) =>
      anchor.point != oldDelegate.anchor.point ||
      anchor.box != oldDelegate.anchor.box;
}

/// The composer popover's content: the GIFs / Stickers / Emoji tab row over
/// the selected tab.
class ExpressionPickerPanel extends StatefulWidget {
  const ExpressionPickerPanel({
    super.key,
    required this.onPick,
    this.spaceId,
    this.channelId,
    this.initialTab = ExpressionTab.emoji,
    this.compact = false,
  });

  final ValueChanged<ExpressionPick> onPick;
  final String? spaceId;
  final String? channelId;
  final ExpressionTab initialTab;
  final bool compact;

  @override
  State<ExpressionPickerPanel> createState() => _ExpressionPickerPanelState();
}

class _ExpressionPickerPanelState extends State<ExpressionPickerPanel> {
  late ExpressionTab _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    Widget tab(ExpressionTab value, String label) {
      final active = _tab == value;
      return Padding(
        padding: EdgeInsets.only(left: value == ExpressionTab.gifs ? 0 : 8),
        child: Material(
          color: active
              ? colors.selection.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: Key('expression-tab-${value.name}'),
            borderRadius: BorderRadius.circular(8),
            hoverColor: colors.hover,
            onTap: () => setState(() => _tab = value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1,
                  color: colors.dirtyWhite,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 17, 16, 12),
          child: Row(
            children: [
              tab(ExpressionTab.gifs, 'GIFs'),
              tab(ExpressionTab.stickers, 'Stickers'),
              tab(ExpressionTab.emoji, 'Emoji'),
            ],
          ),
        ),
        Expanded(
          child: switch (_tab) {
            ExpressionTab.gifs => _GifTab(
              channelId: widget.channelId,
              onPick: widget.onPick,
            ),
            ExpressionTab.stickers => _StickerTab(
              spaceId: widget.spaceId,
              onPick: (s) => widget.onPick(ExpressionPick.sticker(s)),
            ),
            ExpressionTab.emoji => EmojiPickerPanel(
              spaceId: widget.spaceId,
              compact: widget.compact,
              autofocusSearch: !widget.compact,
              embedded: true,
              onPick: (e) => widget.onPick(ExpressionPick.emoji(e)),
            ),
          },
        ),
      ],
    );
  }
}

/// The search field shared by the three tabs: 40 px, a magnifier at the
/// left, the accent outline while focused.
class _PickerSearchField extends StatefulWidget {
  const _PickerSearchField({
    required this.hint,
    required this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.fieldKey,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted;
  final bool autofocus;
  final Key? fieldKey;

  @override
  State<_PickerSearchField> createState() => _PickerSearchFieldState();
}

class _PickerSearchFieldState extends State<_PickerSearchField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _focus.hasFocus ? colors.primary : colors.hairline,
        ),
      ),
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        children: [
          Icon(AppIcons.search, size: 16, color: colors.interactive),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: widget.fieldKey,
              controller: _controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              onSubmitted: (_) => widget.onSubmitted?.call(),
              style: TextStyle(fontSize: 16, color: colors.dirtyWhite),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: TextStyle(fontSize: 16, color: colors.gray),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
