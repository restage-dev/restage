import 'package:meta/meta.dart' show immutable;
import 'package:restage_core/restage_core.dart'
    show InstalledIconTable, RestageIconTable;

import 'restage_widget_libraries.dart';

/// The widgets and icons one surface draws, in the form its app installs.
///
/// Generated surface code carries a `const` vocabulary naming exactly the
/// built-in widgets and icon code points that surface's document references,
/// and the SDK adds it to the process-wide stores before the surface mounts.
/// An app that renders several surfaces installs several vocabularies, and
/// the widgets no surface names stay out of the build.
@immutable
final class SurfaceVocabulary {
  /// Creates a vocabulary from the widgets and icons a surface draws.
  ///
  /// Both parts default to empty, so a surface naming no icon omits [icons].
  const SurfaceVocabulary({
    this.widgets = RestageWidgetLibraries.none,
    this.icons = RestageIconTable.none,
  });

  /// A vocabulary naming no widget and no icon.
  static const SurfaceVocabulary none = SurfaceVocabulary();

  /// The built-in widgets the surface draws, per namespace.
  final RestageWidgetLibraries widgets;

  /// The icons the surface draws, per font family.
  final RestageIconTable icons;

  /// Whether the vocabulary names nothing at all.
  bool get isEmpty => widgets.isEmpty && icons.isEmpty;

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
  }
}
