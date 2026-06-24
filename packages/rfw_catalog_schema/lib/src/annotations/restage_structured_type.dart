import 'package:meta/meta.dart';

/// Marks a class as a discriminated-union root.
///
/// Authored on an abstract class whose concrete subclasses are
/// registered via `@RestageUnionVariant`. The compiler allocates a
/// union wire ID for the annotated type, and a structured-type wire
/// ID for each registered variant.
///
/// ```dart
/// @RestageStructuredType(union: AcmeShape)
/// abstract class AcmeShape {
///   const AcmeShape();
/// }
/// ```
///
/// The [union] field receives the Dart type the annotated class
/// represents. It is captured by the compiler at annotation-evaluation
/// time so customers can reference the type symbolically.
@immutable
final class RestageStructuredType {
  /// Const constructor.
  const RestageStructuredType({required this.union});

  /// Reference to the Dart type the annotated class represents.
  final Type union;
}
