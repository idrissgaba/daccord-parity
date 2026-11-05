import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/spaces/utils/space_media_cache.dart';

/// Resolves a space's `banner` reference to an absolute CDN URL, or null when
/// unset.
String? accordSpaceBannerUrl(
  AccordSpace space,
  String? cdnUrl, {
  bool versioned = true,
}) => _resolveSpaceMedia(
  space,
  space.banner,
  cdnUrl,
  versioned,
  AccordCDN.spaceBanner,
);

/// Resolves a space's `icon` reference to an absolute CDN URL, or null when
/// unset.
String? accordSpaceIconUrl(
  AccordSpace space,
  String? cdnUrl, {
  bool versioned = true,
}) => _resolveSpaceMedia(
  space,
  space.icon,
  cdnUrl,
  versioned,
  AccordCDN.spaceIcon,
);

/// The reference is either a bare asset hash, built into a URL by [byHash], or
/// a server-relative/absolute path (mirrors `accordMemberAvatarUrl`).
String? _resolveSpaceMedia(
  AccordSpace space,
  Object? reference,
  String? cdnUrl,
  bool versioned,
  String Function(String spaceId, String hash, {String format, String cdnUrl})
  byHash,
) {
  if (reference is! String || reference.isEmpty) return null;
  final cdn = cdnUrl ?? '';
  final url = reference.contains('/') || reference.startsWith('http')
      ? AccordCDN.resolvePath(reference, cdnUrl: cdn)
      : byHash(
          space.id,
          reference,
          format: AccordCDN.autoFormat(reference),
          cdnUrl: cdn,
        );
  return versioned ? spaceMediaCache.resolve(url) : url;
}

/// A space's initials for an icon without an image: the first letter of its
/// first two words ("Vale Makers" → "VM"), or "?" for no name.
String accordSpaceInitials(String rawName) {
  final name = rawName.trim();
  if (name.isEmpty) return '?';
  final parts = name.split(RegExp(r'\s+'));
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}
