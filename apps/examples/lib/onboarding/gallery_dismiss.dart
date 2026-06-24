import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A persistent "close to gallery" (×) affordance for the engagement-surface
/// demos.
///
/// The gallery hosts each engagement surface full-bleed with the gallery's own
/// escape control turned off, on the theory that the flow's own back chrome plus
/// the platform system-back keep it escapable. That theory does not hold on iOS:
/// the edge-swipe does not reliably drive the flow's `popHost` system-back, so a
/// flow whose first screen has no visible back affordance (the SDK chevron is
/// shown only once there is in-flow history) — and any host-owned terminal
/// outcome screen — would otherwise trap the user with no way back to the
/// gallery.
///
/// This is a *demo-host* affordance, not a flow feature: a real app drives these
/// surfaces from app navigation and rarely needs a gallery-style close. It calls
/// [Navigator.maybePop] on the surface's host route so a tap returns to the
/// gallery on every platform, independent of the unreliable iOS edge-swipe.
class GalleryDismissButton extends StatelessWidget {
  /// Creates the close affordance. [color] tints the glyph for legibility over
  /// the surface; [scrim] is the translucent disc behind it (transparent for a
  /// terminal screen that needs no scrim).
  const GalleryDismissButton({
    super.key,
    this.color = Colors.white,
    this.scrim = const Color(0x33000000),
  });

  /// The glyph tint, chosen for contrast against the surface behind it.
  final Color color;

  /// The translucent disc behind the glyph. Transparent disables the scrim.
  final Color scrim;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Semantics(
          button: true,
          label: 'Close',
          child: GestureDetector(
            key: const Key('gallery-dismiss'),
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: DecoratedBox(
              decoration: BoxDecoration(color: scrim, shape: BoxShape.circle),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: ExcludeSemantics(
                  child: Icon(Icons.close_rounded, color: color, size: 22),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frames a flow [body] with persistent chrome that keeps the surface escapable
/// to the gallery: a top-left back chevron while in-flow back is available
/// ([FlowChromeState.canBack]) and a top-right [GalleryDismissButton] that is
/// always present.
///
/// This supersedes the SDK's built-in persistent chrome (the auto-shown back
/// chevron), so the back chevron is re-drawn here from [state] — there is one
/// coherent chrome with exactly one back control and one close control, never a
/// stacked pair. [backColor] tints the chevron; [closeColor] / [closeScrim] tint
/// the close affordance.
class GalleryFlowChrome extends StatelessWidget {
  /// Frames [body] with the gallery-escape chrome read from [state].
  const GalleryFlowChrome({
    super.key,
    required this.state,
    required this.body,
    this.backColor = Colors.white,
    this.closeColor = Colors.white,
    this.closeScrim = const Color(0x33000000),
  });

  /// The runtime chrome snapshot (drives the back chevron's visibility).
  final FlowChromeState state;

  /// The animated flow screen stack to frame.
  final Widget body;

  /// The back chevron's tint.
  final Color backColor;

  /// The close glyph's tint.
  final Color closeColor;

  /// The close affordance's scrim disc.
  final Color closeScrim;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: body),
        // Top-right: the always-present close-to-gallery affordance.
        Positioned(
          top: 0,
          right: 0,
          child: GalleryDismissButton(color: closeColor, scrim: closeScrim),
        ),
        // Top-left: the in-flow back chevron, shown only with history to pop.
        if (state.canBack)
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Semantics(
                  button: true,
                  label: 'Back',
                  child: GestureDetector(
                    key: const Key('gallery-flow-back'),
                    behavior: HitTestBehavior.opaque,
                    onTap: state.onBack,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: closeScrim,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: ExcludeSemantics(
                          child: Icon(
                            Icons.arrow_back,
                            color: backColor,
                            size: 22,
                          ),
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
}
