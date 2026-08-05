/// A stand-in [PropertyEntry] for a value that has a shape but no catalog slot.
library;

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A [PropertyEntry] describing a value that is NOT a catalog property: a map
/// key, a map value, or a record label.
///
/// The decoder and translator paths are written against [PropertyEntry], so a
/// value reached inside a map or record borrows one to decode identically to a
/// real widget property. It carries an unallocated wire id and no description,
/// because it never reaches the catalog — [name] appears only in generated
/// source and error messages.
///
/// The entry's `type` and `enumType` are DERIVED from [shape] rather than
/// passed in: they are a restatement of it, and accepting them separately would
/// let a caller describe a value two ways at once.
PropertyEntry syntheticProperty(String name, CatalogValueShape shape) =>
    PropertyEntry(
      wireId: WireId.unallocatedProperty,
      name: name,
      type: shape.propertyType,
      description: '',
      required: true,
      enumType: shape is EnumShape ? shape.enumRef.symbolName : null,
      valueShape: shape,
    );
