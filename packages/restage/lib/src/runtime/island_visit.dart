import 'package:flutter/widgets.dart';

/// Marks one visit of a flow screen; islands below it key per visit.
final class IslandVisit extends InheritedWidget {
  /// Marks [child] as the visit [visit].
  const IslandVisit({required this.visit, required super.child, super.key});

  /// The visit, unique among the visits of one flow.
  final int visit;

  /// The visit [context] sits in, if any.
  static int? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<IslandVisit>()?.visit;

  @override
  bool updateShouldNotify(IslandVisit oldWidget) => visit != oldWidget.visit;
}
