import '../utils/json_utils.dart';

/// A soundboard sound.
class AccordSound {
  String? id;

  /// The space the sound belongs to (absent from older servers).
  String? spaceId;
  String name;
  String audioUrl;
  double volume;

  /// Custom emoji of the space shown with the sound, if any.
  String? emojiId;

  /// Unicode emoji shown with the sound (or the custom emoji's name), if any.
  String? emojiName;
  String? creatorId;
  String createdAt;
  String updatedAt;

  AccordSound({
    this.id,
    this.spaceId,
    this.name = '',
    this.audioUrl = '',
    this.volume = 1.0,
    this.emojiId,
    this.emojiName,
    this.creatorId,
    this.createdAt = '',
    this.updatedAt = '',
  });

  /// Parses a sound, or the `sound` object of a gateway `soundboard.*` event
  /// (`{"space_id": ..., "sound": {...}}`), whose `space_id` fills in
  /// [spaceId] when the sound itself lacks it.
  factory AccordSound.fromJson(Map<String, dynamic> d) {
    final inner = d['sound'];
    if (inner is Map) {
      final sound = AccordSound.fromJson(Map<String, dynamic>.from(inner));
      sound.spaceId ??= asStringOrNull(d['space_id']);
      return sound;
    }
    return AccordSound(
      id: asStringOrNull(d['id']),
      spaceId: asStringOrNull(d['space_id']),
      name: asString(d['name']),
      audioUrl: asString(d['audio_url']),
      volume: asDouble(d['volume'], 1.0),
      emojiId: _nonEmpty(asStringOrNull(d['emoji_id'])),
      emojiName: _nonEmpty(asStringOrNull(d['emoji_name'])),
      creatorId: asStringOrNull(d['creator_id']),
      createdAt: asString(d['created_at']),
      updatedAt: asString(d['updated_at']),
    );
  }

  static String? _nonEmpty(String? v) => v == null || v.isEmpty ? null : v;

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'name': name,
      'audio_url': audioUrl,
      'volume': volume,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
    if (id != null) d['id'] = id;
    if (spaceId != null) d['space_id'] = spaceId;
    if (emojiId != null) d['emoji_id'] = emojiId;
    if (emojiName != null) d['emoji_name'] = emojiName;
    if (creatorId != null) d['creator_id'] = creatorId;
    return d;
  }
}
