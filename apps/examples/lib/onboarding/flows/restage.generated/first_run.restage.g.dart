part of '../first_run.dart';

// ignore_for_file: type=lint

const firstRunFlowRef = SurfaceFlowRef<
    FirstRunResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'first_run',
  version: 1,
  minClient: 9,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeFirstRunFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"actions":{"requestNotifications":{"actionName":"requestNotifications","argsSchema":{"fields":{},"kind":"object"},"argsSchemaHash":"sha256:590f015bf5e877b53e3501b7e12ad48a11158d4c5b696f9a82593c4f3272411a","contractVersion":1,"idempotent":false,"minClient":6,"resultSchema":{"fields":{"granted":{"required":true,"schema":{"kind":"bool"}}},"kind":"object"},"resultSchemaHash":"sha256:ef1c091bc0c82e02a9c18695d6ececbd01dee150396df8bea8ea2b8428ece4ec"}},"flow":"first_run","flowState":{"completed":{"classification":"exportable","type":"bool"}},"initial":"welcome","minClient":9,"outbound":{"customEvents":{"skip":{"fields":{}}},"terminalResult":{"fields":{"completed":{"ref":{"state":"completed"},"type":"bool"}}}},"schemaVersion":1,"screenArtifacts":{"notify":{"contentHash":"sha256:a47364bb6849ee3208c0dd0c0742990e2a93b888065deea45a18848d8e5658f2","minClient":9,"path":"notify.rfw","schemaVersion":1,"version":1},"ready":{"contentHash":"sha256:e16282a5aeec0b872491b211228c9d952827dd395c93200e240db77ca311e3a2","minClient":9,"path":"ready.rfw","schemaVersion":1,"version":1},"value":{"contentHash":"sha256:8b25b8e19a6360cc99ee2b12fbb91d0481c3f6a93d0dfeb6147d23917096b047","minClient":9,"path":"value.rfw","schemaVersion":1,"version":1},"welcome":{"contentHash":"sha256:732f0dd8b7b52edd4285436232f4663c1ea1989402574b24936e7944b8f27724","minClient":9,"path":"welcome.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{"completed":true}},"notify":{"kind":"screen","on":{"enable":{"action":"requestNotifications","resultPredicate":{"field":"granted","kind":"objectBoolFieldEquals","value":true},"target":"ready","type":"action"}},"screen":"notify"},"ready":{"kind":"screen","on":{"start":{"target":"done","type":"goto"}},"screen":"ready"},"value":{"kind":"screen","on":{"next":{"target":"notify","type":"goto"}},"screen":"value"},"welcome":{"kind":"screen","on":{"next":{"target":"value","type":"goto"}},"screen":"welcome"}},"version":1}',
    screens: {
      'welcome': WelcomeScreen.new,
      'value': ValueScreen.new,
      'notify': NotifyScreen.new,
      'ready': ReadyScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      'c2cfadf2cb36afb9e5cebf710c6b6c464af52a8bd2e8d125da1ead0010f665ac',
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

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class FirstRunFlowSurface extends RestageFlowGraph<FirstRunResult> {
  const FirstRunFlowSurface({
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
  }) : super(flow: firstRunFlowRef);
}
