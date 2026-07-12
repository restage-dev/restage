// The second custom-library barrel: it declares the `acme.lessons` library and
// re-exports its widgets. The A2UI build phase reads the capability version off
// this `@RestageLibrary` declaration and stamps it into the generated catalog's
// capability sidecar — proving multiple custom libraries stamp independently
// alongside `acme.widgets` (declared in restage_imports.dart).
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

export 'widgets/lessons/callout.dart';
export 'widgets/lessons/comparison_panel.dart';
export 'widgets/lessons/quiz_check.dart';
export 'widgets/lessons/section_header.dart';

/// Declares the `acme.lessons` custom library at capability version 1.
/// Increment `capabilityVersion` whenever you add a widget or make a
/// render-affecting change so the pre-render check can verify a payload's
/// required capability against what your build provides.
@RestageLibrary(
  library: WidgetLibrary.custom('acme.lessons'),
  capabilityVersion: 1,
)
const restageLessonsLibrary = 0;
