import 'package:meta/meta.dart';

/// Promotes a property from the default `volatile` tier to the
/// `stable` tier.
///
/// Same semantics as `@StableWidget` but at field granularity: the
/// property's wire contract is preserved across minor versions.
@immutable
final class StableProperty {
  /// Const constructor.
  const StableProperty({required this.since});

  /// Catalog version where this property was promoted to `stable`.
  final String since;
}
