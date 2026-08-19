import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/duplicate_implicit_flow.restage.g.dart';

@Screen()
final class DuplicateFlowStart extends StatelessWidget {
  const DuplicateFlowStart({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Start');
}

// A library may derive at most one flow ID from its filename.
@FlowGraph(surface: Surface.general)
const firstImplicitFlow = FlowDefinition(
  start: DuplicateFlowStart,
  transitions: [
    Transition.complete(DuplicateFlowStart.finish),
  ],
);

@FlowGraph(surface: Surface.general)
const secondImplicitFlow = FlowDefinition(
  start: DuplicateFlowStart,
  transitions: [
    Transition.complete(DuplicateFlowStart.finish),
  ],
);
