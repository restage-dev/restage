import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../../widgets/minimal_custom_widget.dart';

part 'starter_stats.rsscreen.g.dart';

/// A delivered surface that renders your own custom widget.
///
/// Authored like any other screen, but its body includes [StatBadge] — a
/// `@RestageWidget` you registered. The codegen lowers this screen to a render
/// blob that references `StatBadge` by its catalog name; at runtime the SDK
/// resolves it through the factory you registered and renders the real widget.
/// So your widget travels inside the server-delivered blob — proof a custom
/// widget is a first-class catalog citizen, not just local Flutter.
@ScreenSource(id: 'starter_stats')
class StarterStatsScreen extends StatelessWidget {
  /// Completes the surface.
  static const done = OnboardingEvent<void>('done');

  /// Const constructor.
  const StarterStatsScreen({super.key});

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
                'Your widget, delivered',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'StatBadge is your @RestageWidget — rendered here from the blob.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              const Center(child: StatBadge(label: 'Streak', value: '7 days')),
              const SizedBox(height: 12),
              const Center(child: StatBadge(label: 'Saved', value: r'$48.20')),
              const SizedBox(height: 12),
              const Center(child: StatBadge(label: 'Rank', value: 'Top 5%')),
              const Spacer(),
              FilledButton(
                onPressed: onboardingEvent(done),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
