import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a full-screen example surface with a floating "back to examples"
/// button so the gallery menu is always reachable.
///
/// The example paywalls and engagement screens are intentionally full-bleed —
/// real paywalls fill the screen and have no app bar (they're dismissed by a
/// purchase / restore / close, not a navigation back arrow). The gallery is a
/// browser for those surfaces, so it overlays a small, unobtrusive back control
/// rather than putting an app bar on top of each example (which would spoil the
/// full-screen presentation the templates are demonstrating).
///
/// The control sits in the top-left safe area on a translucent scrim so it
/// stays legible over any background — light, dark, or a brand gradient.
///
/// Set [showBackButton] to `false` for engagement surfaces (onboarding,
/// messages) whose own flow chrome owns the top-left back affordance: a gallery
/// escape there would sit on top of the flow's own back chevron. Those surfaces
/// stay escapable — the platform system-back returns to the gallery once the
/// flow's in-flow back is exhausted, and completing the flow hands off to a
/// paywall, which carries its own escape.
class ExampleViewer extends StatelessWidget {
  const ExampleViewer({
    required this.child,
    this.showBackButton = true,
    this.surfaceBrightness,
    super.key,
  });

  final Widget child;

  /// Whether to overlay the floating "back to examples" escape control.
  final bool showBackButton;

  /// The brightness of *this surface's* background, used to pick a readable OS
  /// status-bar icon color. A full-screen example fills the screen with no app
  /// bar, so nothing else sets the status-bar style for it.
  ///
  /// Many of these surfaces are fixed-brightness by design (a bold dark-brand
  /// paywall stays dark even under a light app theme), so the status bar must
  /// follow the *surface*, not the app theme. Pass the surface's actual
  /// background brightness here; leave `null` for surfaces that adapt to the
  /// app theme (those painting on `Theme.of(context).colorScheme.surface`),
  /// which then follow the ambient theme brightness.
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Stack(
        children: [
          Positioned.fill(child: child),
          if (showBackButton)
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: 'Back to examples',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
