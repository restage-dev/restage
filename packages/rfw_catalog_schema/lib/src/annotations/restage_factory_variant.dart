import 'package:meta/meta.dart';

/// Registers a static const value or factory method as a named factory
/// variant on a structured type.
///
/// Used when a customer wants to surface a curated factory beyond the
/// default-constructor / named-constructor / static-const-field set the
/// compiler auto-discovers. The compiler allocates a `v*` wire ID for
/// the annotated member.
///
/// ```dart
/// @RestageFactoryVariant(of: AcmeBorderRadius, name: 'pill')
/// const AcmeBorderRadius pillBorderRadius = AcmeBorderRadius._pill();
/// ```
@immutable
final class RestageFactoryVariant {
  /// Const constructor.
  const RestageFactoryVariant({required this.of, required this.name});

  /// The structured type this variant produces.
  final Type of;

  /// Catalog-visible name for the variant. Surfaced in the editor.
  final String name;
}
