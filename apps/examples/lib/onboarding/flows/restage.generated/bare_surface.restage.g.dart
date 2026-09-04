part of '../bare_surface.dart';

const bareSurfaceFlowRef = SurfaceFlowRef<
    BareSurfaceResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'bare_surface',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeBareSurfaceFlowResult,
  measurementPublicationDraftDigest:
      '1219961ed3b4a83dcc663bd01535dba14b5e01bae09f1c1adaa43cb196c481bb',
);

BareSurfaceResult _decodeBareSurfaceFlowResult(Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const BareSurfaceResult();
}

@Deprecated('Use bareSurfaceFlowRef')
abstract final class BareSurfaceFlowDescriptor {
  const BareSurfaceFlowDescriptor._();

  static const SurfaceFlowRef<BareSurfaceResult> ref = bareSurfaceFlowRef;
}

final class BareSurfaceResult {
  const BareSurfaceResult();
}

final class BareSurfaceActions {
  const BareSurfaceActions();
}
