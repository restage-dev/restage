// Flow compatibility DTOs mirror their public field names.
// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:restage_shared/src/flow_document/flow_document.dart';
import 'package:restage_shared/src/flow_document/flow_document_codec.dart';
import 'package:restage_shared/src/flow_document/flow_document_validation.dart';

enum FlowCompatibilityClassification {
  free,
  additive,
  forwarding,
  breaking,
}

final class FlowDocumentCompatibilityChange {
  const FlowDocumentCompatibilityChange({
    required this.code,
    required this.path,
    required this.classification,
    required this.message,
  });

  final String code;
  final String path;
  final FlowCompatibilityClassification classification;
  final String message;
}

final class FlowDocumentCompatibilityReport {
  const FlowDocumentCompatibilityReport({
    required this.classification,
    required this.changes,
  });

  final FlowCompatibilityClassification classification;
  final List<FlowDocumentCompatibilityChange> changes;
}

abstract final class FlowDocumentCompatibility {
  static FlowCompatibilityClassification classify({
    required FlowDocument from,
    required FlowDocument to,
  }) {
    return diff(from: from, to: to).classification;
  }

  static FlowDocumentCompatibilityReport diff({
    required FlowDocument from,
    required FlowDocument to,
  }) {
    FlowDocumentValidation.checkValid(from);
    FlowDocumentValidation.checkValid(to);

    final changes = <FlowDocumentCompatibilityChange>[];

    void add(
      String code,
      String path,
      FlowCompatibilityClassification classification,
      String message,
    ) {
      changes.add(
        FlowDocumentCompatibilityChange(
          code: code,
          path: path,
          classification: classification,
          message: message,
        ),
      );
    }

    _diffLegacyTerminalResultPassthrough(from, to, add);

    if (_canonicalJson(from) == _canonicalJson(to) && changes.isEmpty) {
      return const FlowDocumentCompatibilityReport(
        classification: FlowCompatibilityClassification.free,
        changes: [],
      );
    }

    final fromReachable = _reachableStates(from);
    final toReachable = _reachableStates(to);

    if (from.flow != to.flow) {
      add(
        'flowChanged',
        r'$.flow',
        FlowCompatibilityClassification.breaking,
        'Flow id changed from "${from.flow}" to "${to.flow}".',
      );
    }
    if (to.schemaVersion > from.schemaVersion) {
      add(
        'schemaVersionRaised',
        r'$.schemaVersion',
        FlowCompatibilityClassification.forwarding,
        'schemaVersion raised from ${from.schemaVersion} to '
            '${to.schemaVersion}.',
      );
    } else if (to.schemaVersion < from.schemaVersion) {
      add(
        'schemaVersionLowered',
        r'$.schemaVersion',
        FlowCompatibilityClassification.breaking,
        'schemaVersion lowered from ${from.schemaVersion} to '
            '${to.schemaVersion}.',
      );
    }
    if (to.minClient > from.minClient) {
      add(
        'minClientRaised',
        r'$.minClient',
        FlowCompatibilityClassification.forwarding,
        'minClient raised from ${from.minClient} to ${to.minClient}.',
      );
    }
    if (from.initial != to.initial) {
      add(
        'initialChanged',
        r'$.initial',
        FlowCompatibilityClassification.breaking,
        'Initial state changed from "${from.initial}" to "${to.initial}".',
      );
    }

    _diffActions(from, to, add);
    _diffFlowState(from, to, add);
    _diffOutbound(from, to, add);
    _diffScreenArtifacts(from, to, add);
    _diffStates(from, to, fromReachable, toReachable, add);

    return FlowDocumentCompatibilityReport(
      classification: _maxClassification(
        changes.map((change) => change.classification),
      ),
      changes: List.unmodifiable(changes),
    );
  }
}

typedef _AddChange = void Function(
  String code,
  String path,
  FlowCompatibilityClassification classification,
  String message,
);

void _diffLegacyTerminalResultPassthrough(
  FlowDocument from,
  FlowDocument to,
  _AddChange add,
) {
  if (from.legacyTerminalResultPassthrough ==
      to.legacyTerminalResultPassthrough) {
    return;
  }
  add(
    'legacyTerminalResultPassthroughChanged',
    r'$',
    FlowCompatibilityClassification.breaking,
    'Legacy terminal result passthrough changed from '
        '${from.legacyTerminalResultPassthrough} to '
        '${to.legacyTerminalResultPassthrough}; terminal result filtering '
        'semantics changed.',
  );
}

void _diffActions(
  FlowDocument from,
  FlowDocument to,
  _AddChange add,
) {
  for (final id in from.actions.keys) {
    final before = from.actions[id]!;
    final after = to.actions[id];
    if (after == null) {
      add(
        'actionRemoved',
        '\$.actions.$id',
        FlowCompatibilityClassification.breaking,
        'Action "$id" was removed.',
      );
      continue;
    }
    if (_actionContractFingerprint(before) !=
        _actionContractFingerprint(after)) {
      add(
        'actionChanged',
        '\$.actions.$id',
        FlowCompatibilityClassification.breaking,
        'Action "$id" contract changed.',
      );
    }
  }
  for (final id in to.actions.keys) {
    if (from.actions.containsKey(id)) continue;
    add(
      'actionAdded',
      '\$.actions.$id',
      FlowCompatibilityClassification.additive,
      'Action "$id" was added.',
    );
  }
}

void _diffFlowState(
  FlowDocument from,
  FlowDocument to,
  _AddChange add,
) {
  for (final key in from.flowState.keys) {
    final before = from.flowState[key]!;
    final after = to.flowState[key];
    if (after == null) {
      add(
        'flowStateRemoved',
        '\$.flowState.$key',
        FlowCompatibilityClassification.breaking,
        'Flow-state key "$key" was removed.',
      );
      continue;
    }
    if (before.type != after.type ||
        before.classification != after.classification) {
      add(
        'flowStateChanged',
        '\$.flowState.$key',
        FlowCompatibilityClassification.breaking,
        'Flow-state key "$key" changed type or classification.',
      );
    }
  }
  for (final key in to.flowState.keys) {
    if (from.flowState.containsKey(key)) continue;
    final declaration = to.flowState[key]!;
    add(
      'flowStateAdded',
      '\$.flowState.$key',
      declaration.defaultValue == null
          ? FlowCompatibilityClassification.breaking
          : FlowCompatibilityClassification.additive,
      'Flow-state key "$key" was added.',
    );
  }
}

void _diffOutbound(
  FlowDocument from,
  FlowDocument to,
  _AddChange add,
) {
  _diffOutboundPayloadMap(
    r'$.outbound.actionArgs',
    from.outbound.actionArgs,
    to.outbound.actionArgs,
    add,
  );
  _diffOutboundPayload(
    r'$.outbound.terminalResult',
    from.outbound.terminalResult,
    to.outbound.terminalResult,
    add,
  );
  _diffOutboundPayload(
    r'$.outbound.lifecycle',
    from.outbound.lifecycle,
    to.outbound.lifecycle,
    add,
  );
  _diffOutboundPayload(
    r'$.outbound.surveyAnswers',
    from.outbound.surveyAnswers,
    to.outbound.surveyAnswers,
    add,
  );
  _diffOutboundPayload(
    r'$.outbound.subFlowResult',
    from.outbound.subFlowResult,
    to.outbound.subFlowResult,
    add,
  );
  _diffOutboundPayloadMap(
    r'$.outbound.customEvents',
    from.outbound.customEvents,
    to.outbound.customEvents,
    add,
  );
}

void _diffOutboundPayloadMap(
  String path,
  Map<String, FlowOutboundPayloadDeclaration> before,
  Map<String, FlowOutboundPayloadDeclaration> after,
  _AddChange add,
) {
  for (final key in before.keys) {
    final oldPayload = before[key]!;
    final newPayload = after[key];
    if (newPayload == null) {
      add(
        'outboundPayloadRemoved',
        '$path.$key',
        FlowCompatibilityClassification.breaking,
        'Outbound payload "$key" was removed.',
      );
      continue;
    }
    _diffOutboundPayload('$path.$key', oldPayload, newPayload, add);
  }
  for (final key in after.keys) {
    if (before.containsKey(key)) continue;
    add(
      'outboundPayloadAdded',
      '$path.$key',
      FlowCompatibilityClassification.additive,
      'Outbound payload "$key" was added.',
    );
  }
}

void _diffOutboundPayload(
  String path,
  FlowOutboundPayloadDeclaration before,
  FlowOutboundPayloadDeclaration after,
  _AddChange add,
) {
  for (final key in before.fields.keys) {
    final oldField = before.fields[key]!;
    final newField = after.fields[key];
    if (newField == null) {
      add(
        'outboundFieldRemoved',
        '$path.fields.$key',
        FlowCompatibilityClassification.breaking,
        'Outbound field "$key" was removed.',
      );
      continue;
    }
    if (_outboundFieldFingerprint(oldField) !=
        _outboundFieldFingerprint(newField)) {
      add(
        'outboundFieldChanged',
        '$path.fields.$key',
        FlowCompatibilityClassification.breaking,
        'Outbound field "$key" changed.',
      );
    }
  }
  for (final key in after.fields.keys) {
    if (before.fields.containsKey(key)) continue;
    add(
      'outboundFieldAdded',
      '$path.fields.$key',
      FlowCompatibilityClassification.additive,
      'Outbound field "$key" was added.',
    );
  }
}

void _diffScreenArtifacts(
  FlowDocument from,
  FlowDocument to,
  _AddChange add,
) {
  for (final key in from.screenArtifacts.keys) {
    final before = from.screenArtifacts[key]!;
    final after = to.screenArtifacts[key];
    if (after == null) {
      add(
        'screenArtifactRemoved',
        '\$.screenArtifacts.$key',
        FlowCompatibilityClassification.breaking,
        'Screen artifact "$key" was removed.',
      );
      continue;
    }
    if (_artifactFingerprint(before) != _artifactFingerprint(after)) {
      add(
        'screenArtifactChanged',
        '\$.screenArtifacts.$key',
        FlowCompatibilityClassification.additive,
        'Screen artifact "$key" changed.',
      );
    }
  }
  for (final key in to.screenArtifacts.keys) {
    if (from.screenArtifacts.containsKey(key)) continue;
    add(
      'screenArtifactAdded',
      '\$.screenArtifacts.$key',
      FlowCompatibilityClassification.additive,
      'Screen artifact "$key" was added.',
    );
  }
}

void _diffStates(
  FlowDocument from,
  FlowDocument to,
  Set<String> fromReachable,
  Set<String> toReachable,
  _AddChange add,
) {
  for (final id in from.states.keys) {
    final before = from.states[id]!;
    final after = to.states[id];
    if (after == null) {
      add(
        'stateRemoved',
        '\$.states.$id',
        fromReachable.contains(id)
            ? FlowCompatibilityClassification.breaking
            : FlowCompatibilityClassification.free,
        'State "$id" was removed.',
      );
      continue;
    }
    if (before.kind != after.kind) {
      add(
        'stateKindChanged',
        '\$.states.$id.kind',
        FlowCompatibilityClassification.breaking,
        'State "$id" changed kind.',
      );
      continue;
    }
    _diffState(from, to, id, before, after, toReachable, add);
  }

  for (final id in to.states.keys) {
    if (from.states.containsKey(id)) continue;
    add(
      'stateAdded',
      '\$.states.$id',
      toReachable.contains(id)
          ? FlowCompatibilityClassification.additive
          : FlowCompatibilityClassification.free,
      'State "$id" was added.',
    );
  }
}

void _diffState(
  FlowDocument from,
  FlowDocument to,
  String id,
  FlowState before,
  FlowState after,
  Set<String> toReachable,
  _AddChange add,
) {
  switch ((before, after)) {
    case (
        final ScreenFlowState beforeScreen,
        final ScreenFlowState afterScreen
      ):
      _diffScreenState(
        from,
        to,
        id,
        beforeScreen,
        afterScreen,
        toReachable,
        add,
      );
    case (
        final DecisionFlowState beforeDecision,
        final DecisionFlowState afterDecision
      ):
      _diffDecisionState(
        from,
        to,
        id,
        beforeDecision,
        afterDecision,
        toReachable,
        add,
      );
    case (final SubFlowState beforeSubFlow, final SubFlowState afterSubFlow):
      _diffSubFlowState(
        from,
        to,
        id,
        beforeSubFlow,
        afterSubFlow,
        toReachable,
        add,
      );
    case (final EndFlowState beforeEnd, final EndFlowState afterEnd):
      _diffEndState(id, beforeEnd, afterEnd, add);
    case (
        final UnsupportedFlowState beforeUnsupported,
        final UnsupportedFlowState afterUnsupported
      ):
      if (beforeUnsupported.wireKind != afterUnsupported.wireKind) {
        add(
          'unsupportedStateChanged',
          '\$.states.$id.kind',
          FlowCompatibilityClassification.breaking,
          'Unsupported state "$id" changed wire kind.',
        );
      }
    default:
      add(
        'stateKindChanged',
        '\$.states.$id.kind',
        FlowCompatibilityClassification.breaking,
        'State "$id" changed kind.',
      );
  }
}

void _diffScreenState(
  FlowDocument from,
  FlowDocument to,
  String id,
  ScreenFlowState before,
  ScreenFlowState after,
  Set<String> toReachable,
  _AddChange add,
) {
  if (before.screen != after.screen) {
    add(
      'screenChanged',
      '\$.states.$id.screen',
      FlowCompatibilityClassification.breaking,
      'Screen state "$id" changed artifact id.',
    );
  }
  for (final event in before.on.keys) {
    final oldTransition = before.on[event]!;
    final newTransition = after.on[event];
    if (newTransition == null) {
      add(
        'transitionRemoved',
        '\$.states.$id.on.$event',
        FlowCompatibilityClassification.breaking,
        'Transition "$event" was removed from state "$id".',
      );
      continue;
    }
    _diffTransition(
      from,
      to,
      '\$.states.$id.on.$event',
      oldTransition,
      newTransition,
      toReachable,
      add,
    );
  }
  for (final event in after.on.keys) {
    if (before.on.containsKey(event)) continue;
    add(
      'transitionAdded',
      '\$.states.$id.on.$event',
      FlowCompatibilityClassification.additive,
      'Transition "$event" was added to state "$id".',
    );
  }
}

void _diffTransition(
  FlowDocument from,
  FlowDocument to,
  String path,
  FlowTransition before,
  FlowTransition after,
  Set<String> toReachable,
  _AddChange add,
) {
  if (_transitionFingerprint(before, includeTarget: false) !=
      _transitionFingerprint(after, includeTarget: false)) {
    add(
      'transitionChanged',
      path,
      FlowCompatibilityClassification.breaking,
      'Transition behavior changed.',
    );
  }
  if (before.target == after.target) return;
  add(
    'transitionRetargeted',
    '$path.target',
    _classifyRetarget(from, to, before.target, after.target, toReachable),
    'Transition target changed from "${before.target}" to "${after.target}".',
  );
}

void _diffDecisionState(
  FlowDocument from,
  FlowDocument to,
  String id,
  DecisionFlowState before,
  DecisionFlowState after,
  Set<String> toReachable,
  _AddChange add,
) {
  _diffBranches(
    from,
    to,
    '\$.states.$id.branches',
    before.branches,
    after.branches,
    toReachable,
    add,
  );
  _diffBranchTarget(
    from,
    to,
    '\$.states.$id.default',
    before.defaultBranch,
    after.defaultBranch,
    toReachable,
    add,
  );
}

void _diffSubFlowState(
  FlowDocument from,
  FlowDocument to,
  String id,
  SubFlowState before,
  SubFlowState after,
  Set<String> toReachable,
  _AddChange add,
) {
  if (_subFlowIdentity(before) != _subFlowIdentity(after) ||
      _valueSourcesFingerprint(before.input) !=
          _valueSourcesFingerprint(after.input)) {
    add(
      'subFlowChanged',
      '\$.states.$id',
      FlowCompatibilityClassification.breaking,
      'Sub-flow state "$id" changed identity or input.',
    );
  }
  _diffBranches(
    from,
    to,
    '\$.states.$id.onComplete',
    before.onComplete,
    after.onComplete,
    toReachable,
    add,
  );
  _diffBranchTarget(
    from,
    to,
    '\$.states.$id.default',
    before.defaultBranch,
    after.defaultBranch,
    toReachable,
    add,
  );
  final beforeUnavailable = before.subFlowUnavailable;
  final afterUnavailable = after.subFlowUnavailable;
  switch ((beforeUnavailable, afterUnavailable)) {
    case (null, null):
      return;
    case (null, final FlowBranchTarget _):
      add(
        'subFlowUnavailableAdded',
        '\$.states.$id.subFlowUnavailable',
        FlowCompatibilityClassification.additive,
        'Sub-flow unavailable branch was added to "$id".',
      );
    case (final FlowBranchTarget _, null):
      add(
        'subFlowUnavailableRemoved',
        '\$.states.$id.subFlowUnavailable',
        FlowCompatibilityClassification.breaking,
        'Sub-flow unavailable branch was removed from "$id".',
      );
    case (
        final FlowBranchTarget beforeTarget,
        final FlowBranchTarget afterTarget
      ):
      _diffBranchTarget(
        from,
        to,
        '\$.states.$id.subFlowUnavailable',
        beforeTarget,
        afterTarget,
        toReachable,
        add,
      );
  }
}

void _diffBranches(
  FlowDocument from,
  FlowDocument to,
  String path,
  List<FlowBranch> before,
  List<FlowBranch> after,
  Set<String> toReachable,
  _AddChange add,
) {
  final shared = before.length < after.length ? before.length : after.length;
  for (var index = 0; index < shared; index += 1) {
    final oldBranch = before[index];
    final newBranch = after[index];
    if (_branchPredicateFingerprint(oldBranch.when) !=
            _branchPredicateFingerprint(newBranch.when) ||
        _stateWritesFingerprint(oldBranch.stateWrites) !=
            _stateWritesFingerprint(newBranch.stateWrites)) {
      add(
        'branchChanged',
        '$path[$index]',
        FlowCompatibilityClassification.breaking,
        'Branch $index changed predicate or writes.',
      );
    }
    if (oldBranch.target != newBranch.target) {
      add(
        'branchRetargeted',
        '$path[$index].goto',
        _classifyRetarget(
          from,
          to,
          oldBranch.target,
          newBranch.target,
          toReachable,
        ),
        'Branch $index target changed from "${oldBranch.target}" to '
            '"${newBranch.target}".',
      );
    }
  }
  for (var index = shared; index < before.length; index += 1) {
    add(
      'branchRemoved',
      '$path[$index]',
      FlowCompatibilityClassification.breaking,
      'Branch $index was removed.',
    );
  }
  for (var index = shared; index < after.length; index += 1) {
    add(
      'branchAdded',
      '$path[$index]',
      FlowCompatibilityClassification.breaking,
      'Branch $index was added.',
    );
  }
}

void _diffBranchTarget(
  FlowDocument from,
  FlowDocument to,
  String path,
  FlowBranchTarget before,
  FlowBranchTarget after,
  Set<String> toReachable,
  _AddChange add,
) {
  if (_stateWritesFingerprint(before.stateWrites) !=
      _stateWritesFingerprint(after.stateWrites)) {
    add(
      'branchTargetChanged',
      path,
      FlowCompatibilityClassification.breaking,
      'Branch target writes changed.',
    );
  }
  if (before.target == after.target) return;
  add(
    'branchRetargeted',
    '$path.goto',
    _classifyRetarget(from, to, before.target, after.target, toReachable),
    'Branch target changed from "${before.target}" to "${after.target}".',
  );
}

void _diffEndState(
  String id,
  EndFlowState before,
  EndFlowState after,
  _AddChange add,
) {
  for (final key in before.result.keys) {
    if (!after.result.containsKey(key)) {
      add(
        'terminalResultRemoved',
        '\$.states.$id.result.$key',
        FlowCompatibilityClassification.breaking,
        'Terminal result field "$key" was removed.',
      );
      continue;
    }
    if (_jsonShape(before.result[key]) != _jsonShape(after.result[key])) {
      add(
        'terminalResultChanged',
        '\$.states.$id.result.$key',
        FlowCompatibilityClassification.breaking,
        'Terminal result field "$key" changed type.',
      );
    }
  }
  for (final key in after.result.keys) {
    if (before.result.containsKey(key)) continue;
    add(
      'terminalResultAdded',
      '\$.states.$id.result.$key',
      FlowCompatibilityClassification.additive,
      'Terminal result field "$key" was added.',
    );
  }
}

FlowCompatibilityClassification _classifyRetarget(
  FlowDocument from,
  FlowDocument to,
  String oldTarget,
  String newTarget,
  Set<String> toReachable,
) {
  if (!to.states.containsKey(newTarget) || !toReachable.contains(newTarget)) {
    return FlowCompatibilityClassification.breaking;
  }
  final before = _terminalSignatures(from, oldTarget);
  final after = _terminalSignatures(to, newTarget);
  if (before.isNotEmpty && _setEquals(before, after)) {
    return FlowCompatibilityClassification.forwarding;
  }
  return FlowCompatibilityClassification.breaking;
}

Set<String> _reachableStates(FlowDocument document) {
  if (!document.states.containsKey(document.initial)) return const {};
  final reachable = <String>{};
  final pending = <String>[document.initial];
  while (pending.isNotEmpty) {
    final id = pending.removeLast();
    if (!reachable.add(id)) continue;
    for (final target in _targetsForState(document.states[id])) {
      if (document.states.containsKey(target)) pending.add(target);
    }
  }
  return reachable;
}

Set<String> _terminalSignatures(FlowDocument document, String start) {
  final signatures = <String>{};
  final visited = <String>{};

  void visit(String id) {
    if (!visited.add(id)) return;
    final state = document.states[id];
    switch (state) {
      case EndFlowState(:final result):
        signatures.add(_resultShape(result));
      case null:
        return;
      default:
        _targetsForState(state).forEach(visit);
    }
  }

  visit(start);
  return signatures;
}

Iterable<String> _targetsForState(FlowState? state) sync* {
  switch (state) {
    case ScreenFlowState(:final on):
      for (final transition in on.values) {
        yield transition.target;
      }
    case DecisionFlowState(:final branches, :final defaultBranch):
      for (final branch in branches) {
        yield branch.target;
      }
      yield defaultBranch.target;
    case SubFlowState(
        :final onComplete,
        :final defaultBranch,
        :final subFlowUnavailable,
      ):
      for (final branch in onComplete) {
        yield branch.target;
      }
      yield defaultBranch.target;
      if (subFlowUnavailable != null) yield subFlowUnavailable.target;
    case EndFlowState() || UnsupportedFlowState() || null:
      return;
  }
}

String _canonicalJson(FlowDocument document) {
  return utf8.decode(FlowDocumentCodec.encodeCanonicalJson(document));
}

String _artifactFingerprint(ScreenArtifact artifact) {
  return [
    artifact.path,
    artifact.version,
    artifact.schemaVersion,
    artifact.minClient,
    artifact.contentHash.value,
  ].join('|');
}

String _actionContractFingerprint(FlowActionContract contract) {
  return [
    contract.actionName,
    contract.contractVersion,
    contract.argsSchemaHash.value,
    contract.resultSchemaHash.value,
    contract.minClient,
    contract.idempotent,
  ].join('|');
}

String _outboundFieldFingerprint(FlowOutboundField field) {
  return [
    field.type.wireName,
    _outboundRefFingerprint(field.ref),
  ].join('|');
}

String _outboundRefFingerprint(FlowOutboundRef ref) {
  return switch (ref) {
    StateFlowOutboundRef(:final key, :final path) =>
      'state:$key:${path.join('.')}',
    EventFlowOutboundRef(:final key, :final path) =>
      'event:$key:${path.join('.')}',
  };
}

String _transitionFingerprint(
  FlowTransition transition, {
  required bool includeTarget,
}) {
  return switch (transition) {
    GotoFlowTransition(:final target, :final stateWrites) => [
        'goto',
        if (includeTarget) target,
        _stateWritesFingerprint(stateWrites),
      ].join('|'),
    ActionFlowTransition(
      :final action,
      :final resultPredicate,
      :final target,
      :final stateWrites,
    ) =>
      [
        'action',
        action,
        _actionResultPredicateFingerprint(resultPredicate),
        if (includeTarget) target,
        _stateWritesFingerprint(stateWrites),
      ].join('|'),
  };
}

String _actionResultPredicateFingerprint(FlowActionResultPredicate predicate) {
  return switch (predicate) {
    BoolEqualsActionResultPredicate(:final value) => 'boolEquals:$value',
    ObjectBoolFieldEqualsActionResultPredicate(:final field, :final value) =>
      'objectBoolFieldEquals:$field:$value',
  };
}

String _subFlowIdentity(SubFlowState state) {
  return [
    state.flow,
    state.version,
    state.schemaVersion,
    state.minClient,
    state.contentHash.value,
  ].join('|');
}

String _branchPredicateFingerprint(FlowBranchPredicate predicate) {
  final entries = [
    for (final entry in predicate.fields.entries)
      '${entry.key}:${_predicateConditionFingerprint(entry.value)}',
  ]..sort();
  return entries.join('|');
}

String _predicateConditionFingerprint(FlowPredicateCondition condition) {
  return switch (condition) {
    EqualsFlowPredicateCondition(:final value) =>
      'eq:${_valueSourceFingerprint(value)}',
    NotEqualsFlowPredicateCondition(:final value) =>
      'ne:${_valueSourceFingerprint(value)}',
    InFlowPredicateCondition(:final values) =>
      'in:${values.map(_valueSourceFingerprint).join(',')}',
    GreaterThanFlowPredicateCondition(:final value) =>
      'gt:${_valueSourceFingerprint(value)}',
    GreaterThanOrEqualsFlowPredicateCondition(:final value) =>
      'gte:${_valueSourceFingerprint(value)}',
    LessThanFlowPredicateCondition(:final value) =>
      'lt:${_valueSourceFingerprint(value)}',
    LessThanOrEqualsFlowPredicateCondition(:final value) =>
      'lte:${_valueSourceFingerprint(value)}',
    ExistsFlowPredicateCondition(:final exists) => 'exists:$exists',
  };
}

String _stateWritesFingerprint(Map<String, FlowStateWrite> stateWrites) {
  final entries = [
    for (final entry in stateWrites.entries)
      [
        entry.key,
        entry.value.type.wireName,
        _valueSourceFingerprint(entry.value.value),
      ].join(':'),
  ]..sort();
  return entries.join('|');
}

String _valueSourcesFingerprint(Map<String, FlowValueSource> sources) {
  final entries = [
    for (final entry in sources.entries)
      '${entry.key}:${_valueSourceFingerprint(entry.value)}',
  ]..sort();
  return entries.join('|');
}

String _valueSourceFingerprint(FlowValueSource source) {
  return switch (source) {
    LiteralFlowValueSource(:final type, :final value) =>
      'literal:${type.wireName}:${_jsonShape(value)}:$value',
    StateFlowValueSource(:final key, :final path) =>
      'state:$key:${path.join('.')}',
    EventFlowValueSource(:final key, :final path) =>
      'event:$key:${path.join('.')}',
    ActionResultFlowValueSource(:final key, :final path) =>
      'actionResult:$key:${path.join('.')}',
    SubFlowResultFlowValueSource(:final key, :final path) =>
      'subFlowResult:$key:${path.join('.')}',
  };
}

String _resultShape(Map<String, Object?> result) {
  final entries = [
    for (final entry in result.entries)
      '${entry.key}:${_jsonShape(entry.value)}',
  ]..sort();
  return entries.join('|');
}

String _jsonShape(Object? value) {
  return switch (value) {
    null => 'null',
    bool() => 'bool',
    int() => 'int',
    double() => 'double',
    String() => 'string',
    List<Object?>() => 'list(${value.map(_jsonShape).join(',')})',
    Map<String, Object?>() => 'map(${_resultShape(value)})',
    _ => value.runtimeType.toString(),
  };
}

FlowCompatibilityClassification _maxClassification(
  Iterable<FlowCompatibilityClassification> classifications,
) {
  var result = FlowCompatibilityClassification.free;
  for (final classification in classifications) {
    if (classification.index > result.index) result = classification;
  }
  return result;
}

bool _setEquals(Set<String> left, Set<String> right) {
  if (left.length != right.length) return false;
  for (final value in left) {
    if (!right.contains(value)) return false;
  }
  return true;
}
