import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/models/server_entity_key.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/list_ext.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'soundboard_sounds.g.dart';

/// A space's soundboard sounds. Self-loads via `soundboard.list` the first
/// time it's watched; the gateway's `soundboard.create/update/delete` keep it
/// current (see `accord_event_handler.dart`). `null` means "not loaded yet".
@Riverpod(keepAlive: true)
class SoundboardSoundsController extends _$SoundboardSoundsController {
  @override
  List<AccordSound>? build(String serverKey, String spaceId) {
    final client = ref.watchAccordClientFor(serverKey);
    if (client != null) _load(client);
    return null;
  }

  Future<void> _load(AccordClient client) async {
    final sounds = (await client.soundboard.list(
      spaceId,
    )).listOrLog<AccordSound>('soundboard for $spaceId');
    if (!ref.mounted) return;
    if (sounds != null && ref.isCurrentAccordClient(serverKey, client)) {
      state = sounds;
    }
  }

  /// Reloads the list from the server.
  Future<void> reload() async {
    final client = ref.accordClient;
    if (client != null && ref.isCurrentAccordClient(serverKey, client)) {
      await _load(client);
    }
  }

  /// Inserts [sound] (when the id is new) or replaces it in place.
  void upsert(AccordSound sound) {
    if (sound.id == null) return;
    sound.spaceId ??= spaceId;
    state = (state ?? const <AccordSound>[]).upsertById(sound, (s) => s.id);
  }

  void remove(String soundId) {
    final current = state;
    if (current == null) return;
    state = current.removeById(soundId, (s) => s.id);
  }
}

/// The key a sound is starred and counted under in the settings: sound IDs
/// are only unique within one server.
String soundSettingsKey(String serverKey, String soundId) =>
    ServerEntityKey(serverKey, soundId).encoded;
