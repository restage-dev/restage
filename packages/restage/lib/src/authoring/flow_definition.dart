import 'package:restage_shared/restage_shared.dart'
    show FlowStateClassification;

import '../flow/flow_descriptors.dart' show FlowActionRef, SurfaceEvent;

/// Declarative definition of a flow graph.
///
/// The generator resolves [start], transition targets, and events through Dart
/// analyzer elements. The object itself never treats type names as wire IDs.
final class FlowDefinition {
  /// Creates a declarative flow definition.
  const FlowDefinition({
    required this.start,
    required this.transitions,
    this.state = const [],
    this.nodes = const [],
    this.outbound = const FlowOutboundPolicy(),
  });

  /// Initial screen type.
  final Type start;

  /// Event-driven graph edges.
  final List<Transition<dynamic>> transitions;

  /// Typed flow-state declarations.
  final List<FlowStateRef<dynamic>> state;

  /// Rare forward-reference definitions reachable through [NodeRef].
  final List<FlowNode> nodes;

  /// Explicit outbound state mapping.
  final FlowOutboundPolicy outbound;
}

/// A transition from an event to a screen or internal node.
final class Transition<T> {
  /// Creates a transition with a required destination.
  const Transition(
    this.event, {
    required this.to,
    this.from,
    this.capture,
    this.writes = const [],
    this.action,
  })  : completionId = null,
        completionResult = null;

  /// Creates a transition to the flow's terminal node.
  const Transition.complete(
    this.event, {
    this.from,
    this.capture,
    this.writes = const [],
    String id = 'done',
    Map<String, Object?> result = const {},
  })  : to = null,
        action = null,
        completionId = id,
        completionResult = result;

  /// Resolved static event field.
  final SurfaceEvent<T> event;

  /// Analyzer-validated target: a screen type, [FlowNode], or [NodeRef].
  final Object? to;

  /// Explicit source for an SDK-owned event shared by multiple paywalls.
  final Type? from;

  /// State slot that receives the triggering event payload.
  final FlowStateRef<T>? capture;

  /// Literal writes applied before entering the target.
  final List<FlowStateAssignment<dynamic>> writes;

  /// Optional host-action gate.
  final FlowActionGate<dynamic, dynamic>? action;

  /// Terminal identity for a completion transition.
  final String? completionId;

  /// Structured result for a completion transition.
  final Map<String, Object?>? completionResult;
}

/// A value that may be included in an outbound flow payload.
abstract interface class FlowOutboundValue<T> {
  /// Creates an outbound value reference.
  const FlowOutboundValue();
}

/// A typed predicate over flow state.
sealed class FlowCondition {
  /// Creates a flow-state predicate.
  const FlowCondition();
}

/// The relation used by a value predicate.
enum FlowStateValueRelation {
  /// Values are equal.
  equals,

  /// Values are different.
  notEquals,

  /// The value belongs to a supplied set.
  oneOf,

  /// The value is greater than the supplied value.
  greaterThan,

  /// The value is at least the supplied value.
  atLeast,

  /// The value is less than the supplied value.
  lessThan,

  /// The value is at most the supplied value.
  atMost,
}

/// A predicate comparing a state slot with literal value data.
final class FlowStateValueCondition<T> extends FlowCondition {
  /// Creates a literal value predicate.
  const FlowStateValueCondition({
    required this.state,
    required this.relation,
    required this.value,
  });

  /// State slot being inspected.
  final FlowStateRef<T> state;

  /// Comparison relation.
  final FlowStateValueRelation relation;

  /// Literal comparison value, or a list for [FlowStateValueRelation.oneOf].
  final Object? value;
}

/// A predicate comparing two state slots.
final class FlowStateReferenceCondition<T> extends FlowCondition {
  /// Creates a state-to-state equality predicate.
  const FlowStateReferenceCondition({
    required this.state,
    required this.other,
  });

  /// State slot being inspected.
  final FlowStateRef<T> state;

  /// Other state slot.
  final FlowStateRef<T> other;
}

/// A predicate checking whether a state slot has a value.
final class FlowStatePresenceCondition extends FlowCondition {
  /// Creates a state-presence predicate.
  const FlowStatePresenceCondition({
    required this.state,
    required this.isPresent,
  });

  /// State slot being inspected.
  final FlowStateRef<dynamic> state;

  /// Whether the predicate expects a present value.
  final bool isPresent;
}

/// A typed flow-state declaration and stable wire key.
base class FlowStateRef<T> implements FlowOutboundValue<T> {
  /// Creates a typed flow-state declaration.
  const FlowStateRef(
    this.key, {
    this.classification = FlowStateClassification.internal,
    this.defaultValue,
  });

  /// Stable wire key declared once and reused throughout the graph.
  final String key;

  /// Publication classification for the state slot.
  final FlowStateClassification classification;

  /// Optional initial value.
  final T? defaultValue;

  /// Creates a literal write for this state slot.
  FlowStateAssignment<T> set(T value) => FlowStateAssignment<T>._(this, value);

  /// Uses [parent] as this subflow input's source.
  SubflowInput<T> fromState(FlowStateRef<T> parent) =>
      SubflowInput<T>.fromState(this, parent);

  /// Uses [value] as this subflow input's literal source.
  SubflowInput<T> fromValue(T value) => SubflowInput<T>.fromValue(this, value);

  /// Matches a literal value.
  FlowCondition equals(T value) => FlowStateValueCondition<T>(
        state: this,
        relation: FlowStateValueRelation.equals,
        value: value,
      );

  /// Matches another state slot's value.
  FlowCondition equalsState(FlowStateRef<T> other) =>
      FlowStateReferenceCondition<T>(state: this, other: other);

  /// Rejects a literal value.
  FlowCondition notEquals(T value) => FlowStateValueCondition<T>(
        state: this,
        relation: FlowStateValueRelation.notEquals,
        value: value,
      );

  /// Matches any value in [values].
  FlowCondition oneOf(List<T> values) => FlowStateValueCondition<T>(
        state: this,
        relation: FlowStateValueRelation.oneOf,
        value: values,
      );

  /// Matches a state slot that has a value.
  FlowCondition isSet() =>
      FlowStatePresenceCondition(state: this, isPresent: true);

  /// Matches a state slot that has no value.
  FlowCondition isUnset() =>
      FlowStatePresenceCondition(state: this, isPresent: false);
}

/// A state reference that also produces a generated host seed field.
final class SeedableFlowStateRef<T> extends FlowStateRef<T> {
  /// Creates a seedable state declaration.
  const SeedableFlowStateRef(
    super.key, {
    super.classification,
    super.defaultValue,
  });
}

/// Numeric predicates available to integer state slots.
extension IntFlowStateConditions on FlowStateRef<int> {
  /// Matches a value greater than [value].
  FlowCondition greaterThan(int value) => FlowStateValueCondition<int>(
        state: this,
        relation: FlowStateValueRelation.greaterThan,
        value: value,
      );

  /// Matches a value at least [value].
  FlowCondition atLeast(int value) => FlowStateValueCondition<int>(
        state: this,
        relation: FlowStateValueRelation.atLeast,
        value: value,
      );

  /// Matches a value less than [value].
  FlowCondition lessThan(int value) => FlowStateValueCondition<int>(
        state: this,
        relation: FlowStateValueRelation.lessThan,
        value: value,
      );

  /// Matches a value at most [value].
  FlowCondition atMost(int value) => FlowStateValueCondition<int>(
        state: this,
        relation: FlowStateValueRelation.atMost,
        value: value,
      );
}

/// A literal state write attached to a transition or branch.
final class FlowStateAssignment<T> {
  const FlowStateAssignment._(this.state, this.value);

  /// State slot to update.
  final FlowStateRef<T> state;

  /// New literal value.
  final T value;
}

/// Input supplied to a child flow.
sealed class SubflowInput<T> {
  const SubflowInput(this.child);

  /// Child state declaration receiving the input.
  final FlowStateRef<T> child;

  /// Creates an input sourced from parent flow state.
  const factory SubflowInput.fromState(
    FlowStateRef<T> child,
    FlowStateRef<T> parent,
  ) = SubflowStateInput<T>;

  /// Creates an input sourced from a literal value.
  const factory SubflowInput.fromValue(
    FlowStateRef<T> child,
    T value,
  ) = SubflowLiteralInput<T>;
}

/// A child-flow input backed by parent state.
final class SubflowStateInput<T> extends SubflowInput<T> {
  /// Creates a parent-state input.
  const SubflowStateInput(super.child, this.parent);

  /// Parent state declaration.
  final FlowStateRef<T> parent;
}

/// A child-flow input backed by a literal value.
final class SubflowLiteralInput<T> extends SubflowInput<T> {
  /// Creates a literal child-flow input.
  const SubflowLiteralInput(super.child, this.value);

  /// Literal value supplied to the child.
  final T value;
}

/// A targetable internal flow-node definition.
sealed class FlowNode {
  /// Creates an internal node definition.
  const FlowNode(this.id);

  /// Stable node identity.
  final String id;
}

/// One ordered branch of a [Decision].
final class Branch {
  /// Creates a decision branch.
  const Branch({
    required this.when,
    required this.to,
    this.writes = const [],
  });

  /// Predicate that selects this branch.
  final FlowCondition when;

  /// Analyzer-validated screen, node, or node reference target.
  final Object to;

  /// Writes applied before entering [to].
  final List<FlowStateAssignment<dynamic>> writes;
}

/// A targetable conditional node.
final class Decision extends FlowNode {
  /// Creates a conditional node.
  const Decision(
    super.id, {
    required this.branches,
    required this.otherwise,
  });

  /// Ordered branch list.
  final List<Branch> branches;

  /// Target selected when no branch matches.
  final Object otherwise;
}

/// A targetable terminal node.
final class Completion extends FlowNode {
  /// Creates a terminal node.
  const Completion(
    super.id, {
    this.result = const {},
  });

  /// Structured terminal result.
  final Map<String, Object?> result;
}

/// A targetable child-flow node.
final class Subflow extends FlowNode {
  /// Creates a child-flow node.
  const Subflow(
    super.id, {
    required this.flow,
    this.input = const [],
    required this.onComplete,
    this.onUnavailable,
  });

  /// Analyzer-validated child flow declaration or generated flow reference.
  final Object flow;

  /// Typed parent-to-child state inputs.
  final List<SubflowInput<dynamic>> input;

  /// Target selected after child completion.
  final Object onComplete;

  /// Optional target selected when the child cannot run.
  final Object? onUnavailable;
}

/// Low-level reference for a real initialization cycle or forward reference.
final class NodeRef {
  /// Creates a node reference.
  const NodeRef(this.id);

  /// Stable node identity.
  final String id;
}

/// A host action plus the result predicate that allows the transition.
final class FlowActionGate<I, O> {
  const FlowActionGate._(this.action, this.predicate);

  /// Installed app-owned action.
  final FlowActionRef<I, O> action;

  /// Predicate deciding whether the transition may continue.
  final bool Function(O result) predicate;
}

/// Concise authoring for a host-action transition gate.
extension FlowActionGateAuthoring<I, O> on FlowActionRef<I, O> {
  /// Continues the transition only when [predicate] accepts the action result.
  FlowActionGate<I, O> continueWhen(bool Function(O result) predicate) =>
      FlowActionGate<I, O>._(this, predicate);
}

/// Explicit mapping from state references to outbound payload slots.
final class FlowOutboundPolicy {
  /// Creates outbound flow policy.
  const FlowOutboundPolicy({
    this.terminalResult = const {},
    this.lifecycle = const {},
    this.surveyAnswers = const {},
    this.subflowResult = const {},
  });

  /// Values included in terminal completion payloads.
  final Map<String, FlowOutboundValue<dynamic>> terminalResult;

  /// Values included in lifecycle payloads.
  final Map<String, FlowOutboundValue<dynamic>> lifecycle;

  /// Values included in survey answer payloads.
  final Map<String, FlowOutboundValue<dynamic>> surveyAnswers;

  /// Values forwarded from subflow completion payloads.
  final Map<String, FlowOutboundValue<dynamic>> subflowResult;
}
