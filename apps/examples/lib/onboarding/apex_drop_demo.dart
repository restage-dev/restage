import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'flows/apex_drop.dart';

/// Hosts an in-app message with its generated surface mount.
/// Completion opens the shop; dismissal or an unavailable flow closes the route.
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
    return ApexDropFlowSurface(
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
    // The terminal "acted → opened the shop" hand-off. System back returns to
    // the gallery from here.
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
        ],
      ),
    );
  }
}
