import '../../models/sound.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// Soundboard management within a space: list, fetch, create, update, delete,
/// and trigger playback.
class SoundboardApi extends EndpointBase {
  SoundboardApi(super.rest);

  /// Lists all sounds in a space's soundboard.
  Future<RestResult> list(String spaceId) async {
    final result = await rest.makeRequest('GET', '/spaces/$spaceId/soundboard');
    return result.deserializeArray(AccordSound.fromJson);
  }

  /// Fetches a single sound by ID.
  Future<RestResult> fetch(String spaceId, String soundId) async {
    final result =
        await rest.makeRequest('GET', '/spaces/$spaceId/soundboard/$soundId');
    return result.deserialize(AccordSound.fromJson);
  }

  /// Creates a sound. [data] should include `name` (2–32 characters) and
  /// `audio` (data URI), optionally `volume` (0.0–2.0), `emoji_id` (a custom
  /// emoji of the space) or `emoji_name` (a Unicode emoji). Needs
  /// `manage_soundboard` or `create_expressions`.
  Future<RestResult> create(String spaceId, Map<String, dynamic> data) async {
    final result = await rest.makeRequest('POST', '/spaces/$spaceId/soundboard',
        body: data);
    return result.deserialize(AccordSound.fromJson);
  }

  /// Updates a sound's `name`, `volume`, `emoji_id` or `emoji_name`; an
  /// explicit `null` emoji clears it. Needs `manage_soundboard`, or
  /// `create_expressions` for a sound the caller added.
  Future<RestResult> update(
      String spaceId, String soundId, Map<String, dynamic> data) async {
    final result = await rest.makeRequest(
        'PATCH', '/spaces/$spaceId/soundboard/$soundId',
        body: data);
    return result.deserialize(AccordSound.fromJson);
  }

  /// Deletes a sound.
  Future<RestResult> delete(String spaceId, String soundId) {
    return rest.makeRequest('DELETE', '/spaces/$spaceId/soundboard/$soundId');
  }

  /// Plays a sound into the caller's voice channel, which must be in this
  /// space. Members of that channel receive `soundboard.play` with
  /// `channel_id`, `user_id` and the `sound`.
  Future<RestResult> play(String spaceId, String soundId) {
    return rest.makeRequest(
        'POST', '/spaces/$spaceId/soundboard/$soundId/play');
  }
}
