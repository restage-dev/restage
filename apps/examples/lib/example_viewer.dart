import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a full-screen example surface so the OS status-bar style follows the
/// *surface's* background brightness.
///
/// The gallery imposes no chrome of its own. A surface's screens carry a
/// standard app bar, so the route implies back into the gallery on a single
/// screen and in-flow back on later ones; a paywall keeps its authored close or
/// skip, and the platform back leaves either.
class ExampleViewer extends StatelessWidget {
  /// Wraps [child] with the surface-aware status-bar style.
  const ExampleViewer({
    required this.child,
    this.surfaceBrightness,
    super.key,
  });

  /// The example surface to present.
  final Widget child;

  /// The brightness of *this surface's* background, used to pick a readable OS
  /// status-bar icon color.
  ///
  /// Many of these surfaces are fixed-brightness by design (a bold dark-brand
  /// paywall stays dark under a light app theme), so the status bar follows the
  /// *surface*, not the app theme. Leave `null` for surfaces that adapt.
  final Brightness? surfaceBrightness;

  @override
  Widget build(BuildContext context) {
    final brightness = surfaceBrightness ?? Theme.of(context).brightness;
    // Flutter's overlay-style naming is inverted: `.light` paints *light*
    // status-bar icons (for a dark surface); `.dark` paints *dark* icons (for a
    // light surface). Transparent bar so the surface shows through.
    final overlayStyle = (brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(statusBarColor: Colors.transparent);
    // A fixed-brightness surface also gets a theme of that brightness, so the
    // app's page transition paints its scrim in a matching surface color
    // instead of flashing the app theme's between two dark screens.
    final theme = Theme.of(context);
    final themed =
        surfaceBrightness == null || theme.brightness == surfaceBrightness
            ? child
            : Theme(
                data: ThemeData(
                  useMaterial3: true,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: theme.colorScheme.primary,
                    brightness: surfaceBrightness!,
                  ),
                ),
                child: child,
              );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: themed,
    );
  }
}
