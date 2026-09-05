import 'package:restage/restage.dart';

import 'lumen_cancel.dart';

part 'restage.generated/lumen_cancel_flow.restage.g.dart';

/// The reason a cancelled meditation subscription gives, captured once.
const lumenCancelReason = FlowStateRef<String>(
  'reason',
  classification: FlowStateClassification.exportable,
);

/// A two-screen exit survey: one captured answer, then an acknowledgement.
///
/// Every reason card fires the same event with its own value, so the capture
/// records the chosen answer without forking the graph. The answer reaches the
/// host twice — as the terminal result and as the survey answer payload.
/// Skipping completes the survey with no answer captured.
@FlowGraph(id: 'lumen_cancel', surface: Surface.survey)
const lumenCancel = FlowDefinition(
  start: LumenCancelReasonScreen,
  state: [lumenCancelReason],
  transitions: [
    Transition(
      LumenCancelReasonScreen.reason,
      capture: lumenCancelReason,
      to: LumenCancelThanksScreen,
    ),
    Transition.complete(LumenCancelReasonScreen.skip),
    Transition.complete(LumenCancelThanksScreen.finish),
  ],
  outbound: FlowOutboundPolicy(
    terminalResult: {'reason': lumenCancelReason},
    surveyAnswers: {'reason': lumenCancelReason},
  ),
);
