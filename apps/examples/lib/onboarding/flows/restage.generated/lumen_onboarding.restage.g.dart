part of '../lumen_onboarding.dart';

// ignore_for_file: type=lint, unnecessary_cast

const _lumenOnboardingFlowRefVocabulary = SurfaceVocabulary(
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
);

const lumenOnboardingFlowRef = SurfaceFlowRef<
    LumenOnboardingResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'lumen_onboarding',
  version: 1,
  minClient: 17,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeLumenOnboardingFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"actions":{"enableReminders":{"actionName":"enableReminders","argsSchema":{"fields":{},"kind":"object"},"argsSchemaHash":"sha256:590f015bf5e877b53e3501b7e12ad48a11158d4c5b696f9a82593c4f3272411a","contractVersion":1,"idempotent":false,"minClient":6,"resultSchema":{"fields":{"granted":{"required":true,"schema":{"kind":"bool"}}},"kind":"object"},"resultSchemaHash":"sha256:ef1c091bc0c82e02a9c18695d6ececbd01dee150396df8bea8ea2b8428ece4ec"}},"flow":"lumen_onboarding","flowState":{"goal":{"classification":"exportable","type":"string"}},"initial":"lumen_welcome","minClient":17,"outbound":{"customEvents":{"close":{"fields":{}},"privacy":{"fields":{}},"restore_purchases":{"fields":{}},"sign_in":{"fields":{}},"terms":{"fields":{}}},"surveyAnswers":{"fields":{"goal":{"ref":{"state":"goal"},"type":"string"}}},"terminalResult":{"fields":{"completed":{"ref":{"event":"completed"},"type":"bool"}}}},"schemaVersion":2,"screenArtifacts":{"lumen_experience":{"contentHash":"sha256:72a64f7ad02a6bed9854b96d66d64a8cb0329eae2b720f97b8743cdcd2daf397","minClient":17,"path":"lumen_experience.rfw","schemaVersion":1,"version":1},"lumen_goal":{"contentHash":"sha256:67650c1c677a494132a3f1c2c3c45df5e4ea6436f7004b8ddf0525c633aa8eaf","minClient":17,"path":"lumen_goal.rfw","schemaVersion":1,"version":1},"lumen_recap":{"contentHash":"sha256:5e55ea915412bb515254748cc04dee4ee15b0dff25943711947bd736f3900e4a","minClient":17,"path":"lumen_recap.rfw","schemaVersion":1,"version":1},"lumen_reminder":{"contentHash":"sha256:89227dae05fa4d703519734cae49d018754818889174a31ee2ae361ae7e050ff","minClient":17,"path":"lumen_reminder.rfw","schemaVersion":1,"version":1},"lumen_welcome":{"contentHash":"sha256:a06a754636c9fc6eff323225aa5af2441b689f70417325cd4a271fe4804aadc0","minClient":17,"path":"lumen_welcome.rfw","schemaVersion":1,"version":1},"paywall_lumen_welcome_offer":{"contentHash":"sha256:3b101235ea705b9e597fa28e0e5e2879e09ea4d4a0c1e026db8cf7d315d83701","minClient":17,"path":"measurement/5d2c559be5e2165f/paywall_lumen_welcome_offer.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{"completed":true}},"lumen_experience":{"kind":"screen","on":{"next":{"target":"lumen_goal","type":"goto"}},"screen":"lumen_experience"},"lumen_goal":{"kind":"screen","on":{"curious":{"set":{"goal":{"type":"string","value":{"literal":"curious","type":"string"}}},"target":"route","type":"goto"},"focus":{"set":{"goal":{"type":"string","value":{"literal":"focus","type":"string"}}},"target":"route","type":"goto"},"next":{"target":"route","type":"goto"},"sleep":{"set":{"goal":{"type":"string","value":{"literal":"sleep","type":"string"}}},"target":"route","type":"goto"},"stress":{"set":{"goal":{"type":"string","value":{"literal":"stress","type":"string"}}},"target":"route","type":"goto"}},"screen":"lumen_goal"},"lumen_recap":{"kind":"screen","on":{"next":{"target":"paywall_lumen_welcome_offer","type":"goto"}},"screen":"lumen_recap"},"lumen_reminder":{"kind":"screen","on":{"enable":{"action":"enableReminders","resultPredicate":{"field":"granted","kind":"objectBoolFieldEquals","value":true},"target":"lumen_recap","type":"action"}},"screen":"lumen_reminder"},"lumen_welcome":{"kind":"screen","on":{"next":{"target":"lumen_experience","type":"goto"}},"screen":"lumen_welcome"},"paywall_lumen_welcome_offer":{"kind":"screen","on":{"continue":{"target":"done","type":"goto"}},"screen":"paywall_lumen_welcome_offer"},"route":{"branches":[{"goto":"lumen_recap","when":{"goal":{"eq":{"literal":"curious","type":"string"}}}}],"default":{"goto":"lumen_reminder"},"kind":"decision"}},"surveyQuestionOrder":["goal"],"version":1}',
    screens: {
      'lumen_welcome': LumenWelcomeScreen.new,
      'lumen_experience': LumenExperienceScreen.new,
      'lumen_goal': LumenGoalScreen.new,
      'lumen_reminder': LumenReminderScreen.new,
      'lumen_recap': LumenRecapScreen.new,
    },
    children: {},
  ),
  surfaceWidget: 'LumenOnboardingFlowSurface',
  measurementPublicationDraftDigest:
      '166c6211e11399c1bdb227f7daa2b3593d7fffe308700c9d02a86024540200d7',
  vocabulary: _lumenOnboardingFlowRefVocabulary,
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

final _lumenOnboardingFlowPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: lumenOnboardingFlowRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'onboarding',
    'slug': 'lumen_onboarding',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'flow',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{}
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': <String, Object?>{
      'schemaVersion': 1,
      'deliveryMode': 'typed',
      'hostSeedableState': <String, Object?>{},
      'actions': <String, Object?>{
        'enableReminders': <String, Object?>{
          'actionName': 'enableReminders',
          'contractVersion': 1,
          'argsSchema': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{}
          },
          'resultSchema': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'granted': <String, Object?>{
                'required': true,
                'schema': <String, Object?>{'kind': 'bool'}
              }
            }
          },
          'minClient': 6,
          'idempotent': false
        }
      },
      'signals': <Object?>[
        'close',
        'privacy',
        'restore_purchases',
        'sign_in',
        'terms'
      ],
      'outbound': <String, Object?>{
        'actionArgs': <String, Object?>{},
        'terminalResult': <String, Object?>{'completed': 'bool'},
        'lifecycle': <String, Object?>{},
        'surveyAnswers': <String, Object?>{'goal': 'string'},
        'subFlowResult': <String, Object?>{},
        'customEvents': <String, Object?>{
          'close': <String, Object?>{},
          'privacy': <String, Object?>{},
          'restore_purchases': <String, Object?>{},
          'sign_in': <String, Object?>{},
          'terms': <String, Object?>{}
        }
      }
    }
  },
  vocabulary: lumenOnboardingFlowRef.vocabulary,
);

final lumenOnboardingFlowPlacementDefinition =
    () => _lumenOnboardingFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class LumenOnboardingFlowSurface
    extends RestageFlowGraph<LumenOnboardingResult> {
  /// Mounts this flow at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  LumenOnboardingFlowSurface({
    super.key,
    required CompiledFlowScreenBuilder paywallLumenWelcomeOfferScreenBuilder,
    String? placement,
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
  })  : _restagePlacementName = placement,
        super(flow: lumenOnboardingFlowRef, screenBuilders: {
          'paywall_lumen_welcome_offer': paywallLumenWelcomeOfferScreenBuilder,
        });

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [LumenOnboardingFlowSurface] for the default placement; no name is needed.
  LumenOnboardingFlowSurface.atPlacement(
    String restagePlacementId, {
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
  })  : _restagePlacementName = restagePlacementId,
        super(flow: lumenOnboardingFlowRef, screenBuilders: {
          'paywall_lumen_welcome_offer': paywallLumenWelcomeOfferScreenBuilder,
        });

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: lumenOnboardingFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}
