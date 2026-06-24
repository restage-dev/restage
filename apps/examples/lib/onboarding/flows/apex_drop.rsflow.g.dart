part of 'apex_drop.dart';

abstract final class ApexDropFlowDescriptor {
  const ApexDropFlowDescriptor._();

  static const OnboardingFlowRef<ApexDropResult> ref =
      OnboardingFlowRef<ApexDropResult>(
    id: 'apex_drop',
    version: 1,
    minClient: 1,
    decodeResult: ApexDropFlowDescriptor._decodeResult,
  );

  static ApexDropResult _decodeResult(Map<String, Object?> result) {
    if (result.isNotEmpty) {
      throw const FormatException('Unexpected flow result keys.');
    }
    return const ApexDropResult();
  }
}

final class ApexDropResult {
  const ApexDropResult();
}

final class ApexDropActions {
  const ApexDropActions();
}
