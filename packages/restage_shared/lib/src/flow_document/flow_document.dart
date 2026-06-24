// Flow document DTOs intentionally mirror wire fields; exhaustive per-field
// comments would duplicate the canonical schema names.
// ignore_for_file: public_member_api_docs

import 'package:restage_shared/src/flow_document/flow_action_schema.dart';
import 'package:restage_shared/src/flow_document/flow_document_hash.dart';

enum FlowStateKind {
  screen('screen'),
  decision('decision'),
  subFlow('subFlow'),
  end('end');

  const FlowStateKind(this.wireName);

  final String wireName;
}

enum FlowDataType {
  bool('bool'),
  int('int'),
  string('string');

  const FlowDataType(this.wireName);

  final String wireName;
}

enum FlowStateClassification {
  screen('screen'),
  internal('internal'),
  persistedDevice('persistedDevice'),
  persistedAccount('persistedAccount'),
  exportable('exportable');

  const FlowStateClassification(this.wireName);

  final String wireName;
}

final class FlowDocument {
  const FlowDocument({
    required this.flow,
    required this.version,
    required this.schemaVersion,
    required this.minClient,
    required this.initial,
    required this.screenArtifacts,
    required this.states,
    this.actions = const {},
    this.flowState = const {},
    this.outbound = const FlowOutboundDeclarations(),
    this.legacyTerminalResultPassthrough = false,
    this.unsupportedFeatures = const {},
  });

  final String flow;
  final int version;
  final int schemaVersion;
  final int minClient;
  final String initial;
  final Map<String, FlowActionContract> actions;
  final Map<String, FlowStateDeclaration> flowState;
  final FlowOutboundDeclarations outbound;
  final bool legacyTerminalResultPassthrough;
  final Map<String, ScreenArtifact> screenArtifacts;
  final Map<String, FlowState> states;
  final Set<String> unsupportedFeatures;
}

final class FlowStateDeclaration {
  const FlowStateDeclaration({
    required this.type,
    required this.classification,
    this.defaultValue,
  });

  final FlowDataType type;
  final FlowStateClassification classification;
  final Object? defaultValue;
}

final class FlowOutboundDeclarations {
  const FlowOutboundDeclarations({
    this.actionArgs = const {},
    this.terminalResult = const FlowOutboundPayloadDeclaration(),
    this.lifecycle = const FlowOutboundPayloadDeclaration(),
    this.surveyAnswers = const FlowOutboundPayloadDeclaration(),
    this.subFlowResult = const FlowOutboundPayloadDeclaration(),
    this.customEvents = const {},
  });

  final Map<String, FlowOutboundPayloadDeclaration> actionArgs;
  final FlowOutboundPayloadDeclaration terminalResult;
  final FlowOutboundPayloadDeclaration lifecycle;
  final FlowOutboundPayloadDeclaration surveyAnswers;
  final FlowOutboundPayloadDeclaration subFlowResult;
  final Map<String, FlowOutboundPayloadDeclaration> customEvents;

  bool get isEmpty {
    return actionArgs.isEmpty &&
        terminalResult.isEmpty &&
        lifecycle.isEmpty &&
        surveyAnswers.isEmpty &&
        subFlowResult.isEmpty &&
        customEvents.isEmpty;
  }
}

final class FlowOutboundPayloadDeclaration {
  const FlowOutboundPayloadDeclaration({this.fields = const {}});

  final Map<String, FlowOutboundField> fields;

  bool get isEmpty => fields.isEmpty;
}

final class FlowOutboundField {
  const FlowOutboundField({
    required this.type,
    required this.ref,
  });

  final FlowDataType type;
  final FlowOutboundRef ref;
}

sealed class FlowOutboundRef {
  const FlowOutboundRef({required this.key, this.path = const []});

  final String key;
  final List<String> path;
}

final class StateFlowOutboundRef extends FlowOutboundRef {
  const StateFlowOutboundRef({
    required super.key,
    super.path = const [],
  });
}

final class EventFlowOutboundRef extends FlowOutboundRef {
  const EventFlowOutboundRef({
    required super.key,
    super.path = const [],
  });
}

final class FlowActionContract {
  const FlowActionContract({
    required this.actionName,
    required this.contractVersion,
    required this.argsSchema,
    required this.resultSchema,
    required this.minClient,
    required this.idempotent,
  });

  final String actionName;
  final int contractVersion;
  final FlowActionSchema argsSchema;
  final FlowActionSchema resultSchema;
  final int minClient;
  final bool idempotent;

  FlowContentHash get argsSchemaHash {
    return FlowActionSchema.hashFor(contractKind: 'args', schema: argsSchema);
  }

  FlowContentHash get resultSchemaHash {
    return FlowActionSchema.hashFor(
      contractKind: 'result',
      schema: resultSchema,
    );
  }
}

final class ScreenArtifact {
  const ScreenArtifact({
    required this.path,
    required this.version,
    required this.schemaVersion,
    required this.minClient,
    required this.contentHash,
  });

  final String path;
  final int version;
  final int schemaVersion;
  final int minClient;
  final FlowContentHash contentHash;
}

sealed class FlowState {
  const FlowState();

  FlowStateKind get kind;
}

final class ScreenFlowState extends FlowState {
  const ScreenFlowState({
    required this.screen,
    required this.on,
  });

  final String screen;
  final Map<String, FlowTransition> on;

  @override
  FlowStateKind get kind => FlowStateKind.screen;
}

final class EndFlowState extends FlowState {
  const EndFlowState({required this.result});

  final Map<String, Object?> result;

  @override
  FlowStateKind get kind => FlowStateKind.end;
}

final class DecisionFlowState extends FlowState {
  const DecisionFlowState({
    required this.branches,
    required this.defaultBranch,
  });

  final List<FlowBranch> branches;
  final FlowBranchTarget defaultBranch;

  @override
  FlowStateKind get kind => FlowStateKind.decision;
}

final class SubFlowState extends FlowState {
  const SubFlowState({
    required this.flow,
    required this.version,
    required this.schemaVersion,
    required this.minClient,
    required this.contentHash,
    required this.input,
    required this.onComplete,
    required this.defaultBranch,
    this.subFlowUnavailable,
  });

  final String flow;
  final int version;
  final int schemaVersion;
  final int minClient;
  final FlowContentHash contentHash;
  final Map<String, FlowValueSource> input;
  final List<FlowBranch> onComplete;
  final FlowBranchTarget defaultBranch;
  final FlowBranchTarget? subFlowUnavailable;

  @override
  FlowStateKind get kind => FlowStateKind.subFlow;
}

final class UnsupportedFlowState extends FlowState {
  const UnsupportedFlowState({
    required this.wireKind,
    required this.raw,
  });

  final String wireKind;
  final Map<String, Object?> raw;

  /// Throws by design: an unrecognized wire kind has no valid [FlowStateKind].
  /// Consumers must pattern-match the sealed [FlowState] type and handle
  /// [UnsupportedFlowState] explicitly rather than reading [kind] generically.
  @override
  FlowStateKind get kind {
    throw UnsupportedError(
      'Unsupported flow state kind "$wireKind" has no FlowStateKind.',
    );
  }
}

final class FlowBranch {
  const FlowBranch({
    required this.when,
    required this.target,
    this.stateWrites = const {},
  });

  final FlowBranchPredicate when;
  final String target;
  final Map<String, FlowStateWrite> stateWrites;
}

final class FlowBranchTarget {
  const FlowBranchTarget({
    required this.target,
    this.stateWrites = const {},
  });

  final String target;
  final Map<String, FlowStateWrite> stateWrites;
}

final class FlowBranchPredicate {
  const FlowBranchPredicate({required this.fields});

  final Map<String, FlowPredicateCondition> fields;
}

sealed class FlowPredicateCondition {
  const FlowPredicateCondition();

  String get operator;
}

final class EqualsFlowPredicateCondition extends FlowPredicateCondition {
  const EqualsFlowPredicateCondition({required this.value});

  final FlowValueSource value;

  @override
  String get operator => 'eq';
}

final class NotEqualsFlowPredicateCondition extends FlowPredicateCondition {
  const NotEqualsFlowPredicateCondition({required this.value});

  final FlowValueSource value;

  @override
  String get operator => 'ne';
}

final class InFlowPredicateCondition extends FlowPredicateCondition {
  const InFlowPredicateCondition({required this.values});

  final List<FlowValueSource> values;

  @override
  String get operator => 'in';
}

final class GreaterThanFlowPredicateCondition extends FlowPredicateCondition {
  const GreaterThanFlowPredicateCondition({required this.value});

  final FlowValueSource value;

  @override
  String get operator => 'gt';
}

final class GreaterThanOrEqualsFlowPredicateCondition
    extends FlowPredicateCondition {
  const GreaterThanOrEqualsFlowPredicateCondition({required this.value});

  final FlowValueSource value;

  @override
  String get operator => 'gte';
}

final class LessThanFlowPredicateCondition extends FlowPredicateCondition {
  const LessThanFlowPredicateCondition({required this.value});

  final FlowValueSource value;

  @override
  String get operator => 'lt';
}

final class LessThanOrEqualsFlowPredicateCondition
    extends FlowPredicateCondition {
  const LessThanOrEqualsFlowPredicateCondition({required this.value});

  final FlowValueSource value;

  @override
  String get operator => 'lte';
}

final class ExistsFlowPredicateCondition extends FlowPredicateCondition {
  const ExistsFlowPredicateCondition({required this.exists});

  final bool exists;

  @override
  String get operator => 'exists';
}

final class FlowStateWrite {
  const FlowStateWrite({
    required this.type,
    required this.value,
  });

  final FlowDataType type;
  final FlowValueSource value;
}

sealed class FlowValueSource {
  const FlowValueSource();
}

final class LiteralFlowValueSource extends FlowValueSource {
  const LiteralFlowValueSource({
    required this.type,
    required this.value,
  });

  final FlowDataType type;
  final Object value;
}

sealed class RefFlowValueSource extends FlowValueSource {
  const RefFlowValueSource({required this.key, this.path = const []});

  final String key;
  final List<String> path;
}

final class StateFlowValueSource extends RefFlowValueSource {
  const StateFlowValueSource({
    required super.key,
    super.path = const [],
  });
}

final class EventFlowValueSource extends RefFlowValueSource {
  const EventFlowValueSource({
    required super.key,
    super.path = const [],
  });
}

final class ActionResultFlowValueSource extends RefFlowValueSource {
  const ActionResultFlowValueSource({
    required super.key,
    super.path = const [],
  });
}

final class SubFlowResultFlowValueSource extends RefFlowValueSource {
  const SubFlowResultFlowValueSource({
    required super.key,
    super.path = const [],
  });
}

sealed class FlowTransition {
  const FlowTransition();

  const factory FlowTransition.goto(String target) = GotoFlowTransition;

  String get type;
  String get target;
}

sealed class FlowActionResultPredicate {
  const FlowActionResultPredicate();

  String get kind;
}

final class BoolEqualsActionResultPredicate extends FlowActionResultPredicate {
  const BoolEqualsActionResultPredicate({required this.value});

  final bool value;

  @override
  String get kind => 'boolEquals';
}

final class ObjectBoolFieldEqualsActionResultPredicate
    extends FlowActionResultPredicate {
  const ObjectBoolFieldEqualsActionResultPredicate({
    required this.field,
    required this.value,
  });

  final String field;
  final bool value;

  @override
  String get kind => 'objectBoolFieldEquals';
}

final class GotoFlowTransition extends FlowTransition {
  const GotoFlowTransition(this.target, {this.stateWrites = const {}});

  @override
  String get type => 'goto';

  @override
  final String target;

  final Map<String, FlowStateWrite> stateWrites;
}

final class ActionFlowTransition extends FlowTransition {
  const ActionFlowTransition({
    required this.action,
    required this.resultPredicate,
    required this.target,
    this.stateWrites = const {},
  });

  @override
  String get type => 'action';

  final String action;
  final FlowActionResultPredicate resultPredicate;
  final Map<String, FlowStateWrite> stateWrites;

  @override
  final String target;
}
