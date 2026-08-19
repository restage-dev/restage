import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/starter_welcome.restage.g.dart';

/// Starter onboarding — the welcome screen.
///
/// A `@Screen` is one screen of a flow, authored in ordinary Flutter.
/// Each thing the user can do is a [SurfaceEvent]; `surfaceEvent(...)`
/// wires it to a tap. The flow decides where `next` goes — here, to the
/// question screen.
@Screen()
class StarterWelcomeScreen extends StatelessWidget {
  /// Advances to the first question.
  static const next = SurfaceEvent<void>('next');

  /// Const constructor.
  const StarterWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(
                'Welcome',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'A quick question to set things up the way you like.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: surfaceEvent(next),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Get started'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
