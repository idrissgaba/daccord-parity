// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'friend_ids.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One connection's [FriendsSummary].
///
/// Filled from the same relationship list as `BlockedUsersController` (READY,
/// every relationship event, the Friends page).

@ProviderFor(FriendIdsController)
final friendIdsControllerProvider = FriendIdsControllerFamily._();

/// One connection's [FriendsSummary].
///
/// Filled from the same relationship list as `BlockedUsersController` (READY,
/// every relationship event, the Friends page).
final class FriendIdsControllerProvider
    extends $NotifierProvider<FriendIdsController, FriendsSummary> {
  /// One connection's [FriendsSummary].
  ///
  /// Filled from the same relationship list as `BlockedUsersController` (READY,
  /// every relationship event, the Friends page).
  FriendIdsControllerProvider._({
    required FriendIdsControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'friendIdsControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$friendIdsControllerHash();

  @override
  String toString() {
    return r'friendIdsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  FriendIdsController create() => FriendIdsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FriendsSummary value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FriendsSummary>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FriendIdsControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$friendIdsControllerHash() =>
    r'c1ef5951fdb556a8ea78c159fcd448199f4ddd70';

/// One connection's [FriendsSummary].
///
/// Filled from the same relationship list as `BlockedUsersController` (READY,
/// every relationship event, the Friends page).

final class FriendIdsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          FriendIdsController,
          FriendsSummary,
          FriendsSummary,
          FriendsSummary,
          String
        > {
  FriendIdsControllerFamily._()
    : super(
        retry: null,
        name: r'friendIdsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// One connection's [FriendsSummary].
  ///
  /// Filled from the same relationship list as `BlockedUsersController` (READY,
  /// every relationship event, the Friends page).

  FriendIdsControllerProvider call(String serverKey) =>
      FriendIdsControllerProvider._(argument: serverKey, from: this);

  @override
  String toString() => r'friendIdsControllerProvider';
}

/// One connection's [FriendsSummary].
///
/// Filled from the same relationship list as `BlockedUsersController` (READY,
/// every relationship event, the Friends page).

abstract class _$FriendIdsController extends $Notifier<FriendsSummary> {
  late final _$args = ref.$arg as String;
  String get serverKey => _$args;

  FriendsSummary build(String serverKey);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<FriendsSummary, FriendsSummary>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<FriendsSummary, FriendsSummary>,
              FriendsSummary,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
