// The library barrel: it declares the custom library (its namespace + capability
// version) and re-exports the widgets that belong to it. The A2UI build phase
// reads the capability version off this `@RestageLibrary` declaration and stamps
// it into the generated catalog's capability sidecar.
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

export 'widgets/cta_button.dart';
export 'widgets/product_card.dart';
export 'widgets/rating_picker.dart';
export 'widgets/scalar_list_panel.dart';

/// Declares the `acme.widgets` custom library at capability version 3. Increment
/// `capabilityVersion` whenever you add a widget or make a render-affecting
/// change so the pre-render check can verify a payload's required capability
/// against what your build provides.
@RestageLibrary(
  library: WidgetLibrary.custom('acme.widgets'),
  capabilityVersion: 3,
)
const restageLibrary = 0;
