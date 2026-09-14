import 'package:meta/meta.dart' show immutable;
import 'package:restage_core/library_registration.dart' as restage_core;
import 'package:restage_cupertino/library_registration.dart'
    as restage_cupertino;
import 'package:restage_material/library_registration.dart' as restage_material;
import 'package:rfw/rfw.dart'
    show LibraryName, LocalWidgetBuilder, LocalWidgetLibrary, Runtime;

import 'library_runtime_registry.dart';

// Reported when a surface runtime can resolve no widget at all; names the fix.
const String _noWidgetsAvailableMessage =
    'This Restage surface can resolve no widget: no built-in widgets are '
    'installed and no custom widget library is registered. Generated surface '
    'code installs the widgets its own surface draws, so check that the '
    'surface is mounted through its generated reference. A preview or '
    'authoring tool that renders content it cannot know ahead of time '
    'installs the whole catalog with '
    'InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn()).';

/// The built-in widgets a Restage surface can render, as one builder map per
/// namespace.
///
/// A delivered surface document imports the `restage.core`,
/// `restage.material` and `restage.cupertino` namespaces, and this value
/// decides what each of them contains for this app. Ordinary
/// `Restage.configure()` supplies the whole catalog unless an explicit
/// selection already exists. With `Restage.configureWithInstalledCatalog()`,
/// generated registration and surface references supply the selected widgets.
///
/// A host can also install the whole catalog directly during app startup:
///
/// ```dart
/// void main() {
///   InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
///   runApp(const MyApp());
/// }
/// ```
///
/// See also:
///
///  * [InstalledWidgetLibraries], the process-wide store surfaces read.
@immutable
final class RestageWidgetLibraries {
  /// Creates the libraries from an explicit per-namespace vocabulary.
  ///
  /// Each map is keyed by the unqualified widget name within its namespace and
  /// carries that widget's builder. An omitted namespace contributes nothing.
  ///
  /// The maps are stored exactly as given — nothing is copied, sorted or
  /// canonicalized — so this is usable as a `const` expression.
  const RestageWidgetLibraries.fromVocabulary({
    this.core = const <String, LocalWidgetBuilder>{},
    this.material = const <String, LocalWidgetBuilder>{},
    this.cupertino = const <String, LocalWidgetBuilder>{},
  });

  /// Creates the full core catalog and the selected complete widget families.
  ///
  /// Ordinary `Restage.configure()` uses this when no catalog selection exists.
  /// Both families default to included. Excluding a full family does not
  /// remove entries already installed by the app or a generated surface.
  factory RestageWidgetLibraries.builtIn({
    bool includeMaterial = true,
    bool includeCupertino = true,
  }) {
    // Not const, so the catalog maps enter a build only through a real call to
    // this factory.
    // ignore: prefer_const_constructors
    return RestageWidgetLibraries.fromVocabulary(
      core: restage_core.kCoreLibraryFactories,
      material: includeMaterial
          ? restage_material.kMaterialLibraryFactories
          : const {},
      cupertino: includeCupertino
          ? restage_cupertino.kCupertinoLibraryFactories
          : const {},
    );
  }

  /// Libraries that contribute no widget at all.
  static const RestageWidgetLibraries none =
      RestageWidgetLibraries.fromVocabulary();

  /// Builders contributed to the `restage.core` namespace.
  final Map<String, LocalWidgetBuilder> core;

  /// Builders contributed to the `restage.material` namespace.
  final Map<String, LocalWidgetBuilder> material;

  /// Builders contributed to the `restage.cupertino` namespace.
  final Map<String, LocalWidgetBuilder> cupertino;

  /// Whether all three namespaces are empty.
  bool get isEmpty => core.isEmpty && material.isEmpty && cupertino.isEmpty;

  /// Installs the non-empty namespaces into [runtime] under the given names.
  ///
  /// The names are parameters because a paywall runtime and a flow screen
  /// runtime import the same namespaces under their own [LibraryName]
  /// constants. A namespace with no builders is skipped rather than installed
  /// empty, so an unused namespace stays absent from the runtime.
  ///
  /// A surface drawing only the application's own widgets legitimately carries
  /// no built-in widget at all, and those widgets reach the runtime through
  /// their own registration. Only a runtime that can resolve nothing — no
  /// built-in widget and no registered library — is a wiring mistake: it
  /// asserts in debug, and in release the mount resolves no widget and the
  /// surface takes its usual unavailable path.
  void installInto(
    Runtime runtime, {
    required LibraryName coreName,
    required LibraryName materialName,
    required LibraryName cupertinoName,
  }) {
    assert(
      !isEmpty || LibraryRuntimeRegistry.hasRegistrations,
      _noWidgetsAvailableMessage,
    );
    if (core.isNotEmpty) {
      runtime.update(coreName, LocalWidgetLibrary(core));
    }
    if (material.isNotEmpty) {
      runtime.update(materialName, LocalWidgetLibrary(material));
    }
    if (cupertino.isNotEmpty) {
      runtime.update(cupertinoName, LocalWidgetLibrary(cupertino));
    }
  }
}

/// Process-wide store of the [RestageWidgetLibraries] every Restage surface
/// installs when it mounts.
///
/// Each generated surface [add]s the widgets it draws as it mounts, and the
/// SDK reads [current] each time it assembles a surface runtime. The store
/// starts empty; ordinary `Restage.configure()` supplies the full catalog
/// only when no selection has been made.
abstract final class InstalledWidgetLibraries {
  InstalledWidgetLibraries._();

  static RestageWidgetLibraries _installed = RestageWidgetLibraries.none;
  static bool _hasSelection = false;

  /// Whether an installation or an explicit app vocabulary chose this store.
  ///
  /// An explicitly empty selection is distinct from an unconfigured store.
  static bool get hasSelection => _hasSelection;

  /// The installed libraries — [RestageWidgetLibraries.none] until [install].
  static RestageWidgetLibraries get current => _installed;

  /// Installs [libraries] for the rest of the process, replacing any prior
  /// installation.
  ///
  /// Replacing discards whatever a mounted surface already contributed through
  /// [add], so an app that installs explicitly does it before mounting any
  /// surface.
  ///
  /// For a preview or authoring tool that renders content it cannot know ahead
  /// of time: call once from app startup, before mounting a surface. An
  /// application's surfaces install what they draw through [add] instead.
  static void install(RestageWidgetLibraries libraries) {
    _hasSelection = true;
    _installed = libraries;
  }

  /// Adds [libraries] to what is already installed, one union per namespace.
  ///
  /// Where both carry the same widget name, the already-installed builder
  /// wins, so adding never changes the meaning of a name a surface already
  /// renders. Adding [RestageWidgetLibraries.none] preserves the current object.
  /// Omitting [explicitSelection] treats a nonempty direct addition as an app
  /// selection. Pass false for an implicit surface contribution, or true to
  /// record an explicit selection even when empty. Only an explicit selection
  /// prevents ordinary configuration from widening to the full default.
  static void add(RestageWidgetLibraries libraries, {bool? explicitSelection}) {
    _hasSelection = _hasSelection || (explicitSelection ?? !libraries.isEmpty);
    if (libraries.isEmpty) return;
    final installed = _installed;
    _installed = RestageWidgetLibraries.fromVocabulary(
      core: _unionBuilders(installed.core, libraries.core),
      material: _unionBuilders(installed.material, libraries.material),
      cupertino: _unionBuilders(installed.cupertino, libraries.cupertino),
    );
  }

  /// Drops the installation and restores the [RestageWidgetLibraries.none]
  /// default, so a test cannot leak its installation into the next one.
  static void reset() {
    _hasSelection = false;
    _installed = RestageWidgetLibraries.none;
  }
}

// Unions one namespace, keeping the installed builder on a shared name.
Map<String, LocalWidgetBuilder> _unionBuilders(
  Map<String, LocalWidgetBuilder> installed,
  Map<String, LocalWidgetBuilder> added,
) {
  if (added.isEmpty) return installed;
  if (installed.isEmpty) return added;
  return <String, LocalWidgetBuilder>{...added, ...installed};
}
