import 'package:flutter/widgets.dart';
import 'package:restage_core/restage_core.dart' show RestageIslandStage;
import 'library_runtime_registry.dart';
import 'package:rfw/rfw.dart' show RemoteWidgetLibrary, WidgetLibrary;

/// How a host shows a candidate version beside the shown one.
///
/// A candidate that waits offstage is laid out but not painted until it is
/// shown. It is then shown in the same frame as it takes what the shown
/// version held, so its first paint commits it and only then counts. Other
/// candidates paint above the shown version, inert until they commit.
final class OffstageCandidates {
  final _waiting = Expando<bool>('offstage candidate');
  // Once shown, a version never waits again, also when it comes back after
  // a later candidate failed.
  final _shown = Expando<bool>('shown candidate');
  int _generation = 0;

  /// The one routing choice: candidates that draw a package's islands wait
  /// offstage.
  static bool routesOffstage(WidgetLibrary? library) =>
      library is RemoteWidgetLibrary &&
      library.imports.any((import) =>
          LibraryRuntimeRegistry.isIslandLibrary(import.name.parts.join('.')));

  /// Whether [candidate] has been shown, so the shown version leaves the tree.
  bool isShown(Object? candidate) =>
      candidate != null && (_shown[candidate] ?? false);

  /// Routes [candidate] by its [library], and offstage when it shows a flow
  /// [step] that hosts the app's State.
  void route(Object candidate, WidgetLibrary? library, {bool step = false}) {
    if (step || routesOffstage(library)) _waiting[candidate] = true;
  }

  /// Shows an offstage [candidate] after the frame that laid it out, when
  /// [mayReplace] still holds; otherwise [reject]s it.
  void showAfterLayout(
    Object candidate, {
    required bool Function() mayReplace,
    required void Function(VoidCallback) setState,
    required VoidCallback reject,
  }) {
    if (_waiting[candidate] != true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isShown(candidate)) return;
      if (!mayReplace()) return reject();
      setState(() => _shown[candidate] = true);
    });
  }

  /// Lets the shown version rebuild what a dropped candidate took.
  void release() => _generation++;

  /// Wraps a [candidate]'s layer: offstage while it waits, inert while it is
  /// staged or uncommitted.
  Widget layer(
    Object candidate, {
    required bool inert,
    required Widget child,
  }) {
    final waits = _waiting[candidate] == true && !isShown(candidate);
    return RestageIslandStage(
      candidate: _waiting[candidate] == true ? waits : inert,
      generation: _generation,
      host: this,
      child: Offstage(
        offstage: waits,
        child: ExcludeSemantics(
          excluding: inert,
          child: AbsorbPointer(absorbing: inert, child: child),
        ),
      ),
    );
  }
}
