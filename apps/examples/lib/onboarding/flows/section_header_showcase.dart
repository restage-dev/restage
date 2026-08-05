import 'package:restage/restage.dart';

import '../screens/section_header_showcase.dart';

part 'section_header_showcase.rsflow.g.dart';

/// A single-state flow for the section header showcase.
///
/// The screen's `act` event completes the flow. Its `dismiss` event is handled
/// by the host and does not transition the flow graph.
@FlowSource(id: 'section_header_showcase', version: 1)
final class SectionHeaderShowcaseFlow extends RestageFlow {
  /// Const constructor.
  const SectionHeaderShowcaseFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: SectionHeaderShowcaseScreenDescriptor.ref,
      outbound: const FlowOutboundDeclarations(
        customEvents: {
          'dismiss': FlowOutboundPayloadDeclaration(),
        },
      ),
      states: [
        screen(SectionHeaderShowcaseScreenDescriptor.ref)
            .on(SectionHeaderShowcaseScreen.act)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
