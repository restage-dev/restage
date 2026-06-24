import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'flows/apex_drop.dart';
import 'gallery_dismiss.dart';

/// Hosts the single-screen in-app message engagement surface.
///
/// The host side of a message is tiny: render the flow and act on its two
/// outcomes. Unlike the onboarding host (which shows a fallback surface), a
/// message uses `FlowUnavailablePolicy.hide`, which governs *rendering* — an
/// unavailable message draws nothing rather than a fallback surface. The
/// separate `onFlowUnavailable` callback then governs *routing*: it pops the
/// route so the user isn't left on that otherwise-blank surface.
///
/// `onComplete` (the CTA acted) opens the shop; the `dismiss` custom event (the
/// ×) closes the message. There is no separate "message" API — a message is a
/// flow that happens to have a single screen.
class ApexDropDemo extends StatefulWidget {
  /// Creates the message host.
  const ApexDropDemo({super.key});

  @override
  State<ApexDropDemo> createState() => _ApexDropDemoState();
}

class _ApexDropDemoState extends State<ApexDropDemo> {
  StreamSubscription<RestageEvent>? _events;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _events = Restage.events.listen((event) {
      if (event is FlowCustomEvent &&
          event.flowId == 'apex_drop' &&
          event.eventName == 'dismiss') {
        _close();
      }
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  // "Shop the drop" acted — open the shop.
  void _act() {
    if (_done || !mounted) return;
    setState(() => _done = true);
  }

  // Dismissed (the × or an unavailable message) — close the message.
  void _close() {
    if (_done || !mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const _ShopScreen();
    return RestageOnboarding<ApexDropResult>(
      flow: ApexDropFlowDescriptor.ref,
      onComplete: (result) => _act(),
      onFlowUnavailable: (error) => _close(),
      loadingBuilder: (context) => const ColoredBox(color: Color(0xFF0A0A0A)),
      unavailable: const FlowUnavailablePolicy.hide(),
    );
  }
}

class _ShopScreen extends StatelessWidget {
  const _ShopScreen();

  @override
  Widget build(BuildContext context) {
    // The terminal "acted → opened the shop" hand-off. It needs a close-to-gallery
    // affordance so the gallery stays reachable (the message screen carried its
    // own ×; this host screen replaces it once the CTA acts).
    return const Scaffold(
      backgroundColor: Color(0xFF0A0A0A),
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Text(
                'Browsing the drop',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: GalleryDismissButton(),
          ),
        ],
      ),
    );
  }
}
