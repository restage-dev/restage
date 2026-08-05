/// The build-time reconstruction recipe for a customer record slot.
///
/// This is a code-generation concern, not a wire concern. The delivered value
/// carries only its label-keyed values; it never carries the record's labels.
/// The generated factory encodes those labels in emitted source from this
/// sidecar, so the catalog and the delivered value mint no record entry and no
/// identifier.
library;

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// One label of a record slot, in the analyzer's canonical label order.
typedef RecordLabelPlan = ({
  String name,
  PropertyType type,
  CatalogValueShape shape,
  String? enumLibraryUri, // Set iff shape is an enum shape.
  String? enumTypeName, // Set iff shape is an enum shape.
});

/// The build-time recipe for reconstructing one record slot.
typedef RecordPlan = ({List<RecordLabelPlan> labels});
