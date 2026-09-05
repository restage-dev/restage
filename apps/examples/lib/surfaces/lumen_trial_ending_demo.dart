import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'lumen_trial_ending_flow.dart';

/// Hosts the trial-ending message that leads into the welcome offer.
///
/// The host side of a message surface: a [RestageFlowController] under a
/// [RestageFlowView]. The flow declares no host actions, so the app supplies
/// only the fail-closed fallback and the completion hand-off.
class LumenTrialEndingDemo extends StatefulWidget {
  /// Creates the message host.
  const LumenTrialEndingDemo({super.key});

  @override
  State<LumenTrialEndingDemo> createState() => _LumenTrialEndingDemoState();
}

class _LumenTrialEndingDemoState extends State<LumenTrialEndingDemo> {
  RestageFlowController<LumenTrialOfferResult>? _controller;
  FlowUnavailableError? _unavailableError;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    late final RestageFlowController<LumenTrialOfferResult> controller;
    controller = RestageFlowController<LumenTrialOfferResult>(
      flow: lumenTrialOfferRef,
      resolver: Restage.defaultFlowResolver,
      // The flow declares no host actions.
      actions: null,
      onEvent: (event) {
        if (!mounted || !identical(_controller, controller)) return;
        Restage.fireEvent(event);
      },
      onComplete: (result) {
        if (!mounted || !identical(_controller, controller)) return;
        setState(() => _completed = true);
      },
      onUnavailable: (error) {
        if (!mounted || !identical(_controller, controller)) return;
        setState(() => _unavailableError = error);
      },
    );
    _controller = controller;
    unawaited(controller.load());
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_completed) {
      return const _DoneScreen(message: 'Message dismissed');
    }
    final error = _unavailableError;
    if (error != null) {
      return _DoneScreen(message: error.message);
    }
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return RestageEventDispatcher(
      onEvent: controller.handleEvent,
      child: RestageFlowView<LumenTrialOfferResult>(
        controller: controller,
        loadingBuilder: (context) => const SizedBox.shrink(),
      ),
    );
  }
}

class _DoneScreen extends StatelessWidget {
  const _DoneScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
