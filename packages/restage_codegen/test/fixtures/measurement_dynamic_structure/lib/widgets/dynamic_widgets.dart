import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('dynamic.widgets'),
  capabilityVersion: 1,
)
const dynamicWidgetsLibrary = 0;

@RestageWidget(
  name: 'BadgeCard',
  library: WidgetLibrary.custom('dynamic.widgets'),
  category: WidgetCategory.input,
  description: 'A card with an optional badge.',
)
final class BadgeCard extends StatelessWidget {
  const BadgeCard(
      {required this.title, required this.onTap, this.badge, super.key});

  @RestageProperty(description: 'Title.', required: true)
  final String title;

  @RestageProperty(description: 'Optional badge.')
  final String? badge;

  @RestageProperty(description: 'Activation callback.', required: true)
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            if (badge case final label?) Text(label),
            Text(title),
          ],
        ),
      );
}

/// One labelled row.
final class LabelEntry {
  const LabelEntry({required this.label});

  final String label;
}

@RestageWidget(
  name: 'LabelTable',
  library: WidgetLibrary.custom('dynamic.widgets'),
  category: WidgetCategory.input,
  description: 'A table of labels.',
)
final class LabelTable extends StatelessWidget {
  const LabelTable({required this.labels, required this.onTap, super.key});

  @RestageProperty(description: 'Labels in order.', required: true)
  final List<LabelEntry> labels;

  @RestageProperty(description: 'Activation callback.', required: true)
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            for (final entry in labels) Text(entry.label),
          ],
        ),
      );
}

@RestageWidget(
  name: 'PinnedHeader',
  library: WidgetLibrary.custom('dynamic.widgets'),
  category: WidgetCategory.input,
  description: 'A header that may be pinned.',
)
final class PinnedHeader extends StatelessWidget {
  const PinnedHeader({required this.pinned, required this.onTap, super.key});

  @RestageProperty(description: 'Whether the header is pinned.', required: true)
  final bool pinned;

  @RestageProperty(description: 'Activation callback.', required: true)
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Row(
          children: [
            const Text('Header'),
            if (pinned) ...[
              const SizedBox(width: 8),
              const Icon(Icons.push_pin),
            ],
          ],
        ),
      );
}
