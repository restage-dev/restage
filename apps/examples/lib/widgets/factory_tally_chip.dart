import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// How many [FactoryTallyChip] states the app has created.
var factoryTallyChipStates = 0;

/// A chip that counts its own taps, which designs place whole.
@RestageWidget(
  name: 'FactoryTallyChip',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.decoration,
  description: 'A chip that counts its own taps, placed whole.',
)
class FactoryTallyChip extends StatefulWidget {
  /// Creates a chip.
  const FactoryTallyChip({super.key, required this.label});

  /// The label.
  @RestageProperty(description: 'The label.', required: true)
  final String label;

  @override
  State<FactoryTallyChip> createState() => _FactoryTallyChipState();
}

class _FactoryTallyChipState extends State<FactoryTallyChip> {
  late final int _id = ++factoryTallyChipStates;
  var _taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => _taps++),
        child: Text('${widget.label} #$_id: $_taps'),
      );
}
