import 'dart:async';

import 'package:restage_shared/restage_shared.dart';

/// Base type for valid onboarding flow transition targets.
sealed class FlowTargetRef {
  const FlowTargetRef();
}

/// Reference to a generated onboarding screen artifact.
///
/// The runtime resolves this to a pinned bundled RFW asset. Missing or
/// incompatible artifacts make the owning flow unavailable instead of
/// rendering a partial flow.
final class OnboardingScreenRef extends FlowTargetRef {
  /// Creates a descriptor reference for an onboarding screen.
  const OnboardingScreenRef({
    required this.id,
    required this.artifactPath,
    required this.version,
    required this.minClient,
  });

  /// Stable onboarding screen identifier.
  final String id;

  /// Asset path for the generated screen artifact.
  final String artifactPath;

  /// Descriptor version emitted for this screen.
  final int version;

  /// Minimum client descriptor version that can load this screen.
  final int minClient;
}

/// Reference to a terminal flow state.
final class EndStateRef extends FlowTargetRef {
  /// Creates a terminal state reference.
  const EndStateRef(this.id);

  /// Stable terminal state identifier.
  final String id;
}

/// Creates a reference to a terminal flow state.
EndStateRef endState(String id) => EndStateRef(id);

/// Reference to an authored internal flow graph node.
final class FlowNodeRef extends FlowTargetRef {
  /// Creates a reference to an internal graph node.
  const FlowNodeRef(this.id);

  /// Stable node identifier.
  final String id;
}

/// Creates a reference to an internal graph node.
FlowNodeRef flowNode(String id) => FlowNodeRef(id);

/// Decodes a declaration-filtered terminal flow result payload into the
/// generated result DTO.
typedef FlowResultDecoder<R> = R Function(Map<String, Object?> result);

/// Reference to a generated onboarding flow artifact.
///
/// Generated descriptors carry the flow identity, compatibility floor, and
/// typed terminal-result decoder that `RestageOnboarding` uses for
/// fail-closed completion.
final class OnboardingFlowRef<R> {
  /// Creates a descriptor reference for an onboarding flow.
  const OnboardingFlowRef({
    required this.id,
    required this.version,
    required this.minClient,
    required this.decodeResult,
  });

  /// Stable onboarding flow identifier.
  final String id;

  /// Descriptor version emitted for this flow.
  final int version;

  /// Minimum client descriptor version that can load this flow.
  final int minClient;

  /// Converts a filtered end-state result map into the generated result type.
  final FlowResultDecoder<R> decodeResult;
}

/// Descriptor for an event authored by an onboarding screen.
final class OnboardingEvent<T> {
  /// Creates an onboarding event descriptor.
  const OnboardingEvent(this.id);

  /// Stable event identifier.
  final String id;
}

/// Flow event names commonly emitted by paywall blobs when they are rendered
/// as flow screens.
abstract final class PaywallFlowEvents {
  /// A paywall purchase CTA was tapped.
  static const purchase = OnboardingEvent<Map<String, Object?>>('purchase');

  /// A paywall skipped or dismissed itself through an authored `skip` event.
  static const skip = OnboardingEvent<Map<String, Object?>>('skip');
}

/// Descriptor for a host action that a flow may request.
///
/// Actions are app-owned capabilities. A flow document may select an installed
/// action by contract, but it does not define executable behavior.
final class FlowActionRef<I, O> {
  /// Creates a host action reference.
  const FlowActionRef(this.id, {this.idempotent = false});

  /// Stable action identifier.
  final String id;

  /// Whether this action supports retrying the same logical operation.
  final bool idempotent;
}

/// Context passed to host action handlers.
///
/// Hosts can use [operationId] to dedupe side effects for idempotent actions.
/// The context is minted by the SDK runtime, not by the flow document.
final class FlowActionContext {
  /// Creates action invocation context.
  const FlowActionContext({
    required this.operationId,
    required this.isRetry,
    required this.attemptNumber,
  });

  /// Stable operation id for this action attempt series.
  final String operationId;

  /// Whether this invocation is retrying an earlier attempt.
  final bool isRetry;

  /// One-based attempt number.
  final int attemptNumber;
}

/// Handles a typed host action requested by a flow.
typedef FlowActionHandler<A, R> = FutureOr<R> Function(
  A args,
  FlowActionContext context,
);

/// Decodes a declaration-filtered action argument payload into the generated
/// argument type.
typedef FlowActionArgumentDecoder<A> = A Function(Object? value);

/// Encodes a typed action result into a flow payload.
typedef FlowActionResultEncoder<R> = Object? Function(R result);

/// Contract descriptor for a host action.
///
/// Flow documents must match these generated contract fields before the
/// runtime invokes a handler. Missing or mismatched contracts fail closed.
final class FlowActionDescriptor<A, R> {
  /// Creates a host action contract descriptor.
  const FlowActionDescriptor({
    required this.actionName,
    required this.contractVersion,
    required this.argsSchema,
    required this.resultSchema,
    required this.minClient,
    required this.idempotent,
  });

  /// Stable action name.
  final String actionName;

  /// Contract version implemented by the host binding.
  final int contractVersion;

  /// Implemented argument schema.
  final FlowActionSchema argsSchema;

  /// Implemented result schema.
  final FlowActionSchema resultSchema;

  /// Minimum client action runtime version supported by this descriptor.
  final int minClient;

  /// Whether this action supports retrying the same logical operation.
  final bool idempotent;

  /// Hash of the implemented argument schema.
  FlowContentHash get argsSchemaHash {
    return FlowActionSchema.hashFor(contractKind: 'args', schema: argsSchema);
  }

  /// Hash of the implemented result schema.
  FlowContentHash get resultSchemaHash {
    return FlowActionSchema.hashFor(
      contractKind: 'result',
      schema: resultSchema,
    );
  }
}

/// Installed host action binding used to match a flow action contract.
///
/// Bindings are the only bridge from declarative flow artifacts to app-owned
/// behavior. Runtime argument payloads are filtered before [decodeRuntimeArgs]
/// and [invokeRuntimeHandler] are called.
final class FlowActionBinding<A, R> {
  /// Creates an installed action binding.
  const FlowActionBinding({
    this.descriptor,
    required this.actionName,
    required this.contractVersion,
    required this.argsSchema,
    required this.resultSchema,
    required this.minClient,
    required this.idempotent,
    required this.handler,
    required this.decodeArgs,
    required this.encodeResult,
  });

  /// Generated action contract descriptor, when available.
  final FlowActionDescriptor<A, R>? descriptor;

  /// Stable action name.
  final String actionName;

  /// Contract version implemented by the host binding.
  final int contractVersion;

  /// Implemented argument schema.
  final FlowActionSchema argsSchema;

  /// Implemented result schema.
  final FlowActionSchema resultSchema;

  /// Minimum client action runtime version supported by this binding.
  final int minClient;

  /// Whether this binding permits same-operation retry.
  final bool idempotent;

  /// Typed host action handler.
  final FlowActionHandler<A, R> handler;

  /// Converts flow payloads to typed handler arguments.
  final FlowActionArgumentDecoder<A> decodeArgs;

  /// Converts typed handler results to flow payloads.
  final FlowActionResultEncoder<R> encodeResult;

  /// Decodes untyped event arguments for the runtime.
  A decodeRuntimeArgs(Object? value) => decodeArgs(value);

  /// Invokes the typed handler from the runtime.
  FutureOr<R> invokeRuntimeHandler(A args, FlowActionContext context) {
    return handler(args, context);
  }

  /// Encodes an untyped handler result for predicate evaluation.
  Object? encodeRuntimeResult(Object? value) => encodeResult(value as R);

  /// Hash of the implemented argument schema.
  FlowContentHash get argsSchemaHash {
    return FlowActionSchema.hashFor(contractKind: 'args', schema: argsSchema);
  }

  /// Hash of the implemented result schema.
  FlowContentHash get resultSchemaHash {
    return FlowActionSchema.hashFor(
      contractKind: 'result',
      schema: resultSchema,
    );
  }
}

/// Registry implemented by generated action collections.
///
/// Passing a registry to `RestageOnboarding` is optional for flows with no host
/// actions and required for flows whose document declares action contracts.
abstract interface class FlowActionRegistry {
  /// Installed bindings keyed by authored action id.
  Map<String, FlowActionBinding<dynamic, dynamic>> get flowActionBindings;
}

/// Base class for authored flow graphs.
abstract base class RestageFlow {
  /// Creates an authored flow.
  const RestageFlow();

  /// Builds the flow descriptor graph.
  FlowDef buildFlow();
}

/// Descriptor for an authored flow graph.
final class FlowDef {
  /// Creates a flow graph descriptor.
  const FlowDef({
    required this.initial,
    required this.states,
    this.flowState = const {},
    this.outbound = const FlowOutboundDeclarations(),
  });

  /// Initial onboarding screen.
  final OnboardingScreenRef initial;

  /// Nodes in the authored flow graph.
  final List<FlowNodeDef> states;

  /// Flow-state declarations used by outbound allowlists.
  final Map<String, FlowStateDeclaration> flowState;

  /// Surface-specific outbound allowlists.
  final FlowOutboundDeclarations outbound;
}

/// Creates a flow graph descriptor.
FlowDef flow({
  required OnboardingScreenRef initial,
  required List<FlowNodeDef> states,
  Map<String, FlowStateDeclaration> flowState = const {},
  FlowOutboundDeclarations outbound = const FlowOutboundDeclarations(),
}) {
  return FlowDef(
    initial: initial,
    states: states,
    flowState: flowState,
    outbound: outbound,
  );
}

/// Base class for flow nodes.
abstract base class FlowNodeDef {
  /// Const base constructor for subclasses.
  const FlowNodeDef();
}

/// Descriptor for a screen node.
final class ScreenNodeDef extends FlowNodeDef {
  /// Creates a screen node descriptor.
  const ScreenNodeDef({
    required this.ref,
    this.transitions = const <FlowTransitionDef<dynamic>>[],
  });

  /// Screen rendered by this node.
  final OnboardingScreenRef ref;

  /// Event transitions out of this screen.
  final List<FlowTransitionDef<dynamic>> transitions;

  /// Starts a transition from this screen for [event].
  ///
  /// Chaining `.on()` after `.goTo()` keeps accumulating transitions, so
  /// `screen(r).on(a)…goTo(x).on(b)…goTo(y)` builds one screen node with two
  /// transitions. The first `.on()` on a fresh `screen(...)` carries no prior
  /// transitions, so single-transition authoring is unchanged.
  ScreenEventTransitionBuilder<T> on<T>(OnboardingEvent<T> event) {
    return ScreenEventTransitionBuilder<T>._(
      ref: ref,
      event: event,
      priorTransitions: transitions,
    );
  }
}

/// Creates a screen node descriptor.
ScreenNodeDef screen(OnboardingScreenRef ref) {
  return ScreenNodeDef(ref: ref);
}

/// Creates a flow-screen reference for a Dart-authored paywall.
///
/// The code generator emits a flow-screen adapter artifact for
/// `@PaywallSource(id: ...)` paywalls at `assets/onboarding/screens/paywall_<id>.rfw`.
/// Use this reference in `buildFlow()` when the paywall should stay inside the
/// flow's back stack instead of being opened by host navigation after
/// completion.
OnboardingScreenRef paywallScreen(
  String id, {
  int version = 1,
  int minClient = kBaselineCatalogVersion,
}) {
  return OnboardingScreenRef(
    id: 'paywall_$id',
    artifactPath: 'paywall_$id.rfw',
    version: version,
    minClient: minClient,
  );
}

/// Descriptor for an authored decision node.
final class DecisionFlowNodeDef extends FlowNodeDef {
  /// Creates a decision node descriptor.
  const DecisionFlowNodeDef({
    required this.ref,
    required this.branches,
    required this.defaultBranch,
  });

  /// Internal graph node reference.
  final FlowNodeRef ref;

  /// Ordered decision branches.
  final List<AuthoredFlowBranch> branches;

  /// Branch used when no ordered branch matches.
  final AuthoredFlowBranchTarget defaultBranch;
}

/// Creates a decision node descriptor.
DecisionFlowNodeDef decision(
  FlowNodeRef ref, {
  required List<AuthoredFlowBranch> branches,
  required AuthoredFlowBranchTarget defaultBranch,
}) {
  return DecisionFlowNodeDef(
    ref: ref,
    branches: branches,
    defaultBranch: defaultBranch,
  );
}

/// Descriptor for an authored sub-flow node.
final class SubFlowNodeDef extends FlowNodeDef {
  /// Creates a sub-flow node descriptor.
  const SubFlowNodeDef({
    required this.ref,
    required this.flow,
    this.input = const {},
    required this.onComplete,
    required this.defaultBranch,
    this.subFlowUnavailable,
  });

  /// Internal graph node reference.
  final FlowNodeRef ref;

  /// Child flow descriptor.
  final OnboardingFlowRef<dynamic> flow;

  /// Explicit parent-to-child input.
  final Map<String, FlowValueSource> input;

  /// Ordered child-completion branches.
  final List<AuthoredFlowBranch> onComplete;

  /// Branch used when no child-completion branch matches.
  final AuthoredFlowBranchTarget defaultBranch;

  /// Branch used when the child cannot resolve or run.
  final AuthoredFlowBranchTarget? subFlowUnavailable;
}

/// Creates a sub-flow node descriptor.
SubFlowNodeDef subFlow(
  FlowNodeRef ref, {
  required OnboardingFlowRef<dynamic> flow,
  Map<String, FlowValueSource> input = const {},
  required List<AuthoredFlowBranch> onComplete,
  required AuthoredFlowBranchTarget defaultBranch,
  AuthoredFlowBranchTarget? subFlowUnavailable,
}) {
  return SubFlowNodeDef(
    ref: ref,
    flow: flow,
    input: input,
    onComplete: onComplete,
    defaultBranch: defaultBranch,
    subFlowUnavailable: subFlowUnavailable,
  );
}

/// Descriptor for an authored graph branch.
final class AuthoredFlowBranch {
  /// Creates a graph branch descriptor.
  const AuthoredFlowBranch({
    required this.when,
    required this.target,
    this.stateWrites = const {},
  });

  /// Predicate for taking this branch.
  final FlowBranchPredicate when;

  /// Target graph node, screen, or terminal state.
  final FlowTargetRef target;

  /// State writes applied before entering [target].
  final Map<String, FlowStateWrite> stateWrites;
}

/// Creates a graph branch descriptor.
AuthoredFlowBranch flowBranch({
  required FlowBranchPredicate when,
  required FlowTargetRef target,
  Map<String, FlowStateWrite> stateWrites = const {},
}) {
  return AuthoredFlowBranch(
    when: when,
    target: target,
    stateWrites: stateWrites,
  );
}

/// Descriptor for a default or unavailable graph target.
final class AuthoredFlowBranchTarget {
  /// Creates a graph branch target descriptor.
  const AuthoredFlowBranchTarget({
    required this.target,
    this.stateWrites = const {},
  });

  /// Target graph node, screen, or terminal state.
  final FlowTargetRef target;

  /// State writes applied before entering [target].
  final Map<String, FlowStateWrite> stateWrites;
}

/// Creates a default or unavailable graph target descriptor.
AuthoredFlowBranchTarget flowBranchTarget(
  FlowTargetRef target, {
  Map<String, FlowStateWrite> stateWrites = const {},
}) {
  return AuthoredFlowBranchTarget(
    target: target,
    stateWrites: stateWrites,
  );
}

/// Descriptor for an authored event transition.
final class FlowTransitionDef<T> {
  /// Creates an event transition descriptor.
  const FlowTransitionDef({
    required this.event,
    required this.target,
    this.action,
    this.stateWrites = const <String, FlowStateWrite>{},
  });

  /// Event that triggers this transition.
  final OnboardingEvent<T> event;

  /// Target screen or terminal-state reference.
  final FlowTargetRef target;

  /// Optional action descriptor for action-backed transitions.
  final FlowActionDef<dynamic, dynamic>? action;

  /// State writes applied — with the triggering event's payload as the value
  /// source — before entering [target]. Populated by `.capture()`/`.write()`.
  final Map<String, FlowStateWrite> stateWrites;
}

/// Descriptor for an action-backed transition.
final class FlowActionDef<I, O> {
  /// Creates an action descriptor.
  const FlowActionDef({
    required this.action,
    required this.resultPredicate,
  });

  /// Host action requested by an action-backed flow transition.
  final FlowActionRef<I, O> action;

  /// Predicate used by codegen to describe result handling.
  final bool Function(O result) resultPredicate;
}

/// Builder that accumulates `.capture()`/`.write()` state writes for a
/// transition and completes it with `.goTo(...)`.
///
/// Returned by `.on(event)` once a write has been added, and by the post-action
/// `.result(...)`. There is deliberately no `.run()` here: a host-action gate
/// is started directly after `.on()` (before any write), so a
/// write-before-`.run()` chain is unconstructable — writes are always authored
/// after `.on()` or after `.result()`.
base class ScreenEventWriteBuilder<T> {
  const ScreenEventWriteBuilder._({
    required this.ref,
    required this.event,
    this.action,
    this.priorTransitions = const <FlowTransitionDef<dynamic>>[],
    this.writes = const <String, FlowStateWrite>{},
  });

  /// Screen this transition starts from.
  final OnboardingScreenRef ref;

  /// Event that triggers this transition.
  final OnboardingEvent<T> event;

  /// Resolved action descriptor attached to the transition, when one was
  /// configured via `run(...).result(...)`.
  final FlowActionDef<dynamic, dynamic>? action;

  /// Transitions already accumulated from earlier `.on(...).goTo(...)` chains on
  /// the same screen, prepended when this transition completes via [goTo].
  final List<FlowTransitionDef<dynamic>> priorTransitions;

  /// State writes accumulated by [capture]/[write] for this transition.
  final Map<String, FlowStateWrite> writes;

  /// Captures the triggering event's scalar value into flow-state [key].
  ///
  /// Use this for a single event carrying a runtime/dynamic scalar — a rating,
  /// a slider value, an entered number. The event must be a scalar
  /// `OnboardingEvent<T>` (`T` is `String`, `bool`, or `int`) fired with a
  /// value (`onboardingEvent(event, value)`); the SDK carries that value under
  /// a reserved field, so capture reads it without the screen and flow having
  /// to agree on a payload key — [key] names only the flow-state slot written.
  /// If the event fires without a value the flow fails closed (it does not
  /// silently fall back to the declared default). For a value known at
  /// authoring time, use [write] instead.
  ScreenEventWriteBuilder<T> capture(String key) {
    return _withWrite(
      key,
      FlowStateWrite(
        type: _scalarFlowDataType<T>(),
        value: const EventFlowValueSource(key: kCapturedEventValueKey),
      ),
    );
  }

  /// Writes a statically-known literal [value] into flow-state [key].
  ///
  /// Use this for a value the flow knows at authoring time — typically a
  /// per-branch constant in a fork (`.on(enable).write('wantsReminders', true)`
  /// vs `.on(skip).write('wantsReminders', false)`). The flow-state type is
  /// inferred from [value], which must be a `String`, `bool`, or `int`. For a
  /// value the event itself carries at runtime, use [capture] instead.
  ScreenEventWriteBuilder<T> write(String key, Object value) {
    final type = _literalFlowDataType(value);
    return _withWrite(
      key,
      FlowStateWrite(
        type: type,
        value: LiteralFlowValueSource(type: type, value: value),
      ),
    );
  }

  ScreenEventWriteBuilder<T> _withWrite(String key, FlowStateWrite write) {
    if (writes.containsKey(key)) {
      throw ArgumentError.value(
        key,
        'key',
        'Duplicate state write for a flow-state key on a single transition',
      );
    }
    return ScreenEventWriteBuilder<T>._(
      ref: ref,
      event: event,
      action: action,
      priorTransitions: priorTransitions,
      writes: <String, FlowStateWrite>{...writes, key: write},
    );
  }

  /// Completes this transition with a screen or terminal-state target.
  ScreenNodeDef goTo(FlowTargetRef target) {
    return ScreenNodeDef(
      ref: ref,
      transitions: <FlowTransitionDef<dynamic>>[
        ...priorTransitions,
        FlowTransitionDef<T>(
          event: event,
          target: target,
          action: action,
          stateWrites: writes,
        ),
      ],
    );
  }
}

/// Builder returned by `screen(ref).on(event)`.
///
/// Adds `.run(...)` to start a host-action gate; the write/complete methods are
/// inherited from [ScreenEventWriteBuilder]. Because `.capture()`/`.write()`
/// return a plain [ScreenEventWriteBuilder] (no `.run()`), `.run()` can only be
/// called before any write — the write-before-`.run()` ordering can't compile.
final class ScreenEventTransitionBuilder<T> extends ScreenEventWriteBuilder<T> {
  const ScreenEventTransitionBuilder._({
    required super.ref,
    required super.event,
    super.priorTransitions,
  }) : super._();

  /// Adds a host-action gate to this transition.
  FlowActionResultBuilder<T, I, O> run<I, O>(FlowActionRef<I, O> action) {
    return FlowActionResultBuilder<T, I, O>._(
      ref: ref,
      event: event,
      action: action,
      priorTransitions: priorTransitions,
    );
  }
}

/// Maps the scalar event type [T] to its flow-state [FlowDataType] for
/// `.capture()`. A non-scalar `T` (e.g. `void` or an object payload) is a loud
/// authoring error — capture is scalar-only.
FlowDataType _scalarFlowDataType<T>() {
  if (T == String) return FlowDataType.string;
  if (T == bool) return FlowDataType.bool;
  if (T == int) return FlowDataType.int;
  throw ArgumentError(
    'capture() requires an OnboardingEvent<String|bool|int>; the event is '
    'OnboardingEvent<$T>, whose value is not a capturable scalar.',
  );
}

/// Maps a `.write()` literal [value] to its flow-state [FlowDataType]. Only
/// `String`, `bool`, and `int` literals are supported.
FlowDataType _literalFlowDataType(Object value) {
  final type = flowPredicateLiteralType(value);
  if (type == null) {
    throw ArgumentError.value(
      value,
      'value',
      'write() supports only String, bool, or int literals',
    );
  }
  return type;
}

/// Builder returned by `screen(ref).on(event).run(action)`.
final class FlowActionResultBuilder<T, I, O> {
  const FlowActionResultBuilder._({
    required this.ref,
    required this.event,
    required this.action,
    this.priorTransitions = const <FlowTransitionDef<dynamic>>[],
  });

  /// Screen this transition starts from.
  final OnboardingScreenRef ref;

  /// Event that triggers this transition.
  final OnboardingEvent<T> event;

  /// Host action whose result predicate this builder configures.
  final FlowActionRef<I, O> action;

  /// Transitions accumulated from earlier `.on(...).goTo(...)` chains on the
  /// same screen, threaded through so the completed action transition keeps
  /// them.
  final List<FlowTransitionDef<dynamic>> priorTransitions;

  /// Adds a result predicate to the action-backed transition. Any
  /// `.capture()`/`.write()` are authored after this on the returned builder.
  ScreenEventWriteBuilder<T> result(bool Function(O result) predicate) {
    return ScreenEventWriteBuilder<T>._(
      ref: ref,
      event: event,
      action: FlowActionDef<I, O>(
        action: action,
        resultPredicate: predicate,
      ),
      priorTransitions: priorTransitions,
    );
  }
}

/// Descriptor for a terminal flow state.
final class EndFlowNodeDef extends FlowNodeDef {
  /// Creates a terminal flow state descriptor.
  const EndFlowNodeDef(
    this.endState, {
    this.result = const <String, Object?>{},
  });

  /// Stable terminal state identifier.
  final EndStateRef endState;

  /// Result payload returned to the host when this end state is reached.
  final Map<String, Object?> result;
}

/// Creates a terminal flow state descriptor.
EndFlowNodeDef end(
  EndStateRef endState, {
  Map<String, Object?> result = const <String, Object?>{},
}) {
  return EndFlowNodeDef(endState, result: result);
}
