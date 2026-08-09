import 'package:restage/restage.dart';

export 'widgets/feature_panel.dart';
export 'widgets/feature_row.dart';
export 'widgets/catalog_showcase.dart';
export 'widgets/price_badge.dart';
export 'widgets/stat_tile.dart';

/// Declares the customer catalog capability carried by every generated target.
@RestageLibrary(
  library: WidgetLibrary.custom('restage_widgetbook_example.widgets'),
  capabilityVersion: 2,
)
const restageWidgetbookLibrary = 0;
