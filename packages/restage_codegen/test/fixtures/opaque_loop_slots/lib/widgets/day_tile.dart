import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// One cell in a compact habit grid: a rounded square that reads as
/// "done" or "not yet" at a glance.
@RestageWidget(
  name: 'DayTile',
  library: WidgetLibrary.custom('compact_list_demo.widgets'),
  category: WidgetCategory.decoration,
  description: 'A rounded habit-grid cell, filled when its day is complete.',
)
class DayTile extends StatelessWidget {
  /// Const constructor.
  const DayTile({
    required this.color,
    super.key,
    this.size = 20,
    this.onTap,
  });

  /// The cell's fill color.
  @RestageProperty(
    description: 'Fill color for this cell.',
    required: true,
  )
  final Color color;

  /// The cell's edge length. Both axes, so the cell stays square.
  @RestageProperty(description: 'Edge length of the square cell.')
  final double size;

  /// Fired when the cell is tapped.
  @RestageProperty(description: 'Fires when the cell is tapped.')
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}
