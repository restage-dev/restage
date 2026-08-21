import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart'
    show BuildContext, DefaultTextStyle, Locale, Localizations, MediaQuery;
import 'package:restage_core/library_registration.dart' as restage_core;
import 'package:restage_cupertino/library_registration.dart'
    as restage_cupertino;
import 'package:restage_material/library_registration.dart' as restage_material;
import 'package:restage_shared/restage_shared.dart' show kCapturedEventValueKey;
import 'package:rfw/rfw.dart';

import '../measurement/measurement_rfw_presentation.dart';
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

/// Coerces a flow event payload to the canonical string-keyed args map.
///
/// The single normalization point every render path funnels through — the RFW
/// rendering surfaces and the local-Dart authoring path — so a scalar event
/// value reaches the runtime in one shape on every path and a flow `.capture()`
/// resolves identically. A map is taken as-is; a non-null scalar is carried
/// under the reserved [kCapturedEventValueKey] (the RFW screen blob already
/// wraps it, so this is a no-op there and the active wrap for the local path);
/// a null payload (a value-less event) becomes an empty map.
Map<String, Object?> normalizeEventArgs(Object? args) {
  if (args is Map<String, Object?>) return args;
  if (args is Map) return args.cast<String, Object?>();
  if (args != null) return <String, Object?>{kCapturedEventValueKey: args};
  return <String, Object?>{};
}

/// Populates the RFW data namespaces every flow-screen rendering surface uses.
///
/// [placeholderKeys] is the screen being populated's memoized
/// `data.products.*` reference set (`referencedProductSlots`, walked once by
/// the caller when its library was set — each mounted screen, including a
/// kept-mounted back-stack entry, retains and passes its own), used only
/// when `Restage.hasCommerceContext` is false. [shouldLogPlaceholder]
/// additionally gates whether that no-context branch logs on this call —
/// the caller owns "at most once per screen lifetime" via its own sticky
/// flag, which it should only set after a `true` return, so a call that
/// happened to take the context-present branch first never pre-emptively
/// suppresses the screen's one legitimate placeholder log.
///
/// Returns true iff the no-context (placeholder) branch ran this call.
///
/// [includeInheritedData] is false before a `State` has reached
/// `didChangeDependencies`, because the ambient device/theme values depend on
/// inherited widgets. Product data does not, so it is always published.
bool populateFlowScreenData(
  BuildContext context,
  DynamicContent target, {
  required Map<String, PriceInfo> priceQueries,
  required bool includeInheritedData,
  required Set<String> placeholderKeys,
  required bool shouldLogPlaceholder,
}) {
  final hasCommerceContext =
      Restage.hasCommerceContext(priceQueries: priceQueries);
  if (hasCommerceContext) {
    populateProductData(
      target,
      products: Restage.configuredProducts,
      priceQueries: priceQueries,
    );
  } else {
    populatePlaceholderProductData(
      target,
      placeholderKeys,
      shouldLog: shouldLogPlaceholder,
    );
  }
  if (includeInheritedData) {
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
  return !hasCommerceContext;
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
    installMeasurementRfwPresentationLibrary(runtime);
    return runtime;
  }
}
