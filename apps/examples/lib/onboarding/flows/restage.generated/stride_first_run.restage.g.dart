part of '../stride_first_run.dart';

const strideFirstRunFlowRef = SurfaceFlowRef<
    Map<String, Object?>>.generatedWithMeasurementPublicationDraftDigest(
  id: 'stride_first_run',
  version: 2,
  minClient: 6,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.general,
  decodeResult: _decodeStrideFirstRunFlowResult,
  compiled: CompiledFlow(
    documentJson:
        "{\"actions\":{\"requestNotifications\":{\"actionName\":\"requestNotifications\",\"argsSchema\":{\"fields\":{},\"kind\":\"object\"},\"argsSchemaHash\":\"sha256:590f015bf5e877b53e3501b7e12ad48a11158d4c5b696f9a82593c4f3272411a\",\"contractVersion\":1,\"idempotent\":false,\"minClient\":6,\"resultSchema\":{\"fields\":{\"granted\":{\"required\":true,\"schema\":{\"kind\":\"bool\"}}},\"kind\":\"object\"},\"resultSchemaHash\":\"sha256:ef1c091bc0c82e02a9c18695d6ececbd01dee150396df8bea8ea2b8428ece4ec\"}},\"deliveryMode\":\"general\",\"flow\":\"stride_first_run\",\"flowState\":{\"completed\":{\"classification\":\"exportable\",\"type\":\"bool\"}},\"initial\":\"stride_welcome\",\"minClient\":6,\"outbound\":{\"customEvents\":{\"skip\":{\"fields\":{}}},\"terminalResult\":{\"fields\":{\"completed\":{\"ref\":{\"state\":\"completed\"},\"type\":\"bool\"}}}},\"schemaVersion\":1,\"screenArtifacts\":{\"stride_goals\":{\"contentHash\":\"sha256:c3c320c596dba6e5209c0c5db36b0d52bc44a2d8a853489910bef6adda93f482\",\"minClient\":6,\"path\":\"stride_goals.rfw\",\"schemaVersion\":1,\"version\":1},\"stride_ready\":{\"contentHash\":\"sha256:3cc55db192170bee046b65dea431e08107b6608480a213f53d1b96c07fa7ee88\",\"minClient\":6,\"path\":\"stride_ready.rfw\",\"schemaVersion\":1,\"version\":1},\"stride_reminders\":{\"contentHash\":\"sha256:18b9a0f0a0ed721d6de82236c3b1a1cc00d137e5cb81de418cf3f16cb0667dcd\",\"minClient\":6,\"path\":\"stride_reminders.rfw\",\"schemaVersion\":1,\"version\":1},\"stride_welcome\":{\"contentHash\":\"sha256:9e3cb89e23ddbba0da258557da8585b07aae726d579832d59f713e1b453a0134\",\"minClient\":6,\"path\":\"stride_welcome.rfw\",\"schemaVersion\":1,\"version\":1}},\"states\":{\"done\":{\"kind\":\"end\",\"result\":{\"completed\":true}},\"stride_goals\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"stride_reminders\",\"type\":\"goto\"}},\"screen\":\"stride_goals\"},\"stride_ready\":{\"kind\":\"screen\",\"on\":{\"begin\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"stride_ready\"},\"stride_reminders\":{\"kind\":\"screen\",\"on\":{\"enable\":{\"action\":\"requestNotifications\",\"resultPredicate\":{\"field\":\"granted\",\"kind\":\"objectBoolFieldEquals\",\"value\":true},\"target\":\"stride_ready\",\"type\":\"action\"}},\"screen\":\"stride_reminders\"},\"stride_welcome\":{\"kind\":\"screen\",\"on\":{\"start\":{\"target\":\"stride_goals\",\"type\":\"goto\"}},\"screen\":\"stride_welcome\"}},\"version\":2}",
    screens: {
      "stride_welcome": StrideWelcomeScreen.new,
      "stride_goals": StrideGoalsScreen.new,
      "stride_reminders": StrideRemindersScreen.new,
      "stride_ready": StrideReadyScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '7280ee9b48974f8f18791c52da5ac448499806f48d969a584c341bca25482e80',
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
        0xf635: IconData(0xf635, fontFamily: 'MaterialIcons'),
        0xf6b8: IconData(0xf6b8, fontFamily: 'MaterialIcons'),
        0xf768: IconData(0xf768, fontFamily: 'MaterialIcons'),
        0xf0026: IconData(0xf0026, fontFamily: 'MaterialIcons'),
      },
    }),
  ),
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
    minClient: 6,
    idempotent: false,
  );

  @override
  Set<String> get installedSignalNames => const {'skip'};
}

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class StrideFirstRunFlowSurface
    extends RestageFlowGraph<Map<String, Object?>> {
  const StrideFirstRunFlowSurface({
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
  }) : super(flow: strideFirstRunFlowRef);
}
