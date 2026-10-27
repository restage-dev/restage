import 'package:meta/meta.dart';

/// Ordered native inputs to a deferred widget callback.
enum WidgetBuilderParameter {
  /// Native context, retained by the installed callback and never serialized.
  buildContext,

  /// The native layout constraints projected into an inert frame.
  boxConstraints,

  /// The native orientation projected as an enum token.
  orientation,

  /// The native lazy-child index.
  itemIndex,
}

/// Structural signature of an admitted native widget callback.
@immutable
final class WidgetBuilderContract {
  /// Creates a callback signature with ordered native parameter identities.
  const WidgetBuilderContract({
    required this.parameters,
    this.nullableResult = false,
  });

  /// Ordered inputs, including the native, nonserialized context position.
  final List<WidgetBuilderParameter> parameters;

  /// Whether returning an explicit null widget is admitted.
  final bool nullableResult;

  /// Whether this signature has an installed native adapter.
  bool get isSupported =>
      parameters.isNotEmpty &&
      parameters.first == WidgetBuilderParameter.buildContext &&
      (parameters.length == 1 ||
          parameters.length == 2 &&
              parameters.last != WidgetBuilderParameter.buildContext) &&
      (!nullableResult ||
          parameters.length == 2 &&
              parameters.last == WidgetBuilderParameter.itemIndex);

  @override
  bool operator ==(Object other) =>
      other is WidgetBuilderContract &&
      nullableResult == other.nullableResult &&
      parameters.length == other.parameters.length &&
      Iterable<int>.generate(parameters.length)
          .every((i) => parameters[i] == other.parameters[i]);

  @override
  int get hashCode => Object.hash(nullableResult, Object.hashAll(parameters));
}
