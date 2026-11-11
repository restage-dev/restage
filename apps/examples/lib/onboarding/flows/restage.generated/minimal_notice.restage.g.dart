part of '../minimal_notice.dart';

// ignore_for_file: type=lint, unnecessary_cast

const _minimalNoticeFlowRefVocabulary = SurfaceVocabulary(
  widgets: RestageWidgetLibraries.fromVocabulary(
    core: {
      'Column': buildColumn,
      'Padding': buildPadding,
      'SafeArea': buildSafeArea,
      'SizedBox': buildSizedBox,
      'Spacer': buildSpacer,
      'Text': buildText,
    },
    material: {
      'AppBar': buildAppBar,
      'FilledButton': buildFilledButton,
      'Icon': buildIcon,
      'IconButton': buildIconButton,
      'Scaffold': buildScaffold,
    },
  ),
  icons: RestageIconTable.fromFamilies(families: {
    'MaterialIcons': {
      0xf614: IconData(0xf614, fontFamily: 'MaterialIcons'),
      0xf647: IconData(0xf647, fontFamily: 'MaterialIcons'),
    },
  }),
);

const minimalNoticeFlowRef = SurfaceFlowRef<
    MinimalNoticeResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'minimal_notice',
  version: 1,
  minClient: 17,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeMinimalNoticeFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"minimal_notice","initial":"starter_notice","minClient":17,"outbound":{"customEvents":{"dismiss":{"fields":{}}}},"schemaVersion":1,"screenArtifacts":{"starter_notice":{"contentHash":"sha256:c824c46c94cb9c6be0cb64c135448ebeb7611172af6570f5a50599fc2aa9927f","minClient":17,"path":"starter_notice.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"starter_notice":{"kind":"screen","on":{"act":{"target":"done","type":"goto"}},"screen":"starter_notice"}},"version":1}',
    screens: {
      'starter_notice': StarterNoticeScreen.new,
    },
    children: {},
  ),
  surfaceWidget: 'MinimalNoticeFlowSurface',
  measurementPublicationDraftDigest:
      '2d8e2771203b9577157fc896811456ff7836ef0a3b67cb979c04171105adb142',
  vocabulary: _minimalNoticeFlowRefVocabulary,
);

MinimalNoticeResult _decodeMinimalNoticeFlowResult(
    Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const MinimalNoticeResult();
}

@Deprecated('Use minimalNoticeFlowRef')
abstract final class MinimalNoticeFlowDescriptor {
  const MinimalNoticeFlowDescriptor._();

  static const SurfaceFlowRef<MinimalNoticeResult> ref = minimalNoticeFlowRef;
}

final class MinimalNoticeResult {
  const MinimalNoticeResult();
}

final class MinimalNoticeActions {
  const MinimalNoticeActions();
}

final _minimalNoticeFlowPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: minimalNoticeFlowRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'onboarding',
    'slug': 'minimal_notice',
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
  vocabulary: minimalNoticeFlowRef.vocabulary,
);

final minimalNoticeFlowPlacementDefinition =
    () => _minimalNoticeFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class MinimalNoticeFlowSurface
    extends RestageFlowGraph<MinimalNoticeResult> {
  /// Mounts this flow at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const MinimalNoticeFlowSurface({
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
        super(flow: minimalNoticeFlowRef);

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [MinimalNoticeFlowSurface] for the default placement; no name is needed.
  const MinimalNoticeFlowSurface.atPlacement(
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
        super(flow: minimalNoticeFlowRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: minimalNoticeFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}
