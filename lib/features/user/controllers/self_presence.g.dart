// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'self_presence.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The signed-in user's own presence: status and custom status, per
/// connection, and the timers that end a timed status, custom status or mute
/// ("For 1 Hour", "Clear after"). Timers live in settings (persisted), so a
/// status or mute that ran out while the app was closed is lifted on the next
/// launch.

@ProviderFor(SelfPresenceController)
final selfPresenceControllerProvider = SelfPresenceControllerProvider._();

/// The signed-in user's own presence: status and custom status, per
/// connection, and the timers that end a timed status, custom status or mute
/// ("For 1 Hour", "Clear after"). Timers live in settings (persisted), so a
/// status or mute that ran out while the app was closed is lifted on the next
/// launch.
final class SelfPresenceControllerProvider
    extends $NotifierProvider<SelfPresenceController, void> {
  /// The signed-in user's own presence: status and custom status, per
  /// connection, and the timers that end a timed status, custom status or mute
  /// ("For 1 Hour", "Clear after"). Timers live in settings (persisted), so a
  /// status or mute that ran out while the app was closed is lifted on the next
  /// launch.
  SelfPresenceControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selfPresenceControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selfPresenceControllerHash();

  @$internal
  @override
  SelfPresenceController create() => SelfPresenceController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$selfPresenceControllerHash() =>
    r'0db36e003d313b3242fa3c61b3e5e3025d6a9864';

/// The signed-in user's own presence: status and custom status, per
/// connection, and the timers that end a timed status, custom status or mute
/// ("For 1 Hour", "Clear after"). Timers live in settings (persisted), so a
/// status or mute that ran out while the app was closed is lifted on the next
/// launch.

abstract class _$SelfPresenceController extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
