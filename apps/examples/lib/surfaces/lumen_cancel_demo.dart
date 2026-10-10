import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'lumen_cancel_flow.dart';

/// Hosts the cancellation survey with a fallback and completion callback.
/// Reports the captured answer and note; the flow needs no host actions.
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
  String? _note;
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
          _note = result.note;
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
      final note = _note;
      final reason = answer == null || answer.isEmpty
          ? 'Survey skipped'
          : 'Thanks — you told us: $answer';
      return _DoneScreen(
        message: note == null || note.isEmpty ? reason : '$reason\nNote: $note',
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
