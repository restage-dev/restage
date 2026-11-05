import 'package:flutter/widgets.dart';

import 'compiled_flow.dart';

/// The app's screen builders from its latest build of the flow's host, so a
/// step rebuilds when the app rebuilds the host and not otherwise.
final class FlowScreenBuilders extends InheritedWidget {
  /// Supplies [builders] to the flow below.
  const FlowScreenBuilders({
    required this.builders,
    required super.child,
    super.key,
  });

  /// Builders by screen artifact id.
  final Map<String, CompiledFlowScreenBuilder> builders;

  /// The builders above [context], registering a dependency; null without a
  /// host that supplies them.
  static Map<String, CompiledFlowScreenBuilder>? of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FlowScreenBuilders>()
          ?.builders;

  /// Whether a host above [context] supplies builders.
  static bool suppliedAbove(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FlowScreenBuilders>() != null;

  @override
  bool updateShouldNotify(FlowScreenBuilders oldWidget) =>
      !identical(builders, oldWidget.builders);
}
