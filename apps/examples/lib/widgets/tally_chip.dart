import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/tally_chip.restage.g.dart';

/// How many [TallyChip] states the app has created.
var tallyChipStates = 0;

/// A chip that counts its own taps.
@RestageWidget(
  name: 'TallyChip',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.decoration,
  description: 'A chip that counts its own taps.',
)
class TallyChip extends StatefulWidget {
  /// Creates a chip.
  const TallyChip({super.key, required this.label});

  /// The label.
  @RestageProperty(description: 'The label.', required: true)
  final String label;

  @override
  State<TallyChip> createState() => _TallyChipState();
}

class _TallyChipState extends State<TallyChip> {
  late final int _id = ++tallyChipStates;
  var _taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => _taps++),
        child: Text('${widget.label} #$_id: $_taps'),
      );
}
