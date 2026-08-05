import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// The visual tone of a [SectionHeader].
enum HeaderTone {
  /// Uses the surrounding surface's standard heading treatment.
  neutral,

  /// Gives the heading additional visual emphasis.
  emphasis,
}

/// A section entry that itself carries a record field.
class SectionEntry {
  /// Creates a section entry.
  const SectionEntry({required this.label, required this.meta});

  /// The entry's display label.
  final String label;

  /// The entry's ordering and pinned state.
  final ({int order, bool pinned}) meta;
}

/// A surface-general heading for a section of content.
///
/// A section header can introduce an onboarding step, a survey page, an
/// in-app message, a paywall, or any other server-driven surface. Its heading
/// and entry metadata are record-shaped properties reconstructed by the
/// generated widget factory.
@RestageWidget(
  name: 'SectionHeader',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.decoration,
  description: 'Introduces a section with heading and entry metadata.',
)
class SectionHeader extends StatelessWidget {
  /// Const constructor.
  const SectionHeader({
    super.key,
    required this.heading,
    required this.entry,
  });

  /// The section title, step, and visual tone.
  @RestageProperty(
    description: 'The section title, step, and visual tone.',
    required: true,
  )
  final ({String title, int step, HeaderTone tone}) heading;

  /// The section entry and its record-shaped metadata.
  @RestageProperty(
    description: 'The section entry and its ordering metadata.',
    required: true,
  )
  final SectionEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isEmphasized = heading.tone == HeaderTone.emphasis;
    final titleStyle = theme.textTheme.headlineSmall?.copyWith(
      color: isEmphasized ? scheme.primary : scheme.onSurface,
      fontWeight: isEmphasized ? FontWeight.w700 : FontWeight.w500,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step ${heading.step}', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(heading.title, style: titleStyle),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(entry.label, style: theme.textTheme.titleMedium),
              ),
              Text(
                'Section ${entry.meta.order}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (entry.meta.pinned) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.push_pin_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
