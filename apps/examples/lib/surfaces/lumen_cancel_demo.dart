import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'lumen_cancel_flow.dart';

/// Hosts the cancellation survey.
///
/// The host side of a survey surface. The flow declares no host actions, so
/// the app supplies only the fail-closed fallback and the completion
/// hand-off, which reports the answer the flow captured.
class LumenCancelDemo extends StatefulWidget {
  /// Creates the survey host.
  const LumenCancelDemo({super.key});

  @override
  State<LumenCancelDemo> createState() => _LumenCancelDemoState();
}

class _LumenCancelDemoState extends State<LumenCancelDemo> {
  RestageFlowController<LumenCancelResult>? _controller;
  FlowUnavailableError? _unavailableError;
  String? _answer;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    late final RestageFlowController<LumenCancelResult> controller;
    controller = RestageFlowController<LumenCancelResult>(
      flow: lumenCancelRef,
      resolver: Restage.defaultFlowResolver,
      // The flow declares no host actions.
      actions: null,
      onEvent: (event) {
        if (!mounted || !identical(_controller, controller)) return;
        Restage.fireEvent(event);
      },
      onComplete: (result) {
        if (!mounted || !identical(_controller, controller)) return;
        setState(() {
          _completed = true;
          _answer = result.reason;
        });
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
      final answer = _answer;
      return _DoneScreen(
        message: answer == null || answer.isEmpty
            ? 'Survey skipped'
            : 'Thanks — you told us: $answer',
      );
    }
    final error = _unavailableError;
    if (error != null) {
      return _DoneScreen(message: error.message);
    }
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return RestageEventDispatcher(
      onEvent: controller.handleEvent,
      child: RestageFlowView<LumenCancelResult>(
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
