part of '../apex_drop.dart';

// ignore_for_file: type=lint

const apexDropFlowRef = SurfaceFlowRef<
    ApexDropResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'apex_drop',
  version: 1,
  minClient: 9,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeApexDropFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"apex_drop","initial":"apex_drop","minClient":9,"outbound":{"customEvents":{"dismiss":{"fields":{}}}},"schemaVersion":1,"screenArtifacts":{"apex_drop":{"contentHash":"sha256:2be9387241d683e1855efdafe8d3942b875e25a1b7f3c36bc4bfdb48b390cb30","minClient":9,"path":"apex_drop.rfw","schemaVersion":1,"version":1}},"states":{"apex_drop":{"kind":"screen","on":{"act":{"target":"done","type":"goto"}},"screen":"apex_drop"},"done":{"kind":"end","result":{}}},"version":1}',
    screens: {
      'apex_drop': ApexDropScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      'a96d2984c0709049ca5807cec45286c35272c13e2f405dce2799a4d0300db945',
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
