import 'package:restage/restage.dart';

import '../screens/starter_bare_surface.dart';

part 'restage.generated/bare_surface.restage.g.dart';

/// The smallest flow-backed surface: one screen and no terminal result.
@FlowGraph(surface: Surface.onboarding)
final class BareSurfaceFlow extends RestageFlow {
  /// Const constructor.
  const BareSurfaceFlow();

  @override
  FlowDef buildFlow() {
    return flow(
      initial: starterBareSurfaceScreenRef,
      states: [
        screen(starterBareSurfaceScreenRef),
      ],
    );
  }
}
