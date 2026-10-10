import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart' show internal;

import '../events/restage_event.dart' show RestageEvent;

/// Carries a placement's event callback to the host it directly wraps.
@internal
final class PlacementEventScope extends InheritedWidget {
  const PlacementEventScope(
      {super.key, required this.onEvent, required super.child});

  final void Function(RestageEvent event) onEvent;

  /// The callback for [host], only when [host] is this scope's direct child.
  static void Function(RestageEvent event)? callbackFor(
      BuildContext context, Widget host) {
    final scope = context.getInheritedWidgetOfExactType<PlacementEventScope>();
    return scope != null && identical(scope.child, host) ? scope.onEvent : null;
  }

  @override
  bool updateShouldNotify(PlacementEventScope oldWidget) => false;
}
