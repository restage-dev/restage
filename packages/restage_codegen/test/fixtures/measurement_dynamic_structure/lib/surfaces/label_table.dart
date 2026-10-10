import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/dynamic_widgets.dart';

part 'restage.generated/label_table.restage.g.dart';

@Screen(id: 'label_table', surface: Surface.general)
final class LabelTableScreen extends StatelessWidget {
  const LabelTableScreen({super.key});

  static const open = SurfaceEvent<void>('open');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          LabelTable(
            labels: const [
              LabelEntry(label: 'Pro'),
              LabelEntry(label: 'Starter')
            ],
            onTap: surfaceEvent(open),
          ),
        ],
      );
}
