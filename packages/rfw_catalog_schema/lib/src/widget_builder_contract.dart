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

  /// An app value, projected into inert data by the app's compiled code.
  data,

  /// A widget the caller passes through, such as a builder's `child`.
  child,
}

/// A native value an app builder supplies its delivered body, by its native
/// type id.
@immutable
final class WidgetBuilderNativeValue {
  /// Creates a native value of [type].
  const WidgetBuilderNativeValue(this.type, {this.nullable = false});

  /// The native type id, such as `()->void`.
  final String type;

  /// Whether the value may be null.
  final bool nullable;

  @override
  bool operator ==(Object other) =>
      other is WidgetBuilderNativeValue &&
      type == other.type &&
      nullable == other.nullable;

  @override
  int get hashCode => Object.hash(type, nullable);
}

/// Structural signature of an admitted native widget callback.
@immutable
final class WidgetBuilderContract {
  /// Creates a callback signature with ordered native parameter identities.
  const WidgetBuilderContract({
    required this.parameters,
    this.nullableResult = false,
    this.nativeValues = const {},
  });

  /// Ordered inputs, including the native, nonserialized context position.
  final List<WidgetBuilderParameter> parameters;

  /// Whether returning an explicit null widget is admitted.
  final bool nullableResult;

  /// For an app-value signature, the native values its body reads as
  /// `<scope>.values.<key>`, by key.
  final Map<String, WidgetBuilderNativeValue> nativeValues;

  /// Whether this signature has an installed native adapter.
  bool get isSupported =>
      parameters.isNotEmpty &&
      parameters.first == WidgetBuilderParameter.buildContext &&
      (parameters.length == 1 ||
          parameters.length == 2 && _native(parameters.last)) &&
      (!nullableResult ||
          parameters.length == 2 &&
              parameters.last == WidgetBuilderParameter.itemIndex);

  /// Whether this is the signature of an app builder whose body is
  /// delivered: the context, app values, then at most one passthrough.
  bool get isAppValueSignature {
    if (nullableResult ||
        parameters.firstOrNull != WidgetBuilderParameter.buildContext) {
      return false;
    }
    final rest = parameters.skip(1).toList();
    if (rest.lastOrNull == WidgetBuilderParameter.child) rest.removeLast();
    return rest.isNotEmpty &&
        rest.every((parameter) => parameter == WidgetBuilderParameter.data);
  }

  static bool _native(WidgetBuilderParameter parameter) => const {
        WidgetBuilderParameter.boxConstraints,
        WidgetBuilderParameter.orientation,
        WidgetBuilderParameter.itemIndex,
      }.contains(parameter);

  @override
  bool operator ==(Object other) =>
      other is WidgetBuilderContract &&
      nullableResult == other.nullableResult &&
      parameters.length == other.parameters.length &&
      Iterable<int>.generate(parameters.length)
          .every((i) => parameters[i] == other.parameters[i]) &&
      nativeValues.length == other.nativeValues.length &&
      nativeValues.entries
          .every((entry) => other.nativeValues[entry.key] == entry.value);

  @override
  int get hashCode => Object.hash(
      nullableResult,
      Object.hashAll(parameters),
      Object.hashAllUnordered(nativeValues.entries
          .map((entry) => Object.hash(entry.key, entry.value))));
}
