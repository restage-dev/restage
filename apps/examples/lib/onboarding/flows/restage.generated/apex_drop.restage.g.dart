part of '../apex_drop.dart';

// ignore_for_file: type=lint

const apexDropFlowRef = SurfaceFlowRef<
    ApexDropResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'apex_drop',
  version: 1,
  minClient: 12,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeApexDropFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"apex_drop","initial":"apex_drop","minClient":12,"outbound":{"customEvents":{"dismiss":{"fields":{}}}},"schemaVersion":1,"screenArtifacts":{"apex_drop":{"contentHash":"sha256:acae95667cd778d1a309d005da9661a035ff8d817505e11a667143ba519806fe","minClient":12,"path":"apex_drop.rfw","schemaVersion":1,"version":1}},"states":{"apex_drop":{"kind":"screen","on":{"act":{"target":"done","type":"goto"}},"screen":"apex_drop"},"done":{"kind":"end","result":{}}},"version":1}',
    screens: {
      'apex_drop': ApexDropScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '27e0d4c4c1e158cb4d8e25b69dccedbfdfca9de47b881f22c4f2b7a71e604caa',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Center': buildCenter,
        'Column': buildColumn,
        'Container': buildContainer,
        'Padding': buildPadding,
        'Row': buildRow,
        'SafeArea': buildSafeArea,
        'SizedBox': buildSizedBox,
        'Spacer': buildSpacer,
        'Text': buildText,
      },
      material: {
        'FilledButton': buildFilledButton,
        'Icon': buildIcon,
        'IconButton': buildIconButton,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf647: IconData(0xf647, fontFamily: 'MaterialIcons'),
        0xf76d: IconData(0xf76d, fontFamily: 'MaterialIcons'),
      },
    }),
  ),
);

ApexDropResult _decodeApexDropFlowResult(Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const ApexDropResult();
}

@Deprecated('Use apexDropFlowRef')
abstract final class ApexDropFlowDescriptor {
  const ApexDropFlowDescriptor._();

  static const SurfaceFlowRef<ApexDropResult> ref = apexDropFlowRef;
}

final class ApexDropResult {
  const ApexDropResult();
}

final class ApexDropActions {
  const ApexDropActions();
}

final _apexDropFlowPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: apexDropFlowRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'onboarding',
    'slug': 'apex_drop',
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
      'signals': <Object?>['dismiss'],
      'outbound': <String, Object?>{
        'actionArgs': <String, Object?>{},
        'terminalResult': <String, Object?>{},
        'lifecycle': <String, Object?>{},
        'surveyAnswers': <String, Object?>{},
        'subFlowResult': <String, Object?>{},
        'customEvents': <String, Object?>{'dismiss': <String, Object?>{}}
      }
    }
  },
  vocabulary: apexDropFlowRef.vocabulary,
);

final apexDropFlowPlacementDefinition =
    () => _apexDropFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class ApexDropFlowSurface extends RestageFlowGraph<ApexDropResult> {
  /// Mounts this flow at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ApexDropFlowSurface({
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
        super(flow: apexDropFlowRef);

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ApexDropFlowSurface] for the default placement; no name is needed.
  const ApexDropFlowSurface.atPlacement(
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
        super(flow: apexDropFlowRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: apexDropFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}
