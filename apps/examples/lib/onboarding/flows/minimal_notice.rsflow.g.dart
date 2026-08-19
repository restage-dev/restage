part of 'minimal_notice.dart';

abstract final class MinimalNoticeFlowDescriptor {
  const MinimalNoticeFlowDescriptor._();

  static const SurfaceFlowRef<MinimalNoticeResult> ref =
      SurfaceFlowRef<MinimalNoticeResult>(
    id: 'minimal_notice',
    version: 1,
    minClient: 1,
    surface: Surface.onboarding,
    deliveryMode: FlowDeliveryMode.typed,
    decodeResult: MinimalNoticeFlowDescriptor._decodeResult,
  );

  static MinimalNoticeResult _decodeResult(Map<String, Object?> result) {
    if (result.isNotEmpty) {
      throw const FormatException('Unexpected flow result keys.');
    }
    return const MinimalNoticeResult();
  }
}

final class MinimalNoticeResult {
  const MinimalNoticeResult();
}

final class MinimalNoticeActions {
  const MinimalNoticeActions();
}
