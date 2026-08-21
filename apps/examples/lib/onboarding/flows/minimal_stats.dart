import 'package:restage/restage.dart';

import '../screens/starter_stats.dart';

part 'restage.generated/minimal_stats.restage.g.dart';

/// A single-screen flow that delivers the custom-widget showcase surface.
///
/// One screen, one terminal state — the smallest wrapper needed to render a
/// `@Screen` through the delivery path. `done` completes the surface.
@FlowGraph(surface: Surface.onboarding)
final class MinimalStatsFlow extends RestageFlow {
  /// Const constructor.
  const MinimalStatsFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: starterStatsScreenRef,
      states: [
        screen(starterStatsScreenRef).on(StarterStatsScreen.done).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
