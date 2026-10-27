import 'package:meta/meta.dart';

/// Ordered native inputs to an installed integer callback.
enum ScalarCallbackParameter {
  /// A native key whose admitted scalar value may be projected by the adapter.
  valueKey,

  /// A native widget retained as opaque callback identity.
  widget,

  /// The native child index.
  itemIndex,
}

/// Structural signature for a pure callback returning an integer or null.
@immutable
final class ScalarCallbackContract {
  /// Creates a callback signature with ordered native parameter identities.
  const ScalarCallbackContract({
    required this.parameters,
    this.nullableResult = true,
  });

  /// Ordered native inputs; opaque objects never become payload values.
  final List<ScalarCallbackParameter> parameters;

  /// Whether the callback can explicitly return null.
  final bool nullableResult;

  /// Whether this signature has an installed native adapter.
  bool get isSupported =>
      parameters.length == 1 &&
          parameters.single == ScalarCallbackParameter.valueKey ||
      parameters.length == 2 &&
          parameters.first == ScalarCallbackParameter.widget &&
          parameters.last == ScalarCallbackParameter.itemIndex;

  @override
  bool operator ==(Object other) =>
      other is ScalarCallbackContract &&
      nullableResult == other.nullableResult &&
      parameters.length == other.parameters.length &&
      Iterable<int>.generate(parameters.length)
          .every((i) => parameters[i] == other.parameters[i]);

  @override
  int get hashCode => Object.hash(nullableResult, Object.hashAll(parameters));
}
