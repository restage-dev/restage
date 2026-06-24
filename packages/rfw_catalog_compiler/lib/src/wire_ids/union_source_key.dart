import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Builds the stable source key recorded on a union's `alloc` event.
///
/// The key combines the union's library namespace with the abstract base
/// type's fully-qualified name ([UnionEntry.sourceType]) — for example
/// `restage.core#package:flutter/src/painting/gradient.dart#Gradient`.
///
/// Using the FQN rather than the advisory display name keeps the key stable
/// across renames: identity is stable; names are mutable labels. The library
/// namespace stays in the key because the same abstract base resolves to a
/// distinct union per library (each library curates its own member set), so
/// those unions must receive distinct wire IDs.
///
/// The result is only ever used as a whole-string map key / event `source`
/// field; nothing splits it, so the embedded `#` separators are harmless.
/// Both the allocation side and the resolution side call this so the keys
/// they construct can never drift.
String unionSourceKey(UnionEntry union) =>
    '${union.library.namespace}#${union.sourceType}';
