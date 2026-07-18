import 'package:analyzer/dart/element/type.dart';
import 'package:meta/meta.dart';

/// The JSON scalar family represented by a core Dart scalar type.
enum JsonScalarFamily {
  /// A Dart `String`.
  string,

  /// A Dart `double` or `num`.
  number,

  /// A Dart `int`.
  integer,

  /// A Dart `bool`.
  boolean,
}

/// Analyzer classification for a Dart type in the supported JSON scalar set.
@immutable
final class JsonScalarClassification {
  /// Creates a scalar classification.
  const JsonScalarClassification(
    this.family, {
    this.preserveNumericRuntimeType = false,
  });

  /// The JSON scalar family.
  final JsonScalarFamily family;

  /// Whether a Dart `num` must retain delivered `int` versus `double` values.
  ///
  /// JSON Schema projects both Dart `double` and Dart `num` as `number`, but
  /// generated Dart construction must distinguish them: a `double` field
  /// normalizes numeric input to `double`, while a `num` field accepts the
  /// original numeric runtime type.
  final bool preserveNumericRuntimeType;
}

/// Classifies [type] into the supported core JSON scalar set.
JsonScalarClassification? classifyJsonScalarType(DartType type) {
  if (type.isDartCoreBool) {
    return const JsonScalarClassification(JsonScalarFamily.boolean);
  }
  if (type.isDartCoreInt) {
    return const JsonScalarClassification(JsonScalarFamily.integer);
  }
  if (type.isDartCoreDouble) {
    return const JsonScalarClassification(JsonScalarFamily.number);
  }
  if (type.isDartCoreNum) {
    return const JsonScalarClassification(
      JsonScalarFamily.number,
      preserveNumericRuntimeType: true,
    );
  }
  if (type.isDartCoreString) {
    return const JsonScalarClassification(JsonScalarFamily.string);
  }
  return null;
}
