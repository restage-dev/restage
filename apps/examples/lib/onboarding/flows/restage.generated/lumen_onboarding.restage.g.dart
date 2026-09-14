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
        "{\"actions\":{\"enableReminders\":{\"actionName\":\"enableReminders\",\"argsSchema\":{\"fields\":{},\"kind\":\"object\"},\"argsSchemaHash\":\"sha256:590f015bf5e877b53e3501b7e12ad48a11158d4c5b696f9a82593c4f3272411a\",\"contractVersion\":1,\"idempotent\":false,\"minClient\":6,\"resultSchema\":{\"fields\":{\"granted\":{\"required\":true,\"schema\":{\"kind\":\"bool\"}}},\"kind\":\"object\"},\"resultSchemaHash\":\"sha256:ef1c091bc0c82e02a9c18695d6ececbd01dee150396df8bea8ea2b8428ece4ec\"}},\"flow\":\"lumen_onboarding\",\"initial\":\"lumen_welcome\",\"minClient\":6,\"outbound\":{\"customEvents\":{\"close\":{\"fields\":{}},\"sign_in\":{\"fields\":{}},\"terms\":{\"fields\":{}}},\"terminalResult\":{\"fields\":{\"completed\":{\"ref\":{\"event\":\"completed\"},\"type\":\"bool\"}}}},\"schemaVersion\":1,\"screenArtifacts\":{\"lumen_experience\":{\"contentHash\":\"sha256:f1ec1912799c04f6f28fdd86f3f599b625a87625b5b9fb5d72367d72ba63839a\",\"minClient\":6,\"path\":\"lumen_experience.rfw\",\"schemaVersion\":1,\"version\":1},\"lumen_goal\":{\"contentHash\":\"sha256:733ff915b145417b14848eaa1636c2cb7a50eecf52def393c61edd99c2d5d605\",\"minClient\":6,\"path\":\"lumen_goal.rfw\",\"schemaVersion\":1,\"version\":1},\"lumen_recap\":{\"contentHash\":\"sha256:c92282e68cb5193c31766d4c1268e3c6d7c7fa399d54b6420763d5a782c797d7\",\"minClient\":6,\"path\":\"lumen_recap.rfw\",\"schemaVersion\":1,\"version\":1},\"lumen_reminder\":{\"contentHash\":\"sha256:90cffc0a4ae4c96bec350a32632c3194efabbdc37de162b2b8cd9e05a4b00117\",\"minClient\":6,\"path\":\"lumen_reminder.rfw\",\"schemaVersion\":1,\"version\":1},\"lumen_welcome\":{\"contentHash\":\"sha256:5049d818997c5564bf9f8f272e14eb7e66c62530748802b90f61d96fd273a1f0\",\"minClient\":6,\"path\":\"lumen_welcome.rfw\",\"schemaVersion\":1,\"version\":1},\"paywall_lumen_welcome_offer\":{\"contentHash\":\"sha256:cb565293100a81cdea3eb4c4c6a4f4f9840225ad071a14834987527b724bb4ac\",\"minClient\":6,\"path\":\"paywall_lumen_welcome_offer.rfw\",\"schemaVersion\":1,\"version\":1}},\"states\":{\"done\":{\"kind\":\"end\",\"result\":{\"completed\":true}},\"lumen_experience\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"lumen_goal\",\"type\":\"goto\"}},\"screen\":\"lumen_experience\"},\"lumen_goal\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"lumen_reminder\",\"type\":\"goto\"}},\"screen\":\"lumen_goal\"},\"lumen_recap\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"paywall_lumen_welcome_offer\",\"type\":\"goto\"}},\"screen\":\"lumen_recap\"},\"lumen_reminder\":{\"kind\":\"screen\",\"on\":{\"enable\":{\"action\":\"enableReminders\",\"resultPredicate\":{\"field\":\"granted\",\"kind\":\"objectBoolFieldEquals\",\"value\":true},\"target\":\"lumen_recap\",\"type\":\"action\"}},\"screen\":\"lumen_reminder\"},\"lumen_welcome\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"lumen_experience\",\"type\":\"goto\"}},\"screen\":\"lumen_welcome\"},\"paywall_lumen_welcome_offer\":{\"kind\":\"screen\",\"on\":{\"continue\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"paywall_lumen_welcome_offer\"}},\"version\":1}",
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
