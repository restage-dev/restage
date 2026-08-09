import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' show LiteralDefault;

/// A labelled value tile, e.g. "Active users" over "1,204".
@RestageWidget(
  name: 'StatTile',
  library: WidgetLibrary.custom('restage_widgetbook_example.widgets'),
  category: WidgetCategory.decoration,
)
class StatTile extends StatelessWidget {
  /// Const constructor — catalog widgets are const-constructible.
  const StatTile({super.key, required this.label, required this.value});

  /// Caption text.
  @RestageProperty(defaultSource: LiteralDefault('Active users'))
  final String label;

  /// Value text.
  @RestageProperty(defaultSource: LiteralDefault('1,204'))
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: scheme.onSecondaryContainer,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
