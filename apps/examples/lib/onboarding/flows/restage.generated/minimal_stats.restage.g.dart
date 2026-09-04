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
      'c8eb634040222353d80d5605dda4c469a995206a74f86176e72b56671719f86b',
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
