part of '../minimal_notice.dart';

const minimalNoticeFlowRef = SurfaceFlowRef<
    MinimalNoticeResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'minimal_notice',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeMinimalNoticeFlowResult,
  measurementPublicationDraftDigest:
      '56bb7adcdb4e41b62713459c4f37d0e9dcced94bc9e24a2e2de09fb7ffd3d9c2',
);

MinimalNoticeResult _decodeMinimalNoticeFlowResult(
    Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const MinimalNoticeResult();
}

@Deprecated('Use minimalNoticeFlowRef')
abstract final class MinimalNoticeFlowDescriptor {
  const MinimalNoticeFlowDescriptor._();

  static const SurfaceFlowRef<MinimalNoticeResult> ref = minimalNoticeFlowRef;
}

final class MinimalNoticeResult {
  const MinimalNoticeResult();
}

final class MinimalNoticeActions {
  const MinimalNoticeActions();
}
