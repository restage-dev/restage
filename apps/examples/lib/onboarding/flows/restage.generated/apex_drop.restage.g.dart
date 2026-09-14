part of '../apex_drop.dart';

const apexDropFlowRef = SurfaceFlowRef<
    ApexDropResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'apex_drop',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeApexDropFlowResult,
  measurementPublicationDraftDigest:
      'ed2cb271ff3dc32024eedc1c070e2c4ff84575d5f3c189da49bda48137da59ad',
);

ApexDropResult _decodeApexDropFlowResult(Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const ApexDropResult();
}

@Deprecated('Use apexDropFlowRef')
abstract final class ApexDropFlowDescriptor {
  const ApexDropFlowDescriptor._();

  static const SurfaceFlowRef<ApexDropResult> ref = apexDropFlowRef;
}

final class ApexDropResult {
  const ApexDropResult();
}

final class ApexDropActions {
  const ApexDropActions();
}
