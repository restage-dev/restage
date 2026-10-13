import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../../widgets/minimal_custom_widget.dart';

part 'restage.generated/starter_stats.restage.g.dart';

/// A delivered surface that renders your own custom widget.
///
/// Its body includes [StatBadge], a `@RestageWidget` of your own. The build
/// inlines `StatBadge` into this screen's delivered surface.
@Screen()
class StarterStatsScreen extends StatelessWidget {
  /// Completes the surface.
  static const done = SurfaceEvent<void>('done');

  /// Const constructor.
  const StarterStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface, elevation: 0),
      body: SafeArea(
        top: false,
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
                'StatBadge is your own @RestageWidget, rendered in this delivered surface.',
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
                onPressed: surfaceEvent(done),
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
