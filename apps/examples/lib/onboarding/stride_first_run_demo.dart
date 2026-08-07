import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'flows/stride_first_run.dart';

/// Hosts Stride's first-run onboarding — a **general-delivery** flow.
///
/// The host side is the same shape as any engagement surface: supply the host
/// action, act on the outcomes, and fail closed. What differs from a typed flow
/// is the result type — `RestageOnboarding<Map<String, Object?>>`. The flow is
/// authored in general mode (`delivery: FlowDeliveryMode.general`), so there is
/// no generated result class; `onComplete` receives a plain `Map` — the
/// outbound-declared fields, already filtered by the runtime — and the host
/// reads them (`result['completed']`). Everything else — the host action, the
/// custom-event listener, the fail-closed fallback — is identical to a typed
/// flow.
///
/// This demo ships the flow as a bundled asset (no backend). A production app
/// delivers it over the air by injecting a `ServerFlowResolver` once at startup;
/// general delivery lets the server recompose the graph without an app release,
/// bounded to the vocabulary this app installs.
class StrideFirstRunDemo extends StatefulWidget {
  /// Creates the Stride onboarding host.
  ///
  /// [grantReminders] is the decision the demo's notification host action
  /// returns. `true` walks the granted path (welcome → goals → reminders →
  /// ready); `false` walks the declined path (the gate holds on the reminders
  /// screen — the flow never proceeds on permission it did not get; "Maybe
  /// later" is always available).
  const StrideFirstRunDemo({super.key, this.grantReminders = true});

  /// The fixed reminder decision this demo returns from the host action.
  final bool grantReminders;

  @override
  State<StrideFirstRunDemo> createState() => _StrideFirstRunDemoState();
}

class _StrideFirstRunDemoState extends State<StrideFirstRunDemo> {
  late final StrideFirstRunActions _actions;
  StreamSubscription<RestageEvent>? _events;
  bool _done = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _actions = StrideFirstRunActions(
      requestNotifications: (args, context) async {
        // A real app requests the OS notification permission here and returns
        // the user's answer. The demo returns a fixed decision so both branches
        // are exercisable. Note the error contract: an uncaught throw from a
        // host action fails the WHOLE flow closed (to the unavailable
        // fallback), not to a declined branch — so catch platform-channel
        // failures and return `granted: false` if hold-on-screen is the UX
        // you intend.
        return ReminderDecision(granted: widget.grantReminders);
      },
    );
    _events = Restage.events.listen((event) {
      if (event is FlowCustomEvent &&
          event.flowId == 'stride_first_run' &&
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

  void _enterApp({bool completed = false}) {
    if (_done || !mounted) return;
    setState(() {
      _done = true;
      _completed = completed;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _EnteredAppScreen(completed: _completed);
    return RestageOnboarding<Map<String, Object?>>(
      flow: StrideFirstRunFlowDescriptor.ref,
      actions: _actions,
      // The untyped result: the host reads the fields the flow declared, with
      // no generated class in between — and reads them defensively. Under
      // general delivery the graph can be recomposed over the air, so an
      // outbound field is a contract to honour, not a shape the compiler
      // guarantees.
      onComplete: (result) => _enterApp(completed: result['completed'] == true),
      loadingBuilder: (context) => const ColoredBox(color: Color(0xFF241024)),
      unavailable: FlowUnavailablePolicy.fallback(
        builder: (context, error) => Scaffold(
          backgroundColor: const Color(0xFF241024),
          body: Center(
            child: Text(
              error.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFBEFE9)),
            ),
          ),
        ),
      ),
    );
  }
}

class _EnteredAppScreen extends StatelessWidget {
  const _EnteredAppScreen({required this.completed});

  /// Whether the flow finished through its end state (`result['completed']`)
  /// — as opposed to the user skipping past it. Both land in the app; only a
  /// completion carries the flow's terminal result.
  final bool completed;

  @override
  Widget build(BuildContext context) {
    // The terminal "entered the app" hand-off.
    return Scaffold(
      backgroundColor: const Color(0xFF241024),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Today\'s run',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFFBEFE9),
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (completed) ...[
                const SizedBox(height: 8),
                const Text(
                  'Onboarding complete',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFB9A7B4), fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
