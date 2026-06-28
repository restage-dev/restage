part of 'minimal_stats.dart';

abstract final class MinimalStatsFlowDescriptor {
  const MinimalStatsFlowDescriptor._();

  static const OnboardingFlowRef<MinimalStatsResult> ref =
      OnboardingFlowRef<MinimalStatsResult>(
    id: 'minimal_stats',
    version: 1,
    minClient: 1,
    decodeResult: MinimalStatsFlowDescriptor._decodeResult,
  );

  static MinimalStatsResult _decodeResult(Map<String, Object?> result) {
    if (result.isNotEmpty) {
      throw const FormatException('Unexpected flow result keys.');
    }
    return const MinimalStatsResult();
  }
}

final class MinimalStatsResult {
  const MinimalStatsResult();
}

final class MinimalStatsActions {
  const MinimalStatsActions();
}
