import 'package:meta/meta.dart';

/// A sidecar validation rule attached to a property.
///
/// The expression DSL is sidecar-driven: a small recognized set of
/// predicates (range, oneOf, regex, ...) parsed and applied by the SDK
/// runtime when a blob assigns a value. The catalog ships only the
/// declared rule; predicate evaluation lives in the runtime.
@immutable
final class ValidationExpr {
  /// Const constructor.
  const ValidationExpr({required this.expression, required this.message});

  /// The validation expression — e.g. `'range(0, 100)'`, `'oneOf("a","b")'`,
  /// `'matches("^[a-zA-Z]+$")'`. Future expansion behind the same struct.
  final String expression;

  /// Human-readable message surfaced when validation fails.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ValidationExpr &&
      other.expression == expression &&
      other.message == message;

  @override
  int get hashCode => Object.hash(expression, message);
}
