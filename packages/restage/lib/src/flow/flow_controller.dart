import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:restage_shared/restage_shared.dart' hide WidgetLibrary;
import 'package:rfw/rfw.dart';

import '../events/restage_event.dart';
import 'flow_descriptors.dart';
import 'flow_resolver.dart';

/// SDK-owned onboarding flow runtime controller.
///
/// Interprets validated flow documents, enforces action contracts and outbound
/// filtering, and reports unavailable artifacts through the fail-closed path.
final class RestageFlowController<R> extends ChangeNotifier {
  /// Creates a flow controller.
  RestageFlowController({
    required this.flow,
    required this.resolver,
    required this.actions,
    required this.onEvent,
    required this.onComplete,
    required this.onUnavailable,
  });

  /// Flow descriptor being executed.
  final OnboardingFlowRef<R> flow;

  /// Resolver used to load the pinned flow document and screen blobs.
  final FlowResolver resolver;

  /// Optional host action registry for action-backed flow transitions.
  final FlowActionRegistry? actions;

  /// Emits global SDK events.
  final void Function(RestageEvent event) onEvent;

  /// Called with the typed terminal result.
  final void Function(R result) onComplete;

  /// Called when the flow fails closed.
  final void Function(FlowUnavailableError error) onUnavailable;

  static final Random _operationIdRandom = Random.secure();
  static const Object _missingOutboundValue = Object();
  static const int _maxSubFlowDepth = 4;

  /// Upper bound on a frame's retained screen back-stack. The rendering surface
  /// mirrors the controller's reachable history rather than keeping its own cap,
  /// so this is the single bound on how far back navigation can reach.
  static const int _maxScreenHistory = 8;

  /// Reserved screen-event names with built-in navigation semantics: `back`
  /// falls back to the history pop, `skip` routes to the flow's skip
  /// destination. An authored `on[...]` handler for either name takes
  /// precedence over the built-in behavior.
  static const String _backEventName = 'back';
  static const String _skipEventName = 'skip';
  static const String _purchaseEventName = 'purchase';

  /// Process-global screen-entry sequence. Minting from a shared counter (not a
  /// per-controller one) keeps screen-entry ids unique across controller
  /// instances, so a rendering surface's entry-id gate can never confuse a
  /// stale screen from one controller with the current screen of another.
  static int _screenEntrySequence = 0;

  final String _operationSessionId = _mintOperationSessionId();
  final List<_FlowFrame> _frames = <_FlowFrame>[];
  Object? _activeActionToken;
  int _nextOperationId = 0;
  int? _currentScreenEntryId;
  bool _isChangingState = false;
  bool _isUnavailable = false;
  bool _isComplete = false;
  bool _isDisposed = false;

  /// Current screen state id, if a screen is rendered.
  String? get currentScreenId => _currentFrame?.currentStateId;

  /// Decoded RFW library for the current screen.
  WidgetLibrary? get currentLibrary => _currentFrame?.currentLibrary;

  /// Monotonic id of the current screen *visit*; null when no screen is
  /// mounted — before the first screen loads, while crossing a sub-flow
  /// boundary, or after the flow fails closed. It stays set after the flow
  /// completes (the last screen remains the current screen, consistent with
  /// [currentScreenId]).
  ///
  /// A fresh id is minted on every screen entry — including re-entering the
  /// same screen state — so a rendering surface can distinguish a new forward
  /// navigation from a notify that re-renders the same screen.
  int? get currentScreenEntryId => _currentScreenEntryId;

  /// Whether a transition is currently being applied.
  bool get isChangingState => _isChangingState;

  /// Whether the flow has failed closed and can no longer render or advance.
  ///
  /// A rendering surface uses this to distinguish a terminal failure (drop the
  /// surface) from a transient absence of a current screen (e.g. crossing a
  /// sub-flow boundary), where the prior screen should be held.
  bool get isUnavailable => _isUnavailable;

  /// Whether the flow has reached an end state and finished.
  ///
  /// A completed flow no longer navigates ([canBack]/[canSkip] are false). A
  /// rendering surface uses this to collapse chrome on completion — the last
  /// screen remains rendered but its affordances are gone.
  bool get isComplete => _isComplete;

  /// Whether an interaction would currently be a no-op because the controller
  /// is mid-work — a state transition is being applied ([isChangingState]) or a
  /// host action is in flight.
  ///
  /// [handleEvent] / [back] / [skip] are all gated on this same condition, so a
  /// rendering surface uses it to keep a back/skip affordance inert while the
  /// flow is busy, rather than presenting a live control whose tap silently does
  /// nothing.
  bool get isBusy => _isChangingState || _activeActionToken != null;

  /// Whether there is a prior screen in the current sub-flow to navigate back
  /// to. Reflects history availability (the affordance is shown when true); the
  /// [back] method additionally enforces the in-flight gating. A sub-flow
  /// boundary is a barrier — a child frame's history never reaches into the
  /// parent — so this is `false` on a frame's first screen.
  bool get canBack =>
      !_isDisposed &&
      !_isUnavailable &&
      !_isComplete &&
      (_currentFrame?.screenHistory.length ?? 0) > 1;

  /// The entry ids of every screen still reachable by back navigation, across
  /// all live frames (a parent frame's screens stay reachable once a sub-flow
  /// returns to it). The rendering surface mirrors this set: it keeps exactly
  /// these screens mounted and prunes any others (e.g. a completed sub-flow's
  /// screens), so the single per-frame history cap is the only bound and
  /// `canBack` can never disagree with what is actually mounted/restorable.
  ///
  /// Package-internal: the view↔controller coupling for the keep-mounted
  /// keystone, not part of the public contract.
  @internal
  List<int> get reachableScreenEntryIds => <int>[
        for (final frame in _frames)
          for (final entry in frame.screenHistory) entry.entryId,
      ];

  _FlowFrame? get _currentFrame {
    return _frames.isEmpty ? null : _frames.last;
  }

  /// Loads and decodes the initial flow screen.
  Future<void> load() async {
    try {
      final resolved = await resolver.resolve(flow);
      if (_isDisposed) return;
      _validateResolved(resolved);
      final actionBindings = _validateActionContracts(resolved.document);
      final rootFrame = _FlowFrame(
        resolved: resolved,
        flowId: flow.id,
        flowVersion: flow.version,
        flowSessionId: _mintFlowSessionId(),
        parentFlowSessionId: null,
        subFlowDepth: 0,
        actionBindings: actionBindings,
        flowState: _initialFlowState(resolved.document),
      );
      _frames
        ..clear()
        ..add(rootFrame);
      await _goTo(rootFrame, resolved.document.initial);
      if (_isDisposed || _isUnavailable || _isComplete) return;
      _emitFlowStarted(rootFrame);
    } on FlowUnavailableError catch (e) {
      _fail(e);
    } on Object catch (e) {
      _fail(_error('resolve_failed', 'Failed to resolve flow: $e.'));
    }
  }

  /// Routes an RFW event through the flow transition table.
  void handleEvent(String name, Object? args) {
    if (_isDisposed ||
        _isUnavailable ||
        _isComplete ||
        _isChangingState ||
        _activeActionToken != null) {
      return;
    }
    final frame = _currentFrame;
    final current = frame?.currentStateId;
    if (frame == null || current == null) return;
    final state = frame.resolved.document.states[current];
    if (state is! ScreenFlowState) {
      _fail(_error(
        'invalid_current_state',
        'Current flow state "$current" is not a screen.',
      ));
      return;
    }
    final flowEventName = _flowEventNameForRfw(name);
    final transition = state.on[flowEventName];
    // A skip is funnel-critical drop-off. Emit it whenever the skip has a real
    // destination ([canSkip] — an authored `on['skip']` transition or a declared
    // `skip` custom event), regardless of which path honors it below. Additive:
    // the authored transition / custom event still fires as before. Reusing
    // [canSkip] single-sources the skip-destination predicate (its other guards
    // are already satisfied here).
    if (flowEventName == _skipEventName && canSkip) {
      onEvent(OnboardingSkipped(
        flowId: frame.flowId,
        flowVersion: frame.flowVersion,
        flowSessionId: frame.flowSessionId,
        atScreenId: current,
        stepIndex: frame.screenHistory.length - 1,
      ));
      // The host's synchronous `onEvent` can re-enter and fail the controller
      // closed / disposed / busy; re-check the same gate as the method entry so
      // the skip's transition or custom event never runs on a closed controller.
      if (_isDisposed ||
          _isUnavailable ||
          _isComplete ||
          _isChangingState ||
          _activeActionToken != null) {
        return;
      }
    }
    if (transition == null) {
      // The reserved `back` event falls back to the default history pop when the
      // screen authors no `on['back']` handler, so an in-screen or chrome back
      // affordance works without per-screen wiring.
      if (flowEventName == _backEventName) {
        back();
        return;
      }
      if (!_emitCustomEvent(frame, flowEventName, args)) {
        debugPrint(
          '[restage] Dropping unsupported onboarding event "$name" in '
          'state "$current".',
        );
      }
      return;
    }
    switch (transition) {
      case GotoFlowTransition(:final target, :final stateWrites):
        unawaited(_goToWithWrites(
          frame,
          target,
          stateWrites,
          eventSource: args,
        ));
      case ActionFlowTransition(:final action):
        final binding = frame.actionBindings[action];
        if (binding == null) {
          _fail(_actionContractError(
            'Missing installed binding for action "$action".',
          ));
          return;
        }
        unawaited(_invokeAction(frame, transition, binding, args));
    }
  }

  String _flowEventNameForRfw(String name) {
    return switch (name) {
      RestageEventNames.purchase => _purchaseEventName,
      _ => name,
    };
  }

  /// Fails the flow closed in response to a screen that threw while rendering.
  ///
  /// A rendering surface calls this with the thrown [error] when the current
  /// screen's subtree throws, so the fail-closed posture — and the failure
  /// reason — live in the controller (the single source of truth) rather than
  /// in an optional view callback. After this the controller is unavailable and
  /// stops accepting events; the configured `onUnavailable` is notified and a
  /// `FlowUnavailable` event is emitted with the `render_failed` reason.
  void reportRenderFailure(Object error) {
    _fail(_error(
      'render_failed',
      'A widget in the flow screen threw during build: $error.',
    ));
  }

  /// Returns to the previous screen in the current sub-flow, if any.
  ///
  /// Pops to the prior screen *visit*, restoring its original entry id so a
  /// rendering surface restores the still-mounted instance — its state
  /// preserved — rather than re-decoding it. Decision and action states are
  /// never recorded on the back-stack (they run *between* screens), so back
  /// structurally skips them and never re-runs a transition or re-fires an
  /// action.
  ///
  /// A no-op while a transition or action is in flight (the same re-entrancy
  /// gate as [handleEvent]), after the flow has failed closed or completed, and
  /// at a sub-flow boundary (no prior screen in this frame — a barrier). It does
  /// not roll back flow state: back is a navigation, not a transaction rollback.
  void back() {
    if (_isDisposed ||
        _isUnavailable ||
        _isComplete ||
        _isChangingState ||
        _activeActionToken != null) {
      return;
    }
    final frame = _currentFrame;
    if (frame == null || frame.screenHistory.length <= 1) return;
    frame.screenHistory.removeLast();
    final prior = frame.screenHistory.last;
    frame.currentStateId = prior.stateId;
    frame.currentLibrary = prior.library;
    _currentScreenEntryId = prior.entryId;
    notifyListeners();
  }

  /// Requests the reserved `skip` action for the current screen.
  ///
  /// Routes through the flow's event machinery: an authored `on['skip']` takes
  /// that transition; otherwise a declared `outbound.customEvents['skip']`
  /// emits a `FlowCustomEvent` the host handles (commonly to dismiss the flow).
  /// A no-op when skip has no destination ([canSkip] is false).
  void skip() => handleEvent(_skipEventName, null);

  /// Whether the current screen offers a skip destination — an authored
  /// `on['skip']` transition or a declared `outbound.customEvents['skip']`.
  ///
  /// A default skip affordance is shown only when this is true, so there is
  /// never a visible-but-dead skip control.
  bool get canSkip {
    if (_isDisposed || _isUnavailable || _isComplete) return false;
    final frame = _currentFrame;
    final current = frame?.currentStateId;
    if (frame == null || current == null) return false;
    final state = frame.resolved.document.states[current];
    if (state is! ScreenFlowState) return false;
    return state.on.containsKey(_skipEventName) ||
        frame.resolved.document.outbound.customEvents
            .containsKey(_skipEventName);
  }

  Map<String, Object?> _initialFlowState(FlowDocument document) {
    return Map.unmodifiable({
      for (final entry in document.flowState.entries)
        if (entry.value.defaultValue != null)
          entry.key: entry.value.defaultValue,
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _activeActionToken = null;
    _currentScreenEntryId = null;
    _frames.clear();
    super.dispose();
  }

  void _validateResolved(ResolvedFlow resolved) {
    final document = resolved.document;
    if (document.flow != flow.id) {
      throw _error(
        'flow_mismatch',
        'Flow JSON id "${document.flow}" does not match requested '
            'flow "${flow.id}".',
      );
    }
    if (document.version != flow.version) {
      throw _error(
        'version_mismatch',
        'Flow JSON version ${document.version} does not match requested '
            'version ${flow.version}.',
      );
    }
    if (document.schemaVersion != 1) {
      throw _error(
        'unsupported_schema_version',
        'Unsupported flow schemaVersion ${document.schemaVersion}.',
      );
    }
    if (document.minClient > flow.minClient) {
      throw _error(
        'unsupported_min_client',
        'Flow minClient ${document.minClient} exceeds requested client '
            '${flow.minClient}.',
      );
    }
    for (final entry in document.screenArtifacts.entries) {
      final artifact = entry.value;
      if (artifact.schemaVersion != 1) {
        throw _error(
          'unsupported_schema_version',
          'Unsupported screen artifact schemaVersion '
              '${artifact.schemaVersion} for "${entry.key}".',
        );
      }
      if (artifact.minClient > flow.minClient) {
        throw _error(
          'unsupported_min_client',
          'Screen artifact minClient ${artifact.minClient} for "${entry.key}" '
              'exceeds requested client ${flow.minClient}.',
        );
      }
    }

    final issues = FlowDocumentValidation.validate(document);
    if (issues.isNotEmpty) {
      final reason = issues.any((issue) => issue.code == 'unsupportedStateKind')
          ? 'unsupported_state_kind'
          : issues.any((issue) => issue.code == 'unsupportedFeature')
              ? 'unsupported_feature'
              : 'validation_failed';
      throw _error(
        reason,
        'Flow document failed validation: ${issues.join('; ')}.',
      );
    }
  }

  Map<String, FlowActionBinding<dynamic, dynamic>> _validateActionContracts(
    FlowDocument document,
  ) {
    final registry = actions;
    if (document.actions.isEmpty) {
      return registry == null
          ? const {}
          : Map<String, FlowActionBinding<dynamic, dynamic>>.unmodifiable(
              registry.flowActionBindings,
            );
    }

    if (registry == null) {
      throw _actionContractError(
        'Document requires actions, but no actions registry was provided.',
      );
    }

    final bindings =
        Map<String, FlowActionBinding<dynamic, dynamic>>.unmodifiable(
            registry.flowActionBindings);
    for (final entry in document.actions.entries) {
      final actionId = entry.key;
      final expected = entry.value;
      final binding = bindings[actionId];
      if (binding == null) {
        throw _actionContractError(
          'Missing installed binding for action "$actionId".',
        );
      }
      _validateActionContractField(
        actionId: actionId,
        field: 'actionName',
        expected: expected.actionName,
        actual: binding.actionName,
      );
      _validateActionContractField(
        actionId: actionId,
        field: 'contractVersion',
        expected: expected.contractVersion,
        actual: binding.contractVersion,
      );
      _validateActionSchemaContract(
        actionId: actionId,
        field: 'argsSchemaHash',
        expected: expected.argsSchema,
        actual: binding.argsSchema,
      );
      _validateActionSchemaContract(
        actionId: actionId,
        field: 'resultSchemaHash',
        expected: expected.resultSchema,
        actual: binding.resultSchema,
      );
      _validateActionContractField(
        actionId: actionId,
        field: 'idempotent',
        expected: expected.idempotent,
        actual: binding.idempotent,
      );
      if (binding.minClient < expected.minClient) {
        throw _actionContractError(
          'Action "$actionId" field minClient mismatch: document requires '
          '${expected.minClient}, installed binding supports '
          '${binding.minClient}.',
        );
      }
    }
    _validateActionResultPredicates(document);
    return bindings;
  }

  void _validateActionContractField({
    required String actionId,
    required String field,
    required Object expected,
    required Object actual,
  }) {
    if (expected == actual) return;
    throw _actionContractError(
      'Action "$actionId" field $field mismatch: document has $expected, '
      'installed binding has $actual.',
    );
  }

  void _validateActionSchemaContract({
    required String actionId,
    required String field,
    required FlowActionSchema expected,
    required FlowActionSchema actual,
  }) {
    final expectedHash = FlowActionSchema.hashFor(
      contractKind: field == 'argsSchemaHash' ? 'args' : 'result',
      schema: expected,
    );
    final actualHash = FlowActionSchema.hashFor(
      contractKind: field == 'argsSchemaHash' ? 'args' : 'result',
      schema: actual,
    );
    if (expectedHash == actualHash) return;
    final diffs = FlowActionSchema.diff(expected, actual);
    throw _actionContractError(
      'Action "$actionId" field $field mismatch: document has '
      '${expectedHash.value}, installed binding has ${actualHash.value}. '
      'Schema diff: ${diffs.join(', ')}.',
    );
  }

  void _validateActionResultPredicates(FlowDocument document) {
    for (final stateEntry in document.states.entries) {
      final state = stateEntry.value;
      if (state is! ScreenFlowState) continue;
      for (final eventEntry in state.on.entries) {
        final transition = eventEntry.value;
        if (transition is! ActionFlowTransition) continue;
        final contract = document.actions[transition.action];
        if (contract == null) continue;
        final issue = _resultPredicateCompatibilityIssue(
          transition.resultPredicate,
          contract.resultSchema,
        );
        if (issue == null) continue;
        throw _actionContractError(
          'Action "${transition.action}" resultPredicate for event '
          '"${eventEntry.key}" in state "${stateEntry.key}" is incompatible '
          'with result schema: $issue.',
        );
      }
    }
  }

  String? _resultPredicateCompatibilityIssue(
    FlowActionResultPredicate predicate,
    FlowActionSchema resultSchema,
  ) {
    switch (predicate) {
      case BoolEqualsActionResultPredicate():
        if (resultSchema is FlowBoolActionSchema) return null;
        return 'boolEquals requires a bool result, found '
            '${resultSchema.kind}.';
      case ObjectBoolFieldEqualsActionResultPredicate(:final field):
        if (resultSchema is! FlowObjectActionSchema) {
          return 'objectBoolFieldEquals.$field requires an object result, '
              'found ${resultSchema.kind}.';
        }
        final fieldSchema = resultSchema.fields[field];
        if (fieldSchema == null) {
          return 'objectBoolFieldEquals field "$field" is missing.';
        }
        if (!fieldSchema.required) {
          return 'objectBoolFieldEquals field "$field" must be required.';
        }
        if (fieldSchema.schema is FlowBoolActionSchema) return null;
        return 'objectBoolFieldEquals field "$field" must be bool, found '
            '${fieldSchema.schema.kind}.';
    }
  }

  Future<void> _goTo(_FlowFrame frame, String target) async {
    _isChangingState = true;
    try {
      await Future<void>.delayed(Duration.zero);
      if (!_isActiveFrame(frame)) return;
      await _enterState(frame, target, depth: 0);
    } on FlowUnavailableError catch (e) {
      await _handleFrameUnavailable(frame, e);
    } finally {
      _isChangingState = false;
    }
  }

  Future<void> _goToWithWrites(
    _FlowFrame frame,
    String target,
    Map<String, FlowStateWrite> stateWrites, {
    Object? eventSource,
  }) async {
    try {
      if (!_isActiveFrame(frame)) return;
      _applyStateWrites(frame, stateWrites, eventSource: eventSource);
      await _goTo(frame, target);
    } on FlowUnavailableError catch (e) {
      await _handleFrameUnavailable(frame, e);
    }
  }

  Future<void> _enterState(
    _FlowFrame frame,
    String target, {
    required int depth,
  }) async {
    final document = frame.resolved.document;
    if (depth > document.states.length) {
      throw _errorForFrame(
        frame,
        'screenless_cycle',
        'Screenless flow traversal exceeded ${document.states.length} states.',
      );
    }
    final state = document.states[target];
    switch (state) {
      case ScreenFlowState():
        await _showScreen(frame, target);
      case DecisionFlowState(:final branches, :final defaultBranch):
        for (final branch in branches) {
          if (!_matchesBranch(frame, branch, frame.flowState)) continue;
          _applyStateWrites(frame, branch.stateWrites);
          await _enterState(frame, branch.target, depth: depth + 1);
          return;
        }
        _applyStateWrites(frame, defaultBranch.stateWrites);
        await _enterState(frame, defaultBranch.target, depth: depth + 1);
      case SubFlowState():
        await _enterSubFlow(frame, state);
      case EndFlowState(:final result):
        await _completeFrame(frame, result);
      case UnsupportedFlowState(:final wireKind):
        throw _errorForFrame(
          frame,
          'unsupported_state_kind',
          'Unsupported flow state kind "$wireKind".',
        );
      case null:
        throw _errorForFrame(
          frame,
          'missing_transition_target',
          'Transition target "$target" does not exist.',
        );
    }
  }

  Future<void> _enterSubFlow(
    _FlowFrame parentFrame,
    SubFlowState state,
  ) async {
    if (parentFrame.subFlowDepth >= _maxSubFlowDepth) {
      throw _errorForFrame(
        parentFrame,
        'sub_flow_depth_exceeded',
        'Sub-flow nesting exceeded $_maxSubFlowDepth.',
      );
    }

    _emitFlowStarted(parentFrame);
    parentFrame.currentStateId = null;
    parentFrame.currentLibrary = null;
    _currentScreenEntryId = null;
    notifyListeners();

    final childRef = OnboardingFlowRef<Map<String, Object?>>(
      id: state.flow,
      version: state.version,
      minClient: state.minClient,
      decodeResult: _decodeSubFlowResult,
    );

    try {
      final childResolved = await resolver.resolve(childRef);
      if (!_isActiveFrame(parentFrame)) return;
      _validateSubFlowResolved(parentFrame, state, childResolved);
      final childActionBindings =
          _validateActionContracts(childResolved.document);
      final childInput = _subFlowInput(parentFrame, state, childResolved);
      final childFrame = _FlowFrame(
        resolved: childResolved,
        flowId: state.flow,
        flowVersion: state.version,
        flowSessionId: _mintFlowSessionId(),
        parentFlowSessionId: parentFrame.flowSessionId,
        subFlowDepth: parentFrame.subFlowDepth + 1,
        actionBindings: childActionBindings,
        flowState: {
          ..._initialFlowState(childResolved.document),
          ...childInput,
        },
        parent: _SubFlowParent(frame: parentFrame, state: state),
      );
      _frames.add(childFrame);
      await _enterState(childFrame, childResolved.document.initial, depth: 0);
      if (_frames.contains(childFrame) && !_isUnavailable && !_isComplete) {
        _emitFlowStarted(childFrame);
      }
    } on FlowUnavailableError catch (e) {
      await _handleSubFlowUnavailable(parentFrame, state, e);
    } on Object catch (e) {
      await _handleSubFlowUnavailable(
        parentFrame,
        state,
        _subFlowUnavailableError(
          state,
          reason: 'sub_flow_unavailable',
          message: 'Sub-flow "${state.flow}" failed: $e.',
        ),
      );
    }
  }

  void _validateSubFlowResolved(
    _FlowFrame parentFrame,
    SubFlowState state,
    ResolvedFlow resolved,
  ) {
    final document = resolved.document;
    if (document.flow != state.flow) {
      throw _subFlowUnavailableError(
        state,
        reason: 'flow_mismatch',
        message: 'Sub-flow JSON id "${document.flow}" does not match '
            'requested flow "${state.flow}".',
      );
    }
    if (document.version != state.version) {
      throw _subFlowUnavailableError(
        state,
        reason: 'version_mismatch',
        message: 'Sub-flow JSON version ${document.version} does not match '
            'requested version ${state.version}.',
      );
    }
    if (document.schemaVersion != state.schemaVersion) {
      throw _subFlowUnavailableError(
        state,
        reason: 'unsupported_schema_version',
        message: 'Sub-flow schemaVersion ${document.schemaVersion} does not '
            'match requested schemaVersion ${state.schemaVersion}.',
      );
    }
    if (document.minClient != state.minClient) {
      throw _subFlowUnavailableError(
        state,
        reason: 'unsupported_min_client',
        message: 'Sub-flow minClient ${document.minClient} does not match '
            'requested minClient ${state.minClient}.',
      );
    }
    if (resolved.contentHash != state.contentHash) {
      throw _subFlowUnavailableError(
        state,
        reason: 'hash_mismatch',
        message: 'Sub-flow document hash mismatch for "${state.flow}".',
      );
    }
    final issues = FlowDocumentValidation.validate(document);
    if (issues.isNotEmpty) {
      throw _subFlowUnavailableError(
        state,
        reason: 'validation_failed',
        message: 'Sub-flow document failed validation: ${issues.join('; ')}.',
      );
    }
    for (final key in state.input.keys) {
      if (document.flowState.containsKey(key)) continue;
      throw _errorForFrame(
        parentFrame,
        'sub_flow_input_mismatch',
        'Sub-flow input "$key" is not declared by "${state.flow}".',
      );
    }
  }

  Map<String, Object?> _subFlowInput(
    _FlowFrame parentFrame,
    SubFlowState state,
    ResolvedFlow childResolved,
  ) {
    final input = <String, Object?>{};
    for (final entry in state.input.entries) {
      final declaration = childResolved.document.flowState[entry.key];
      if (declaration == null) {
        throw _errorForFrame(
          parentFrame,
          'sub_flow_input_mismatch',
          'Sub-flow input "${entry.key}" is not declared by "${state.flow}".',
        );
      }
      final value = _resolveFlowValueSource(parentFrame, entry.value);
      if (identical(value, _missingOutboundValue)) {
        throw _errorForFrame(
          parentFrame,
          'sub_flow_input_unavailable',
          'Sub-flow input "${entry.key}" source is unavailable.',
        );
      }
      if (!_matchesFlowDataType(declaration.type, value)) {
        throw _errorForFrame(
          parentFrame,
          'sub_flow_input_type_mismatch',
          'Sub-flow input "${entry.key}" expected '
              '${declaration.type.wireName}, found ${value.runtimeType}.',
        );
      }
      input[entry.key] = value;
    }
    return input;
  }

  Future<void> _handleSubFlowUnavailable(
    _FlowFrame parentFrame,
    SubFlowState state,
    FlowUnavailableError error,
  ) async {
    if (!_restoreParentFrame(parentFrame) || _isDisposed || _isUnavailable) {
      return;
    }
    final unavailableBranch = state.subFlowUnavailable;
    if (unavailableBranch == null) {
      throw _errorForFrame(
        parentFrame,
        'sub_flow_unavailable',
        'Sub-flow "${state.flow}" is unavailable: ${error.reason}.',
      );
    }
    _applyStateWrites(parentFrame, unavailableBranch.stateWrites);
    await _enterState(parentFrame, unavailableBranch.target, depth: 0);
  }

  bool _restoreParentFrame(_FlowFrame parentFrame) {
    final parentIndex = _frames.indexOf(parentFrame);
    if (parentIndex < 0) return false;
    if (parentIndex + 1 < _frames.length) {
      _frames.removeRange(parentIndex + 1, _frames.length);
    }
    return true;
  }

  Future<void> _handleFrameUnavailable(
    _FlowFrame frame,
    FlowUnavailableError error,
  ) async {
    final parent = frame.parent;
    if (parent == null) {
      _fail(error);
      return;
    }
    try {
      await _handleSubFlowUnavailable(parent.frame, parent.state, error);
    } on FlowUnavailableError catch (parentError) {
      _fail(parentError);
    }
  }

  FlowUnavailableError _subFlowUnavailableError(
    SubFlowState state, {
    required String reason,
    required String message,
  }) {
    return FlowUnavailableError(
      flowId: state.flow,
      flowVersion: state.version,
      reason: reason,
      message: message,
    );
  }

  Future<void> _showScreen(_FlowFrame frame, String stateId) async {
    if (_isDisposed) return;
    final resolved = frame.resolved;
    final state = resolved.document.states[stateId];
    if (state is! ScreenFlowState) {
      throw _errorForFrame(
        frame,
        'invalid_screen_state',
        'Flow state "$stateId" is not a screen state.',
      );
    }
    final library = _decodeScreenBlob(frame, state.screen);
    final entryId = ++_screenEntrySequence;
    frame.currentStateId = stateId;
    frame.currentLibrary = library;
    _currentScreenEntryId = entryId;
    // Record this screen *visit* on the frame's back-stack. Forward navigation
    // pushes; back() pops. Decision/action states are never recorded (they sit
    // between screens), so back structurally skips them.
    frame.screenHistory.add(_ScreenEntry(
      entryId: entryId,
      stateId: stateId,
      library: library,
    ));
    _evictScreenHistory(frame);
    _emitFlowStarted(frame);
    // `_emitFlowStarted` invokes the host's synchronous `onEvent`, which can
    // re-enter and fail the controller closed (or disposed). Re-check the frame
    // is still active before emitting the step impression / notifying — neither
    // should run for a screen the host just tore down.
    if (!_isActiveFrame(frame)) return;
    _emitStepViewed(frame, stateId);
    notifyListeners();
  }

  /// Bounds the frame's screen back-stack, dropping the oldest visit past the
  /// cap. This is the *single* bound on retained history: the rendering surface
  /// mounts exactly the entries in [reachableScreenEntryIds] and prunes the
  /// rest, so coherence is structural — there is no second, hand-synchronized
  /// mounted-screen cap to keep in lockstep. The evicted boundary becomes a
  /// natural `canBack:false` barrier, and because the view mounts only reachable
  /// entries, back never targets an unmounted (and thus un-restorable) screen.
  /// Realistic onboarding flows are far smaller than the cap, so this never
  /// trips in practice.
  void _evictScreenHistory(_FlowFrame frame) {
    while (frame.screenHistory.length > _maxScreenHistory) {
      final evicted = frame.screenHistory.removeAt(0);
      debugPrint(
        '[restage] Flow screen history exceeded $_maxScreenHistory visits; '
        'dropping the oldest (entry ${evicted.entryId}); back past here is '
        'unavailable.',
      );
    }
  }

  WidgetLibrary _decodeScreenBlob(_FlowFrame frame, String screenId) {
    final resolved = frame.resolved;
    final artifact = resolved.document.screenArtifacts[screenId];
    if (artifact == null) {
      throw _errorForFrame(
        frame,
        'missing_screen_artifact',
        'Screen artifact "$screenId" does not exist.',
      );
    }
    final bytes = resolved.screenBlobs[screenId];
    if (bytes == null) {
      throw _errorForFrame(
        frame,
        'missing_screen_blob',
        'Resolved flow omitted screen blob "$screenId".',
      );
    }
    final actualHash = FlowContentHash.compute(bytes);
    if (actualHash != artifact.contentHash) {
      throw _errorForFrame(
        frame,
        'hash_mismatch',
        artifact.contentHash.diagnosticForMismatch(
          path: artifact.path,
          actual: actualHash,
        ),
      );
    }
    try {
      return decodeLibraryBlob(bytes);
    } on Object catch (e) {
      throw _errorForFrame(
        frame,
        'decode_failed',
        'Could not decode onboarding screen "$screenId": $e.',
      );
    }
  }

  Future<void> _completeFrame(
    _FlowFrame frame,
    Map<String, Object?> result,
  ) async {
    if (_isDisposed) return;
    if (!_frames.contains(frame)) return;
    final filteredResult = _terminalResultForDecode(frame, result);
    _emitFlowStarted(frame);
    final parent = frame.parent;
    if (parent != null) {
      onEvent(FlowCompleted(
        flowId: frame.flowId,
        flowVersion: frame.flowVersion,
        flowSessionId: frame.flowSessionId,
        parentFlowSessionId: frame.parentFlowSessionId,
      ));
      await _completeSubFlow(frame, parent, filteredResult);
      return;
    }
    final R decoded;
    try {
      decoded = flow.decodeResult(filteredResult);
    } on Object catch (e) {
      _fail(_errorForFrame(
        frame,
        'result_decode_failed',
        'Could not decode terminal result for flow "${flow.id}": $e.',
      ));
      return;
    }
    onEvent(FlowCompleted(
      flowId: frame.flowId,
      flowVersion: frame.flowVersion,
      flowSessionId: frame.flowSessionId,
      parentFlowSessionId: frame.parentFlowSessionId,
    ));
    _isComplete = true;
    // Announce completion before the host callback: a completed flow no longer
    // navigates (`canBack`/`canSkip` are false), so a rendering surface rebuilds
    // and collapses its chrome. Notifying *before* `onComplete` keeps it safe if
    // the host disposes the controller inside that callback. The current screen
    // entry is unchanged, so the view's screen reconciliation is a no-op.
    notifyListeners();
    onComplete(decoded);
  }

  Future<void> _completeSubFlow(
    _FlowFrame childFrame,
    _SubFlowParent parent,
    Map<String, Object?> childResult,
  ) async {
    if (!identical(_currentFrame, childFrame)) return;
    _frames.removeLast();
    final parentFrame = parent.frame;
    if (!_frames.contains(parentFrame) || _isDisposed || _isUnavailable) {
      return;
    }
    final subFlowResult = _filterOutboundFields(
      parentFrame,
      parentFrame.resolved.document.outbound.subFlowResult,
      childResult,
      allowStateRefs: false,
      allowLegacyStateRefFallback: false,
      diagnosticSurface: 'sub-flow result',
    );
    var target = parent.state.defaultBranch;
    for (final branch in parent.state.onComplete) {
      if (!_matchesBranch(
        parentFrame,
        branch,
        subFlowResult,
        subFlowResultSource: subFlowResult,
      )) {
        continue;
      }
      target = FlowBranchTarget(
        target: branch.target,
        stateWrites: branch.stateWrites,
      );
      break;
    }
    _applyStateWrites(
      parentFrame,
      target.stateWrites,
      subFlowResultSource: subFlowResult,
    );
    await _enterState(parentFrame, target.target, depth: 0);
  }

  void _emitFlowStarted(_FlowFrame frame) {
    if (frame.hasStarted) return;
    frame.hasStarted = true;
    onEvent(FlowStarted(
      flowId: frame.flowId,
      flowVersion: frame.flowVersion,
      flowSessionId: frame.flowSessionId,
      parentFlowSessionId: frame.parentFlowSessionId,
    ));
  }

  /// Emits the per-screen funnel impression for [screenId] on [frame]. Fired
  /// once per *forward* screen entry (back navigation restores from history and
  /// does not call [_showScreen]); [OnboardingStepViewed.stepIndex] is the
  /// screen's 0-based depth in the frame's retained back-stack.
  void _emitStepViewed(_FlowFrame frame, String screenId) {
    onEvent(OnboardingStepViewed(
      flowId: frame.flowId,
      flowVersion: frame.flowVersion,
      flowSessionId: frame.flowSessionId,
      screenId: screenId,
      stepIndex: frame.screenHistory.length - 1,
      stepCount: _screenStateCount(frame),
    ));
  }

  /// The number of screen states authored in [frame]'s flow document — the
  /// best-effort `stepCount` denominator.
  int _screenStateCount(_FlowFrame frame) =>
      frame.resolved.document.states.values.whereType<ScreenFlowState>().length;

  /// Emits [OnboardingPermissionResponse] when a host action's [encodedResult]
  /// reports a `granted` boolean — the convention that marks an action as a
  /// permission request (e.g. notification priming). A non-permission action
  /// (no `granted` boolean in its result) emits nothing.
  void _maybeEmitPermissionResponse(
    _FlowFrame frame,
    String action,
    Object? encodedResult,
  ) {
    if (encodedResult is! Map) return;
    final granted = encodedResult['granted'];
    if (granted is! bool) return;
    onEvent(OnboardingPermissionResponse(
      flowId: frame.flowId,
      flowVersion: frame.flowVersion,
      flowSessionId: frame.flowSessionId,
      permission: action,
      granted: granted,
    ));
  }

  Map<String, Object?> _terminalResultForDecode(
    _FlowFrame frame,
    Map<String, Object?> result,
  ) {
    final document = frame.resolved.document;
    if (document.legacyTerminalResultPassthrough) {
      return result;
    }
    return _filterOutboundFields(
      frame,
      document.outbound.terminalResult,
      result,
      allowStateRefs: true,
      allowLegacyStateRefFallback: !_usesGraphRuntime(document),
      diagnosticSurface: 'terminal result',
    );
  }

  bool _emitCustomEvent(
    _FlowFrame frame,
    String eventName,
    Object? args,
  ) {
    final document = frame.resolved.document;
    final declaration = document.outbound.customEvents[eventName];
    if (declaration == null) return false;
    final fields = _filterOutboundFields(
      frame,
      declaration,
      args,
      allowStateRefs: false,
      allowLegacyStateRefFallback: false,
      diagnosticSurface: 'custom event "$eventName"',
    );
    onEvent(FlowCustomEvent(
      flowId: frame.flowId,
      flowVersion: frame.flowVersion,
      eventName: eventName,
      fields: Map.unmodifiable(fields),
    ));
    return true;
  }

  Map<String, Object?> _filterOutboundFields(
    _FlowFrame frame,
    FlowOutboundPayloadDeclaration declaration,
    Object? source, {
    required bool allowStateRefs,
    required bool allowLegacyStateRefFallback,
    required String diagnosticSurface,
  }) {
    final fields = <String, Object?>{};
    for (final entry in declaration.fields.entries) {
      final value = _resolveOutboundField(
        frame,
        entry.value.ref,
        source,
        allowStateRefs: allowStateRefs,
        allowLegacyStateRefFallback: allowLegacyStateRefFallback,
      );
      if (identical(value, _missingOutboundValue)) {
        debugPrint(
          '[restage] Dropping flow outbound field "${entry.key}" on '
          '$diagnosticSurface: source is unavailable.',
        );
        continue;
      }
      if (!_matchesFlowDataType(entry.value.type, value)) {
        debugPrint(
          '[restage] Dropping flow outbound field "${entry.key}" on '
          '$diagnosticSurface: value does not match '
          '${entry.value.type.wireName}.',
        );
        continue;
      }
      fields[entry.key] = value;
    }
    return fields;
  }

  Object? _resolveOutboundField(
    _FlowFrame frame,
    FlowOutboundRef ref,
    Object? source, {
    required bool allowStateRefs,
    required bool allowLegacyStateRefFallback,
  }) {
    switch (ref) {
      case EventFlowOutboundRef(:final key, :final path):
        return _readObjectPath(source, key, path);
      case StateFlowOutboundRef(:final key, :final path):
        if (!allowStateRefs) return _missingOutboundValue;
        final stateValue = _readObjectPath(frame.flowState, key, path);
        if (!identical(stateValue, _missingOutboundValue)) return stateValue;
        return allowLegacyStateRefFallback
            ? _readObjectPath(source, key, path)
            : _missingOutboundValue;
    }
  }

  Object? _readObjectPath(Object? source, String key, List<String> path) {
    var value = _readObjectKey(source, key);
    if (identical(value, _missingOutboundValue)) {
      return value;
    }
    for (final segment in path) {
      value = _readObjectKey(value, segment);
      if (identical(value, _missingOutboundValue)) {
        return value;
      }
    }
    return value;
  }

  Object? _readObjectKey(Object? value, String key) {
    if (value is Map<String, Object?>) {
      return value.containsKey(key) ? value[key] : _missingOutboundValue;
    }
    if (value is Map) {
      return value.containsKey(key) ? value[key] : _missingOutboundValue;
    }
    return _missingOutboundValue;
  }

  bool _matchesFlowDataType(FlowDataType type, Object? value) {
    return switch (type) {
      FlowDataType.bool => value is bool,
      FlowDataType.int => value is int,
      FlowDataType.string => value is String,
    };
  }

  void _fail(FlowUnavailableError error) {
    // A completed flow already delivered its result; it can never retroactively
    // fail closed (e.g. a late render error from a lingering completed screen).
    if (_isDisposed || _isUnavailable || _isComplete) return;
    _isUnavailable = true;
    _activeActionToken = null;
    _currentScreenEntryId = null;
    _frames.clear();
    onEvent(FlowUnavailable(
      flowId: error.flowId,
      flowVersion: error.flowVersion,
      reason: error.reason,
      message: error.message,
    ));
    onUnavailable(error);
    notifyListeners();
  }

  FlowUnavailableError _error(String reason, String message) {
    return FlowUnavailableError(
      flowId: flow.id,
      flowVersion: flow.version,
      reason: reason,
      message: message,
    );
  }

  FlowUnavailableError _errorForFrame(
    _FlowFrame frame,
    String reason,
    String message,
  ) {
    return FlowUnavailableError(
      flowId: frame.flowId,
      flowVersion: frame.flowVersion,
      reason: reason,
      message: message,
    );
  }

  FlowUnavailableError _actionContractError(String message) {
    return _error('action_contract_mismatch', message);
  }

  Object? _actionArgsForDecode(
    _FlowFrame frame,
    ActionFlowTransition transition,
    Object? rawArgs,
  ) {
    final declaration =
        frame.resolved.document.outbound.actionArgs[transition.action];
    if (declaration == null) {
      if (_isEmptyActionArgs(rawArgs)) return rawArgs;
      throw _errorForFrame(
        frame,
        'action_args_unavailable',
        'Action "${transition.action}" received arguments without an '
            'outbound actionArgs declaration.',
      );
    }
    return _filterOutboundFields(
      frame,
      declaration,
      rawArgs,
      allowStateRefs: true,
      allowLegacyStateRefFallback: false,
      diagnosticSurface: 'action args for "${transition.action}"',
    );
  }

  bool _isEmptyActionArgs(Object? value) {
    return value == null || (value is Map && value.isEmpty);
  }

  Future<void> _invokeAction(
    _FlowFrame frame,
    ActionFlowTransition transition,
    FlowActionBinding<dynamic, dynamic> binding,
    Object? rawArgs,
  ) async {
    final token = Object();
    _activeActionToken = token;
    // The flow is now busy (a host action is in flight): notify so a rendering
    // surface can reflect [isBusy] — e.g. hold the back/skip chrome inert while
    // the action runs. This is purely a listener ping; it does not change the
    // current screen, so the view's screen reconciliation is a no-op.
    notifyListeners();
    try {
      // A listener re-entering the action-start notify above can have failed the
      // controller closed (`reportRenderFailure`) or disposed it — neither is
      // gated by the action token. Re-check before running the host handler so a
      // failed-closed/disposed controller never invokes it (the fail-closed
      // invariant). Inside the `try` so the `finally` still clears the token (a
      // return before it would leak `_activeActionToken` and wedge back/skip).
      if (!_isActiveAction(token, frame)) return;
      final filteredArgs = _actionArgsForDecode(frame, transition, rawArgs);
      final decodedArgs = binding.decodeRuntimeArgs(filteredArgs);
      final context = FlowActionContext(
        operationId: _mintOperationId(),
        isRetry: false,
        attemptNumber: 1,
      );
      final result = await Future<dynamic>.value(
        binding.invokeRuntimeHandler(decodedArgs, context),
      );
      if (!_isActiveAction(token, frame)) return;
      final encoded = binding.encodeRuntimeResult(result);
      if (!_isActiveAction(token, frame)) return;
      // A permission host-action reports a `granted` boolean; surface it as the
      // funnel event before the predicate decides flow advancement, so a decline
      // (which keeps the user on the screen) is captured too.
      _maybeEmitPermissionResponse(frame, transition.action, encoded);
      final matched = _evaluateActionResultPredicate(
        frame,
        transition.resultPredicate,
        encoded,
      );
      if (!_isActiveAction(token, frame)) return;
      if (matched) {
        _applyStateWrites(
          frame,
          transition.stateWrites,
          eventSource: rawArgs,
          actionResultSource: encoded,
        );
        // The action resolved and is advancing the flow: clear the in-flight
        // token now (before the transition) so the advance is gated only by
        // `_isChangingState`.
        _activeActionToken = null;
        await _goTo(frame, transition.target);
      }
    } on FlowUnavailableError catch (e) {
      if (_isActiveAction(token, frame)) {
        await _handleFrameUnavailable(frame, e);
      }
    } on Object catch (e) {
      if (_isActiveAction(token, frame)) {
        await _handleFrameUnavailable(
          frame,
          _errorForFrame(
            frame,
            'action_handler_failed',
            'Action "${transition.action}" failed: $e.',
          ),
        );
      }
    } finally {
      // Reached when the action did not advance the flow (predicate false, or a
      // failure already handled). Clear the in-flight token and notify so chrome
      // affordances become interactive again — unless the controller was
      // disposed mid-action (then notifying would throw; dispose already cleared
      // the token).
      if (identical(_activeActionToken, token)) {
        _activeActionToken = null;
        if (!_isDisposed) notifyListeners();
      }
    }
  }

  bool _isActiveAction(Object token, _FlowFrame frame) {
    return !_isDisposed &&
        !_isUnavailable &&
        !_isComplete &&
        _isActiveFrame(frame) &&
        identical(_activeActionToken, token);
  }

  bool _isActiveFrame(_FlowFrame frame) {
    return !_isDisposed &&
        !_isUnavailable &&
        !_isComplete &&
        identical(_currentFrame, frame);
  }

  String _mintOperationId() {
    _nextOperationId += 1;
    return 'flow-action:$_operationSessionId:$_nextOperationId';
  }

  static String _mintFlowSessionId() {
    return 'flow-session:${_mintOperationSessionId()}';
  }

  static String _mintOperationSessionId() {
    final parts = List<String>.generate(
      4,
      (_) => _operationIdRandom.nextInt(0x100000000).toRadixString(16).padLeft(
            8,
            '0',
          ),
      growable: false,
    );
    return parts.join();
  }

  static Map<String, Object?> _decodeSubFlowResult(
    Map<String, Object?> result,
  ) {
    return Map.unmodifiable(result);
  }

  bool _evaluateActionResultPredicate(
    _FlowFrame frame,
    FlowActionResultPredicate predicate,
    Object? result,
  ) {
    switch (predicate) {
      case BoolEqualsActionResultPredicate(:final value):
        if (result is bool) return result == value;
        throw _errorForFrame(
          frame,
          'action_result_mismatch',
          'Action result predicate expected a bool result, found '
              '${result.runtimeType}.',
        );
      case ObjectBoolFieldEqualsActionResultPredicate(
          :final field,
          :final value,
        ):
        if (result is! Map) {
          throw _errorForFrame(
            frame,
            'action_result_mismatch',
            'Action result predicate expected an object result, found '
                '${result.runtimeType}.',
          );
        }
        final fieldValue = result[field];
        if (fieldValue is bool) return fieldValue == value;
        throw _errorForFrame(
          frame,
          'action_result_mismatch',
          'Action result predicate expected bool field "$field", found '
              '${fieldValue.runtimeType}.',
        );
    }
  }

  void _applyStateWrites(
    _FlowFrame frame,
    Map<String, FlowStateWrite> stateWrites, {
    Object? eventSource,
    Object? actionResultSource,
    Object? subFlowResultSource,
  }) {
    if (stateWrites.isEmpty) return;
    final resolvedWrites = <String, Object?>{};
    for (final entry in stateWrites.entries) {
      final value = _resolveFlowValueSource(
        frame,
        entry.value.value,
        eventSource: eventSource,
        actionResultSource: actionResultSource,
        subFlowResultSource: subFlowResultSource,
      );
      if (identical(value, _missingOutboundValue)) {
        throw _errorForFrame(
          frame,
          'state_write_unavailable',
          'State write "${entry.key}" source is unavailable.',
        );
      }
      if (!_matchesFlowDataType(entry.value.type, value)) {
        throw _errorForFrame(
          frame,
          'state_write_type_mismatch',
          'State write "${entry.key}" expected '
              '${entry.value.type.wireName}, found ${value.runtimeType}.',
        );
      }
      resolvedWrites[entry.key] = value;
    }
    frame.flowState = Map.unmodifiable({
      ...frame.flowState,
      ...resolvedWrites,
    });
  }

  bool _matchesBranch(
    _FlowFrame frame,
    FlowBranch branch,
    Object? subject, {
    Object? subFlowResultSource,
  }) {
    for (final entry in branch.when.fields.entries) {
      final value = _readObjectPath(subject, entry.key, const []);
      if (!_matchesPredicateCondition(
        frame,
        value,
        entry.value,
        subFlowResultSource: subFlowResultSource,
      )) {
        return false;
      }
    }
    return true;
  }

  bool _matchesPredicateCondition(
    _FlowFrame frame,
    Object? actual,
    FlowPredicateCondition condition, {
    Object? subFlowResultSource,
  }) {
    switch (condition) {
      case ExistsFlowPredicateCondition(:final exists):
        return !identical(actual, _missingOutboundValue) == exists;
      case EqualsFlowPredicateCondition(:final value):
        if (identical(actual, _missingOutboundValue)) return false;
        return actual ==
            _requiredPredicateValue(
              frame,
              value,
              subFlowResultSource: subFlowResultSource,
            );
      case NotEqualsFlowPredicateCondition(:final value):
        if (identical(actual, _missingOutboundValue)) return false;
        return actual !=
            _requiredPredicateValue(
              frame,
              value,
              subFlowResultSource: subFlowResultSource,
            );
      case InFlowPredicateCondition(:final values):
        if (identical(actual, _missingOutboundValue)) return false;
        return values.any(
          (value) =>
              actual ==
              _requiredPredicateValue(
                frame,
                value,
                subFlowResultSource: subFlowResultSource,
              ),
        );
      case GreaterThanFlowPredicateCondition(:final value):
        return _compareIntPredicate(
          frame,
          actual,
          value,
          (left, right) => left > right,
          subFlowResultSource: subFlowResultSource,
        );
      case GreaterThanOrEqualsFlowPredicateCondition(:final value):
        return _compareIntPredicate(
          frame,
          actual,
          value,
          (left, right) => left >= right,
          subFlowResultSource: subFlowResultSource,
        );
      case LessThanFlowPredicateCondition(:final value):
        return _compareIntPredicate(
          frame,
          actual,
          value,
          (left, right) => left < right,
          subFlowResultSource: subFlowResultSource,
        );
      case LessThanOrEqualsFlowPredicateCondition(:final value):
        return _compareIntPredicate(
          frame,
          actual,
          value,
          (left, right) => left <= right,
          subFlowResultSource: subFlowResultSource,
        );
    }
  }

  Object? _requiredPredicateValue(
    _FlowFrame frame,
    FlowValueSource source, {
    Object? subFlowResultSource,
  }) {
    final value = _resolveFlowValueSource(
      frame,
      source,
      subFlowResultSource: subFlowResultSource,
    );
    if (identical(value, _missingOutboundValue)) {
      throw _errorForFrame(
        frame,
        'predicate_source_unavailable',
        'Decision predicate source is unavailable.',
      );
    }
    return value;
  }

  bool _compareIntPredicate(
    _FlowFrame frame,
    Object? actual,
    FlowValueSource expected,
    bool Function(int left, int right) compare, {
    Object? subFlowResultSource,
  }) {
    if (identical(actual, _missingOutboundValue)) return false;
    final expectedValue = _requiredPredicateValue(
      frame,
      expected,
      subFlowResultSource: subFlowResultSource,
    );
    if (actual is int && expectedValue is int) {
      return compare(actual, expectedValue);
    }
    throw _errorForFrame(
      frame,
      'predicate_type_mismatch',
      'Numeric decision predicate expected int values.',
    );
  }

  Object? _resolveFlowValueSource(
    _FlowFrame frame,
    FlowValueSource source, {
    Object? eventSource,
    Object? actionResultSource,
    Object? subFlowResultSource,
  }) {
    switch (source) {
      case LiteralFlowValueSource(:final value):
        return value;
      case StateFlowValueSource(:final key, :final path):
        return _readObjectPath(frame.flowState, key, path);
      case EventFlowValueSource(:final key, :final path):
        if (eventSource == null) return _missingOutboundValue;
        return _readObjectPath(eventSource, key, path);
      case ActionResultFlowValueSource(:final key, :final path):
        if (actionResultSource == null) return _missingOutboundValue;
        return _readObjectPath(actionResultSource, key, path);
      case SubFlowResultFlowValueSource(:final key, :final path):
        if (subFlowResultSource == null) return _missingOutboundValue;
        return _readObjectPath(subFlowResultSource, key, path);
    }
  }

  bool _usesGraphRuntime(FlowDocument document) {
    for (final state in document.states.values) {
      switch (state) {
        case DecisionFlowState():
        case SubFlowState():
          return true;
        case ScreenFlowState(:final on):
          for (final transition in on.values) {
            switch (transition) {
              case GotoFlowTransition(:final stateWrites):
              case ActionFlowTransition(:final stateWrites):
                if (stateWrites.isNotEmpty) return true;
            }
          }
        case EndFlowState() || UnsupportedFlowState():
          continue;
      }
    }
    return false;
  }
}

final class _FlowFrame {
  _FlowFrame({
    required this.resolved,
    required this.flowId,
    required this.flowVersion,
    required this.flowSessionId,
    required this.parentFlowSessionId,
    required this.subFlowDepth,
    required this.actionBindings,
    required Map<String, Object?> flowState,
    this.parent,
  }) : flowState = Map.unmodifiable(flowState);

  final ResolvedFlow resolved;
  final String flowId;
  final int flowVersion;
  final String flowSessionId;
  final String? parentFlowSessionId;
  final int subFlowDepth;
  final Map<String, FlowActionBinding<dynamic, dynamic>> actionBindings;
  final _SubFlowParent? parent;

  Map<String, Object?> flowState;
  String? currentStateId;
  WidgetLibrary? currentLibrary;
  bool hasStarted = false;

  /// The frame's screen back-stack: one entry per screen *visit*, in visit
  /// order. The last entry is the current screen. Scoped to this frame so a
  /// sub-flow boundary is an automatic back barrier.
  final List<_ScreenEntry> screenHistory = <_ScreenEntry>[];
}

/// One recorded screen visit on a frame's back-stack. Holds the minted entry id
/// and the decoded library so back can restore the *same* visit (and thus the
/// same mounted instance, keyed by entry id) without re-decoding.
final class _ScreenEntry {
  _ScreenEntry({
    required this.entryId,
    required this.stateId,
    required this.library,
  });

  final int entryId;
  final String stateId;
  final WidgetLibrary library;
}

final class _SubFlowParent {
  const _SubFlowParent({
    required this.frame,
    required this.state,
  });

  final _FlowFrame frame;
  final SubFlowState state;
}
