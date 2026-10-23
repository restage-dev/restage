import 'package:meta/meta.dart';

/// One constructor input that a compile target could not carry into its
/// catalog, recorded so the omission is queryable rather than silent.
///
/// A widget's constructor input becomes a catalog property only when the
/// compiler can build its value from wire data. When no decoder exists for the
/// input's type and the input is optional, generated construction simply leaves
/// it out — which is legal Dart and preserves the widget's own semantics — and
/// the omission is recorded here instead of failing the build. When the input
/// cannot be left out, the widget itself is left out of the catalog and the
/// input is recorded here with the reason, so a use of the widget can say why
/// it is absent.
@immutable
final class PropertyExclusion {
  /// Const constructor.
  const PropertyExclusion({
    required this.widget,
    required this.property,
    required this.target,
    required this.reason,
    required this.location,
  });

  /// Simple name of the widget declaring the excluded input.
  final String widget;

  /// The excluded constructor input's public name, or empty when the widget
  /// is left out for a reason no single input carries.
  final String property;

  /// Name of the compile target that dropped the input.
  ///
  /// The same input can be carried by one target and dropped by another, so an
  /// exclusion is always target-qualified.
  final String target;

  /// Human-readable explanation naming the type that has no decoder.
  final String reason;

  /// The excluded input as `<library uri>#<widget>.<property>`, or the
  /// widget alone as `<library uri>#<widget>` when [property] is empty.
  final String location;

  /// Whether this records the widget whose `flutterType` is [flutterType].
  bool isOf(String flutterType) =>
      location == flutterType || location.startsWith('$flutterType.');
}
