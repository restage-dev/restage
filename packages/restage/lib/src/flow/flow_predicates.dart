import 'package:restage_shared/restage_shared.dart';

/// References a flow-state value by [key].
///
/// The returned [StateFlowValueSource] is usable directly as a value source —
/// a comparison right-hand side, a `stateWrites` value, or a `subFlow` input —
/// and the comparison operators in [StateRefPredicates] hang off it to build
/// branch predicates: `state('goal').equals('sleep')`.
StateFlowValueSource state(String key) => StateFlowValueSource(key: key);

/// Fluent comparison operators that desugar a [state] reference into a
/// single-field [FlowBranchPredicate].
///
/// Each operator returns a predicate over exactly the [StateFlowValueSource.key]
/// field. Combine several with [allOf]. A right-hand side is either another value
/// source (passed through, e.g. `state('preferred')`) or a raw `bool`/`int`/
/// `String` literal (auto-wrapped as a [LiteralFlowValueSource]); a non-scalar
/// literal is a loud [ArgumentError]. The numeric operators (`greaterThan`/
/// `atLeast`/`lessThan`/`atMost`) compare integers, so a non-int literal to them
/// is a loud [ArgumentError] rather than a comparison the runtime cannot make.
///
/// A literal right-hand side must be a literal constant — written bare,
/// parenthesized, or as adjacent string literals. A computed const expression
/// (`'a' + 'b'`, `1 + 1`, a const reference) is not supported by the build-time
/// lowering and is a build error; write the value as a literal instead.
extension StateRefPredicates on StateFlowValueSource {
  /// `field == value`.
  FlowBranchPredicate equals(Object value) =>
      _build(FlowPredicateOperator.equals, value);

  /// `field != value`.
  FlowBranchPredicate notEquals(Object value) =>
      _build(FlowPredicateOperator.notEquals, value);

  /// `field > value` (integers).
  FlowBranchPredicate greaterThan(Object value) =>
      _build(FlowPredicateOperator.greaterThan, value);

  /// `field >= value` (integers).
  FlowBranchPredicate atLeast(Object value) =>
      _build(FlowPredicateOperator.atLeast, value);

  /// `field < value` (integers).
  FlowBranchPredicate lessThan(Object value) =>
      _build(FlowPredicateOperator.lessThan, value);

  /// `field <= value` (integers).
  FlowBranchPredicate atMost(Object value) =>
      _build(FlowPredicateOperator.atMost, value);

  /// `field` is one of [values].
  FlowBranchPredicate oneOf(List<Object> values) {
    final sources = values
        .map((value) => _coerce(FlowPredicateOperator.oneOf, value))
        .toList();
    return _wrap(
      buildFlowPredicateCondition(FlowPredicateOperator.oneOf, values: sources),
    );
  }

  /// `field` has a value.
  FlowBranchPredicate isSet() =>
      _wrap(buildFlowPredicateCondition(FlowPredicateOperator.isSet));

  /// `field` has no value.
  FlowBranchPredicate isUnset() =>
      _wrap(buildFlowPredicateCondition(FlowPredicateOperator.isUnset));

  FlowBranchPredicate _build(FlowPredicateOperator operator, Object value) {
    return _wrap(
      buildFlowPredicateCondition(operator, value: _coerce(operator, value)),
    );
  }

  FlowBranchPredicate _wrap(FlowPredicateCondition condition) =>
      FlowBranchPredicate(fields: {key: condition});
}

/// Coerces a sugar right-hand side into a [FlowValueSource]: a value source is
/// passed through; a `bool`/`int`/`String` literal is wrapped as a
/// [LiteralFlowValueSource]. Throws [ArgumentError] for an unsupported literal,
/// or for a non-int literal to an int-only [operator].
FlowValueSource _coerce(FlowPredicateOperator operator, Object value) {
  if (value is FlowValueSource) {
    // A passed-through literal source must still satisfy the int-only rule, so
    // the authoring guard can't be bypassed with a pre-wrapped non-int literal.
    // Require the literal to be int in BOTH its declared type and its value, so
    // an internally mismatched source (`type: int, value: 'old'` or
    // `type: string, value: 18`) is rejected here regardless of direction.
    // A ref source (state/event/...) is runtime-typed and can't be checked.
    if (operator.intOnly &&
        value is LiteralFlowValueSource &&
        (value.type != FlowDataType.int || value.value is! int)) {
      throw ArgumentError.value(
        value,
        'value',
        '${operator.methodName} compares integers; pass an int literal or a '
            'state(...) reference',
      );
    }
    return value;
  }
  final type = flowPredicateLiteralType(value);
  if (type == null) {
    throw ArgumentError.value(
      value,
      'value',
      'flow predicate literals must be a bool, int, or String '
          '(or a value source such as state(...))',
    );
  }
  if (operator.intOnly && type != FlowDataType.int) {
    throw ArgumentError.value(
      value,
      'value',
      '${operator.methodName} compares integers; pass an int literal or a '
          'state(...) reference',
    );
  }
  return LiteralFlowValueSource(type: type, value: value);
}

/// Merges single-field [predicates] into one AND-ed [FlowBranchPredicate].
///
/// Throws [ArgumentError] if two predicates target the same field — the wire
/// allows at most one condition per field, so a same-field range
/// (`allOf([state('age').atLeast(18), state('age').atMost(65)])`) is not
/// representable and must be authored as separate branches.
///
/// Note: `package:matcher` (re-exported by `package:flutter_test`) also exports
/// a top-level `allOf`. App authoring code never imports those, but a test file
/// that uses both this and the matcher should disambiguate — e.g.
/// `import 'package:restage/restage.dart' hide allOf;` or an `as` prefix.
FlowBranchPredicate allOf(List<FlowBranchPredicate> predicates) =>
    mergeFlowBranchPredicates(predicates);
