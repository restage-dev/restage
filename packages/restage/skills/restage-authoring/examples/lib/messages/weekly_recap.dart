import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../app_widgets.dart';

part 'restage.generated/weekly_recap.restage.g.dart';

const kHighlights = ['Longest session', 'Most active day', 'New habits'];

/// A standalone message that shows data the app already has.
@Screen(id: 'weekly_recap', surface: Surface.message)
final class WeeklyRecap extends StatelessWidget {
  const WeeklyRecap({super.key, required this.name, required this.streakDays});

  final String name;
  final int streakDays;

  static const dismiss = SurfaceEvent<void>('dismiss');
  static const openStats = SurfaceEvent<String>('open_stats');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Nice week, $name'),
          const RecapHeading(title: 'Weekly highlights'),
          const SizedBox(height: 12),
          StreakBadge(days: streakDays),
          const SizedBox(height: 12),
          for (final highlight in kHighlights) Text(highlight),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: surfaceEvent(openStats, 'weekly'),
            child: const Text('See your stats'),
          ),
          TextButton(
            onPressed: surfaceEvent(dismiss),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}
