import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/branching_notice.restage.g.dart';

@Screen(id: 'branching_notice', surface: Surface.general)
final class BranchingNotice extends StatefulWidget {
  const BranchingNotice({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  State<BranchingNotice> createState() => _BranchingNoticeState();
}

class _BranchingNoticeState extends State<BranchingNotice> {
  bool highlighted = true;

  void select() => setState(() => highlighted = true);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          GestureDetector(
            onTap: select,
            child: highlighted
                ? const Text('Highlighted')
                : const Text('Ordinary'),
          ),
          FilledButton(
            onPressed: surfaceEvent(BranchingNotice.dismiss),
            child: const Text('Dismiss'),
          ),
        ],
      );
}
