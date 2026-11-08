part of '../section_header_showcase.dart';

// ignore_for_file: type=lint, unnecessary_cast

const _sectionHeaderShowcaseFlowRefVocabulary = SurfaceVocabulary(
  widgets: RestageWidgetLibraries.fromVocabulary(
    core: {
      'Column': buildColumn,
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
    },
  }),
);

const sectionHeaderShowcaseFlowRef = SurfaceFlowRef<
    SectionHeaderShowcaseResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'section_header_showcase',
  version: 1,
  minClient: 17,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeSectionHeaderShowcaseFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"section_header_showcase","initial":"section_header_showcase","minClient":17,"outbound":{"customEvents":{"dismiss":{"fields":{}}}},"schemaVersion":1,"screenArtifacts":{"section_header_showcase":{"contentHash":"sha256:0cf0af5920a211460a72c0a2f27a7661382890b73f5b99ff6d1d07671b5434b3","minClient":17,"path":"section_header_showcase.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"section_header_showcase":{"kind":"screen","on":{"act":{"target":"done","type":"goto"}},"screen":"section_header_showcase"}},"version":1}',
    screens: {
      'section_header_showcase': SectionHeaderShowcaseScreen.new,
    },
    children: {},
  ),
  surfaceWidget: 'SectionHeaderShowcaseFlowSurface',
  measurementPublicationDraftDigest:
      '85079ffd02ac3ea44284167cdea4c5f5dd77e958f23ac8ef7d97d15f3ed63f46',
  vocabulary: _sectionHeaderShowcaseFlowRefVocabulary,
);

SectionHeaderShowcaseResult _decodeSectionHeaderShowcaseFlowResult(
    Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const SectionHeaderShowcaseResult();
}

@Deprecated('Use sectionHeaderShowcaseFlowRef')
abstract final class SectionHeaderShowcaseFlowDescriptor {
  const SectionHeaderShowcaseFlowDescriptor._();

  static const SurfaceFlowRef<SectionHeaderShowcaseResult> ref =
      sectionHeaderShowcaseFlowRef;
}

final class SectionHeaderShowcaseResult {
  const SectionHeaderShowcaseResult();
}

final class SectionHeaderShowcaseActions {
  const SectionHeaderShowcaseActions();
}

final _sectionHeaderShowcaseFlowPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: sectionHeaderShowcaseFlowRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'onboarding',
    'slug': 'section_header_showcase',
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
  vocabulary: sectionHeaderShowcaseFlowRef.vocabulary,
);

final sectionHeaderShowcaseFlowPlacementDefinition =
    () => _sectionHeaderShowcaseFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class SectionHeaderShowcaseFlowSurface
    extends RestageFlowGraph<SectionHeaderShowcaseResult> {
  /// Mounts this flow at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const SectionHeaderShowcaseFlowSurface({
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
        super(flow: sectionHeaderShowcaseFlowRef);

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [SectionHeaderShowcaseFlowSurface] for the default placement; no name is needed.
  const SectionHeaderShowcaseFlowSurface.atPlacement(
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
        super(flow: sectionHeaderShowcaseFlowRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: sectionHeaderShowcaseFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}
