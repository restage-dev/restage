// The library barrel: it declares the custom library (its namespace + capability
// version) and re-exports the widgets that belong to it. The A2UI build phase
// reads the capability version off this `@RestageLibrary` declaration and stamps
// it into the generated catalog's capability sidecar.
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

export 'widgets/cta_button.dart';
export 'widgets/product_card.dart';
export 'widgets/rating_picker.dart';

/// Declares the `acme.widgets` custom library at capability version 2. Increment
/// `capabilityVersion` whenever you add a widget or make a render-affecting
/// change so the delivery layer can reason about which client builds can render
/// a given surface.
@RestageLibrary(
  library: WidgetLibrary.custom('acme.widgets'),
  capabilityVersion: 2,
)
const restageLibrary = 0;
