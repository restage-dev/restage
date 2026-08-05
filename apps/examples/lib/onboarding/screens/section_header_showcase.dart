import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../../widgets/section_header.dart';

part 'section_header_showcase.rsscreen.g.dart';

/// A general screen that showcases a record-backed section header.
///
/// The surface is authored as ordinary Flutter and compiled to a committed
/// screen artifact. Both record-shaped properties are reconstructed by the
/// generated widget factory when that artifact renders.
@ScreenSource(id: 'section_header_showcase')
class SectionHeaderShowcaseScreen extends StatelessWidget {
  /// Continues from the showcased section.
  static const act = OnboardingEvent<void>('act');

  /// Dismisses the surface (host-handled custom event).
  static const dismiss = OnboardingEvent<void>('dismiss');

  /// Const constructor.
  const SectionHeaderShowcaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              Text(
                'Set up your experience',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              SectionHeader(
                heading: (
                  title: 'Choose a plan',
                  step: 2,
                  tone: HeaderTone.emphasis,
                ),
                entry: const SectionEntry(
                  label: 'Billing',
                  meta: (order: 1, pinned: true),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Review the highlighted section, then continue when you are '
                'ready.',
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
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
