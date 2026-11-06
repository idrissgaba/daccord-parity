// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'soundboard_activity.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Who in our voice channel is playing a soundboard sound right now, keyed by
/// user ID. Feeds the reference client's cues: the sound's emoji rising over
/// the player's call tile, the speaking ring on the tile and channel row, and
/// the played card's outline in the picker.

@ProviderFor(SoundboardActivityController)
final soundboardActivityControllerProvider =
    SoundboardActivityControllerProvider._();

/// Who in our voice channel is playing a soundboard sound right now, keyed by
/// user ID. Feeds the reference client's cues: the sound's emoji rising over
/// the player's call tile, the speaking ring on the tile and channel row, and
/// the played card's outline in the picker.
final class SoundboardActivityControllerProvider
    extends
        $NotifierProvider<
          SoundboardActivityController,
          Map<String, SoundboardActivity>
        > {
  /// Who in our voice channel is playing a soundboard sound right now, keyed by
  /// user ID. Feeds the reference client's cues: the sound's emoji rising over
  /// the player's call tile, the speaking ring on the tile and channel row, and
  /// the played card's outline in the picker.
  SoundboardActivityControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'soundboardActivityControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$soundboardActivityControllerHash();

  @$internal
  @override
  SoundboardActivityController create() => SoundboardActivityController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, SoundboardActivity> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, SoundboardActivity>>(
        value,
      ),
    );
  }
}

String _$soundboardActivityControllerHash() =>
    r'f996fd86214332febeb5806abef57c21b08594b6';

/// Who in our voice channel is playing a soundboard sound right now, keyed by
/// user ID. Feeds the reference client's cues: the sound's emoji rising over
/// the player's call tile, the speaking ring on the tile and channel row, and
/// the played card's outline in the picker.

abstract class _$SoundboardActivityController
    extends $Notifier<Map<String, SoundboardActivity>> {
  Map<String, SoundboardActivity> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<String, SoundboardActivity>,
              Map<String, SoundboardActivity>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, SoundboardActivity>,
                Map<String, SoundboardActivity>
              >,
              Map<String, SoundboardActivity>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
