import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart' show immutable;
import 'package:restage_core/restage_core.dart'
    show InstalledIconTable, RestageIconTable;

import 'library_runtime_registry.dart';
import 'restage_widget_libraries.dart';
import 'restage_widget_library_registration.dart';

/// Renders a flow step's delivered content [child] with what the app computes
/// for it, reading the step's inputs from [original], the step widget the app
/// built for this frame.
typedef RestageStepMount = Widget Function(
  BuildContext context,
  Widget child,
  Widget original,
);

/// Values a generated step mount supplies to its step's delivered content.
final class RestageStepValues extends InheritedWidget {
  /// Supplies [values] to the step content in [child].
  const RestageStepValues({
    required this.values,
    required super.child,
    this.built,
    super.key,
  });

  /// The step as the mount's build produced it, rendered where no delivered
  /// content stands in for it.
  final Widget? built;

  /// Values by name.
  final Map<String, Object?> values;

  /// The values above [context], if any.
  static Map<String, Object?>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RestageStepValues>()?.values;

  @override
  bool updateShouldNotify(RestageStepValues oldWidget) =>
      !identical(values, oldWidget.values) ||
      !identical(built, oldWidget.built);
}

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
    this.stepMounts = const <String, RestageStepMount>{},
  });

  /// A vocabulary naming no widget and no icon.
  static const SurfaceVocabulary none = SurfaceVocabulary();

  /// The built-in widgets the surface draws, per namespace.
  final RestageWidgetLibraries widgets;

  /// The icons the surface draws, per font family.
  final RestageIconTable icons;

  /// The app widgets the surface draws, per custom library.
  final List<RestageWidgetLibraryRegistration> libraries;

  /// Mounts for flow steps that render with the app's code, by screen.
  ///
  /// Nothing is installed for them, so they do not count toward [isEmpty].
  final Map<String, RestageStepMount> stepMounts;

  /// Whether the vocabulary names nothing at all.
  bool get isEmpty => widgets.isEmpty && icons.isEmpty && libraries.isEmpty;

  /// Adds this vocabulary to the process-wide stores.
  ///
  /// Entries already installed keep their meaning, so calling this repeatedly
  /// — on every mount of the same surface — installs the same thing once.
  /// [explicitSelection] records an app's generated widget catalog policy even
  /// when its vocabulary is empty. Surface mounts leave it false and only add what
  /// they draw. Neither form changes the identity of an empty installation.
  void addToInstalled({bool explicitSelection = false}) {
    InstalledWidgetLibraries.add(widgets, explicitSelection: explicitSelection);
    InstalledIconTable.add(icons);
    libraries.forEach(LibraryRuntimeRegistry.install);
  }
}
