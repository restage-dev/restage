import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'lumen_trial_ending_flow.dart';

/// Hosts the trial-ending message with its generated surface mount.
/// Completion hands control back to the app.
class LumenTrialEndingDemo extends StatefulWidget {
  /// Creates the message host.
  const LumenTrialEndingDemo({super.key});

  @override
  State<LumenTrialEndingDemo> createState() => _LumenTrialEndingDemoState();
}

class _LumenTrialEndingDemoState extends State<LumenTrialEndingDemo> {
  bool _completed = false;

  @override
  Widget build(BuildContext context) {
    if (_completed) {
      return const _DoneScreen(message: 'Message dismissed');
    }
    return LumenTrialOfferSurface(
      onComplete: (result) {
        if (mounted) setState(() => _completed = true);
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
