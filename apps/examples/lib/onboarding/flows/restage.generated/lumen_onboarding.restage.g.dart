part of '../lumen_onboarding.dart';

const lumenOnboardingFlowRef = SurfaceFlowRef<
    LumenOnboardingResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'lumen_onboarding',
  version: 1,
  minClient: 6,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeLumenOnboardingFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"actions":{"enableReminders":{"actionName":"enableReminders","argsSchema":{"fields":{},"kind":"object"},"argsSchemaHash":"sha256:590f015bf5e877b53e3501b7e12ad48a11158d4c5b696f9a82593c4f3272411a","contractVersion":1,"idempotent":false,"minClient":6,"resultSchema":{"fields":{"granted":{"required":true,"schema":{"kind":"bool"}}},"kind":"object"},"resultSchemaHash":"sha256:ef1c091bc0c82e02a9c18695d6ececbd01dee150396df8bea8ea2b8428ece4ec"}},"flow":"lumen_onboarding","flowState":{"goal":{"classification":"internal","type":"string"}},"initial":"lumen_welcome","minClient":6,"outbound":{"customEvents":{"close":{"fields":{}},"sign_in":{"fields":{}},"terms":{"fields":{}}},"terminalResult":{"fields":{"completed":{"ref":{"event":"completed"},"type":"bool"}}}},"schemaVersion":1,"screenArtifacts":{"lumen_experience":{"contentHash":"sha256:bf340c9a36ad0d64bdb695211aa5be970b3176c271fb7acc66624f5776d8e097","minClient":6,"path":"lumen_experience.rfw","schemaVersion":1,"version":1},"lumen_goal":{"contentHash":"sha256:7645a1c6c2d0d6fd82f3c0515d432a86de9ab2f3dacef0308bc63f7aab460f05","minClient":6,"path":"lumen_goal.rfw","schemaVersion":1,"version":1},"lumen_recap":{"contentHash":"sha256:0e00d94b4fab4a0d4ae6d6fe0a4136373eeb8382f52f3381fd051b39f0773332","minClient":6,"path":"lumen_recap.rfw","schemaVersion":1,"version":1},"lumen_reminder":{"contentHash":"sha256:7fa522da1cb899d2f7f85e60fc95551afd6d5cbdb5486d0bf045ec1f18076f06","minClient":6,"path":"lumen_reminder.rfw","schemaVersion":1,"version":1},"lumen_welcome":{"contentHash":"sha256:0d7a6431f4d616df5ad887172b5764835d46a317e4413edb0c8e7fc2a1ed071e","minClient":6,"path":"lumen_welcome.rfw","schemaVersion":1,"version":1},"paywall_lumen_welcome_offer":{"contentHash":"sha256:42bf98d9adb150ff667ea5bd2b765d36437972567ba9aa8d62e896d39227a989","minClient":6,"path":"measurement/5d2c559be5e2165f/paywall_lumen_welcome_offer.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{"completed":true}},"lumen_experience":{"kind":"screen","on":{"next":{"target":"lumen_goal","type":"goto"}},"screen":"lumen_experience"},"lumen_goal":{"kind":"screen","on":{"curious":{"set":{"goal":{"type":"string","value":{"literal":"curious","type":"string"}}},"target":"route","type":"goto"},"focus":{"set":{"goal":{"type":"string","value":{"literal":"focus","type":"string"}}},"target":"route","type":"goto"},"next":{"target":"route","type":"goto"},"sleep":{"set":{"goal":{"type":"string","value":{"literal":"sleep","type":"string"}}},"target":"route","type":"goto"},"stress":{"set":{"goal":{"type":"string","value":{"literal":"stress","type":"string"}}},"target":"route","type":"goto"}},"screen":"lumen_goal"},"lumen_recap":{"kind":"screen","on":{"next":{"target":"paywall_lumen_welcome_offer","type":"goto"}},"screen":"lumen_recap"},"lumen_reminder":{"kind":"screen","on":{"enable":{"action":"enableReminders","resultPredicate":{"field":"granted","kind":"objectBoolFieldEquals","value":true},"target":"lumen_recap","type":"action"}},"screen":"lumen_reminder"},"lumen_welcome":{"kind":"screen","on":{"next":{"target":"lumen_experience","type":"goto"}},"screen":"lumen_welcome"},"paywall_lumen_welcome_offer":{"kind":"screen","on":{"continue":{"target":"done","type":"goto"}},"screen":"paywall_lumen_welcome_offer"},"route":{"branches":[{"goto":"lumen_recap","when":{"goal":{"eq":{"literal":"curious","type":"string"}}}}],"default":{"goto":"lumen_reminder"},"kind":"decision"}},"version":1}',
    screens: {
      'lumen_welcome': LumenWelcomeScreen.new,
      'lumen_experience': LumenExperienceScreen.new,
      'lumen_goal': LumenGoalScreen.new,
      'lumen_reminder': LumenReminderScreen.new,
      'lumen_recap': LumenRecapScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      'cb62556592b71d4f1b765c8fb6ed30d10378e68e6e2657be97a24d84c7bde635',
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
          'paywall_lumen_welcome_offer': paywallLumenWelcomeOfferScreenBuilder,
        });
}
