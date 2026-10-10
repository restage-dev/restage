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
  const PlanBadge({
    super.key,
    required this.label,
    this.weight = FontWeight.w400,
  });

  /// The badge text.
  final String label;

  /// The badge font weight.
  final FontWeight weight;

  @override
  Widget build(BuildContext context) =>
      Text(label, style: TextStyle(fontWeight: weight));
}

@RestageWidget(
  name: 'PlanNote',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.decoration,
  description: 'A plan note.',
)
final class PlanNote extends StatelessWidget {
  const PlanNote({super.key, required this.text});

  /// The note text.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
