part of '../minimal_stats.dart';

const minimalStatsFlowRef = SurfaceFlowRef<
    MinimalStatsResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'minimal_stats',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeMinimalStatsFlowResult,
  measurementPublicationDraftDigest:
      '8dd3ac89fbfb467374089e8554a33c281a7189c490b719e9fdf0d5b481938154',
);

MinimalStatsResult _decodeMinimalStatsFlowResult(Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const MinimalStatsResult();
}

@Deprecated('Use minimalStatsFlowRef')
abstract final class MinimalStatsFlowDescriptor {
  const MinimalStatsFlowDescriptor._();

  static const SurfaceFlowRef<MinimalStatsResult> ref = minimalStatsFlowRef;
}

final class MinimalStatsResult {
  const MinimalStatsResult();
}

final class MinimalStatsActions {
  const MinimalStatsActions();
}
