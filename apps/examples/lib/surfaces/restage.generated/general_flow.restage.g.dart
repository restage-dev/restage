part of '../general_flow.dart';

// ignore_for_file: type=lint

const generalJourneyRef = SurfaceFlowRef<
    GeneralJourneyResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'general_journey',
  version: 1,
  minClient: 1,
  surface: Surface.general,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeGeneralJourneyResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"general_journey","initial":"general_status","minClient":1,"outbound":{},"schemaVersion":1,"screenArtifacts":{"general_status":{"contentHash":"sha256:016e8c65b83c8307d340282158862e9df50aa0c61396eb403be89c891c01d455","minClient":1,"path":"measurement/83088be4886b490b/general_status.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"general_status":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"general_status"}},"version":1}',
    screens: {
      'general_status': GeneralStatus.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '6d600714b85f06047e0ea755c09847d95ec83ab189f951fd65f37ae97d6dba64',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
      material: {
        'FilledButton': buildFilledButton,
      },
    ),
  ),
);

GeneralJourneyResult _decodeGeneralJourneyResult(Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const GeneralJourneyResult();
}

final class GeneralJourneyResult {
  const GeneralJourneyResult();
}

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class GeneralJourneySurface
    extends RestageFlowGraph<GeneralJourneyResult> {
  const GeneralJourneySurface({
    super.key,
    super.initialState,
    super.actions,
    super.installedSignalNames,
    super.resolver,
    super.onFlowUnavailable,
    super.onComplete,
    super.loadingBuilder,
    super.transition,
    super.systemBack,
    super.liveRefresh,
    super.context,
    super.unavailable = const FlowUnavailablePolicy.hide(),
  }) : super(flow: generalJourneyRef);
}
