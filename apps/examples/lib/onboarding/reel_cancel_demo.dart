import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'flows/reel_cancel.dart';
import 'gallery_dismiss.dart';

/// Hosts the "before you cancel" retention-survey engagement surface.
///
/// The host side: supply the `redeemOffer` host action, act on the two outcomes,
/// and fail closed. It does what a real app does:
///
/// 1. **Supplies the host action.** A real app applies the retention discount
///    through billing and returns the result; this demo returns a fixed
///    [redeemOffer] decision so both branches are exercisable. The flow advances
///    to the confirmation **only on a redeemed result** — the save-offer gate is
///    the one conditional the flow runtime offers.
/// 2. **Owns the "cancel" outcome.** The save-offer's "No thanks, cancel" fires a
///    `cancel` custom event the flow does not handle; the host listens for it and
///    confirms the cancellation.
/// 3. **Fails closed.** An unavailable flow shows a plain surface, never a
///    broken or partial one.
///
/// Like the other examples it ships its flow as a bundled asset (no backend). A
/// production app delivers it over the air by injecting a `ServerFlowResolver`.
class ReelCancelDemo extends StatefulWidget {
  /// Creates the survey host.
  ///
  /// [redeemOffer] is the decision the demo's retention host action returns.
  /// `true` walks the retained path (the offer redeems → the confirmation);
  /// `false` walks the failed-redemption path (the gate holds on the save-offer
  /// — the flow never proceeds on a redemption it did not get).
  const ReelCancelDemo({super.key, this.redeemOffer = true});

  /// The fixed redemption decision this demo returns from the host action.
  final bool redeemOffer;

  @override
  State<ReelCancelDemo> createState() => _ReelCancelDemoState();
}

enum _Outcome { none, retained, cancelled }

class _ReelCancelDemoState extends State<ReelCancelDemo> {
  late final ReelCancelActions _actions;
  StreamSubscription<RestageEvent>? _events;
  _Outcome _outcome = _Outcome.none;

  @override
  void initState() {
    super.initState();
    _actions = ReelCancelActions(
      redeemOffer: (args, context) async {
        // A real app applies the retention discount through billing here and
        // returns the result. The demo returns a fixed decision so both
        // branches are exercisable.
        return OfferDecision(redeemed: widget.redeemOffer);
      },
    );
    _events = Restage.events.listen((event) {
      if (event is FlowCustomEvent &&
          event.flowId == 'reel_cancel' &&
          event.eventName == 'cancel') {
        _settle(_Outcome.cancelled);
      }
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  void _settle(_Outcome outcome) {
    if (_outcome != _Outcome.none || !mounted) return;
    setState(() => _outcome = outcome);
  }

  @override
  Widget build(BuildContext context) {
    if (_outcome != _Outcome.none) {
      return _OutcomeScreen(retained: _outcome == _Outcome.retained);
    }
    return RestageOnboarding<ReelCancelResult>(
      flow: ReelCancelFlowDescriptor.ref,
      actions: _actions,
      onComplete: (result) => _settle(_Outcome.retained),
      loadingBuilder: (context) => const ColoredBox(color: Color(0xFF141414)),
      // The survey paints on a near-black canvas with no own dismiss-to-gallery
      // control, and a held save-offer gate would otherwise trap the user. A
      // persistent close keeps the surface escapable to the gallery on every
      // platform (the gallery escape is off here and iOS edge-swipe does not
      // reliably drive the flow's system-back); the chevron handles in-flow back.
      persistentChromeBuilder: (context, state, body) =>
          GalleryFlowChrome(state: state, body: body),
      unavailable: FlowUnavailablePolicy.fallback(
        builder: (context, error) => Scaffold(
          backgroundColor: const Color(0xFF141414),
          body: Center(
            child: Text(
              error.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutcomeScreen extends StatelessWidget {
  const _OutcomeScreen({required this.retained});

  final bool retained;

  @override
  Widget build(BuildContext context) {
    // The terminal retention outcome. It needs the same close-to-gallery
    // affordance as the survey so the gallery stays reachable.
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Text(
                retained ? 'Membership kept' : 'Membership cancelled',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const Positioned(
            top: 0,
            right: 0,
            child: GalleryDismissButton(),
          ),
        ],
      ),
    );
  }
}
