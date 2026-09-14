part of '../general_flow.dart';

const generalJourneyRef = SurfaceFlowRef<
    GeneralJourneyResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'general_journey',
  version: 1,
  minClient: 1,
  surface: Surface.general,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeGeneralJourneyResult,
  measurementPublicationDraftDigest:
      '6da416d4eb5fa259ed2ec57f5758f68a9caecbd32603eb6dfdbf54afea5409bb',
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
