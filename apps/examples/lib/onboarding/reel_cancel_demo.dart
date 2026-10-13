import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'flows/reel_cancel.dart';

/// Hosts the cancellation survey with a simulated discount action.
/// Successful redemption keeps the membership; the cancel event ends it.
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

enum _Outcome { none, retained, canceled }

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
        _settle(_Outcome.canceled);
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
    return ReelCancelFlowSurface(
      actions: _actions,
      onComplete: (result) => _settle(_Outcome.retained),
      loadingBuilder: (context) => const ColoredBox(color: Color(0xFF141414)),
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
    // The terminal retention outcome. System back returns to the gallery.
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Text(
                retained ? 'Membership kept' : 'Membership canceled',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
