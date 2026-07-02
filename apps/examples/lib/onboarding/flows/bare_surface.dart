import 'package:restage/restage.dart';

import '../screens/starter_bare_surface.dart';

part 'bare_surface.rsflow.g.dart';

/// The smallest flow-backed surface: one screen and no terminal result.
@FlowSource(id: 'bare_surface', version: 1)
final class BareSurfaceFlow extends RestageFlow {
  /// Const constructor.
  const BareSurfaceFlow();

  @override
  FlowDef buildFlow() {
    return flow(
      initial: StarterBareSurfaceScreenDescriptor.ref,
      states: [
        screen(StarterBareSurfaceScreenDescriptor.ref),
      ],
    );
  }
}
