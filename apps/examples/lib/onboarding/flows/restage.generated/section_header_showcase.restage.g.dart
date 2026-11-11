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
        '{"flow":"section_header_showcase","initial":"section_header_showcase","minClient":17,"outbound":{"customEvents":{"dismiss":{"fields":{}}}},"schemaVersion":1,"screenArtifacts":{"section_header_showcase":{"contentHash":"sha256:7a25cd5ec10d593202bdb433320360d9493abfd60e7115842d953ae3a58b8bc6","minClient":17,"path":"section_header_showcase.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"section_header_showcase":{"kind":"screen","on":{"act":{"target":"done","type":"goto"}},"screen":"section_header_showcase"}},"version":1}',
    screens: {
      'section_header_showcase': SectionHeaderShowcaseScreen.new,
    },
    children: {},
  ),
  surfaceWidget: 'SectionHeaderShowcaseFlowSurface',
  measurementPublicationDraftDigest:
      '2977013a01e78e1751115216cea3239e5bd87d5a5003fa4b4c30e35ca349f209',
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
