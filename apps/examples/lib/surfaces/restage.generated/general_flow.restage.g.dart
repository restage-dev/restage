part of '../general_flow.dart';

// ignore_for_file: type=lint

const generalJourneyRef = SurfaceFlowRef<
    GeneralJourneyResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'general_journey',
  version: 1,
  minClient: 1,
  surface: Surface.general,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeGeneralJourneyResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"general_journey","initial":"general_status","minClient":1,"outbound":{},"schemaVersion":1,"screenArtifacts":{"general_status":{"contentHash":"sha256:7fed04db5118f0332cc89220594b96a3273312c106b8648969c50a4078229faf","minClient":1,"path":"measurement/83088be4886b490b/general_status.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"general_status":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"general_status"}},"version":1}',
    screens: {
      'general_status': GeneralStatus.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '4ac9de0c0db6d0be76db838474000d49a39a1e7466f3db25e6411e03490e8cfd',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
      material: {
        'FilledButton': buildFilledButton,
      },
    ),
  ),
);

GeneralJourneyResult _decodeGeneralJourneyResult(Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const GeneralJourneyResult();
}

final class GeneralJourneyResult {
  const GeneralJourneyResult();
}

final _generalJourneyPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: generalJourneyRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'general',
    'slug': 'general_journey',
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
      'actions': <String, Object?>{},
      'signals': <Object?>[],
      'outbound': <String, Object?>{
        'actionArgs': <String, Object?>{},
        'terminalResult': <String, Object?>{},
        'lifecycle': <String, Object?>{},
        'surveyAnswers': <String, Object?>{},
        'subFlowResult': <String, Object?>{},
        'customEvents': <String, Object?>{}
      }
    }
  },
  vocabulary: generalJourneyRef.vocabulary,
);

final generalJourneyPlacementDefinition =
    () => _generalJourneyPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class GeneralJourneySurface
    extends RestageFlowGraph<GeneralJourneyResult> {
  /// Mounts this flow at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const GeneralJourneySurface({
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
        super(flow: generalJourneyRef);

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [GeneralJourneySurface] for the default placement; no name is needed.
  const GeneralJourneySurface.atPlacement(
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
        super(flow: generalJourneyRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: generalJourneyPlacementDefinition,
        name: _restagePlacementName,
      );
}
