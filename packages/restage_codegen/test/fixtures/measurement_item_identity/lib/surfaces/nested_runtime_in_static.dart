import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/nested_runtime_in_static.restage.g.dart';

final class Row2 {
  const Row2({required this.id});

  final String id;
}

@Screen(id: 'nested_runtime_in_static', surface: Surface.general)
final class NestedRuntimeInStatic extends StatelessWidget {
  const NestedRuntimeInStatic({required this.rows, super.key});

  final List<Row2> rows;

  static const pick = SurfaceEvent<String>('pick');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final tier in const ['free', 'pro'])
            Column(
              children: [
                Text(tier),
                for (final row in rows)
                  InkWell(
                    onTap: surfaceEvent(pick, row.id),
                    child: Text(row.id),
                  ),
              ],
            ),
        ],
      );
}
