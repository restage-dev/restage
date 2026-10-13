import 'package:meta/meta.dart' show immutable;
import 'package:restage_core/restage_core.dart'
    show InstalledIconTable, RestageIconTable;

import 'library_runtime_registry.dart';
import 'restage_widget_libraries.dart';
import 'restage_widget_library_registration.dart';

/// Widgets and icons installed before a generated surface mounts.
/// Each surface names its required built-ins, app widgets and icon codepoints;
/// unreferenced built-ins can be removed from the build.
@immutable
final class SurfaceVocabulary {
  /// Creates a vocabulary from the widgets and icons a surface draws.
  ///
  /// Every part defaults to empty, so a surface naming no icon omits [icons].
  const SurfaceVocabulary({
    this.widgets = RestageWidgetLibraries.none,
    this.icons = RestageIconTable.none,
    this.libraries = const <RestageWidgetLibraryRegistration>[],
  });

  /// A vocabulary naming no widget and no icon.
  static const SurfaceVocabulary none = SurfaceVocabulary();

  /// The built-in widgets the surface draws, per namespace.
  final RestageWidgetLibraries widgets;

  /// The icons the surface draws, per font family.
  final RestageIconTable icons;

  /// The app widgets the surface draws, per custom library.
  final List<RestageWidgetLibraryRegistration> libraries;

  /// Whether the vocabulary names nothing at all.
  bool get isEmpty => widgets.isEmpty && icons.isEmpty && libraries.isEmpty;

  /// Adds this vocabulary to the process-wide stores.
  ///
  /// Entries already installed keep their meaning, so calling this repeatedly
  /// — on every mount of the same surface — installs the same thing once.
  /// [explicitSelection] records an app's generated catalog policy even when
  /// its vocabulary is empty. Surface mounts leave it false and only add what
  /// they draw. Neither form changes the identity of an empty installation.
  void addToInstalled({bool explicitSelection = false}) {
    InstalledWidgetLibraries.add(widgets, explicitSelection: explicitSelection);
    InstalledIconTable.add(icons, explicitSelection: explicitSelection);
    libraries.forEach(LibraryRuntimeRegistry.install);
  }
}
