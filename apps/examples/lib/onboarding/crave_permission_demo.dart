import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'flows/crave_permission.dart';

/// Hosts the location primer with a simulated permission action.
/// A grant advances the flow; the skip event opens the example app.
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
    return CravePermissionFlowSurface(
      actions: _actions,
      onComplete: (result) => _enterApp(),
      loadingBuilder: (context) => const ColoredBox(color: Colors.white),
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
    // The terminal "entered the app" hand-off. System back returns to the
    // gallery from here.
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
        ],
      ),
    );
  }
}
