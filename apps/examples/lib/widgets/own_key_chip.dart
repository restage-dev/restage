import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/own_key_chip.restage.g.dart';

/// How many states the chip's keyed child has created.
var ownKeyChipStates = 0;

/// A chip whose build keys its own child.
@RestageWidget(
  name: 'OwnKeyChip',
  library: WidgetLibrary.custom('restage_example.widgets'),
  category: WidgetCategory.decoration,
  description: 'A chip whose build keys its own child.',
)
class OwnKeyChip extends StatelessWidget {
  /// Creates a chip.
  const OwnKeyChip({super.key});

  @override
  Widget build(BuildContext context) =>
      const _OwnKeyCount(key: ValueKey<String>('chip'));
}

class _OwnKeyCount extends StatefulWidget {
  const _OwnKeyCount({super.key});

  @override
  State<_OwnKeyCount> createState() => _OwnKeyCountState();
}

class _OwnKeyCountState extends State<_OwnKeyCount> {
  late final int _id = ++ownKeyChipStates;

  @override
  Widget build(BuildContext context) => Text('chip $_id');
}
