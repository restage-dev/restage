import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/restage_shared.dart';

/// The runtime sink each outbound surface reaches.
///
/// Analytics-reaching surfaces must be event-args only on a general flow;
/// host-facing surfaces may read flow-state, subject to the branch-only
/// provenance rule for terminalResult; internal surfaces are not egress sinks.
enum OutboundSinkClass {
  /// An outbound surface that reaches analytics.
  analyticsReaching,

  /// An outbound surface that reaches the host application.
  hostFacing,

  /// An outbound surface consumed inside flow execution.
  internal,
}

/// Every outbound slot, classified by its runtime sink.
///
/// The single source of truth for the analytics-sink *classification* — which
/// slots may not carry flow state. It does not itself enumerate the slots (Dart
/// can't reflect over the typed fields); [validateGeneralDiscipline] binds each
/// slot name here to its payload, and a guard test asserts this classifies
/// every slot the wire format serializes. A new outbound slot must be added
/// here (and to that binding); the guard trips once the new slot is serialized.
const Map<String, OutboundSinkClass> kOutboundSlotSinks = {
  'customEvents': OutboundSinkClass.analyticsReaching,
  'surveyAnswers': OutboundSinkClass.analyticsReaching,
  'lifecycle': OutboundSinkClass.analyticsReaching,
  'terminalResult': OutboundSinkClass.hostFacing,
  'actionArgs': OutboundSinkClass.hostFacing,
  'subFlowResult': OutboundSinkClass.internal,
};

/// Validates build-time general-mode outbound discipline.
///
/// The caller appends the returned issues to the build issue list. This is
/// invoked only for general-mode flows; typed flows do not call it.
List<Issue> validateGeneralDiscipline({
  required FlowOutboundDeclarations outbound,
  required Map<String, FlowStateDeclaration> flowState,
  required String location,
}) {
  final issues = <Issue>[];

  final slotPayloads = <String, List<FlowOutboundPayloadDeclaration>>{
    'actionArgs': outbound.actionArgs.values.toList(),
    'terminalResult': [outbound.terminalResult],
    'lifecycle': [outbound.lifecycle],
    'surveyAnswers': [outbound.surveyAnswers],
    'subFlowResult': [outbound.subFlowResult],
    'customEvents': outbound.customEvents.values.toList(),
  };
  assert(
    slotPayloads.length == kOutboundSlotSinks.length &&
        kOutboundSlotSinks.keys.every(slotPayloads.containsKey),
    'slotPayloads and kOutboundSlotSinks must classify the same outbound '
    'slots.',
  );

  for (final entry in kOutboundSlotSinks.entries) {
    if (entry.value != OutboundSinkClass.analyticsReaching) continue;
    final payloads = slotPayloads[entry.key];
    if (payloads == null) {
      throw StateError('Unclassified outbound slot "${entry.key}".');
    }
    for (final payload in payloads) {
      for (final field in payload.fields.entries) {
        final ref = field.value.ref;
        if (ref is StateFlowOutboundRef) {
          issues.add(
            Issue(
              code: IssueCode.generalAnalyticsSinkStateRef,
              message:
                  'Analytics-reaching outbound (${entry.key}) is event-args '
                  'only and must never reference flow state. Field '
                  '"${field.key}" references flow-state key "${ref.key}". '
                  'surveyAnswers is the canonical trap: an analytics event '
                  'reads event args, not captured flow-state.',
              location: location,
            ),
          );
        }
      }
    }
  }

  for (final field in outbound.terminalResult.fields.entries) {
    final ref = field.value.ref;
    if (ref is StateFlowOutboundRef &&
        (flowState[ref.key]?.hostSeedable ?? false)) {
      issues.add(
        Issue(
          code: IssueCode.generalHostSeededResultRef,
          message: 'Host-seeded flow-state key "${ref.key}" must not egress '
              'via terminalResult field "${field.key}"; host-supplied state '
              'is branch-only. Capture the value in-flow instead of seeding '
              'it.',
          location: location,
        ),
      );
    }
  }

  return issues;
}
