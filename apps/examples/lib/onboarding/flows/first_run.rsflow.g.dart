part of 'first_run.dart';

abstract final class FirstRunFlowDescriptor {
  const FirstRunFlowDescriptor._();

  static const OnboardingFlowRef<FirstRunResult> ref =
      OnboardingFlowRef<FirstRunResult>(
    id: 'first_run',
    version: 1,
    minClient: 1,
    decodeResult: FirstRunFlowDescriptor._decodeResult,
  );

  static FirstRunResult _decodeResult(Map<String, Object?> result) {
    if (result.length != 1 || !result.containsKey('completed')) {
      throw const FormatException('Unexpected flow result keys.');
    }
    final completed = result['completed'];
    if (completed is! bool) {
      throw const FormatException(
          'Expected result field completed to be bool.');
    }
    return FirstRunResult(completed: completed);
  }
}

final class FirstRunResult {
  const FirstRunResult({required this.completed});
  final bool completed;
}

final class FirstRunActions implements FlowActionRegistry {
  FirstRunActions({
    required FlowActionHandler<void, NotificationDecision> requestNotifications,
  }) : flowActionBindings =
            Map<String, FlowActionBinding<dynamic, dynamic>>.unmodifiable({
          'requestNotifications': FlowActionBinding<void, NotificationDecision>(
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

  static final FlowActionDescriptor<void, NotificationDecision>
      requestNotificationsDescriptor =
      FlowActionDescriptor<void, NotificationDecision>(
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
}
