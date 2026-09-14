part of '../first_run.dart';

const firstRunFlowRef = SurfaceFlowRef<
    FirstRunResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'first_run',
  version: 1,
  minClient: 6,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeFirstRunFlowResult,
  compiled: CompiledFlow(
    documentJson:
        "{\"actions\":{\"requestNotifications\":{\"actionName\":\"requestNotifications\",\"argsSchema\":{\"fields\":{},\"kind\":\"object\"},\"argsSchemaHash\":\"sha256:590f015bf5e877b53e3501b7e12ad48a11158d4c5b696f9a82593c4f3272411a\",\"contractVersion\":1,\"idempotent\":false,\"minClient\":6,\"resultSchema\":{\"fields\":{\"granted\":{\"required\":true,\"schema\":{\"kind\":\"bool\"}}},\"kind\":\"object\"},\"resultSchemaHash\":\"sha256:ef1c091bc0c82e02a9c18695d6ececbd01dee150396df8bea8ea2b8428ece4ec\"}},\"flow\":\"first_run\",\"flowState\":{\"completed\":{\"classification\":\"exportable\",\"type\":\"bool\"}},\"initial\":\"welcome\",\"minClient\":6,\"outbound\":{\"customEvents\":{\"skip\":{\"fields\":{}}},\"terminalResult\":{\"fields\":{\"completed\":{\"ref\":{\"state\":\"completed\"},\"type\":\"bool\"}}}},\"schemaVersion\":1,\"screenArtifacts\":{\"notify\":{\"contentHash\":\"sha256:9cd953204f78ce572ac761edcddf0747b486e04d72c47180a4e328c736a6ece5\",\"minClient\":6,\"path\":\"notify.rfw\",\"schemaVersion\":1,\"version\":1},\"ready\":{\"contentHash\":\"sha256:90033f1402bb4143b4055ecc9930fb45973ff86959b5c4ed4e4f64c945ce74f4\",\"minClient\":6,\"path\":\"ready.rfw\",\"schemaVersion\":1,\"version\":1},\"value\":{\"contentHash\":\"sha256:d12a99d63335e46b9c36b3ae64be40980bfc14aaa4ee6821d35d496c03ca80d4\",\"minClient\":6,\"path\":\"value.rfw\",\"schemaVersion\":1,\"version\":1},\"welcome\":{\"contentHash\":\"sha256:6fd7f2ee612868dc2ff4fb4765d9387f3c8f2ed4965bb1ef83bdb1aa3798c03c\",\"minClient\":6,\"path\":\"welcome.rfw\",\"schemaVersion\":1,\"version\":1}},\"states\":{\"done\":{\"kind\":\"end\",\"result\":{\"completed\":true}},\"notify\":{\"kind\":\"screen\",\"on\":{\"enable\":{\"action\":\"requestNotifications\",\"resultPredicate\":{\"field\":\"granted\",\"kind\":\"objectBoolFieldEquals\",\"value\":true},\"target\":\"ready\",\"type\":\"action\"}},\"screen\":\"notify\"},\"ready\":{\"kind\":\"screen\",\"on\":{\"start\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"ready\"},\"value\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"notify\",\"type\":\"goto\"}},\"screen\":\"value\"},\"welcome\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"value\",\"type\":\"goto\"}},\"screen\":\"welcome\"}},\"version\":1}",
    screens: {
      "welcome": WelcomeScreen.new,
      "value": ValueScreen.new,
      "notify": NotifyScreen.new,
      "ready": ReadyScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      'df65b815514d314666235a3c9b9a1793ccb9e77bfa9663c810ff630a13544e5c',
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
