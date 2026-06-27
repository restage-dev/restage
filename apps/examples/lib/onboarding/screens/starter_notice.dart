import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'starter_notice.rsscreen.g.dart';

/// A minimal general surface — one screen, framed as "any screen you render."
///
/// Restage is server-driven UI for *every* surface, not just paywalls. This is
/// the smallest proof: a single-screen notice (an announcement, a what's-new, a
/// soft prompt). It has two outcomes:
///
/// - **act** completes the flow — the host then does the real thing
///   (`onComplete`): open the feature, the link, the next screen.
/// - **dismiss** is a host-handled custom event — the host listens and closes
///   the surface. Dismissing is not a graph transition; the notice just goes
///   away.
///
/// Theme-adaptive, so it repaints with the app theme.
@ScreenSource(id: 'starter_notice')
class StarterNoticeScreen extends StatelessWidget {
  /// The primary action — completes the flow so the host can act.
  static const act = OnboardingEvent<void>('act');

  /// Dismisses the surface (host-handled custom event).
  static const dismiss = OnboardingEvent<void>('dismiss');

  /// Const constructor.
  const StarterNoticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Dismiss affordance, top-right.
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: onboardingEvent(dismiss),
                    icon: Icon(
                      Icons.close_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Icon(
                Icons.campaign_rounded,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                "What's new",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'A short, server-driven announcement — delivered over the air, '
                'rendered as real Flutter widgets.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.45,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: onboardingEvent(act),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Take a look'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
