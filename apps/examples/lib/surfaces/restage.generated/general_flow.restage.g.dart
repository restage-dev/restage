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
      '58c7a4ecc6a2025610c4a461d7387e2b917da80a7e168410e86c74d5b7a3d0ff',
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
