import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A vertical run of children the user can drag to reorder.
@RestageWidget(
  name: 'ReorderableColumn',
  library: WidgetLibrary.custom('compact_list_demo.widgets'),
  category: WidgetCategory.layout,
  description: 'A vertical run of children the user can drag to reorder.',
)
class ReorderableColumn extends StatelessWidget {
  /// Const constructor.
  const ReorderableColumn({
    required this.children,
    super.key,
    this.onReorder,
  });

  /// The rows, top to bottom.
  @RestageProperty(description: 'The rows, top to bottom.', required: true)
  final List<Widget> children;

  /// Fires with `[from, to]` once a drag settles on a new position.
  @RestageProperty(
    description: "Fires with the moved row's [from, to] indices.",
  )
  final ValueChanged<List<int>>? onReorder;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // Reports the index the row lands on.
      onReorderItem: _handleReorder,
      children: <Widget>[
        for (var index = 0; index < children.length; index++)
          KeyedSubtree(
            key: ValueKey<int>(index),
            child: children[index],
          ),
      ],
    );
  }

  void _handleReorder(int oldIndex, int newIndex) {
    if (newIndex == oldIndex) return;
    onReorder?.call(<int>[oldIndex, newIndex]);
  }
}
