import 'package:restage/restage.dart';

import 'exit_note.dart';

part 'restage.generated/exit_note_flow.restage.g.dart';

const exitNote = FlowStateRef<String>(
  'note',
  classification: FlowStateClassification.exportable,
);

@FlowGraph(id: 'exit_note_survey', surface: Surface.survey)
const exitNoteSurvey = FlowDefinition(
  start: ExitNoteScreen,
  state: [exitNote],
  transitions: [
    Transition.complete(ExitNoteScreen.submit, capture: exitNote),
  ],
  outbound: FlowOutboundPolicy(terminalResult: {'note': exitNote}),
);
