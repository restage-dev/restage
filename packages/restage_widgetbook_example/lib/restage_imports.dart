// #docregion catalog-library
import 'package:restage/restage.dart';

export 'widgets/bare_catalog_card.dart';
export 'widgets/catalog_showcase.dart';
export 'widgets/feature_panel.dart';
export 'widgets/feature_row.dart';
export 'widgets/price_badge.dart';
export 'widgets/stat_tile.dart';

/// The typed custom widget library used by the example package.
final class RestageWidgetbookLibrary extends WidgetLibrary {
  /// Creates the example custom widget library declaration.
  const RestageWidgetbookLibrary();

  @override
  final String namespace = 'restage_widgetbook_example.widgets';
}

/// The package's one custom-widget-library identity declaration.
const WidgetLibrary restageWidgetbookLibrary = RestageWidgetbookLibrary();

/// Declares the custom-widget catalog capability carried by every generated target.
@RestageLibrary(library: restageWidgetbookLibrary, capabilityVersion: 2)
const restageWidgetbookCatalog = 0;
// #enddocregion catalog-library
