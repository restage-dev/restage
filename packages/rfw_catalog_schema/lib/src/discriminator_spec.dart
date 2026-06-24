import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/wire_id.dart';

/// On-wire discriminator describing how to read which member of a
/// union slot a blob carries.
@immutable
final class DiscriminatorSpec {
  /// Const constructor.
  const DiscriminatorSpec({required this.field, required this.values});

  /// Discriminator field name on the union-typed slot. Typically `'_s'`
  /// for structured-level union membership.
  final String field;

  /// Recognized discriminator values, expressed as cross-library
  /// references to structured-type wire IDs.
  final List<WireIdRef> values;
}
