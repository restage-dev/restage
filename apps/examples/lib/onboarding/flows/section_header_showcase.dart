import 'package:restage/restage.dart';

import '../screens/section_header_showcase.dart';

part 'restage.generated/section_header_showcase.restage.g.dart';

/// A single-state flow for the section header showcase.
///
/// The screen's `act` event completes the flow. Its `dismiss` event is handled
/// by the host and does not transition the flow graph.
@FlowGraph(surface: Surface.onboarding)
final class SectionHeaderShowcaseFlow extends RestageFlow {
  /// Const constructor.
  const SectionHeaderShowcaseFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: sectionHeaderShowcaseScreenRef,
      outbound: const FlowOutboundDeclarations(
        customEvents: {
          'dismiss': FlowOutboundPayloadDeclaration(),
        },
      ),
      states: [
        screen(sectionHeaderShowcaseScreenRef)
            .on(SectionHeaderShowcaseScreen.act)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
