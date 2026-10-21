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

/// Labels [child] with [label] when source badges are on in a debug build.
///
/// A parent-data widget such as `Expanded` is returned unlabeled.
@internal
Widget withSourceBadge(String Function() label, Widget child) {
  if (!kDebugMode || !Restage.showSourceBadges || child is ParentDataWidget) {
    return child;
  }
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
    ],
  );
}
