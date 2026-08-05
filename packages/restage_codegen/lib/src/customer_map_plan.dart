/// Build-time reconstruction recipes for customer map slots.
///
/// These sidecars describe the Dart key and value types that the generated
/// factory must reconstruct. They are not part of the catalog wire format.
library;

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// One key layer in a possibly nested map slot.
///
/// A null `enumRef` means the layer's keys are strings; a non-null one names
/// the enum whose members they are. The ref is carried whole, as the
/// classifier produced it, rather than restated as a kind plus a name: a key
/// layer cannot then claim to be enum-keyed without saying which enum, and the
/// two halves of the enum's identity cannot go missing separately.
typedef MapKeyPlan = ({DartTypeRef? enumRef});

/// The build-time recipe for reconstructing one customer map slot.
typedef MapPlan = ({
  List<MapKeyPlan> keys,
  CatalogValueShape valueShape,
  String? valueSourceType,
});
