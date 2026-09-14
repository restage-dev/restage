part of '../crave_permission.dart';

const cravePermissionFlowRef = SurfaceFlowRef<
    CravePermissionResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'crave_permission',
  version: 1,
  minClient: 6,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeCravePermissionFlowResult,
  compiled: CompiledFlow(
    documentJson:
        "{\"actions\":{\"requestLocation\":{\"actionName\":\"requestLocation\",\"argsSchema\":{\"fields\":{},\"kind\":\"object\"},\"argsSchemaHash\":\"sha256:590f015bf5e877b53e3501b7e12ad48a11158d4c5b696f9a82593c4f3272411a\",\"contractVersion\":1,\"idempotent\":false,\"minClient\":6,\"resultSchema\":{\"fields\":{\"granted\":{\"required\":true,\"schema\":{\"kind\":\"bool\"}}},\"kind\":\"object\"},\"resultSchemaHash\":\"sha256:ef1c091bc0c82e02a9c18695d6ececbd01dee150396df8bea8ea2b8428ece4ec\"}},\"flow\":\"crave_permission\",\"flowState\":{\"locationEnabled\":{\"classification\":\"exportable\",\"type\":\"bool\"}},\"initial\":\"crave_location\",\"minClient\":6,\"outbound\":{\"customEvents\":{\"skip\":{\"fields\":{}}},\"terminalResult\":{\"fields\":{\"locationEnabled\":{\"ref\":{\"state\":\"locationEnabled\"},\"type\":\"bool\"}}}},\"schemaVersion\":1,\"screenArtifacts\":{\"crave_location\":{\"contentHash\":\"sha256:15ceee212ce856d2e9aa6db93c4c55724b651deefe2f64a03ca7549f5259f6f4\",\"minClient\":6,\"path\":\"crave_location.rfw\",\"schemaVersion\":1,\"version\":1},\"crave_ready\":{\"contentHash\":\"sha256:11a345f65dc2b943d0021a42040085987e660977275f65cff73192fd712a7f2a\",\"minClient\":6,\"path\":\"crave_ready.rfw\",\"schemaVersion\":1,\"version\":1}},\"states\":{\"crave_location\":{\"kind\":\"screen\",\"on\":{\"allow\":{\"action\":\"requestLocation\",\"resultPredicate\":{\"field\":\"granted\",\"kind\":\"objectBoolFieldEquals\",\"value\":true},\"target\":\"crave_ready\",\"type\":\"action\"}},\"screen\":\"crave_location\"},\"crave_ready\":{\"kind\":\"screen\",\"on\":{\"start\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"crave_ready\"},\"done\":{\"kind\":\"end\",\"result\":{\"locationEnabled\":true}}},\"version\":1}",
    screens: {
      "crave_location": CraveLocationScreen.new,
      "crave_ready": CraveReadyScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '7db00203878987dd69ddcd26db9d6e0768b0177c8a77241bff43cb63d84c00b9',
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
        0xf8f8: IconData(0xf8f8, fontFamily: 'MaterialIcons'),
      },
    }),
  ),
);

CravePermissionResult _decodeCravePermissionFlowResult(
    Map<String, Object?> result) {
  if (result.length != 1 || !result.containsKey('locationEnabled')) {
    throw const FormatException('Unexpected flow result keys.');
  }
  final locationEnabled = result['locationEnabled'];
  if (locationEnabled is! bool) {
    throw const FormatException(
        'Expected result field locationEnabled to be bool.');
  }
  return CravePermissionResult(locationEnabled: locationEnabled);
}

@Deprecated('Use cravePermissionFlowRef')
abstract final class CravePermissionFlowDescriptor {
  const CravePermissionFlowDescriptor._();

  static const SurfaceFlowRef<CravePermissionResult> ref =
      cravePermissionFlowRef;
}

final class CravePermissionResult {
  const CravePermissionResult({required this.locationEnabled});
  final bool locationEnabled;
}

final class CravePermissionActions implements FlowActionRegistry {
  CravePermissionActions({
    required FlowActionHandler<void, LocationDecision> requestLocation,
  }) : flowActionBindings =
            Map<String, FlowActionBinding<dynamic, dynamic>>.unmodifiable({
          'requestLocation': FlowActionBinding<void, LocationDecision>(
            descriptor: requestLocationDescriptor,
            actionName: requestLocationDescriptor.actionName,
            contractVersion: requestLocationDescriptor.contractVersion,
            argsSchema: requestLocationDescriptor.argsSchema,
            resultSchema: requestLocationDescriptor.resultSchema,
            minClient: requestLocationDescriptor.minClient,
            idempotent: requestLocationDescriptor.idempotent,
            handler: requestLocation,
            decodeArgs: (_) {},
            encodeResult: (value) => {'granted': value.granted},
          ),
        });

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;

  static final FlowActionDescriptor<void, LocationDecision>
      requestLocationDescriptor = FlowActionDescriptor<void, LocationDecision>(
    actionName: 'requestLocation',
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
final class CravePermissionFlowSurface
    extends RestageFlowGraph<CravePermissionResult> {
  const CravePermissionFlowSurface({
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
  }) : super(flow: cravePermissionFlowRef);
}
