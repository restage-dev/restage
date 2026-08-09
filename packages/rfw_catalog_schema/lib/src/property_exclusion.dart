import 'package:meta/meta.dart';

/// One constructor input that a compile target could not carry into its
/// catalog, recorded so the omission is queryable rather than silent.
///
/// A widget's constructor input becomes a catalog property only when the
/// compiler can build its value from wire data. When no decoder exists for the
/// input's type and the input is optional, generated construction simply leaves
/// it out — which is legal Dart and preserves the widget's own semantics — and
/// the omission is recorded here instead of failing the build. An input that
/// cannot be left out is an error rather than an exclusion, so it never appears
/// in this list.
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

  /// The excluded constructor input's public name.
  final String property;

  /// Name of the compile target that dropped the input.
  ///
  /// The same input can be carried by one target and dropped by another, so an
  /// exclusion is always target-qualified.
  final String target;

  /// Human-readable explanation naming the type that has no decoder.
  final String reason;

  /// Source location of the excluded input, as `<asset path>#<owner>.<name>`.
  final String location;
}
