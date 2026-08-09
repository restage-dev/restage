import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' show LiteralDefault;

/// A feature-list row: check icon, title, and subtitle.
@RestageWidget(
  name: 'FeatureRow',
  library: WidgetLibrary.custom('restage_widgetbook_example.widgets'),
  category: WidgetCategory.layout,
)
class FeatureRow extends StatelessWidget {
  /// Const constructor — catalog widgets are const-constructible.
  const FeatureRow({super.key, required this.title, required this.subtitle});

  /// Feature title.
  @RestageProperty(defaultSource: LiteralDefault('Unlimited projects'))
  final String title;

  /// Supporting line under the title.
  @RestageProperty(defaultSource: LiteralDefault('No caps on what you ship.'))
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle, color: scheme.primary, size: 22),
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}
