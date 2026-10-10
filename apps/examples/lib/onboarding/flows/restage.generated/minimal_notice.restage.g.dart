part of '../minimal_notice.dart';

// ignore_for_file: type=lint

const minimalNoticeFlowRef = SurfaceFlowRef<
    MinimalNoticeResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'minimal_notice',
  version: 1,
  minClient: 9,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeMinimalNoticeFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"minimal_notice","initial":"starter_notice","minClient":9,"outbound":{"customEvents":{"dismiss":{"fields":{}}}},"schemaVersion":1,"screenArtifacts":{"starter_notice":{"contentHash":"sha256:036fad8ac7f265dcef0ebe8b266809a210f1f517996c04ed8d80196c986057c8","minClient":9,"path":"starter_notice.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"starter_notice":{"kind":"screen","on":{"act":{"target":"done","type":"goto"}},"screen":"starter_notice"}},"version":1}',
    screens: {
      'starter_notice': StarterNoticeScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      'ef21c42f55d43ea452e54454ba96eee2c59795734dd9619bc38665facf8c6f26',
  vocabulary: SurfaceVocabulary(
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
  ),
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
  vocabulary: minimalNoticeFlowRef.vocabulary,
);

final minimalNoticeFlowPlacementDefinition =
    () => _minimalNoticeFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class MinimalNoticeFlowSurface
    extends RestageFlowGraph<MinimalNoticeResult> {
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
    super.unavailable = const FlowUnavailablePolicy.hide(),
  })  : _restagePlacementName = placement,
        super(flow: minimalNoticeFlowRef);

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
    super.unavailable = const FlowUnavailablePolicy.hide(),
  })  : _restagePlacementName = restagePlacementId,
        super(flow: minimalNoticeFlowRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: minimalNoticeFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}
