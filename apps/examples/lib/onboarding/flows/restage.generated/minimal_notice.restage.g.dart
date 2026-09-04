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
      '4021a02d134a5b9c1d74917416a2c92ac85cdfce2e13845fe47781f5a417dcc7',
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
