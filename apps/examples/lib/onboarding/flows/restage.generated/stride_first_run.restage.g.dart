part of '../stride_first_run.dart';

const strideFirstRunFlowRef = SurfaceFlowRef<Map<String, Object?>>(
  id: 'stride_first_run',
  version: 2,
  minClient: 1,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.general,
  decodeResult: _decodeStrideFirstRunFlowResult,
);

Map<String, Object?> _decodeStrideFirstRunFlowResult(
        Map<String, Object?> result) =>
    result;

@Deprecated('Use strideFirstRunFlowRef')
abstract final class StrideFirstRunFlowDescriptor {
  const StrideFirstRunFlowDescriptor._();

  static const SurfaceFlowRef<Map<String, Object?>> ref = strideFirstRunFlowRef;
}

class StrideFirstRunActions implements FlowActionRegistry, FlowSignalRegistry {
  StrideFirstRunActions({
    required FlowActionHandler<void, ReminderDecision> requestNotifications,
  }) : flowActionBindings =
            Map<String, FlowActionBinding<dynamic, dynamic>>.unmodifiable({
          'requestNotifications': FlowActionBinding<void, ReminderDecision>(
            descriptor: requestNotificationsDescriptor,
            actionName: requestNotificationsDescriptor.actionName,
            contractVersion: requestNotificationsDescriptor.contractVersion,
            argsSchema: requestNotificationsDescriptor.argsSchema,
            resultSchema: requestNotificationsDescriptor.resultSchema,
            minClient: requestNotificationsDescriptor.minClient,
            idempotent: requestNotificationsDescriptor.idempotent,
            handler: requestNotifications,
            decodeArgs: (_) {},
            encodeResult: (value) => {'granted': value.granted},
          ),
        });

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;

  static final FlowActionDescriptor<void, ReminderDecision>
      requestNotificationsDescriptor =
      FlowActionDescriptor<void, ReminderDecision>(
    actionName: 'requestNotifications',
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

  @override
  Set<String> get installedSignalNames => const {'skip'};
}
