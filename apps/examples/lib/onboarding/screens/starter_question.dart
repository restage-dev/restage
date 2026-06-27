import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'starter_question.rsscreen.g.dart';

/// Starter onboarding — the branching question.
///
/// Each option fires a DISTINCT event, so the flow can fork: the flow writes
/// the chosen answer into flow-state and a later `decision` routes the ending
/// on it (see `flows/minimal_onboarding.dart`). This is answer-driven
/// branching — the user's choice changes where they go.
@ScreenSource(id: 'starter_question')
class StarterQuestionScreen extends StatelessWidget {
  /// The user wants a guided setup.
  static const guided = OnboardingEvent<void>('guided');

  /// The user wants to explore on their own.
  static const explore = OnboardingEvent<void>('explore');

  /// Const constructor.
  const StarterQuestionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top room so the flow's back chevron (shown from page 2 on)
              // clears the title.
              const SizedBox(height: 48),
              Text(
                'How do you want to start?',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 28),
              // Option A — fires `guided`.
              GestureDetector(
                onTap: onboardingEvent(guided),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Guide me through it',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Option B — fires `explore`.
              GestureDetector(
                onTap: onboardingEvent(explore),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "I'll explore on my own",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
