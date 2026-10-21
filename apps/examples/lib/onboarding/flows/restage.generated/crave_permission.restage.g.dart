part of '../crave_permission.dart';

// ignore_for_file: type=lint

const cravePermissionFlowRef = SurfaceFlowRef<
    CravePermissionResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'crave_permission',
  version: 1,
  minClient: 12,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeCravePermissionFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"actions":{"requestLocation":{"actionName":"requestLocation","argsSchema":{"fields":{},"kind":"object"},"argsSchemaHash":"sha256:590f015bf5e877b53e3501b7e12ad48a11158d4c5b696f9a82593c4f3272411a","contractVersion":1,"idempotent":false,"minClient":6,"resultSchema":{"fields":{"granted":{"required":true,"schema":{"kind":"bool"}}},"kind":"object"},"resultSchemaHash":"sha256:ef1c091bc0c82e02a9c18695d6ececbd01dee150396df8bea8ea2b8428ece4ec"}},"flow":"crave_permission","flowState":{"locationEnabled":{"classification":"exportable","type":"bool"}},"initial":"crave_location","minClient":12,"outbound":{"customEvents":{"skip":{"fields":{}}},"terminalResult":{"fields":{"locationEnabled":{"ref":{"state":"locationEnabled"},"type":"bool"}}}},"schemaVersion":1,"screenArtifacts":{"crave_location":{"contentHash":"sha256:b438a8096b2c4343ac1e4a3fdd8b98532c3d40d96a9301193da2199ef5fdf4d9","minClient":12,"path":"crave_location.rfw","schemaVersion":1,"version":1},"crave_ready":{"contentHash":"sha256:ad8b4b0f458437a4a54621d728f019fd9cac502b1d949c844ef54fcf29e6c5d8","minClient":12,"path":"crave_ready.rfw","schemaVersion":1,"version":1}},"states":{"crave_location":{"kind":"screen","on":{"allow":{"action":"requestLocation","resultPredicate":{"field":"granted","kind":"objectBoolFieldEquals","value":true},"target":"crave_ready","type":"action"}},"screen":"crave_location"},"crave_ready":{"kind":"screen","on":{"start":{"target":"done","type":"goto"}},"screen":"crave_ready"},"done":{"kind":"end","result":{"locationEnabled":true}}},"version":1}',
    screens: {
      'crave_location': CraveLocationScreen.new,
      'crave_ready': CraveReadyScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '3af587bd668d3e3682acf202151f04a1e8b018795113a26152234667d2774769',
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

final _cravePermissionFlowPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: cravePermissionFlowRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'onboarding',
    'slug': 'crave_permission',
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
        'requestLocation': <String, Object?>{
          'actionName': 'requestLocation',
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
        'terminalResult': <String, Object?>{'locationEnabled': 'bool'},
        'lifecycle': <String, Object?>{},
        'surveyAnswers': <String, Object?>{},
        'subFlowResult': <String, Object?>{},
        'customEvents': <String, Object?>{'skip': <String, Object?>{}}
      }
    }
  },
  vocabulary: cravePermissionFlowRef.vocabulary,
);

final cravePermissionFlowPlacementDefinition =
    () => _cravePermissionFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class CravePermissionFlowSurface
    extends RestageFlowGraph<CravePermissionResult> {
  /// Mounts this flow at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const CravePermissionFlowSurface({
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
        super(flow: cravePermissionFlowRef);

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [CravePermissionFlowSurface] for the default placement; no name is needed.
  const CravePermissionFlowSurface.atPlacement(
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
        super(flow: cravePermissionFlowRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: cravePermissionFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}
