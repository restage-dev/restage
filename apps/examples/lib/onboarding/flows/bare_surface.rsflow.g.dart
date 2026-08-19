part of 'bare_surface.dart';

abstract final class BareSurfaceFlowDescriptor {
  const BareSurfaceFlowDescriptor._();

  static const SurfaceFlowRef<BareSurfaceResult> ref =
      SurfaceFlowRef<BareSurfaceResult>(
    id: 'bare_surface',
    version: 1,
    minClient: 1,
    surface: Surface.onboarding,
    deliveryMode: FlowDeliveryMode.typed,
    decodeResult: BareSurfaceFlowDescriptor._decodeResult,
  );

  static BareSurfaceResult _decodeResult(Map<String, Object?> result) {
    if (result.isNotEmpty) {
      throw const FormatException('Unexpected flow result keys.');
    }
    return const BareSurfaceResult();
  }
}

final class BareSurfaceResult {
  const BareSurfaceResult();
}

final class BareSurfaceActions {
  const BareSurfaceActions();
}
