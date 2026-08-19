import 'package:flutter/widgets.dart';

import 'surface_screen_types.dart';

/// Builds host UI for an unavailable standalone screen.
typedef SurfaceScreenUnavailableBuilder = Widget Function(
  BuildContext context,
  SurfaceScreenUnavailableError error,
);

/// Required unavailable behavior for a standalone screen host.
///
/// This lives apart from the rest of the standalone-screen types because it is
/// the only part of them that is Flutter-typed. Keeping it here leaves
/// [SurfaceScreenUnavailableError] and its siblings — and everything that
/// reaches them, including the generated flow descriptors — importable from
/// pure Dart, so generated descriptors stay consumable by Dart-only tooling.
@immutable
final class SurfaceScreenUnavailablePolicy {
  /// Shows host-provided fallback UI when the screen is unavailable.
  const SurfaceScreenUnavailablePolicy.fallback({
    required SurfaceScreenUnavailableBuilder builder,
  })  : fallbackBuilder = builder,
        hide = false;

  /// Hides the screen when it is unavailable.
  const SurfaceScreenUnavailablePolicy.hide()
      : fallbackBuilder = null,
        hide = true;

  /// The fallback builder, when this policy presents fallback UI.
  final SurfaceScreenUnavailableBuilder? fallbackBuilder;

  /// Whether unavailable screen UI is intentionally hidden.
  final bool hide;
}
