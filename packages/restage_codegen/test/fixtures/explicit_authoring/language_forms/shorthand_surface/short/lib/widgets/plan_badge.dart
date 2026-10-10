// @dart=3.13
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.widgets'),
  capabilityVersion: 1,
)
const acmeWidgets = 0;

@RestageWidget(
  name: 'PlanBadge',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.decoration,
  description: 'A plan badge.',
)
final class PlanBadge extends StatelessWidget {
  const PlanBadge({super.key, required this.label, this.weight = .w400});

  /// The badge text.
  final String label;

  /// The badge font weight.
  final FontWeight weight;

  @override
  Widget build(BuildContext context) =>
      Text(label, style: TextStyle(fontWeight: weight));
}
