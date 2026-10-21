import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// One row of a compact habit list: a leading badge, an optional name, and
/// a right-aligned run of day cells.
@RestageWidget(
  name: 'HabitRow',
  library: WidgetLibrary.custom('compact_list_demo.widgets'),
  category: WidgetCategory.layout,
  description: 'A habit-list row: leading badge, optional name, and day cells.',
)
class HabitRow extends StatelessWidget {
  /// Const constructor.
  const HabitRow({
    required this.leading,
    required this.name,
    required this.days,
    required this.nameVisible,
    super.key,
    this.labelWidth = 84,
  });

  /// The badge shown at the start of the row.
  @RestageProperty(
    description: 'The badge shown at the start of the row.',
    required: true,
  )
  final Widget leading;

  /// The row's name.
  @RestageProperty(description: 'The name shown for this row.', required: true)
  final String name;

  /// The day cells, oldest first.
  @RestageProperty(description: 'The day cells, oldest first.', required: true)
  final List<Widget> days;

  /// Whether the name is shown.
  @RestageProperty(
    description: 'Whether the name is shown.',
    required: true,
  )
  final bool nameVisible;

  /// Width reserved for the name.
  @RestageProperty(description: 'Width reserved for the name.')
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Visibility(
            visible: nameVisible,
            child: SizedBox(
              width: labelWidth,
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: days,
          ),
        ],
      ),
    );
  }
}
