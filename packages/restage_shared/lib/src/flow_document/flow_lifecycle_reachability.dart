import 'package:restage_shared/src/flow_document/flow_document.dart';

/// Screen lifecycle callbacks that the root flow can emit.
///
/// This is deliberately limited to screen lifecycle reachability. Root
/// lifecycle callbacks and child-flow callbacks have their own owners.
enum FlowScreenLifecycleChannel {
  presentation,
  skip,
  completion,
}

/// The screen lifecycle callbacks reachable from one flow document.
///
/// A screen is presented when its state is reached. It can skip when its own
/// `skip` route or the document's global `skip` custom event gives the runtime
/// a destination. It completes only when the root graph can reach an end state
/// while that screen remains current. Decisions preserve the current screen;
/// entering a sub-flow clears it.
final class FlowScreenLifecycleReachability {
  const FlowScreenLifecycleReachability._({
    required this.reachableScreenIds,
    required this.skipScreenIds,
    required this.completingScreenIds,
  });

  /// Screens whose presentation can be emitted by the root flow.
  final Set<String> reachableScreenIds;

  /// Screens whose skip can be emitted by the root flow.
  final Set<String> skipScreenIds;

  /// Screens whose completion can be emitted by the root flow.
  final Set<String> completingScreenIds;

  /// Classifies the lifecycle callbacks that the root flow can emit.
  factory FlowScreenLifecycleReachability.analyze(FlowDocument document) {
    if (!document.states.containsKey(document.initial)) {
      return const FlowScreenLifecycleReachability._(
        reachableScreenIds: {},
        skipScreenIds: {},
        completingScreenIds: {},
      );
    }

    final reachableScreenIds = <String>{};
    final skipScreenIds = <String>{};
    final completingScreenIds = <String>{};
    final globalSkip = document.outbound.customEvents.containsKey('skip');
    final pending = <(String, String?)>[(document.initial, null)];
    final visited = <(String, String?)>{};

    void enter(String target, String? carriedScreenId) {
      if (document.states.containsKey(target)) {
        pending.add((target, carriedScreenId));
      }
    }

    while (pending.isNotEmpty) {
      final (stateId, carriedScreenId) = pending.removeLast();
      if (!visited.add((stateId, carriedScreenId))) continue;

      switch (document.states[stateId]) {
        case ScreenFlowState(:final on):
          reachableScreenIds.add(stateId);
          if (globalSkip || on.containsKey('skip')) {
            skipScreenIds.add(stateId);
          }
          for (final transition in on.values) {
            enter(transition.target, stateId);
          }
        case DecisionFlowState(:final branches, :final defaultBranch):
          for (final branch in branches) {
            enter(branch.target, carriedScreenId);
          }
          enter(defaultBranch.target, carriedScreenId);
        case SubFlowState(
            :final onComplete,
            :final defaultBranch,
            :final subFlowUnavailable,
          ):
          for (final branch in onComplete) {
            enter(branch.target, null);
          }
          enter(defaultBranch.target, null);
          if (subFlowUnavailable != null) {
            enter(subFlowUnavailable.target, null);
          }
        case EndFlowState():
          if (carriedScreenId != null) {
            completingScreenIds.add(carriedScreenId);
          }
        case UnsupportedFlowState() || null:
          break;
      }
    }

    return FlowScreenLifecycleReachability._(
      reachableScreenIds: Set.unmodifiable(reachableScreenIds),
      skipScreenIds: Set.unmodifiable(skipScreenIds),
      completingScreenIds: Set.unmodifiable(completingScreenIds),
    );
  }

  /// Whether [screenId] can emit [channel] while the root flow runs.
  bool allows({
    required String screenId,
    required FlowScreenLifecycleChannel channel,
  }) =>
      switch (channel) {
        FlowScreenLifecycleChannel.presentation =>
          reachableScreenIds.contains(screenId),
        FlowScreenLifecycleChannel.skip => skipScreenIds.contains(screenId),
        FlowScreenLifecycleChannel.completion =>
          completingScreenIds.contains(screenId),
      };

  /// The lifecycle channels that can be emitted for [screenId], in callback
  /// order.
  Iterable<FlowScreenLifecycleChannel> channelsFor(String screenId) sync* {
    for (final channel in FlowScreenLifecycleChannel.values) {
      if (allows(screenId: screenId, channel: channel)) yield channel;
    }
  }
}
