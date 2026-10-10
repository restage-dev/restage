import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/host_rows.restage.g.dart';

final class Row0 {
  const Row0({required this.id, required this.title});

  final String id;
  final String title;
}

@Screen(id: 'host_rows', surface: Surface.general)
final class HostRows extends StatelessWidget {
  const HostRows({required this.rows, super.key});

  final List<Row0> rows;

  static const pick = SurfaceEvent<String>('pick');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final row in rows)
            InkWell(
              onTap: surfaceEvent(pick, row.id),
              child: Text(row.title),
            ),
        ],
      );
}
