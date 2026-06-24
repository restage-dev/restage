part of 'crave_permission.dart';

abstract final class CravePermissionFlowDescriptor {
  const CravePermissionFlowDescriptor._();

  static const OnboardingFlowRef<CravePermissionResult> ref =
      OnboardingFlowRef<CravePermissionResult>(
    id: 'crave_permission',
    version: 1,
    minClient: 1,
    decodeResult: CravePermissionFlowDescriptor._decodeResult,
  );

  static CravePermissionResult _decodeResult(Map<String, Object?> result) {
    if (result.length != 1 || !result.containsKey('locationEnabled')) {
      throw const FormatException('Unexpected flow result keys.');
    }
    final locationEnabled = result['locationEnabled'];
    if (locationEnabled is! bool) {
      throw const FormatException(
          'Expected result field locationEnabled to be bool.');
    }
    return CravePermissionResult(locationEnabled: locationEnabled);
  }
}

final class CravePermissionResult {
  const CravePermissionResult({required this.locationEnabled});
  final bool locationEnabled;
}

final class CravePermissionActions implements FlowActionRegistry {
  CravePermissionActions({
    required FlowActionHandler<void, LocationDecision> requestLocation,
  }) : flowActionBindings =
            Map<String, FlowActionBinding<dynamic, dynamic>>.unmodifiable({
          'requestLocation': FlowActionBinding<void, LocationDecision>(
            descriptor: requestLocationDescriptor,
            actionName: requestLocationDescriptor.actionName,
            contractVersion: requestLocationDescriptor.contractVersion,
            argsSchema: requestLocationDescriptor.argsSchema,
            resultSchema: requestLocationDescriptor.resultSchema,
            minClient: requestLocationDescriptor.minClient,
            idempotent: requestLocationDescriptor.idempotent,
            handler: requestLocation,
            decodeArgs: (_) {},
            encodeResult: (value) => {'granted': value.granted},
          ),
        });

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;

  static final FlowActionDescriptor<void, LocationDecision>
      requestLocationDescriptor = FlowActionDescriptor<void, LocationDecision>(
    actionName: 'requestLocation',
    contractVersion: 1,
    argsSchema: const FlowActionSchema.object({}),
    resultSchema: const FlowActionSchema.object({
      'granted': FlowActionSchemaField(
        required: true,
        schema: FlowActionSchema.bool(),
      )
    }),
    minClient: 1,
    idempotent: false,
  );
}
