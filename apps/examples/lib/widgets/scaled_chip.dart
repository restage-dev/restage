import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/scaled_chip.restage.g.dart';

/// A chip whose label follows the app's text scale, up to one and a half.
@RestageWidget(
  name: 'ScaledChip',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.decoration,
  description: "A chip whose label follows the app's text scale.",
)
class ScaledChip extends StatefulWidget {
  /// Creates a chip.
  const ScaledChip({super.key, required this.label});

  /// The label.
  @RestageProperty(description: 'The label.', required: true)
  final String label;

  @override
  State<ScaledChip> createState() => _ScaledChipState();
}

class _ScaledChipState extends State<ScaledChip> {
  @override
  Widget build(BuildContext context) => Text(widget.label,
      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.5));
}
