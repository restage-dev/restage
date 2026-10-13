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
  String? _answer;
  String? _note;
  bool _completed = false;

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
    return LumenCancelSurface(
      onComplete: (result) {
        if (!mounted) return;
        setState(() {
          _completed = true;
          _answer = result.reason;
          _note = result.note;
        });
      },
      unavailable: FlowUnavailablePolicy.fallback(
        builder: (context, error) => _DoneScreen(message: error.message),
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
