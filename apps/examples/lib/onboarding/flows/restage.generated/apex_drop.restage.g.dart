part of '../apex_drop.dart';

// ignore_for_file: type=lint, unnecessary_cast

const _apexDropFlowRefVocabulary = SurfaceVocabulary(
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
);

const apexDropFlowRef = SurfaceFlowRef<
    ApexDropResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'apex_drop',
  version: 1,
  minClient: 17,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeApexDropFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"apex_drop","initial":"apex_drop","minClient":17,"outbound":{"customEvents":{"dismiss":{"fields":{}}}},"schemaVersion":1,"screenArtifacts":{"apex_drop":{"contentHash":"sha256:4ee5ef21a298d6ab32cd6a2f52f7e25ea05cc4b75d4f50e95cf4377c35f5aa2d","minClient":17,"path":"apex_drop.rfw","schemaVersion":1,"version":1}},"states":{"apex_drop":{"kind":"screen","on":{"act":{"target":"done","type":"goto"}},"screen":"apex_drop"},"done":{"kind":"end","result":{}}},"version":1}',
    screens: {
      'apex_drop': ApexDropScreen.new,
    },
    children: {},
  ),
  surfaceWidget: 'ApexDropFlowSurface',
  measurementPublicationDraftDigest:
      '68abcb6a82f3e2b81e83bdc33eb049390255d3e745fa1d47d37dd819609470b7',
  vocabulary: _apexDropFlowRefVocabulary,
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
    super.fallbackBuilder,
    super.errorBuilder,
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
    super.fallbackBuilder,
    super.errorBuilder,
  })  : _restagePlacementName = restagePlacementId,
        super(flow: apexDropFlowRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: apexDropFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}
