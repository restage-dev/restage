import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/filtered_rows.restage.g.dart';

final class FilteredRow {
  const FilteredRow(
      {required this.id, required this.title, required this.visible});

  final String id;
  final String title;
  final bool visible;
}

@Screen(id: 'filtered_rows', surface: Surface.general)
final class FilteredRows extends StatelessWidget {
  const FilteredRows({required this.rows, super.key});

  final List<FilteredRow> rows;

  static const pick = SurfaceEvent<String>('pick');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const Text('Before'),
          for (final row in rows)
            if (row.visible)
              GestureDetector(
                onTap: surfaceEvent(pick, row.id),
                child: Text(row.title),
              ),
          const Text('After'),
        ],
      );
}
