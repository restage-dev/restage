import 'package:meta/meta.dart';

/// Promotes a widget class from the default `volatile` tier to the
/// `stable` tier.
///
/// `stable` carries a maintainer commitment: the widget's wire
/// contract is preserved across minor versions; any breaking change
/// requires a new wire ID and a `replace` event. The [since] field
/// records the version at which the commitment took effect.
@immutable
final class StableWidget {
  /// Const constructor.
  const StableWidget({required this.since});

  /// Catalog version where this widget was promoted to `stable`.
  final String since;
}
