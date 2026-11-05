import 'package:flutter/foundation.dart';
import 'package:restage_shared/rfw_formats.dart' as shared;
import 'package:rfw/formats.dart' as rfw;

import 'library_runtime_registry.dart';
import 'restage.dart';
import 'restage_widget_libraries.dart';

// A context key the compiler owns: only a generated widget computes it.
final RegExp _computedKey = RegExp(r'^_h[0-9a-f]{10}$');

/// Whether [library], decoded from [blob], reads values or places app
/// widgets that only a generated widget provides and its host doesn't: a
/// computed key missing from [provided], or an island rendering [root] places
/// outside every split widget's body with no [islandsHosted] scope.
@internal
bool needsGeneratedSurface(
  rfw.WidgetLibrary library,
  Uint8List blob, {
  required String root,
  required Set<String> provided,
  required bool islandsHosted,
}) {
  if (library is! rfw.RemoteWidgetLibrary) return false;
  final islandImports = {
    for (final import in library.imports)
      if (import.name.parts.last == 'islands') import.name.parts.join('.'),
  };
  if (!islandsHosted &&
      islandImports.isNotEmpty &&
      _placesIslandOutsideSplitBodies(
          shared.decodeLibraryBlob(blob), root, islandImports)) {
    return true;
  }
  bool missing(String key) =>
      _computedKey.hasMatch(key) && !provided.contains(key);
  bool reads(Object? value) => switch (value) {
        rfw.DataReference(:final parts) => parts.length >= 2 &&
            parts.first == 'context' &&
            parts[1] is String &&
            missing(parts[1] as String),
        {'kind': 'nativeBinding', 'key': final String key} => missing(key),
        rfw.ConstructorCall(:final arguments) => reads(arguments),
        rfw.Loop(:final input, :final output) => reads(input) || reads(output),
        rfw.Switch(:final input, :final outputs) =>
          reads(input) || outputs.values.any(reads),
        rfw.WidgetBuilderDeclaration(:final widget) => reads(widget),
        rfw.EventHandler(:final eventArguments) => reads(eventArguments),
        rfw.SetStateHandler(:final value) => reads(value),
        final Map<Object?, Object?> map => map.values.any(reads),
        final List<Object?> list => list.any(reads),
        _ => false,
      };
  return library.widgets.any((widget) => reads(widget.root));
}

// A split widget's wrapper provides the islands its body places; any other
// island needs the surface's generated widget. A name no installed library
// declares, the host's own included, is taken as an island.
bool _placesIslandOutsideSplitBodies(
  shared.RemoteWidgetLibrary library,
  String root,
  Set<String> islandImports,
) {
  final registrations = LibraryRuntimeRegistry.registrationSnapshot();
  final local = {for (final widget in library.widgets) widget.name};
  final islands = <String>{};
  final others = <String>{};
  for (final registration in registrations) {
    final names = registration.widgets.map((widget) => widget.name);
    if (registration.islands) {
      if (islandImports.contains(registration.library.namespace)) {
        islands.addAll(names);
      }
    } else {
      others.addAll(names);
    }
  }
  final builtIn = InstalledWidgetLibraries.current;
  bool declaredElsewhere(String name) =>
      local.contains(name) ||
      others.contains(name) ||
      shared.kHostInstalledRfwLibraries
          .any((library) => library.constructors.contains(name)) ||
      builtIn.core.containsKey(name) ||
      builtIn.material.containsKey(name) ||
      builtIn.cupertino.containsKey(name);
  return shared.rfwPlacesIslandOutsideSplitBodies(
    library,
    root,
    isSplitWrapper: (name) =>
        name.endsWith(shared.kSplitWrapperSuffix) && others.contains(name),
    isIsland: (name) => islands.contains(name) || !declaredElsewhere(name),
  );
}

/// Whether the fit failure [token] names what only a generated widget
/// provides: a value it computes or an app widget it places.
@internal
bool fitTokenNeedsGeneratedSurface(String token) {
  if (token.startsWith('missingIsland:')) return true;
  const prefix = 'missingHostField:';
  if (!token.startsWith(prefix)) return false;
  final subject = token.substring(prefix.length).split(RegExp('[@;]')).first;
  return _computedKey.hasMatch(subject);
}

/// The refusal for paywall [id] shown without its generated widget.
@internal
String generatedSurfaceRequiredMessage(String id) {
  final surface = Restage.paywallSurfaceWidget(id);
  if (surface == null) {
    return "`RestagePaywall(id: '$id')` shows a design that needs values from "
        'its generated widget. Try showing that widget instead of '
        '`RestagePaywall`.';
  }
  return "`RestagePaywall(id: '$id')` shows a design that needs values from "
      'the generated `$surface`. Try showing `$surface` instead.';
}

final Set<String> _logged = {};

/// Prints [message] once per paywall [id] in debug builds.
@internal
void debugLogGeneratedSurfaceRequired(String id, String message) {
  if (!kDebugMode || !_logged.add(id)) return;
  debugPrint('[restage] $message');
}

/// Forgets which refusals were printed.
@internal
void resetGeneratedSurfaceLog() => _logged.clear();
