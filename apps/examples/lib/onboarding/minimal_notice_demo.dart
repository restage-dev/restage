import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'flows/minimal_notice.dart';

/// Gallery host for the single-screen surface starter.
///
/// It renders the flow and reacts to its two outcomes:
/// - `onComplete` (the CTA acted) hands off to the app — here a small result
///   screen stands in for "your app takes over" (open the feature, the link,
///   the next screen). The CTA leads somewhere, so it never reads as inert.
/// - the `dismiss` custom event (the ×) closes the surface — back to the
///   gallery.
class MinimalNoticeDemo extends StatefulWidget {
  /// Creates the surface gallery host.
  const MinimalNoticeDemo({super.key});

  @override
  State<MinimalNoticeDemo> createState() => _MinimalNoticeDemoState();
}

class _MinimalNoticeDemoState extends State<MinimalNoticeDemo> {
  StreamSubscription<RestageEvent>? _events;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _events = Restage.events.listen((event) {
      if (event is FlowCustomEvent &&
          event.flowId == 'minimal_notice' &&
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

  void _close() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  // The CTA acted — the host takes over. A real app opens the feature; the demo
  // shows a stand-in result screen so the action has a visible effect.
  void _open() {
    if (!mounted || _opened) return;
    setState(() => _opened = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_opened) return const _OpenedScreen();
    return RestageOnboarding<MinimalNoticeResult>(
      flow: MinimalNoticeFlowDescriptor.ref,
      // A one-screen surface draws nothing if it can't load, rather than a
      // fallback; `onFlowUnavailable` then routes away from the blank surface.
      unavailable: const FlowUnavailablePolicy.hide(),
      onComplete: (result) => _open(),
      onFlowUnavailable: (error) => _close(),
    );
  }
}

/// The hand-off the CTA leads to. In a real app this is the app itself (the
/// feature, the link, the next screen); the demo stands in for it and carries a
/// back affordance to the gallery.
class _OpenedScreen extends StatelessWidget {
  const _OpenedScreen();

  @override
  Widget build(BuildContext context) {
    // No AppBar — a top-left back keeps the top-centre clear for the gallery's
    // in-surface theme toggle.
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your app takes it from here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
