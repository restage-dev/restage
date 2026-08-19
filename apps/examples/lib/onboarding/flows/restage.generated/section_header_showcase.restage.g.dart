part of '../section_header_showcase.dart';

abstract final class SectionHeaderShowcaseFlowDescriptor {
  const SectionHeaderShowcaseFlowDescriptor._();

  static const SurfaceFlowRef<SectionHeaderShowcaseResult> ref =
      SurfaceFlowRef<SectionHeaderShowcaseResult>(
    id: 'section_header_showcase',
    version: 1,
    minClient: 1,
    surface: Surface.onboarding,
    deliveryMode: FlowDeliveryMode.typed,
    decodeResult: SectionHeaderShowcaseFlowDescriptor._decodeResult,
  );

  static SectionHeaderShowcaseResult _decodeResult(
      Map<String, Object?> result) {
    if (result.isNotEmpty) {
      throw const FormatException('Unexpected flow result keys.');
    }
    return const SectionHeaderShowcaseResult();
  }
}

final class SectionHeaderShowcaseResult {
  const SectionHeaderShowcaseResult();
}

final class SectionHeaderShowcaseActions {
  const SectionHeaderShowcaseActions();
}
