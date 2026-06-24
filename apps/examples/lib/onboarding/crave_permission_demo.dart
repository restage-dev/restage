import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'flows/crave_permission.dart';
import 'gallery_dismiss.dart';

/// Hosts the location permission-priming engagement surface.
///
/// The host side of a permission prime is small: supply the `requestLocation`
/// host action, act on the two outcomes, and fail closed. It does what a real
/// app does:
///
/// 1. **Supplies the host action.** A real app shows the OS location dialog and
///    returns the user's answer; this demo returns a fixed [grantLocation]
///    decision so both branches are exercisable. The flow advances to the
///    confirmation **only on a granted result** — the gate is the one
///    conditional the flow runtime offers.
/// 2. **Owns the "Not now" outcome.** The primer's "Not now" fires a `skip`
///    custom event the flow does not handle; the host listens for it and carries
///    the user into the app without the grant.
/// 3. **Fails closed.** An unavailable flow shows a plain surface, never a
///    broken or partial one.
///
/// Like the other examples it ships its flow as a bundled asset (no backend). A
/// production app delivers it over the air by injecting a `ServerFlowResolver`
/// once at startup — the host action, navigation, and fail-closed wiring are
/// identical either way.
class CravePermissionDemo extends StatefulWidget {
  /// Creates the permission host.
  ///
  /// [grantLocation] is the decision the demo's location host action returns.
  /// `true` walks the granted path (primer → grant → confirmation); `false`
  /// walks the declined path (the gate holds on the primer — the flow never
  /// proceeds on permission it did not get; "Not now" is always available).
  const CravePermissionDemo({super.key, this.grantLocation = true});

  /// The fixed location decision this demo returns from the host action.
  final bool grantLocation;

  @override
  State<CravePermissionDemo> createState() => _CravePermissionDemoState();
}

class _CravePermissionDemoState extends State<CravePermissionDemo> {
  late final CravePermissionActions _actions;
  StreamSubscription<RestageEvent>? _events;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _actions = CravePermissionActions(
      requestLocation: (args, context) async {
        // A real app requests the OS location permission here and returns the
        // user's answer. The demo returns a fixed decision so both branches are
        // exercisable.
        return LocationDecision(granted: widget.grantLocation);
      },
    );
    _events = Restage.events.listen((event) {
      if (event is FlowCustomEvent &&
          event.flowId == 'crave_permission' &&
          event.eventName == 'skip') {
        _enterApp();
      }
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  void _enterApp() {
    if (_done || !mounted) return;
    setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const _EnteredAppScreen();
    return RestageOnboarding<CravePermissionResult>(
      flow: CravePermissionFlowDescriptor.ref,
      actions: _actions,
      onComplete: (result) => _enterApp(),
      loadingBuilder: (context) => const ColoredBox(color: Colors.white),
      // The primer paints on a white canvas with no own dismiss-to-gallery
      // control, and a declined gate holds the user on it. A persistent close
      // keeps the surface escapable to the gallery on every platform (the
      // gallery escape is off here and iOS edge-swipe does not reliably drive
      // the flow's system-back); the chevron handles any in-flow back.
      persistentChromeBuilder: (context, state, body) => GalleryFlowChrome(
        state: state,
        body: body,
        backColor: const Color(0xFF1F1B16),
        closeColor: const Color(0xFF1F1B16),
        closeScrim: const Color(0x1F000000),
      ),
      unavailable: FlowUnavailablePolicy.fallback(
        builder: (context, error) => Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Text(
              error.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF1F1B16)),
            ),
          ),
        ),
      ),
    );
  }
}

class _EnteredAppScreen extends StatelessWidget {
  const _EnteredAppScreen();

  @override
  Widget build(BuildContext context) {
    // The terminal "entered the app" hand-off. It needs the same close-to-gallery
    // affordance as the flow so the gallery stays reachable.
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Text(
                'Browsing restaurants',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF1F1B16),
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: GalleryDismissButton(
              color: Color(0xFF1F1B16),
              scrim: Color(0x1F000000),
            ),
          ),
        ],
      ),
    );
  }
}
