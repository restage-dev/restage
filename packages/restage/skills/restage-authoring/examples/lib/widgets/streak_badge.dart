import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A pill showing how many days in a row the user has been active.
@RestageWidget()
class StreakBadge extends StatelessWidget {
  /// Creates a streak badge.
  const StreakBadge({super.key, required this.days, this.label = 'day streak'});

  /// Consecutive active days.
  final int days;

  /// Text shown after the number.
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text('$days $label'),
      ),
    );
  }
}
