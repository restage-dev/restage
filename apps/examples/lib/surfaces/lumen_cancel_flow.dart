import 'package:restage/restage.dart';

import 'lumen_cancel.dart';

part 'restage.generated/lumen_cancel_flow.restage.g.dart';

/// The reason a cancelled meditation subscription gives, captured once.
const lumenCancelReason = FlowStateRef<String>(
  'reason',
  defaultValue: '',
  classification: FlowStateClassification.exportable,
);

/// The optional note the user types, returned with the result only.
const lumenCancelNote = FlowStateRef<String>(
  'note',
  defaultValue: '',
  classification: FlowStateClassification.exportable,
);

/// Exit survey with a measured answer and an optional unmeasured note.
/// Skipping returns empty strings; only a changed reason emits an answer event.
@FlowGraph(id: 'lumen_cancel', surface: Surface.survey)
const lumenCancel = FlowDefinition(
  start: LumenCancelReasonScreen,
  state: [lumenCancelReason, lumenCancelNote],
  transitions: [
    Transition(
      LumenCancelReasonScreen.reason,
      capture: lumenCancelReason,
      to: LumenCancelNoteScreen,
    ),
    Transition.complete(LumenCancelReasonScreen.skip),
    Transition(
      LumenCancelNoteScreen.send,
      capture: lumenCancelNote,
      to: LumenCancelThanksScreen,
    ),
    Transition(LumenCancelNoteScreen.skip, to: LumenCancelThanksScreen),
    Transition.complete(LumenCancelThanksScreen.finish),
  ],
  outbound: FlowOutboundPolicy(
    terminalResult: {'reason': lumenCancelReason, 'note': lumenCancelNote},
    surveyAnswers: {'reason': lumenCancelReason},
    measurementAnswers: {
      'reason': FlowAnswerMeasurement.category(
        outcomeKey: 'survey.cancel_reason',
        propertyName: 'reason',
        categoryLabels: {
          'too_expensive': 'It costs too much',
          'not_used_enough': 'I did not use it enough',
          'found_better': 'I found something better',
          'content_not_for_me': 'The content was not for me',
          'something_else': 'Something else',
        },
      ),
    },
  ),
);
