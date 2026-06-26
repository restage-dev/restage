import 'package:restage_shared/src/flow_document/flow_document.dart';

/// The number of value sources a [FlowPredicateOperator] consumes.
enum FlowPredicateValueArity {
  /// No value source (an existence check).
  none,

  /// A single value source.
  single,

  /// A list of value sources.
  list,
}

/// The fluent predicate-sugar operators, single-sourced so the runtime
/// authoring extension and the build-time codegen parser cannot diverge on the
/// operator set, the operator → wire-condition mapping, or which operators are
/// numeric-only.
///
/// Each operator names the authoring method that produces it (`equals`,
/// `greaterThan`, …), the [arity] of value sources it carries, and whether it
/// is [intOnly] — the comparison operators (`greaterThan`/`atLeast`/`lessThan`/
/// `atMost`) compare integers at runtime, so the sugar must reject a non-int
/// literal to them rather than author a comparison the runtime cannot evaluate.
enum FlowPredicateOperator {
  /// `state(k).equals(v)` → [EqualsFlowPredicateCondition].
  equals('equals', FlowPredicateValueArity.single),

  /// `state(k).notEquals(v)` → [NotEqualsFlowPredicateCondition].
  notEquals('notEquals', FlowPredicateValueArity.single),

  /// `state(k).greaterThan(v)` → [GreaterThanFlowPredicateCondition].
  greaterThan(
    'greaterThan',
    FlowPredicateValueArity.single,
    intOnly: true,
  ),

  /// `state(k).atLeast(v)` → [GreaterThanOrEqualsFlowPredicateCondition].
  atLeast(
    'atLeast',
    FlowPredicateValueArity.single,
    intOnly: true,
  ),

  /// `state(k).lessThan(v)` → [LessThanFlowPredicateCondition].
  lessThan(
    'lessThan',
    FlowPredicateValueArity.single,
    intOnly: true,
  ),

  /// `state(k).atMost(v)` → [LessThanOrEqualsFlowPredicateCondition].
  atMost(
    'atMost',
    FlowPredicateValueArity.single,
    intOnly: true,
  ),

  /// `state(k).oneOf([…])` → [InFlowPredicateCondition].
  oneOf('oneOf', FlowPredicateValueArity.list),

  /// `state(k).isSet()` → [ExistsFlowPredicateCondition] (`exists: true`).
  isSet('isSet', FlowPredicateValueArity.none),

  /// `state(k).isUnset()` → [ExistsFlowPredicateCondition] (`exists: false`).
  isUnset('isUnset', FlowPredicateValueArity.none);

  const FlowPredicateOperator(
    this.methodName,
    this.arity, {
    this.intOnly = false,
  });

  /// The authoring method name that produces this operator.
  final String methodName;

  /// How many value sources this operator carries.
  final FlowPredicateValueArity arity;

  /// Whether this operator compares integers only (the runtime numeric
  /// comparisons). A non-int literal is rejected loud at authoring time.
  final bool intOnly;
}

/// Infers the scalar [FlowDataType] of a predicate literal, or `null` if
/// [value] is not a supported scalar (only `bool`, `int`, and `String`).
FlowDataType? flowPredicateLiteralType(Object value) {
  if (value is bool) return FlowDataType.bool;
  if (value is int) return FlowDataType.int;
  if (value is String) return FlowDataType.string;
  return null;
}

/// Returns the first field key that appears in more than one of [predicates],
/// or `null` if every field is unique.
///
/// The predicate wire allows at most one condition per field, so a duplicate
/// cannot be merged into one predicate. Single-sourced here so the authoring
/// API and the build-time lowering apply the same one-condition-per-field rule
/// (each reporting it in its own idiom — a thrown error vs a build diagnostic).
String? firstDuplicatePredicateField(
  Iterable<FlowBranchPredicate> predicates,
) {
  final seen = <String>{};
  for (final predicate in predicates) {
    for (final key in predicate.fields.keys) {
      if (!seen.add(key)) return key;
    }
  }
  return null;
}

/// Merges single-field [predicates] into one AND-ed [FlowBranchPredicate].
///
/// Throws [ArgumentError] if two predicates target the same field (a same-field
/// range must be authored as separate branches), per
/// [firstDuplicatePredicateField].
FlowBranchPredicate mergeFlowBranchPredicates(
  Iterable<FlowBranchPredicate> predicates,
) {
  final duplicate = firstDuplicatePredicateField(predicates);
  if (duplicate != null) {
    throw ArgumentError(
      'allOf cannot merge two conditions on field "$duplicate"; the predicate '
      'wire allows one condition per field',
    );
  }
  return FlowBranchPredicate(
    fields: {for (final predicate in predicates) ...predicate.fields},
  );
}

/// Builds the wire [FlowPredicateCondition] for [operator] from
/// already-resolved value sources.
///
/// Single-arity operators require [value]; `oneOf` requires [values]; existence
/// operators (`isSet`/`isUnset`) take neither. A missing required argument is a
/// loud [ArgumentError] — callers derive the requirement from [operator]'s
/// [FlowPredicateOperator.arity].
FlowPredicateCondition buildFlowPredicateCondition(
  FlowPredicateOperator operator, {
  FlowValueSource? value,
  List<FlowValueSource>? values,
}) {
  FlowValueSource requireValue() {
    if (value == null) {
      throw ArgumentError.notNull('value');
    }
    return value;
  }

  List<FlowValueSource> requireValues() {
    if (values == null) {
      throw ArgumentError.notNull('values');
    }
    return values;
  }

  switch (operator) {
    case FlowPredicateOperator.equals:
      return EqualsFlowPredicateCondition(value: requireValue());
    case FlowPredicateOperator.notEquals:
      return NotEqualsFlowPredicateCondition(value: requireValue());
    case FlowPredicateOperator.greaterThan:
      return GreaterThanFlowPredicateCondition(value: requireValue());
    case FlowPredicateOperator.atLeast:
      return GreaterThanOrEqualsFlowPredicateCondition(value: requireValue());
    case FlowPredicateOperator.lessThan:
      return LessThanFlowPredicateCondition(value: requireValue());
    case FlowPredicateOperator.atMost:
      return LessThanOrEqualsFlowPredicateCondition(value: requireValue());
    case FlowPredicateOperator.oneOf:
      return InFlowPredicateCondition(values: requireValues());
    case FlowPredicateOperator.isSet:
      return const ExistsFlowPredicateCondition(exists: true);
    case FlowPredicateOperator.isUnset:
      return const ExistsFlowPredicateCondition(exists: false);
  }
}
