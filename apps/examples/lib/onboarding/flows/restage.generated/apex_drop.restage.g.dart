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
      'daa060634f056f3cb1fc3e4d9d2efff64bb7a8c466b0d56f460b0b4e19715b65',
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
