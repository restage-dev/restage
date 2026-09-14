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
      '0455c05f94bdbc9120084352837c2427bd61c0893efe6860007f6e9ff750ce7e',
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
