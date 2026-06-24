// Validation issue DTOs intentionally mirror wire fields; exhaustive per-field
// comments would duplicate the code/path/message names.
// ignore_for_file: public_member_api_docs

import 'package:restage_shared/src/flow_document/flow_document.dart';

abstract final class FlowDocumentValidation {
  static List<FlowDocumentValidationIssue> validate(FlowDocument document) {
    final issues = <FlowDocumentValidationIssue>[];

    _validateIdentifier(issues, r'$.flow', document.flow);
    _validateIdentifier(issues, r'$.initial', document.initial);
    _validateIntValue(issues, r'$.version', document.version);
    _validateIntValue(issues, r'$.schemaVersion', document.schemaVersion);
    _validateIntValue(issues, r'$.minClient', document.minClient);

    for (final feature in document.unsupportedFeatures) {
      issues.add(
        FlowDocumentValidationIssue(
          code: 'unsupportedFeature',
          path: r'$.features',
          message: 'Unsupported feature flag: $feature.',
        ),
      );
    }

    if (document.legacyTerminalResultPassthrough &&
        (document.flowState.isNotEmpty || !document.outbound.isEmpty)) {
      issues.add(
        const FlowDocumentValidationIssue(
          code: 'invalidLegacyTerminalResultPassthrough',
          path: r'$',
          message: 'Legacy terminal result passthrough requires both '
              'flowState and outbound declarations to be empty.',
        ),
      );
    }

    for (final entry in document.flowState.entries) {
      final id = entry.key;
      final declaration = entry.value;
      _validateIdentifier(issues, '\$.flowState.$id', id);
      if (declaration.defaultValue != null) {
        _validateJsonValue(
          issues,
          '\$.flowState.$id.default',
          declaration.defaultValue,
        );
        _validateDefaultValueType(
          issues,
          '\$.flowState.$id.default',
          declaration.type,
          declaration.defaultValue,
        );
      }
    }

    _validateOutboundDeclarations(document, issues);

    final actionNames = <String>{};
    for (final entry in document.actions.entries) {
      final id = entry.key;
      final contract = entry.value;
      _validateIdentifier(issues, '\$.actions.$id', id);
      _validateIdentifier(
        issues,
        '\$.actions.$id.actionName',
        contract.actionName,
      );
      _validateIntValue(
        issues,
        '\$.actions.$id.contractVersion',
        contract.contractVersion,
      );
      _validateIntValue(
        issues,
        '\$.actions.$id.minClient',
        contract.minClient,
      );
      if (contract.actionName != id) {
        issues.add(
          FlowDocumentValidationIssue(
            code: 'actionNameMismatch',
            path: '\$.actions.$id.actionName',
            message: 'Action contract name ${contract.actionName} must match '
                'table key $id.',
          ),
        );
      }
      if (!actionNames.add(contract.actionName)) {
        issues.add(
          FlowDocumentValidationIssue(
            code: 'duplicateActionName',
            path: '\$.actions.$id.actionName',
            message: 'Action name ${contract.actionName} is declared more '
                'than once.',
          ),
        );
      }
    }

    if (!document.states.containsKey(document.initial)) {
      issues.add(
        FlowDocumentValidationIssue(
          code: 'missingInitialState',
          path: r'$.initial',
          message: 'Initial state ${document.initial} does not exist.',
        ),
      );
    }

    for (final entry in document.screenArtifacts.entries) {
      final id = entry.key;
      final artifact = entry.value;
      _validateIdentifier(issues, '\$.screenArtifacts.$id', id);
      _validatePath(
        issues,
        '\$.screenArtifacts.$id.path',
        artifact.path,
      );
      _validateIntValue(
        issues,
        '\$.screenArtifacts.$id.version',
        artifact.version,
      );
      _validateIntValue(
        issues,
        '\$.screenArtifacts.$id.schemaVersion',
        artifact.schemaVersion,
      );
      _validateIntValue(
        issues,
        '\$.screenArtifacts.$id.minClient',
        artifact.minClient,
      );
    }

    var hasEndState = false;
    for (final entry in document.states.entries) {
      final id = entry.key;
      final state = entry.value;
      _validateIdentifier(issues, '\$.states.$id', id);

      switch (state) {
        case ScreenFlowState(:final screen, :final on):
          _validateIdentifier(issues, '\$.states.$id.screen', screen);
          if (!document.screenArtifacts.containsKey(screen)) {
            issues.add(
              FlowDocumentValidationIssue(
                code: 'missingScreenArtifact',
                path: '\$.states.$id.screen',
                message: 'Screen artifact $screen does not exist.',
              ),
            );
          }
          for (final event in on.entries) {
            _validateIdentifier(
              issues,
              '\$.states.$id.on.${event.key}',
              event.key,
            );
            switch (event.value) {
              case GotoFlowTransition(:final target, :final stateWrites):
                _validateTransitionTarget(
                  issues,
                  document,
                  '\$.states.$id.on.${event.key}.target',
                  target,
                );
                _validateStateWrites(
                  issues,
                  document,
                  '\$.states.$id.on.${event.key}.set',
                  stateWrites,
                  _eventTransitionWriteSources,
                );
              case ActionFlowTransition(
                  :final action,
                  :final resultPredicate,
                  :final target,
                  :final stateWrites,
                ):
                _validateIdentifier(
                  issues,
                  '\$.states.$id.on.${event.key}.action',
                  action,
                );
                _validateActionResultPredicate(
                  issues,
                  '\$.states.$id.on.${event.key}.resultPredicate',
                  resultPredicate,
                );
                if (!document.actions.containsKey(action)) {
                  issues.add(
                    FlowDocumentValidationIssue(
                      code: 'missingAction',
                      path: '\$.states.$id.on.${event.key}.action',
                      message: 'Action $action does not exist.',
                    ),
                  );
                }
                _validateTransitionTarget(
                  issues,
                  document,
                  '\$.states.$id.on.${event.key}.target',
                  target,
                );
                _validateStateWrites(
                  issues,
                  document,
                  '\$.states.$id.on.${event.key}.set',
                  stateWrites,
                  _actionTransitionWriteSources,
                );
            }
          }
        case DecisionFlowState(:final branches, :final defaultBranch):
          _validateBranches(
            issues,
            document,
            '\$.states.$id.branches',
            branches,
            predicateSources: _stateScopedValueSources,
            writeSources: _stateScopedValueSources,
          );
          _validateDecisionPredicateFields(
            issues,
            document,
            '\$.states.$id.branches',
            branches,
          );
          _validateBranchTarget(
            issues,
            document,
            '\$.states.$id.default',
            defaultBranch,
            writeSources: _stateScopedValueSources,
          );
        case SubFlowState(
            :final flow,
            :final version,
            :final schemaVersion,
            :final minClient,
            :final input,
            :final onComplete,
            :final defaultBranch,
            :final subFlowUnavailable,
          ):
          _validateIdentifier(issues, '\$.states.$id.flow', flow);
          if (flow == document.flow) {
            issues.add(
              FlowDocumentValidationIssue(
                code: 'subFlowCycle',
                path: '\$.states.$id.flow',
                message: 'Sub-flow "$flow" directly references its parent.',
              ),
            );
          }
          _validateIntValue(issues, '\$.states.$id.version', version);
          _validateIntValue(
            issues,
            '\$.states.$id.schemaVersion',
            schemaVersion,
          );
          _validateIntValue(issues, '\$.states.$id.minClient', minClient);
          _validateValueSourceMap(
            issues,
            document,
            '\$.states.$id.input',
            input,
            _stateScopedValueSources,
          );
          _validateBranches(
            issues,
            document,
            '\$.states.$id.onComplete',
            onComplete,
            predicateSources: _subFlowResultValueSources,
            writeSources: _subFlowResultValueSources,
          );
          _validateBranchTarget(
            issues,
            document,
            '\$.states.$id.default',
            defaultBranch,
            writeSources: _subFlowResultValueSources,
          );
          if (subFlowUnavailable != null) {
            _validateBranchTarget(
              issues,
              document,
              '\$.states.$id.subFlowUnavailable',
              subFlowUnavailable,
              writeSources: _stateScopedValueSources,
            );
          }
        case EndFlowState(:final result):
          hasEndState = true;
          _validateJsonValue(issues, '\$.states.$id.result', result);
        case UnsupportedFlowState(:final wireKind):
          issues.add(
            FlowDocumentValidationIssue(
              code: 'unsupportedStateKind',
              path: '\$.states.$id.kind',
              message: 'Unsupported flow state kind: $wireKind.',
            ),
          );
      }
    }

    if (!hasEndState) {
      issues.add(
        const FlowDocumentValidationIssue(
          code: 'missingEndState',
          path: r'$.states',
          message: 'At least one end state is required.',
        ),
      );
    }

    _validateReachability(document, issues);
    _validateScreenlessCycles(document, issues);

    return issues;
  }

  static void checkValid(FlowDocument document) {
    final issues = validate(document);
    if (issues.isNotEmpty) {
      throw ArgumentError.value(
        document,
        'document',
        issues.map((issue) => issue.toString()).join('\n'),
      );
    }
  }
}

final class FlowDocumentValidationIssue {
  const FlowDocumentValidationIssue({
    required this.code,
    required this.path,
    required this.message,
  });

  final String code;
  final String path;
  final String message;

  @override
  String toString() => '$code at $path: $message';
}

final RegExp _identifierPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$');
final RegExp _outboundFieldPattern =
    RegExp(r'^[A-Za-z][A-Za-z0-9_-]*(\.[A-Za-z][A-Za-z0-9_-]*)*$');
final RegExp _pathPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_./-]*$');

enum _FlowValueSourceKind {
  literal,
  state,
  event,
  actionResult,
  subFlowResult,
}

const Set<_FlowValueSourceKind> _stateScopedValueSources = {
  _FlowValueSourceKind.literal,
  _FlowValueSourceKind.state,
};
const Set<_FlowValueSourceKind> _eventTransitionWriteSources = {
  _FlowValueSourceKind.literal,
  _FlowValueSourceKind.state,
  _FlowValueSourceKind.event,
};
const Set<_FlowValueSourceKind> _actionTransitionWriteSources = {
  _FlowValueSourceKind.literal,
  _FlowValueSourceKind.state,
  _FlowValueSourceKind.event,
  _FlowValueSourceKind.actionResult,
};
const Set<_FlowValueSourceKind> _subFlowResultValueSources = {
  _FlowValueSourceKind.literal,
  _FlowValueSourceKind.state,
  _FlowValueSourceKind.subFlowResult,
};

void _validateDefaultValueType(
  List<FlowDocumentValidationIssue> issues,
  String path,
  FlowDataType type,
  Object? value,
) {
  final valid = switch (type) {
    FlowDataType.bool => value is bool,
    FlowDataType.int => value is int,
    FlowDataType.string => value is String,
  };
  if (valid) return;
  issues.add(
    FlowDocumentValidationIssue(
      code: 'invalidFlowStateDefault',
      path: path,
      message: 'Default value must match declared type ${type.wireName}.',
    ),
  );
}

void _validateOutboundDeclarations(
  FlowDocument document,
  List<FlowDocumentValidationIssue> issues,
) {
  void validatePayload(
    String fieldsPath,
    FlowOutboundPayloadDeclaration payload,
  ) {
    for (final entry in payload.fields.entries) {
      final field = entry.key;
      if (!_outboundFieldPattern.hasMatch(field)) {
        issues.add(
          FlowDocumentValidationIssue(
            code: 'invalidIdentifier',
            path: '$fieldsPath.$field',
            message: 'Expected outbound field path, got "$field".',
          ),
        );
      }
      _validateOutboundRef(
        document,
        issues,
        '$fieldsPath.$field.ref',
        entry.value.type,
        entry.value.ref,
      );
    }
  }

  for (final entry in document.outbound.actionArgs.entries) {
    _validateIdentifier(
      issues,
      '\$.outbound.actionArgs.${entry.key}',
      entry.key,
    );
    validatePayload('\$.outbound.actionArgs.${entry.key}', entry.value);
  }
  validatePayload(
    r'$.outbound.terminalResult.fields',
    document.outbound.terminalResult,
  );
  validatePayload(r'$.outbound.lifecycle.fields', document.outbound.lifecycle);
  validatePayload(
    r'$.outbound.surveyAnswers.fields',
    document.outbound.surveyAnswers,
  );
  validatePayload(
    r'$.outbound.subFlowResult.fields',
    document.outbound.subFlowResult,
  );
  for (final entry in document.outbound.customEvents.entries) {
    _validateIdentifier(
      issues,
      '\$.outbound.customEvents.${entry.key}',
      entry.key,
    );
    validatePayload(
      '\$.outbound.customEvents.${entry.key}.fields',
      entry.value,
    );
  }
}

void _validateOutboundRef(
  FlowDocument document,
  List<FlowDocumentValidationIssue> issues,
  String path,
  FlowDataType outboundType,
  FlowOutboundRef ref,
) {
  _validateIdentifier(issues, '$path.key', ref.key);
  for (var index = 0; index < ref.path.length; index += 1) {
    _validateIdentifier(issues, '$path.path[$index]', ref.path[index]);
  }
  switch (ref) {
    case StateFlowOutboundRef(:final key):
      final declaration = document.flowState[key];
      if (declaration == null) {
        issues.add(
          FlowDocumentValidationIssue(
            code: 'missingFlowStateDeclaration',
            path: path,
            message: 'Outbound state ref "$key" has no flowState declaration.',
          ),
        );
      } else if (declaration.type != outboundType) {
        issues.add(
          FlowDocumentValidationIssue(
            code: 'outboundTypeMismatch',
            path: path,
            message: 'Outbound ref "$key" declares ${outboundType.wireName} '
                'but flowState declares ${declaration.type.wireName}.',
          ),
        );
      }
    case EventFlowOutboundRef():
      return;
  }
}

void _validateIdentifier(
  List<FlowDocumentValidationIssue> issues,
  String path,
  String value,
) {
  if (!_identifierPattern.hasMatch(value)) {
    issues.add(
      FlowDocumentValidationIssue(
        code: 'invalidIdentifier',
        path: path,
        message: 'Expected ASCII identifier, got "$value".',
      ),
    );
  }
}

void _validatePath(
  List<FlowDocumentValidationIssue> issues,
  String path,
  String value,
) {
  if (!_pathPattern.hasMatch(value) ||
      value.contains('..') ||
      value.startsWith('/') ||
      value.endsWith('/')) {
    issues.add(
      FlowDocumentValidationIssue(
        code: 'invalidPath',
        path: path,
        message: 'Expected ASCII artifact path, got "$value".',
      ),
    );
  }
}

void _validateIntValue(
  List<FlowDocumentValidationIssue> issues,
  String path,
  int value,
) {
  if (value < 0) {
    issues.add(
      FlowDocumentValidationIssue(
        code: 'invalidNumber',
        path: path,
        message: 'Expected a non-negative integer, got $value.',
      ),
    );
  }
}

void _validateJsonValue(
  List<FlowDocumentValidationIssue> issues,
  String path,
  Object? value,
) {
  switch (value) {
    case null:
      issues.add(
        FlowDocumentValidationIssue(
          code: 'invalidJsonValue',
          path: path,
          message: 'Null JSON values are not supported in flow documents.',
        ),
      );
    case String() || bool() || int():
      return;
    case double():
      issues.add(
        FlowDocumentValidationIssue(
          code: 'invalidNumber',
          path: path,
          message: 'Doubles and non-finite numbers are not supported.',
        ),
      );
    case List<Object?>():
      for (var index = 0; index < value.length; index += 1) {
        _validateJsonValue(issues, '$path[$index]', value[index]);
      }
    case Map<String, Object?>():
      for (final entry in value.entries) {
        _validateJsonValue(issues, '$path.${entry.key}', entry.value);
      }
    case Map():
      issues.add(
        FlowDocumentValidationIssue(
          code: 'invalidJsonValue',
          path: path,
          message: 'JSON object keys must be strings.',
        ),
      );
    default:
      issues.add(
        FlowDocumentValidationIssue(
          code: 'invalidJsonValue',
          path: path,
          message: 'Unsupported JSON value type ${value.runtimeType}.',
        ),
      );
  }
}

void _validateActionResultPredicate(
  List<FlowDocumentValidationIssue> issues,
  String path,
  FlowActionResultPredicate predicate,
) {
  switch (predicate) {
    case BoolEqualsActionResultPredicate():
      return;
    case ObjectBoolFieldEqualsActionResultPredicate(:final field):
      _validateIdentifier(issues, '$path.field', field);
  }
}

void _validateBranches(
  List<FlowDocumentValidationIssue> issues,
  FlowDocument document,
  String path,
  List<FlowBranch> branches, {
  required Set<_FlowValueSourceKind> predicateSources,
  required Set<_FlowValueSourceKind> writeSources,
}) {
  for (var index = 0; index < branches.length; index += 1) {
    final branch = branches[index];
    _validateBranchPredicate(
      issues,
      document,
      '$path[$index].when',
      branch.when,
      predicateSources,
    );
    _validateTransitionTarget(
      issues,
      document,
      '$path[$index].goto',
      branch.target,
    );
    _validateStateWrites(
      issues,
      document,
      '$path[$index].set',
      branch.stateWrites,
      writeSources,
    );
  }
}

void _validateBranchTarget(
  List<FlowDocumentValidationIssue> issues,
  FlowDocument document,
  String path,
  FlowBranchTarget branch, {
  required Set<_FlowValueSourceKind> writeSources,
}) {
  _validateTransitionTarget(issues, document, '$path.goto', branch.target);
  _validateStateWrites(
    issues,
    document,
    '$path.set',
    branch.stateWrites,
    writeSources,
  );
}

void _validateBranchPredicate(
  List<FlowDocumentValidationIssue> issues,
  FlowDocument document,
  String path,
  FlowBranchPredicate predicate,
  Set<_FlowValueSourceKind> allowedSources,
) {
  for (final entry in predicate.fields.entries) {
    _validateIdentifier(issues, '$path.${entry.key}', entry.key);
    _validatePredicateCondition(
      issues,
      document,
      '$path.${entry.key}',
      entry.value,
      allowedSources,
    );
  }
}

void _validateDecisionPredicateFields(
  List<FlowDocumentValidationIssue> issues,
  FlowDocument document,
  String path,
  List<FlowBranch> branches,
) {
  for (var branchIndex = 0; branchIndex < branches.length; branchIndex += 1) {
    final predicate = branches[branchIndex].when;
    for (final entry in predicate.fields.entries) {
      final fieldPath = '$path[$branchIndex].when.${entry.key}';
      final declaration = document.flowState[entry.key];
      if (declaration == null) {
        issues.add(
          FlowDocumentValidationIssue(
            code: 'missingFlowStateDeclaration',
            path: fieldPath,
            message: 'Decision predicate field "${entry.key}" has no '
                'flowState declaration.',
          ),
        );
        continue;
      }
      _validateDecisionPredicateType(
        issues,
        document,
        fieldPath,
        declaration.type,
        entry.value,
      );
    }
  }
}

void _validateDecisionPredicateType(
  List<FlowDocumentValidationIssue> issues,
  FlowDocument document,
  String path,
  FlowDataType fieldType,
  FlowPredicateCondition condition,
) {
  switch (condition) {
    case EqualsFlowPredicateCondition(:final value):
    case NotEqualsFlowPredicateCondition(:final value):
      _validateComparableSourceType(
        issues,
        document,
        '$path.${condition.operator}',
        fieldType,
        value,
      );
    case InFlowPredicateCondition(:final values):
      if (values.isEmpty) {
        issues.add(
          FlowDocumentValidationIssue(
            code: 'emptyPredicateValues',
            path: '$path.in',
            message: 'Membership predicates require at least one value.',
          ),
        );
      }
      for (var index = 0; index < values.length; index += 1) {
        _validateComparableSourceType(
          issues,
          document,
          '$path.in[$index]',
          fieldType,
          values[index],
        );
      }
    case GreaterThanFlowPredicateCondition(:final value):
    case GreaterThanOrEqualsFlowPredicateCondition(:final value):
    case LessThanFlowPredicateCondition(:final value):
    case LessThanOrEqualsFlowPredicateCondition(:final value):
      if (fieldType != FlowDataType.int) {
        issues.add(
          FlowDocumentValidationIssue(
            code: 'predicateTypeMismatch',
            path: path,
            message: 'Numeric predicate requires an int flowState field.',
          ),
        );
      }
      _validateComparableSourceType(
        issues,
        document,
        '$path.${condition.operator}',
        FlowDataType.int,
        value,
      );
    case ExistsFlowPredicateCondition():
      return;
  }
}

void _validateComparableSourceType(
  List<FlowDocumentValidationIssue> issues,
  FlowDocument document,
  String path,
  FlowDataType expected,
  FlowValueSource source,
) {
  final actual = _valueSourceType(document, source);
  if (actual == null || actual == expected) return;
  issues.add(
    FlowDocumentValidationIssue(
      code: 'predicateTypeMismatch',
      path: path,
      message: 'Predicate expects ${expected.wireName} but source declares '
          '${actual.wireName}.',
    ),
  );
}

void _validatePredicateCondition(
  List<FlowDocumentValidationIssue> issues,
  FlowDocument document,
  String path,
  FlowPredicateCondition condition,
  Set<_FlowValueSourceKind> allowedSources,
) {
  switch (condition) {
    case EqualsFlowPredicateCondition(:final value):
    case NotEqualsFlowPredicateCondition(:final value):
    case GreaterThanFlowPredicateCondition(:final value):
    case GreaterThanOrEqualsFlowPredicateCondition(:final value):
    case LessThanFlowPredicateCondition(:final value):
    case LessThanOrEqualsFlowPredicateCondition(:final value):
      _validateValueSource(
        issues,
        document,
        '$path.${condition.operator}',
        value,
        allowedSources,
      );
    case InFlowPredicateCondition(:final values):
      for (var index = 0; index < values.length; index += 1) {
        _validateValueSource(
          issues,
          document,
          '$path.${condition.operator}[$index]',
          values[index],
          allowedSources,
        );
      }
    case ExistsFlowPredicateCondition():
      return;
  }
}

void _validateStateWrites(
  List<FlowDocumentValidationIssue> issues,
  FlowDocument document,
  String path,
  Map<String, FlowStateWrite> stateWrites,
  Set<_FlowValueSourceKind> allowedSources,
) {
  for (final entry in stateWrites.entries) {
    _validateIdentifier(issues, '$path.${entry.key}', entry.key);
    final declaration = document.flowState[entry.key];
    if (declaration == null) {
      issues.add(
        FlowDocumentValidationIssue(
          code: 'missingFlowStateDeclaration',
          path: '$path.${entry.key}',
          message: 'State write "${entry.key}" has no flowState declaration.',
        ),
      );
    } else if (declaration.type != entry.value.type) {
      issues.add(
        FlowDocumentValidationIssue(
          code: 'stateWriteTypeMismatch',
          path: '$path.${entry.key}.type',
          message: 'State write "${entry.key}" declares '
              '${entry.value.type.wireName} but flowState declares '
              '${declaration.type.wireName}.',
        ),
      );
    }
    _validateValueSource(
      issues,
      document,
      '$path.${entry.key}.value',
      entry.value.value,
      allowedSources,
    );
    final value = entry.value.value;
    if (value is LiteralFlowValueSource && value.type != entry.value.type) {
      issues.add(
        FlowDocumentValidationIssue(
          code: 'stateWriteTypeMismatch',
          path: '$path.${entry.key}.value',
          message: 'State write "${entry.key}" declares '
              '${entry.value.type.wireName} but literal declares '
              '${value.type.wireName}.',
        ),
      );
    }
    final sourceType = _valueSourceType(document, value);
    if (sourceType != null && sourceType != entry.value.type) {
      issues.add(
        FlowDocumentValidationIssue(
          code: 'stateWriteTypeMismatch',
          path: '$path.${entry.key}.value',
          message: 'State write "${entry.key}" expects '
              '${entry.value.type.wireName} but source declares '
              '${sourceType.wireName}.',
        ),
      );
    }
  }
}

void _validateValueSourceMap(
  List<FlowDocumentValidationIssue> issues,
  FlowDocument document,
  String path,
  Map<String, FlowValueSource> sources,
  Set<_FlowValueSourceKind> allowedSources,
) {
  for (final entry in sources.entries) {
    _validateIdentifier(issues, '$path.${entry.key}', entry.key);
    _validateValueSource(
      issues,
      document,
      '$path.${entry.key}',
      entry.value,
      allowedSources,
    );
  }
}

void _validateValueSource(
  List<FlowDocumentValidationIssue> issues,
  FlowDocument document,
  String path,
  FlowValueSource source,
  Set<_FlowValueSourceKind> allowedSources,
) {
  final sourceKind = _valueSourceKind(source);
  if (!allowedSources.contains(sourceKind)) {
    issues.add(
      FlowDocumentValidationIssue(
        code: 'invalidValueSourceContext',
        path: path,
        message: 'Value source ${sourceKind.name} is not available here.',
      ),
    );
  }
  switch (source) {
    case LiteralFlowValueSource(:final type, :final value):
      _validateLiteralValueType(issues, '$path.literal', type, value);
    case RefFlowValueSource(:final key, path: final sourcePath):
      _validateIdentifier(issues, '$path.key', key);
      if (source is StateFlowValueSource &&
          !document.flowState.containsKey(key)) {
        issues.add(
          FlowDocumentValidationIssue(
            code: 'missingFlowStateDeclaration',
            path: path,
            message: 'State value ref "$key" has no flowState declaration.',
          ),
        );
      }
      for (var index = 0; index < sourcePath.length; index += 1) {
        _validateIdentifier(
          issues,
          '$path.path[$index]',
          sourcePath[index],
        );
      }
  }
}

_FlowValueSourceKind _valueSourceKind(FlowValueSource source) {
  return switch (source) {
    LiteralFlowValueSource() => _FlowValueSourceKind.literal,
    StateFlowValueSource() => _FlowValueSourceKind.state,
    EventFlowValueSource() => _FlowValueSourceKind.event,
    ActionResultFlowValueSource() => _FlowValueSourceKind.actionResult,
    SubFlowResultFlowValueSource() => _FlowValueSourceKind.subFlowResult,
  };
}

FlowDataType? _valueSourceType(FlowDocument document, FlowValueSource source) {
  return switch (source) {
    LiteralFlowValueSource(:final type) => type,
    StateFlowValueSource(:final key) => document.flowState[key]?.type,
    EventFlowValueSource() ||
    ActionResultFlowValueSource() ||
    SubFlowResultFlowValueSource() =>
      null,
  };
}

void _validateLiteralValueType(
  List<FlowDocumentValidationIssue> issues,
  String path,
  FlowDataType type,
  Object value,
) {
  final valid = switch (type) {
    FlowDataType.bool => value is bool,
    FlowDataType.int => value is int,
    FlowDataType.string => value is String,
  };
  if (valid) return;
  issues.add(
    FlowDocumentValidationIssue(
      code: 'literalTypeMismatch',
      path: path,
      message: 'Literal value must match declared type ${type.wireName}.',
    ),
  );
}

void _validateTransitionTarget(
  List<FlowDocumentValidationIssue> issues,
  FlowDocument document,
  String path,
  String target,
) {
  _validateIdentifier(issues, path, target);
  if (!document.states.containsKey(target)) {
    issues.add(
      FlowDocumentValidationIssue(
        code: 'missingTransitionTarget',
        path: path,
        message: 'Transition target $target does not exist.',
      ),
    );
  }
}

void _validateReachability(
  FlowDocument document,
  List<FlowDocumentValidationIssue> issues,
) {
  if (!document.states.containsKey(document.initial)) {
    return;
  }

  final reachable = <String>{};
  final pending = <String>[document.initial];
  while (pending.isNotEmpty) {
    final id = pending.removeLast();
    if (!reachable.add(id)) {
      continue;
    }
    final state = document.states[id];
    for (final target in _reachableTargetsFor(state)) {
      if (document.states.containsKey(target)) {
        pending.add(target);
      }
    }
  }

  for (final id in document.states.keys) {
    if (!reachable.contains(id)) {
      issues.add(
        FlowDocumentValidationIssue(
          code: 'unreachableState',
          path: '\$.states.$id',
          message: 'State $id is not reachable from ${document.initial}.',
        ),
      );
    }
  }
}

void _validateScreenlessCycles(
  FlowDocument document,
  List<FlowDocumentValidationIssue> issues,
) {
  final visiting = <String>{};
  final visited = <String>{};
  var reported = false;

  void visit(String id, List<String> stack) {
    if (reported || visited.contains(id)) return;
    final state = document.states[id];
    if (!_isScreenlessState(state)) return;
    if (visiting.contains(id)) {
      reported = true;
      issues.add(
        FlowDocumentValidationIssue(
          code: 'screenlessCycle',
          path: '\$.states.$id',
          message: 'Screenless state cycle: ${[...stack, id].join(' -> ')}.',
        ),
      );
      return;
    }

    visiting.add(id);
    for (final target in _reachableTargetsFor(state)) {
      visit(target, [...stack, id]);
    }
    visiting.remove(id);
    visited.add(id);
  }

  for (final id in document.states.keys) {
    visit(id, const []);
  }
}

bool _isScreenlessState(FlowState? state) {
  return state is DecisionFlowState || state is SubFlowState;
}

Iterable<String> _reachableTargetsFor(FlowState? state) sync* {
  switch (state) {
    case null:
      return;
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
      if (subFlowUnavailable != null) {
        yield subFlowUnavailable.target;
      }
    case EndFlowState() || UnsupportedFlowState():
      return;
  }
}
