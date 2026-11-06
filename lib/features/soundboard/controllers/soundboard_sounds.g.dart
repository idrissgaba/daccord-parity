// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'soundboard_sounds.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A space's soundboard sounds. Self-loads via `soundboard.list` the first
/// time it's watched; the gateway's `soundboard.create/update/delete` keep it
/// current (see `accord_event_handler.dart`). `null` means "not loaded yet".

@ProviderFor(SoundboardSoundsController)
final soundboardSoundsControllerProvider = SoundboardSoundsControllerFamily._();

/// A space's soundboard sounds. Self-loads via `soundboard.list` the first
/// time it's watched; the gateway's `soundboard.create/update/delete` keep it
/// current (see `accord_event_handler.dart`). `null` means "not loaded yet".
final class SoundboardSoundsControllerProvider
    extends $NotifierProvider<SoundboardSoundsController, List<AccordSound>?> {
  /// A space's soundboard sounds. Self-loads via `soundboard.list` the first
  /// time it's watched; the gateway's `soundboard.create/update/delete` keep it
  /// current (see `accord_event_handler.dart`). `null` means "not loaded yet".
  SoundboardSoundsControllerProvider._({
    required SoundboardSoundsControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'soundboardSoundsControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$soundboardSoundsControllerHash();

  @override
  String toString() {
    return r'soundboardSoundsControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SoundboardSoundsController create() => SoundboardSoundsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AccordSound>? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AccordSound>?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SoundboardSoundsControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$soundboardSoundsControllerHash() =>
    r'2535aca1684799815fa40c7a04a73c431da69165';

/// A space's soundboard sounds. Self-loads via `soundboard.list` the first
/// time it's watched; the gateway's `soundboard.create/update/delete` keep it
/// current (see `accord_event_handler.dart`). `null` means "not loaded yet".

final class SoundboardSoundsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SoundboardSoundsController,
          List<AccordSound>?,
          List<AccordSound>?,
          List<AccordSound>?,
          (String, String)
        > {
  SoundboardSoundsControllerFamily._()
    : super(
        retry: null,
        name: r'soundboardSoundsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// A space's soundboard sounds. Self-loads via `soundboard.list` the first
  /// time it's watched; the gateway's `soundboard.create/update/delete` keep it
  /// current (see `accord_event_handler.dart`). `null` means "not loaded yet".

  SoundboardSoundsControllerProvider call(String serverKey, String spaceId) =>
      SoundboardSoundsControllerProvider._(
        argument: (serverKey, spaceId),
        from: this,
      );

  @override
  String toString() => r'soundboardSoundsControllerProvider';
}

/// A space's soundboard sounds. Self-loads via `soundboard.list` the first
/// time it's watched; the gateway's `soundboard.create/update/delete` keep it
/// current (see `accord_event_handler.dart`). `null` means "not loaded yet".

abstract class _$SoundboardSoundsController
    extends $Notifier<List<AccordSound>?> {
  late final _$args = ref.$arg as (String, String);
  String get serverKey => _$args.$1;
  String get spaceId => _$args.$2;

  List<AccordSound>? build(String serverKey, String spaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<AccordSound>?, List<AccordSound>?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<AccordSound>?, List<AccordSound>?>,
              List<AccordSound>?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
