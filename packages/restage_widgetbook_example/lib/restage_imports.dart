// #docregion catalog-library
import 'package:restage/restage.dart';

export 'widgets/bare_catalog_card.dart';
export 'widgets/catalog_showcase.dart';
export 'widgets/feature_panel.dart';
export 'widgets/feature_row.dart';
export 'widgets/price_badge.dart';
export 'widgets/stat_tile.dart';

/// The typed customer library used by the generated multi-target fixture.
final class RestageWidgetbookLibrary extends WidgetLibrary {
  /// Creates the example customer library declaration.
  const RestageWidgetbookLibrary();

  @override
  final String namespace = 'restage_widgetbook_example.widgets';
}

/// The package's one customer-library identity declaration.
const WidgetLibrary restageWidgetbookLibrary = RestageWidgetbookLibrary();

/// Declares the customer catalog capability carried by every generated target.
@RestageLibrary(library: restageWidgetbookLibrary, capabilityVersion: 2)
const restageWidgetbookCatalog = 0;
// #enddocregion catalog-library
