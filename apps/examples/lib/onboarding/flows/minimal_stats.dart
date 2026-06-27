import 'package:restage/restage.dart';

import '../screens/starter_stats.dart';

part 'minimal_stats.rsflow.g.dart';

/// A single-screen flow that delivers the custom-widget showcase surface.
///
/// One screen, one terminal state — the smallest wrapper needed to render a
/// `@ScreenSource` through the delivery path. `done` completes the surface.
@FlowSource(id: 'minimal_stats', version: 1)
final class MinimalStatsFlow extends RestageFlow {
  /// Const constructor.
  const MinimalStatsFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: StarterStatsScreenDescriptor.ref,
      states: [
        screen(StarterStatsScreenDescriptor.ref)
            .on(StarterStatsScreen.done)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
