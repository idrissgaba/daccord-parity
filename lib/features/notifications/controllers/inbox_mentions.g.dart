// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbox_mentions.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The messages that mentioned the user on one connection, newest first.
///
/// Accord has no "recent mentions" endpoint, so the list is what this client
/// saw: every mention delivered over the gateway while it ran, plus those the
/// inbox finds in unread channels when it opens. Dismissed messages stay
/// dismissed for the session.

@ProviderFor(InboxMentionsController)
final inboxMentionsControllerProvider = InboxMentionsControllerFamily._();

/// The messages that mentioned the user on one connection, newest first.
///
/// Accord has no "recent mentions" endpoint, so the list is what this client
/// saw: every mention delivered over the gateway while it ran, plus those the
/// inbox finds in unread channels when it opens. Dismissed messages stay
/// dismissed for the session.
final class InboxMentionsControllerProvider
    extends $NotifierProvider<InboxMentionsController, List<InboxMention>> {
  /// The messages that mentioned the user on one connection, newest first.
  ///
  /// Accord has no "recent mentions" endpoint, so the list is what this client
  /// saw: every mention delivered over the gateway while it ran, plus those the
  /// inbox finds in unread channels when it opens. Dismissed messages stay
  /// dismissed for the session.
  InboxMentionsControllerProvider._({
    required InboxMentionsControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'inboxMentionsControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$inboxMentionsControllerHash();

  @override
  String toString() {
    return r'inboxMentionsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  InboxMentionsController create() => InboxMentionsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<InboxMention> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<InboxMention>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is InboxMentionsControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$inboxMentionsControllerHash() =>
    r'2c6abb81a834faba2022a03e44149b25676843d0';

/// The messages that mentioned the user on one connection, newest first.
///
/// Accord has no "recent mentions" endpoint, so the list is what this client
/// saw: every mention delivered over the gateway while it ran, plus those the
/// inbox finds in unread channels when it opens. Dismissed messages stay
/// dismissed for the session.

final class InboxMentionsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          InboxMentionsController,
          List<InboxMention>,
          List<InboxMention>,
          List<InboxMention>,
          String
        > {
  InboxMentionsControllerFamily._()
    : super(
        retry: null,
        name: r'inboxMentionsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// The messages that mentioned the user on one connection, newest first.
  ///
  /// Accord has no "recent mentions" endpoint, so the list is what this client
  /// saw: every mention delivered over the gateway while it ran, plus those the
  /// inbox finds in unread channels when it opens. Dismissed messages stay
  /// dismissed for the session.

  InboxMentionsControllerProvider call(String serverKey) =>
      InboxMentionsControllerProvider._(argument: serverKey, from: this);

  @override
  String toString() => r'inboxMentionsControllerProvider';
}

/// The messages that mentioned the user on one connection, newest first.
///
/// Accord has no "recent mentions" endpoint, so the list is what this client
/// saw: every mention delivered over the gateway while it ran, plus those the
/// inbox finds in unread channels when it opens. Dismissed messages stay
/// dismissed for the session.

abstract class _$InboxMentionsController extends $Notifier<List<InboxMention>> {
  late final _$args = ref.$arg as String;
  String get serverKey => _$args;

  List<InboxMention> build(String serverKey);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<InboxMention>, List<InboxMention>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<InboxMention>, List<InboxMention>>,
              List<InboxMention>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
