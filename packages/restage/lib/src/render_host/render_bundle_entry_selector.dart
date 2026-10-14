import 'package:restage_shared/restage_shared.dart' show surfaceRootWidgetName;
import 'package:rfw/formats.dart' show RemoteWidgetLibrary;

/// Selects the supported root declaration for a render-bundle RFW library.
///
/// Uses the shared surface root rule; a library without a root is refused.
String selectRenderBundleEntryWidgetName(RemoteWidgetLibrary library) =>
    surfaceRootWidgetName(library.widgets.map((widget) => widget.name)) ??
    (throw const FormatException('No unique render bundle entry.'));
