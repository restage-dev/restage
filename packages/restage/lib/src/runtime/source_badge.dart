import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../resolver/surface_resolution_report.dart';
import 'restage.dart';

/// The badge label for content from [source] at [version].
@internal
String sourceBadgeLabel(SurfaceResolutionSource? source, Object? version) =>
    switch (source) {
      SurfaceResolutionSource.fresh ||
      SurfaceResolutionSource.holdLastGood =>
        version == null ? 'delivered' : 'delivered r$version',
      _ => 'compiled',
    };

/// The badge label for compiled content shown while delivered content at
/// [version] arrived too late for this mount; the next mount shows it.
@internal
String lateSourceBadgeLabel(Object? version) => version == null
    ? 'compiled · next mount'
    : 'compiled · r$version next mount';

/// What [lateSourceBadgeLabel] means, for a screen reader or a test.
@internal
String lateSourceBadgeDescription(Object? version) => version == null
    ? 'Showing the compiled screen. A delivered version arrived after it '
        'painted and shows on the next mount.'
    : 'Showing the compiled screen. Version r$version arrived after it '
        'painted and shows on the next mount.';

/// Labels [child] with [label] when source badges are on in a debug build;
/// [description], when given, is what a screen reader announces.
///
/// A parent-data widget such as `Expanded` is returned unlabeled.
@internal
Widget withSourceBadge(String Function() label, Widget child,
    {String? Function()? description}) {
  if (!kDebugMode || !Restage.showSourceBadges || child is ParentDataWidget) {
    return child;
  }
  final announced = description?.call();
  return Stack(
    fit: StackFit.passthrough,
    children: [
      child,
      Positioned(
        top: 0,
        left: 0,
        child: IgnorePointer(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ColoredBox(
              color: const Color(0xCC000000),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Semantics(
                  label: announced,
                  excludeSemantics: announced != null,
                  child: Text(
                    label(),
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 10,
                      height: 1.2,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
