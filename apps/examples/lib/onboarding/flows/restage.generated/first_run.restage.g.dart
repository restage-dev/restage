part of '../first_run.dart';

// ignore_for_file: type=lint

const firstRunFlowRef = SurfaceFlowRef<
    FirstRunResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'first_run',
  version: 1,
  minClient: 10,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeFirstRunFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"actions":{"requestNotifications":{"actionName":"requestNotifications","argsSchema":{"fields":{},"kind":"object"},"argsSchemaHash":"sha256:590f015bf5e877b53e3501b7e12ad48a11158d4c5b696f9a82593c4f3272411a","contractVersion":1,"idempotent":false,"minClient":6,"resultSchema":{"fields":{"granted":{"required":true,"schema":{"kind":"bool"}}},"kind":"object"},"resultSchemaHash":"sha256:ef1c091bc0c82e02a9c18695d6ececbd01dee150396df8bea8ea2b8428ece4ec"}},"flow":"first_run","flowState":{"completed":{"classification":"exportable","type":"bool"}},"initial":"welcome","minClient":10,"outbound":{"customEvents":{"skip":{"fields":{}}},"terminalResult":{"fields":{"completed":{"ref":{"state":"completed"},"type":"bool"}}}},"schemaVersion":1,"screenArtifacts":{"notify":{"contentHash":"sha256:69de866e8216e048a4801a06cc1a30c875245f98a2dbd6081443b13db8666dce","minClient":10,"path":"notify.rfw","schemaVersion":1,"version":1},"ready":{"contentHash":"sha256:3827777b4a73afcae5edc86d0c8c8aa73635d36a5b11e6fbd34c7d727e27e2ad","minClient":10,"path":"ready.rfw","schemaVersion":1,"version":1},"value":{"contentHash":"sha256:f0fa92dfe3f010101ccc0b031cacb369f73c44ace32ae91f01d05478293dc2b7","minClient":10,"path":"value.rfw","schemaVersion":1,"version":1},"welcome":{"contentHash":"sha256:fab25148acb8e0451b99045d393c32e692fa3dea3772e74b7e446fd8380ae36a","minClient":10,"path":"welcome.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{"completed":true}},"notify":{"kind":"screen","on":{"enable":{"action":"requestNotifications","resultPredicate":{"field":"granted","kind":"objectBoolFieldEquals","value":true},"target":"ready","type":"action"}},"screen":"notify"},"ready":{"kind":"screen","on":{"start":{"target":"done","type":"goto"}},"screen":"ready"},"value":{"kind":"screen","on":{"next":{"target":"notify","type":"goto"}},"screen":"value"},"welcome":{"kind":"screen","on":{"next":{"target":"value","type":"goto"}},"screen":"welcome"}},"version":1}',
    screens: {
      'welcome': WelcomeScreen.new,
      'value': ValueScreen.new,
      'notify': NotifyScreen.new,
      'ready': ReadyScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '37da92cb35d43023597667c2ed6aa3ec3c861e0d98de5a9a4fcaab2e231bd1e9',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Container': buildContainer,
        'Expanded': buildExpanded,
        'Padding': buildPadding,
        'Row': buildRow,
        'SafeArea': buildSafeArea,
        'SizedBox': buildSizedBox,
        'Text': buildText,
      },
      material: {
        'AppBar': buildAppBar,
        'FilledButton': buildFilledButton,
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
        'TextButton': buildTextButton,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf5fe: IconData(0xf5fe, fontFamily: 'MaterialIcons'),
        0xf636: IconData(0xf636, fontFamily: 'MaterialIcons'),
        0xf0026: IconData(0xf0026, fontFamily: 'MaterialIcons'),
        0xf0144: IconData(0xf0144, fontFamily: 'MaterialIcons'),
      },
    }),
  ),
);

FirstRunResult _decodeFirstRunFlowResult(Map<String, Object?> result) {
  if (result.length != 1 || !result.containsKey('completed')) {
    throw const FormatException('Unexpected flow result keys.');
  }
  final completed = result['completed'];
  if (completed is! bool) {
    throw const FormatException('Expected result field completed to be bool.');
  }
  return FirstRunResult(completed: completed);
}

@Deprecated('Use firstRunFlowRef')
abstract final class FirstRunFlowDescriptor {
  const FirstRunFlowDescriptor._();

  static const SurfaceFlowRef<FirstRunResult> ref = firstRunFlowRef;
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
    minClient: 6,
    idempotent: false,
  );
}

final _firstRunFlowPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: firstRunFlowRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'onboarding',
    'slug': 'first_run',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'flow',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'inputs': <String, Object?>{},
      'schemaVersion': 1
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
        'requestNotifications': <String, Object?>{
          'actionName': 'requestNotifications',
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
      'signals': <Object?>['skip'],
      'outbound': <String, Object?>{
        'actionArgs': <String, Object?>{},
        'terminalResult': <String, Object?>{'completed': 'bool'},
        'lifecycle': <String, Object?>{},
        'surveyAnswers': <String, Object?>{},
        'subFlowResult': <String, Object?>{},
        'customEvents': <String, Object?>{'skip': <String, Object?>{}}
      }
    }
  },
  vocabulary: firstRunFlowRef.vocabulary,
);

final firstRunFlowPlacementDefinition =
    () => _firstRunFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class FirstRunFlowSurface extends RestageFlowGraph<FirstRunResult> {
  /// Mounts this flow at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const FirstRunFlowSurface({
    super.key,
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
        super(flow: firstRunFlowRef);

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [FirstRunFlowSurface] for the default placement; no name is needed.
  const FirstRunFlowSurface.atPlacement(
    String restagePlacementId, {
    super.key,
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
        super(flow: firstRunFlowRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: firstRunFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}
