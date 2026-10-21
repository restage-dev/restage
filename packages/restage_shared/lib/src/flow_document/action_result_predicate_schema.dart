import 'package:restage_shared/src/flow_document/flow_action_schema.dart';
import 'package:restage_shared/src/flow_document/flow_document.dart';

/// Why [predicate] cannot be evaluated against an action result of
/// [schema], or null when it can.
String? actionResultPredicateSchemaIssue(
  FlowActionResultPredicate predicate,
  FlowActionSchema schema,
) {
  switch (predicate) {
    case AlwaysActionResultPredicate():
      return null;
    case BoolEqualsActionResultPredicate():
      if (schema is FlowBoolActionSchema) return null;
      return 'boolEquals requires a bool result, found ${schema.kind}.';
    case ObjectBoolFieldEqualsActionResultPredicate(:final field):
      if (schema is! FlowObjectActionSchema) {
        return 'objectBoolFieldEquals.$field requires an object result, '
            'found ${schema.kind}.';
      }
      final fieldSchema = schema.fields[field];
      if (fieldSchema == null) {
        return 'objectBoolFieldEquals field "$field" is missing.';
      }
      if (!fieldSchema.required) {
        return 'objectBoolFieldEquals field "$field" must be required.';
      }
      if (fieldSchema.schema is FlowBoolActionSchema) return null;
      return 'objectBoolFieldEquals field "$field" must be bool, found '
          '${fieldSchema.schema.kind}.';
    case MatchesActionResultPredicate(:final result, :final fields):
      if (result != null) {
        final issue = _conditionIssue('the result', result, schema, true);
        if (issue != null) return issue;
      }
      if (fields.isEmpty) return null;
      if (schema is! FlowObjectActionSchema) {
        return 'field conditions require an object result, found '
            '${schema.kind}.';
      }
      for (final entry in fields.entries) {
        final field = schema.fields[entry.key];
        if (field == null) return 'result field "${entry.key}" is missing.';
        final issue = _conditionIssue(
          'result field "${entry.key}"',
          entry.value,
          field.schema,
          field.required,
        );
        if (issue != null) return issue;
      }
      return null;
  }
}

String? _conditionIssue(
  String subject,
  FlowPredicateCondition condition,
  FlowActionSchema schema,
  bool required,
) {
  var target = schema;
  var optional = !required;
  if (target is FlowNullableActionSchema) {
    target = target.child;
    optional = true;
  }
  final literals = switch (condition) {
    ExistsFlowPredicateCondition() => const <FlowValueSource>[],
    EqualsFlowPredicateCondition(:final value) ||
    NotEqualsFlowPredicateCondition(:final value) ||
    GreaterThanFlowPredicateCondition(:final value) ||
    GreaterThanOrEqualsFlowPredicateCondition(:final value) ||
    LessThanFlowPredicateCondition(:final value) ||
    LessThanOrEqualsFlowPredicateCondition(:final value) =>
      [value],
    InFlowPredicateCondition(:final values) => values,
  };
  if (condition is ExistsFlowPredicateCondition) {
    return optional ? null : '$subject is always present.';
  }
  final ordered = condition is GreaterThanFlowPredicateCondition ||
      condition is GreaterThanOrEqualsFlowPredicateCondition ||
      condition is LessThanFlowPredicateCondition ||
      condition is LessThanOrEqualsFlowPredicateCondition;
  for (final source in literals) {
    if (source is! LiteralFlowValueSource) {
      return '$subject must be compared with a literal.';
    }
    final matches = switch ((source.type, target)) {
      (FlowDataType.bool, FlowBoolActionSchema()) => !ordered,
      (FlowDataType.int, FlowIntActionSchema()) => true,
      (FlowDataType.string, FlowStringActionSchema()) => !ordered,
      (FlowDataType.string, FlowEnumActionSchema(:final values)) =>
        !ordered && values.contains(source.value),
      _ => false,
    };
    if (!matches) {
      return '$subject is ${target.kind} and cannot be compared with '
          '${source.type.wireName} ${source.value}'
          '${ordered ? ' by order' : ''}.';
    }
  }
  return null;
}
