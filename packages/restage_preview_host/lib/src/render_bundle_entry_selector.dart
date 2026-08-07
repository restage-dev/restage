import 'package:rfw/formats.dart' show RemoteWidgetLibrary;

/// Selects the supported root declaration for a render-bundle RFW library.
///
/// A unique `main` declaration is authoritative. Libraries without `main`
/// retain compatibility with the legacy `Paywall` root only when that
/// declaration is also unique.
String selectRenderBundleEntryWidgetName(RemoteWidgetLibrary library) {
  final mainCount =
      library.widgets.where((declaration) => declaration.name == 'main').length;
  if (mainCount == 1) return 'main';
  if (mainCount > 1) {
    throw const FormatException('Multiple main declarations.');
  }

  final paywallCount = library.widgets
      .where((declaration) => declaration.name == 'Paywall')
      .length;
  if (paywallCount == 1) return 'Paywall';
  throw const FormatException('No unique render bundle entry.');
}
