part of 'lumen_onboarding.dart';

abstract final class LumenOnboardingFlowDescriptor {
  const LumenOnboardingFlowDescriptor._();

  static const OnboardingFlowRef<LumenOnboardingResult> ref =
      OnboardingFlowRef<LumenOnboardingResult>(
    id: 'lumen_onboarding',
    version: 1,
    minClient: 1,
    decodeResult: LumenOnboardingFlowDescriptor._decodeResult,
  );

  static LumenOnboardingResult _decodeResult(Map<String, Object?> result) {
    if (result.length != 1 || !result.containsKey('subscribed')) {
      throw const FormatException('Unexpected flow result keys.');
    }
    final subscribed = result['subscribed'];
    if (subscribed is! bool) {
      throw const FormatException(
          'Expected result field subscribed to be bool.');
    }
    return LumenOnboardingResult(subscribed: subscribed);
  }
}

final class LumenOnboardingResult {
  const LumenOnboardingResult({required this.subscribed});
  final bool subscribed;
}

final class LumenOnboardingActions implements FlowActionRegistry {
  LumenOnboardingActions({
    required FlowActionHandler<void, ReminderDecision> enableReminders,
  }) : flowActionBindings =
            Map<String, FlowActionBinding<dynamic, dynamic>>.unmodifiable({
          'enableReminders': FlowActionBinding<void, ReminderDecision>(
            descriptor: enableRemindersDescriptor,
            actionName: enableRemindersDescriptor.actionName,
            contractVersion: enableRemindersDescriptor.contractVersion,
            argsSchema: enableRemindersDescriptor.argsSchema,
            resultSchema: enableRemindersDescriptor.resultSchema,
            minClient: enableRemindersDescriptor.minClient,
            idempotent: enableRemindersDescriptor.idempotent,
            handler: enableReminders,
            decodeArgs: (_) {},
            encodeResult: (value) => {'granted': value.granted},
          ),
        });

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;

  static final FlowActionDescriptor<void, ReminderDecision>
      enableRemindersDescriptor = FlowActionDescriptor<void, ReminderDecision>(
    actionName: 'enableReminders',
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
