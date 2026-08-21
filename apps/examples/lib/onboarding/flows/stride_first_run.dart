import 'package:restage/restage.dart';

import '../screens/stride_goals.dart';
import '../screens/stride_ready.dart';
import '../screens/stride_reminders.dart';
import '../screens/stride_welcome.dart';

part 'restage.generated/stride_first_run.restage.g.dart';

/// Stride's first-run onboarding: welcome → goals → reminder priming → ready.
///
/// This flow is authored the same way as any other — a graph of screens and
/// transitions in pure Dart — but it opts into **general delivery** with
/// `delivery: FlowDeliveryMode.general`. That one choice changes the contract
/// in three ways worth understanding, because this is the canonical example of
/// authoring a general flow.
///
/// ## 1. The result is an untyped `Map`
///
/// A typed flow generates a result class from its `terminalResult` fields, and
/// the host reads `result.completed`. A general flow does not: codegen emits an
/// identity decoder and the host receives a plain `Map<String, Object?>` — the
/// `outbound`-declared fields, already filtered by the runtime (never raw flow
/// state). The host reads `result['completed']`, with no generated class in
/// between. Author the surface with
/// `RestageFlowGraph<Map<String, Object?>>` (see `stride_first_run_demo.dart`).
/// The untyped shape is what lets the *same* runtime interpret a flow the app
/// never compiled against — an editor-authored or over-the-air composition.
///
/// ## 2. The graph is structurally over-the-air
///
/// For a typed flow, changing the graph — adding a screen, rerouting a
/// transition — changes the client-observable contract, so the delivery gate
/// refuses to serve it to an app built against the old shape (the app keeps
/// rendering its bundled copy). A general flow's
/// gate is *structurally permissive*: the server can ship a recomposed graph
/// (and roll it back) without an app release. The engagement team can add a
/// step, reorder screens, or A/B a different path over the air.
///
/// ## 3. …but only over the **installed vocabulary**
///
/// The permissive gate is bounded by construction. A general flow may only
/// reference host actions and custom events the app already ships — here,
/// [requestNotifications] and the `skip` custom event. Over-the-air delivery
/// can compose these installed verbs in new ways; it can never introduce a new
/// verb. A new capability is a new app release. That invariant is what keeps
/// general delivery safe: the app's compiled-in vocabulary is the ceiling, and
/// nothing the server ships can raise it.
///
/// ## The host action and the skip event
///
/// [requestNotifications] is a host action — the app owns the behaviour (the OS
/// dialog); the flow only branches on the typed result. The `reminders` screen
/// runs it on `enable` and advances to `ready` **only when the result is
/// granted**; a declined permission leaves the user on the priming screen. The
/// screen's "Maybe later" fires a `skip` custom event the flow declares but does
/// not route — the host listens for it and carries the user into the app
/// without the grant. The flow describes intent; the app acts on it.
@FlowGraph(
  surface: Surface.onboarding,
  version: 2,
  delivery: FlowDeliveryMode.general,
)
final class StrideFirstRunFlow extends RestageFlow {
  /// Host action that shows the OS notification dialog and reports the grant.
  static const requestNotifications =
      FlowActionRef<void, ReminderDecision>('requestNotifications');

  const StrideFirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: strideWelcomeScreenRef,
      flowState: const {
        'completed': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.exportable,
        ),
      },
      outbound: const FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'completed': FlowOutboundField(
              type: FlowDataType.bool,
              ref: StateFlowOutboundRef(key: 'completed'),
            ),
          },
        ),
        customEvents: {
          // "Maybe later" — handled by the host, not the flow graph.
          'skip': FlowOutboundPayloadDeclaration(),
        },
      ),
      states: [
        screen(strideWelcomeScreenRef)
            .on(StrideWelcomeScreen.start)
            .goTo(strideGoalsScreenRef),
        screen(strideGoalsScreenRef)
            .on(StrideGoalsScreen.next)
            .goTo(strideRemindersScreenRef),
        screen(strideRemindersScreenRef)
            .on(StrideRemindersScreen.enable)
            .run(requestNotifications)
            .result((result) => result.granted)
            .goTo(strideReadyScreenRef),
        screen(strideReadyScreenRef).on(StrideReadyScreen.begin).goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}

/// Typed result of the notification host action.
final class ReminderDecision {
  /// Creates a reminder decision.
  const ReminderDecision({required this.granted});

  /// Whether the user granted the OS notification permission.
  final bool granted;
}
