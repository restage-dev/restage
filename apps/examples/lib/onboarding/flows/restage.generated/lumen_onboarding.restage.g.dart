part of '../lumen_onboarding.dart';

const lumenOnboardingFlowRef = SurfaceFlowRef<LumenOnboardingResult>(
  id: 'lumen_onboarding',
  version: 1,
  minClient: 6,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeLumenOnboardingFlowResult,
  compiled: CompiledFlow(
    documentJson:
        "{\"actions\":{\"enableReminders\":{\"actionName\":\"enableReminders\",\"argsSchema\":{\"fields\":{},\"kind\":\"object\"},\"argsSchemaHash\":\"sha256:590f015bf5e877b53e3501b7e12ad48a11158d4c5b696f9a82593c4f3272411a\",\"contractVersion\":1,\"idempotent\":false,\"minClient\":6,\"resultSchema\":{\"fields\":{\"granted\":{\"required\":true,\"schema\":{\"kind\":\"bool\"}}},\"kind\":\"object\"},\"resultSchemaHash\":\"sha256:ef1c091bc0c82e02a9c18695d6ececbd01dee150396df8bea8ea2b8428ece4ec\"}},\"flow\":\"lumen_onboarding\",\"initial\":\"lumen_welcome\",\"minClient\":6,\"outbound\":{\"customEvents\":{\"close\":{\"fields\":{}},\"sign_in\":{\"fields\":{}},\"terms\":{\"fields\":{}}},\"terminalResult\":{\"fields\":{\"completed\":{\"ref\":{\"event\":\"completed\"},\"type\":\"bool\"}}}},\"schemaVersion\":1,\"screenArtifacts\":{\"lumen_experience\":{\"contentHash\":\"sha256:aa5cae7508347dc4151351e8adc17923ad7894615e839078c252b0d7579e3d44\",\"minClient\":6,\"path\":\"lumen_experience.rfw\",\"schemaVersion\":1,\"version\":1},\"lumen_goal\":{\"contentHash\":\"sha256:dcee2c0c970ab78565fa3acfb0b069b73f7c52d9e8c0bde34be88a8a1d5dc085\",\"minClient\":6,\"path\":\"lumen_goal.rfw\",\"schemaVersion\":1,\"version\":1},\"lumen_recap\":{\"contentHash\":\"sha256:a9695c7bfb1a21f07d156c8757f44627bfcd1f840dbb1efdb6ec22639b6c6b31\",\"minClient\":6,\"path\":\"lumen_recap.rfw\",\"schemaVersion\":1,\"version\":1},\"lumen_reminder\":{\"contentHash\":\"sha256:a39c4f345f3f8c9b64aeec0c5dd72efb991dc2704da79cf3898fde770242474e\",\"minClient\":6,\"path\":\"lumen_reminder.rfw\",\"schemaVersion\":1,\"version\":1},\"lumen_welcome\":{\"contentHash\":\"sha256:5049d818997c5564bf9f8f272e14eb7e66c62530748802b90f61d96fd273a1f0\",\"minClient\":6,\"path\":\"lumen_welcome.rfw\",\"schemaVersion\":1,\"version\":1},\"paywall_lumen_welcome_offer\":{\"contentHash\":\"sha256:f809aa600e507e03d44d8663d79400cefa0332cdce2f9864f1b10a30d4635182\",\"minClient\":6,\"path\":\"paywall_lumen_welcome_offer.rfw\",\"schemaVersion\":1,\"version\":1}},\"states\":{\"done\":{\"kind\":\"end\",\"result\":{\"completed\":true}},\"lumen_experience\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"lumen_goal\",\"type\":\"goto\"}},\"screen\":\"lumen_experience\"},\"lumen_goal\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"lumen_reminder\",\"type\":\"goto\"}},\"screen\":\"lumen_goal\"},\"lumen_recap\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"paywall_lumen_welcome_offer\",\"type\":\"goto\"}},\"screen\":\"lumen_recap\"},\"lumen_reminder\":{\"kind\":\"screen\",\"on\":{\"enable\":{\"action\":\"enableReminders\",\"resultPredicate\":{\"field\":\"granted\",\"kind\":\"objectBoolFieldEquals\",\"value\":true},\"target\":\"lumen_recap\",\"type\":\"action\"}},\"screen\":\"lumen_reminder\"},\"lumen_welcome\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"lumen_experience\",\"type\":\"goto\"}},\"screen\":\"lumen_welcome\"},\"paywall_lumen_welcome_offer\":{\"kind\":\"screen\",\"on\":{\"continue\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"paywall_lumen_welcome_offer\"}},\"version\":1}",
    screens: {
      "lumen_welcome": LumenWelcomeScreen.new,
      "lumen_experience": LumenExperienceScreen.new,
      "lumen_goal": LumenGoalScreen.new,
      "lumen_reminder": LumenReminderScreen.new,
      "lumen_recap": LumenRecapScreen.new,
    },
    children: {},
  ),
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Center': buildCenter,
        'Column': buildColumn,
        'Container': buildContainer,
        'Expanded': buildExpanded,
        'Flexible': buildFlexible,
        'GestureDetector': buildGestureDetector,
        'Padding': buildPadding,
        'Positioned': buildPositioned,
        'Row': buildRow,
        'SingleChildScrollView': buildSingleChildScrollView,
        'SizedBox': buildSizedBox,
        'Stack': buildStack,
        'Text': buildText,
      },
      material: {
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xef9f: IconData(0xef9f, fontFamily: 'MaterialIcons'),
        0xf636: IconData(0xf636, fontFamily: 'MaterialIcons'),
        0xf0026: IconData(0xf0026, fontFamily: 'MaterialIcons'),
      },
    }, mirrored: {
      'MaterialIcons': {
        0xf63a: IconData(0xf63a,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
      },
    }),
  ),
);

LumenOnboardingResult _decodeLumenOnboardingFlowResult(
    Map<String, Object?> result) {
  if (result.length != 1 || !result.containsKey('completed')) {
    throw const FormatException('Unexpected flow result keys.');
  }
  final completed = result['completed'];
  if (completed is! bool) {
    throw const FormatException('Expected result field completed to be bool.');
  }
  return LumenOnboardingResult(completed: completed);
}

@Deprecated('Use lumenOnboardingFlowRef')
abstract final class LumenOnboardingFlowDescriptor {
  const LumenOnboardingFlowDescriptor._();

  static const SurfaceFlowRef<LumenOnboardingResult> ref =
      lumenOnboardingFlowRef;
}

final class LumenOnboardingResult {
  const LumenOnboardingResult({required this.completed});
  final bool completed;
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
    minClient: 6,
    idempotent: false,
  );
}

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class LumenOnboardingFlowSurface
    extends RestageFlowGraph<LumenOnboardingResult> {
  LumenOnboardingFlowSurface({
    super.key,
    required CompiledFlowScreenBuilder paywallLumenWelcomeOfferScreenBuilder,
    super.initialState,
    super.actions,
    super.installedSignalNames,
    super.resolver,
    super.onFlowUnavailable,
    super.onComplete,
    super.loadingBuilder,
    super.transition,
    super.systemBack,
    super.liveRefresh,
    super.context,
    super.unavailable = const FlowUnavailablePolicy.hide(),
  }) : super(flow: lumenOnboardingFlowRef, screenBuilders: {
          "paywall_lumen_welcome_offer": paywallLumenWelcomeOfferScreenBuilder,
        });
}
