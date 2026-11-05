import 'dart:async';
import 'dart:ui' as ui;

import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/theme/app_icons.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The profile cards' surface (`#242429` on Dark): the raised surface with a
/// touch more light — the popout, the account card and the full profile's
/// left card.
Color profileCardColor(BonfireThemeExtension colors) =>
    Color.alphaBlend(colors.dirtyWhite.withValues(alpha: 0.02), colors.raised);

/// The custom-status bubble and the account card's menu groups (`#2C2D32`).
Color profileBubbleColor(BonfireThemeExtension colors) =>
    Color.alphaBlend(colors.dirtyWhite.withValues(alpha: 0.05), colors.raised);

/// The banner colour when the user chose none: the reference client's light
/// grey (`#DDDEE2`) until the avatar's dominant colour is known.
const Color kDefaultBannerColor = Color(0xFFDDDEE2);

/// The most common colour of the image at [url] (coarsely bucketed), as the
/// reference client fills a banner the user left empty.
final avatarDominantColorProvider = FutureProvider.family<Color?, String>((
  ref,
  url,
) async {
  final provider = ResizeImage(
    CachedNetworkImageProvider(url),
    width: 24,
    height: 24,
  );
  final completer = Completer<ui.Image?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image.clone());
      stream.removeListener(listener);
    },
    onError: (_, _) {
      if (!completer.isCompleted) completer.complete(null);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  final image = await completer.future;
  if (image == null) return null;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final counts = <int, int>{};
    final sums = <int, List<int>>{};
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      final a = data.getUint8(i + 3);
      if (a < 128) continue;
      final r = data.getUint8(i), g = data.getUint8(i + 1), b = data.getUint8(i + 2);
      final bucket = (r >> 5) << 6 | (g >> 5) << 3 | (b >> 5);
      counts[bucket] = (counts[bucket] ?? 0) + 1;
      final s = sums.putIfAbsent(bucket, () => [0, 0, 0]);
      s[0] += r;
      s[1] += g;
      s[2] += b;
    }
    if (counts.isEmpty) return null;
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final s = sums[top.key]!;
    return Color.fromARGB(
      255,
      s[0] ~/ top.value,
      s[1] ~/ top.value,
      s[2] ~/ top.value,
    );
  } catch (_) {
    // A cross-origin image on the web can't be read back.
    return null;
  } finally {
    image.dispose();
  }
});

/// A profile banner of [height]: the user's banner colour, else the avatar's
/// dominant colour, else the default grey. [topRadius] rounds its top corners.
class ProfileBanner extends ConsumerWidget {
  const ProfileBanner({
    super.key,
    required this.height,
    required this.topRadius,
    this.color,
    this.avatarUrl,
    this.trailing = const [],
  });

  final double height;
  final double topRadius;
  final Color? color;
  final String? avatarUrl;

  /// Round buttons at the top-right corner.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = avatarUrl;
    final dominant = color == null && url != null
        ? ref.watch(avatarDominantColorProvider(url)).value
        : null;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color ?? dominant ?? kDefaultBannerColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
      ),
      alignment: Alignment.topRight,
      padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < trailing.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            trailing[i],
          ],
        ],
      ),
    );
  }
}

/// A 32 px round button on a banner (bg black 56 %, white 8 % border).
class BannerRoundButton extends StatelessWidget {
  const BannerRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final void Function(Offset position) onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTapUp: (d) => onTap(d.globalPosition),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.56),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// The avatar that sits astride the banner, cut out of it by a ring of the
/// card colour, with its status dot.
class ProfileAvatarCutout extends StatelessWidget {
  const ProfileAvatarCutout({
    super.key,
    required this.size,
    required this.ring,
    required this.avatarUrl,
    required this.initial,
    required this.backgroundColor,
    required this.status,
    required this.cardColor,
  });

  final double size;
  final double ring;
  final String? avatarUrl;
  final String initial;
  final Color backgroundColor;
  final String? status;
  final Color cardColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size + 2 * ring,
      height: size + 2 * ring,
      decoration: BoxDecoration(color: cardColor, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: AccordMemberAvatar(
        avatarUrl: avatarUrl,
        initial: initial,
        radius: size / 2,
        backgroundColor: backgroundColor,
        status: status,
        statusRingColor: cardColor,
        statusSize: size * 0.3,
        statusRingWidth: size * 0.05,
        initialStyle: TextStyle(fontSize: size * 0.4),
      ),
    );
  }
}

/// The thought bubble right of the avatar: the custom status, or — on your
/// own card — "+ [prompt]" to set one.
class CustomStatusBubble extends StatelessWidget {
  const CustomStatusBubble({
    super.key,
    required this.text,
    this.prompt,
    this.onTap,
  });

  /// The custom status; null shows [prompt].
  final String? text;
  final String? prompt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final bubble = profileBubbleColor(colors);
    final showing = text != null && text!.isNotEmpty;
    final style = TextStyle(
      fontSize: 14,
      height: 18 / 14,
      fontStyle: showing ? FontStyle.normal : FontStyle.italic,
      color: showing ? colors.dirtyWhite : _muted(colors),
    );
    final content = Container(
      constraints: const BoxConstraints(maxWidth: 179, minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bubble,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            if (!showing)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(AppIcons.addCircleOutline, size: 14, color: _muted(colors)),
                ),
              ),
            TextSpan(text: showing ? text : prompt),
          ],
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The bubble's tail: two dots trailing back to the avatar.
            Positioned(
              left: -6,
              top: -2,
              child: _Dot(size: 12, color: bubble),
            ),
            Positioned(
              left: -14,
              top: -10,
              child: _Dot(size: 6, color: bubble),
            ),
            content,
          ],
        ),
      ),
    );
  }

  static Color _muted(BonfireThemeExtension colors) =>
      Color.lerp(colors.gray, colors.interactive, 0.5)!;
}

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// The prompts the reference client cycles in an empty status bubble
/// (rotated per day).
const List<String> kStatusPrompts = [
  'Last song stuck in your head?',
  'Most-used emoji lately?',
  'Most satisfying game mechanic?',
  'Pick a mythical creature as a pet',
];

String statusPromptOfTheDay() =>
    kStatusPrompts[DateTime.now().day % kStatusPrompts.length];
