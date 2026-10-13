import 'package:restage/restage.dart';

import '../screens/crave_location.dart';
import '../screens/crave_ready.dart';

part 'restage.generated/crave_permission.restage.g.dart';

/// A location permission flow: a primer, then a confirmation.
///
/// The primer runs the `requestLocation` host action and moves to the
/// confirmation only when permission is granted. "Not now" is a custom event your
/// app handles by continuing without the permission.
@FlowGraph(surface: Surface.onboarding, minClient: 6)
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
      initial: craveLocationScreenRef,
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
          // "Not now" is a custom event your app handles.
          'skip': FlowOutboundPayloadDeclaration(),
        },
      ),
      states: [
        screen(craveLocationScreenRef)
            .on(CraveLocationScreen.allow)
            .run(requestLocation)
            .result((result) => result.granted)
            .goTo(craveReadyScreenRef),
        screen(craveReadyScreenRef).on(CraveReadyScreen.start).goTo(done),
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
