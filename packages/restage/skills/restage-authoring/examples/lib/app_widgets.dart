import 'package:restage/restage.dart';

export 'widgets/streak_badge.dart';

/// The app's custom widget library.
final class AppWidgets extends WidgetLibrary {
  /// Creates the library declaration.
  const AppWidgets();

  @override
  final String namespace = 'app.widgets';
}

/// The library identity.
const WidgetLibrary appWidgets = AppWidgets();

/// Raise `capabilityVersion` when a catalog change needs a newer app.
@RestageLibrary(library: appWidgets, capabilityVersion: 1)
const appWidgetCatalog = 0;
