// #docregion catalog-library
import 'package:restage/restage.dart';

export 'widgets/bare_catalog_card.dart';
export 'widgets/status_panel.dart';
export 'widgets/feature_panel.dart';
export 'widgets/feature_row.dart';
export 'widgets/price_badge.dart';
export 'widgets/stat_tile.dart';

/// The custom widget library of the example package.
final class RestageWidgetbookLibrary extends WidgetLibrary {
  /// Creates the library.
  const RestageWidgetbookLibrary();

  @override
  final String namespace = 'restage_widgetbook_example.widgets';
}

/// The package's widget library.
const WidgetLibrary restageWidgetbookLibrary = RestageWidgetbookLibrary();

/// Declares the library's capability version for every generated target.
@RestageLibrary(library: restageWidgetbookLibrary, capabilityVersion: 3)
const restageWidgetbookCatalog = 0;
// #enddocregion catalog-library
