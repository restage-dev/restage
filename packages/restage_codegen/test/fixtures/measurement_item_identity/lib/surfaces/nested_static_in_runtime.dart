import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/nested_static_in_runtime.restage.g.dart';

final class Row1 {
  const Row1({required this.id});

  final String id;
}

@Screen(id: 'nested_static_in_runtime', surface: Surface.general)
final class NestedStaticInRuntime extends StatelessWidget {
  const NestedStaticInRuntime({required this.rows, super.key});

  final List<Row1> rows;

  static const pick = SurfaceEvent<String>('pick');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final row in rows)
            Column(
              children: [
                for (final plan in const ['monthly', 'yearly'])
                  TextButton(
                    onPressed: surfaceEvent(pick, plan),
                    child: Text(row.id),
                  ),
              ],
            ),
        ],
      );
}
