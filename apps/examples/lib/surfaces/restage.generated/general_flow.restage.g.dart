part of '../general_flow.dart';

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
        "{\"flow\":\"general_journey\",\"initial\":\"general_status\",\"minClient\":1,\"outbound\":{},\"schemaVersion\":1,\"screenArtifacts\":{\"general_status\":{\"contentHash\":\"sha256:5e3d337414301058ab8a74a34ed20dbb0d9617218f1d97f9f9aba6ebbe7b1abe\",\"minClient\":1,\"path\":\"general_status.rfw\",\"schemaVersion\":1,\"version\":1}},\"states\":{\"done\":{\"kind\":\"end\",\"result\":{}},\"general_status\":{\"kind\":\"screen\",\"on\":{\"finish\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"general_status\"}},\"version\":1}",
    screens: {
      "general_status": GeneralStatus.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '6da416d4eb5fa259ed2ec57f5758f68a9caecbd32603eb6dfdbf54afea5409bb',
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
