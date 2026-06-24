import 'package:restage/restage.dart';

import '../screens/crave_location.dart';
import '../screens/crave_ready.dart';

part 'crave_permission.rsflow.g.dart';

/// A location permission-priming flow: a value-first primer whose grant is a
/// host-action **gate**, then a confirmation.
///
/// The shape: the primer screen runs the `requestLocation` host action and
/// advances to the confirmation **only on a granted result** (the one
/// conditional the flow runtime offers — advance-or-stay). The primer's
/// "Not now" is a host-handled custom event (continue without the grant); the
/// flow itself never proceeds on permission it did not get.
@FlowSource(id: 'crave_permission', version: 1)
final class CravePermissionFlow extends RestageFlow {
  /// Host action that requests the OS location permission and reports the grant.
  /// The flow advances to the confirmation only on a granted result.
  static const requestLocation =
      FlowActionRef<void, LocationDecision>('requestLocation');

  const CravePermissionFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: CraveLocationScreenDescriptor.ref,
      flowState: const {
        'locationEnabled': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.exportable,
        ),
      },
      outbound: const FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'locationEnabled': FlowOutboundField(
              type: FlowDataType.bool,
              ref: StateFlowOutboundRef(key: 'locationEnabled'),
            ),
          },
        ),
        customEvents: {
          // "Not now" — handled by the host, not the flow graph.
          'skip': FlowOutboundPayloadDeclaration(),
        },
      ),
      states: [
        screen(CraveLocationScreenDescriptor.ref)
            .on(CraveLocationScreen.allow)
            .run(requestLocation)
            .result((result) => result.granted)
            .goTo(CraveReadyScreenDescriptor.ref),
        screen(CraveReadyScreenDescriptor.ref)
            .on(CraveReadyScreen.start)
            .goTo(done),
        end(done, result: {'locationEnabled': true}),
      ],
    );
  }
}

/// Typed result of the location host action.
final class LocationDecision {
  /// Creates a location decision.
  const LocationDecision({required this.granted});

  /// Whether the user granted the OS location permission.
  final bool granted;
}
