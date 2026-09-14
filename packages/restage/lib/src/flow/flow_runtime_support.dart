import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart'
    show BuildContext, DefaultTextStyle, Locale, Localizations, MediaQuery;
import 'package:restage_shared/restage_shared.dart' show kCapturedEventValueKey;
import 'package:rfw/rfw.dart';

import '../measurement/measurement_rfw_presentation.dart';
import '../runtime/context_data.dart';
import '../runtime/library_runtime_registry.dart';
import '../runtime/restage_widget_libraries.dart';
import '../runtime/state_variables.dart'
    show currentDevicePlatform, populateDeviceData, populateThemeData;

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
/// [includeInheritedData] is false before a `State` has reached
/// `didChangeDependencies`, because the ambient device/theme values depend on
/// inherited widgets.
/// [contextPublisher] publishes [hostContext] independently of inherited data.
void populateFlowScreenData(
  BuildContext context,
  DynamicContent target, {
  required bool includeInheritedData,
  ContextPublisher? contextPublisher,
  ContextSnapshot? hostContext,
}) {
  assert(
    hostContext == null || contextPublisher != null,
    'hostContext requires a contextPublisher bound to the target.',
  );
  contextPublisher?.publishSnapshot(hostContext);
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
    textTheme: theme.textTheme,
  );
}

/// A fresh [Runtime] importing the installed base widget libraries (core /
/// material / cupertino) plus the given [screen] blob under
/// [kFlowScreenLibrary], with the custom widget registry applied.
///
/// The installed libraries are read here, as the runtime is built, so a screen
/// assembled after another surface installs its own vocabulary renders with
/// everything installed by then. Each screen visit gets its own [Runtime], so
/// screens never share live render state.
Runtime flowScreenRuntime(WidgetLibrary screen) {
  final runtime = Runtime();
  InstalledWidgetLibraries.current.installInto(
    runtime,
    coreName: kFlowCoreLibrary,
    materialName: kFlowMaterialLibrary,
    cupertinoName: kFlowCupertinoLibrary,
  );
  runtime.update(kFlowScreenLibrary, screen);
  LibraryRuntimeRegistry.applyTo(runtime);
  installMeasurementRfwPresentationLibrary(runtime);
  return runtime;
}
