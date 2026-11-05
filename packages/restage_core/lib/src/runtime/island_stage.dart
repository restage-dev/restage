import 'package:flutter/widgets.dart';

/// Marks one version of a published surface: shown, or staged beside the
/// shown one while it proves it builds. A staged version builds its islands
/// and the app's global keys only once it is shown, so none is ever built in
/// two versions at once.
final class RestageIslandStage extends InheritedWidget {
  /// Creates a stage marker; a new [generation] rebuilds what reads it.
  const RestageIslandStage({
    required this.candidate,
    required super.child,
    this.generation = 0,
    this.host,
    super.key,
  });

  /// Whether this version is staged and not yet shown.
  final bool candidate;

  /// Changes when what reads the stage must rebuild, such as after a staged
  /// version gave back what it had taken.
  final int generation;

  /// What shows this version, the same object for every version it shows.
  final Object? host;

  /// Whether [context] is inside a staged version.
  static bool isCandidate(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<RestageIslandStage>()
          ?.candidate ??
      false;

  /// The stage element [context] sits in, if any.
  static Element? stageOf(BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<RestageIslandStage>();

  @override
  bool updateShouldNotify(RestageIslandStage oldWidget) =>
      candidate != oldWidget.candidate || generation != oldWidget.generation;

  @override
  InheritedElement createElement() => _RestageIslandStageElement(this);
}

// Builds what reads the stage once per change, in the element tree's order,
// so a version that is shown builds its islands in the order the app's build
// would: what the stage's own update reaches builds there, and the rest after
// it, in tree order.
final class _RestageIslandStageElement extends InheritedElement {
  _RestageIslandStageElement(RestageIslandStage super.widget);

  final List<Element> _notified = [];

  @override
  void notifyDependent(covariant InheritedWidget oldWidget, Element dependent) {
    _notified.add(dependent);
    super.notifyDependent(oldWidget, dependent);
  }

  @override
  void update(covariant RestageIslandStage newWidget) {
    _notified.clear();
    super.update(newWidget);
    if (_notified.isEmpty) return;
    final notified = Set<Element>.identity()..addAll(_notified);
    _notified.clear();
    void visit(Element element) {
      if (element.dirty && notified.contains(element)) element.rebuild();
      element.visitChildren(visit);
    }

    visitChildren(visit);
  }
}
