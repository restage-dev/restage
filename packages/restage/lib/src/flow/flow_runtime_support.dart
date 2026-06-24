import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart'
    show BuildContext, DefaultTextStyle, Locale, Localizations, MediaQuery;
import 'package:restage_core/library_registration.dart' as restage_core;
import 'package:restage_cupertino/library_registration.dart'
    as restage_cupertino;
import 'package:restage_material/library_registration.dart' as restage_material;
import 'package:rfw/rfw.dart';

import '../runtime/library_runtime_registry.dart';
import '../runtime/restage.dart';
import '../runtime/state_variables.dart';

/// RFW library names a flow screen runtime imports.
const LibraryName kFlowCoreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName kFlowMaterialLibrary =
    LibraryName(<String>['restage', 'material']);
const LibraryName kFlowCupertinoLibrary =
    LibraryName(<String>['restage', 'cupertino']);

/// The library namespace a flow screen blob is registered under.
const LibraryName kFlowScreenLibrary =
    LibraryName(<String>['restage', 'onboarding']);

/// The root widget every flow screen blob exposes.
const FullyQualifiedWidgetName kFlowScreenWidget =
    FullyQualifiedWidgetName(kFlowScreenLibrary, 'OnboardingScreen');

/// Coerces RFW event args to a string-keyed map. Inert non-map payloads become
/// an empty map. Shared by the flow rendering surfaces so they normalize event
/// arguments identically.
Map<String, Object?> normalizeRfwEventArgs(Object? args) {
  if (args is Map<String, Object?>) return args;
  if (args is Map) return args.cast<String, Object?>();
  return <String, Object?>{};
}

/// Populates the RFW data namespaces every flow-screen rendering surface uses.
///
/// [includeInheritedData] is false before a `State` has reached
/// `didChangeDependencies`, because the ambient device/theme values depend on
/// inherited widgets. Product data does not, so it is always published.
void populateFlowScreenData(
  BuildContext context,
  DynamicContent target, {
  required Map<String, PriceInfo> priceQueries,
  required bool includeInheritedData,
}) {
  populateProductData(
    target,
    products: Restage.configuredProducts,
    priceQueries: priceQueries,
  );
  if (!includeInheritedData) return;
  final mediaQuery = MediaQuery.maybeOf(context);
  if (mediaQuery != null) {
    populateDeviceData(
      target,
      locale: Localizations.maybeLocaleOf(context) ?? const Locale('en'),
      mediaQuery: mediaQuery,
      platform: currentDevicePlatform(),
    );
  }
  final theme = Theme.of(context);
  populateThemeData(
    target,
    colorScheme: theme.colorScheme,
    iconTheme: theme.iconTheme,
    defaultTextStyle: DefaultTextStyle.of(context).style,
  );
}

/// The immutable base widget libraries (core / material / cupertino) a flow
/// screen runtime needs. Built once per rendering surface and reused to stamp a
/// fresh [Runtime] per screen blob.
///
/// Each screen visit gets its own [Runtime] (so screens never share live render
/// state), but they all share these immutable base libraries.
final class FlowScreenLibraries {
  /// Builds the three base libraries. Construct once (e.g. in a `State`'s
  /// `initState`) and reuse [runtimeFor] across screens.
  FlowScreenLibraries()
      : _core = restage_core.buildCoreWidgetLibrary(),
        _material = restage_material.buildMaterialWidgetLibrary(),
        _cupertino = restage_cupertino.buildCupertinoWidgetLibrary();

  final WidgetLibrary _core;
  final WidgetLibrary _material;
  final WidgetLibrary _cupertino;

  /// A fresh [Runtime] importing the base libraries plus the given [screen]
  /// blob under [kFlowScreenLibrary], with the customer widget registry applied.
  Runtime runtimeFor(WidgetLibrary screen) {
    final runtime = Runtime()
      ..update(kFlowCoreLibrary, _core)
      ..update(kFlowMaterialLibrary, _material)
      ..update(kFlowCupertinoLibrary, _cupertino)
      ..update(kFlowScreenLibrary, screen);
    LibraryRuntimeRegistry.applyTo(runtime);
    return runtime;
  }
}
