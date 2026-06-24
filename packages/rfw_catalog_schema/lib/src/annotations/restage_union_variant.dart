import 'package:meta/meta.dart';

/// Registers a concrete class as a member of a discriminated union.
///
/// The compiler allocates a structured wire ID for the annotated class
/// and emits an `addMember` event in the host package's wire ID event
/// log pointing at the [of] union.
///
/// ```dart
/// @RestageUnionVariant(of: Gradient)
/// class MyAcmeGradient extends Gradient {
///   const MyAcmeGradient({required this.colors, required this.swirl});
///   final List<Color> colors;
///   final double swirl;
///
///   @override
///   Shader createShader(Rect rect, {TextDirection? textDirection}) { /* … */ }
/// }
/// ```
@immutable
final class RestageUnionVariant {
  /// Const constructor.
  const RestageUnionVariant({required this.of});

  /// The union type this class extends.
  final Type of;
}
