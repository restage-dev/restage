import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// What to do after the route refused a draft that changed since it was read.
/// A copy reads from a source draft; an activation adds the review step.
String staleDraftSentence(
  String? draftId,
  ExperimentAuthoringOperationV1 operation, {
  SelectorSyntax? syntax,
}) {
  final mcp = _isMcp(syntax);
  final id = draftId ?? '<draft id>';
  final verb = mcp ? 'Call' : 'Run';
  if (operation == ExperimentAuthoringOperationV1.copyDraftToTarget) {
    return 'The source draft changed after you read it. '
        '$verb ${_resolveDraft(id, mcp, json: false)} '
        '${mcp ? 'with the source target' : 'at its source target'}, then '
        'copy again.';
  }
  final next = operation == ExperimentAuthoringOperationV1.activateDraft
      ? 'review that revision, then activate it'
      : 'then try again with the revision it returns';
  return 'The draft changed after you read it. '
      '$verb ${_resolveDraft(id, mcp, json: true)} to read it again, $next.';
}

/// What to do after the route found the draft's dependencies moved since its
/// review.
String staleReviewSentence({SelectorSyntax? syntax}) =>
    "The draft's dependencies changed after the review. "
    '${_isMcp(syntax) ? 'Call restage_experiment_apply with operation reviewDraft, then activate.' : 'Review the draft again, then activate it.'}';

/// What to do when a write's reply could not be read, so the write may have
/// been applied. [payload] is the request's payload, which names the draft or
/// experiment to check.
String unreadableWriteReplySentence(
  Map<String, Object?> payload, {
  SelectorSyntax? syntax,
}) {
  final mcp = _isMcp(syntax);
  final draftId = payload['draftId'];
  final experimentId = payload['experimentId'];
  final check = draftId is String
      ? _resolveDraft(draftId, mcp, json: false)
      : experimentId is String
      ? mcp
            ? 'restage_experiment_apply with operation readExperiment and '
                  'experimentId $experimentId'
            : '`restage experiment read --experiment-id $experimentId`'
      : null;
  const lead = "Restage didn't confirm the change. It may already be applied.";
  return check == null
      ? '$lead Check before you retry.'
      : '$lead ${mcp ? 'Call' : 'Run'} $check to check, then retry.';
}

bool _isMcp(SelectorSyntax? syntax) =>
    (syntax ?? currentSelectorSyntax) == SelectorSyntax.mcp;

String _resolveDraft(String id, bool mcp, {required bool json}) => mcp
    ? 'restage_experiment_apply with operation resolveDraft and draftId $id'
    : '`restage experiment resolve-draft --draft-id $id${json ? ' --json' : ''}`';
