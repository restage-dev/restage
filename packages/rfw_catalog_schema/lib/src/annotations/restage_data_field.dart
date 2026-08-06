import 'package:meta/meta.dart';
import 'package:meta/meta_meta.dart';

/// Supplies documentation for one analyzer-resolved member of a nested data
/// class used by a Restage widget.
///
/// Exactly one annotation may resolve to a canonical member across its
/// constructor parameter, public field, and public getter. The generator
/// rejects blank descriptions and ambiguous associations rather than guessing.
@immutable
@Target({TargetKind.field, TargetKind.getter, TargetKind.parameter})
final class RestageDataField {
  /// Creates nested-field documentation with the required [description].
  const RestageDataField({required this.description});

  /// Human-readable documentation for this member occurrence.
  final String description;
}
