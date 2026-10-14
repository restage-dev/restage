part of '../lumen_cancel_flow.dart';

// ignore_for_file: type=lint

const lumenCancelRef = SurfaceFlowRef<
    LumenCancelResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'lumen_cancel',
  version: 1,
  minClient: 10,
  surface: Surface.survey,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeLumenCancelResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"lumen_cancel","flowState":{"note":{"classification":"exportable","default":"","type":"string"},"reason":{"classification":"exportable","default":"","type":"string"}},"initial":"lumen_cancel_reason","minClient":10,"outbound":{"surveyAnswers":{"fields":{"reason":{"ref":{"state":"reason"},"type":"string"}}},"terminalResult":{"fields":{"note":{"ref":{"state":"note"},"type":"string"},"reason":{"ref":{"state":"reason"},"type":"string"}}}},"schemaVersion":2,"screenArtifacts":{"lumen_cancel_note":{"contentHash":"sha256:9537cbb41a42ae02ad3451bdba4f943346cd8576497195207ad6fee04de72a45","minClient":10,"path":"measurement/102ed2ac499caf5b/lumen_cancel_note.rfw","schemaVersion":1,"version":1},"lumen_cancel_reason":{"contentHash":"sha256:f8622447a65e4aa9ba477e28e1938d9e08db9b9671ecc3d6ea3dd9474f0e532a","minClient":10,"path":"measurement/102ed2ac499caf5b/lumen_cancel_reason.rfw","schemaVersion":1,"version":1},"lumen_cancel_thanks":{"contentHash":"sha256:7671bfcbe7ba0d9b8e9e679e29507ea69fc18b5ea0d4e945df9abeb4fd8c3666","minClient":10,"path":"measurement/102ed2ac499caf5b/lumen_cancel_thanks.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"lumen_cancel_note":{"kind":"screen","on":{"send":{"set":{"note":{"type":"string","value":{"ref":{"event":"value"}}}},"target":"lumen_cancel_thanks","type":"goto"},"skip":{"target":"lumen_cancel_thanks","type":"goto"}},"screen":"lumen_cancel_note"},"lumen_cancel_reason":{"kind":"screen","on":{"reason":{"set":{"reason":{"type":"string","value":{"ref":{"event":"value"}}}},"target":"lumen_cancel_note","type":"goto"},"skip":{"target":"done","type":"goto"}},"screen":"lumen_cancel_reason"},"lumen_cancel_thanks":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"lumen_cancel_thanks"}},"surveyQuestionOrder":["reason"],"version":1}',
    screens: {
      'lumen_cancel_note': LumenCancelNoteScreen.new,
      'lumen_cancel_reason': LumenCancelReasonScreen.new,
      'lumen_cancel_thanks': LumenCancelThanksScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '6636bd349de1f1314727bce240687742d59ac59006352148bfe6a8dc7eee4c24',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Center': buildCenter,
        'Column': buildColumn,
        'Container': buildContainer,
        'Expanded': buildExpanded,
        'GestureDetector': buildGestureDetector,
        'Padding': buildPadding,
        'Positioned': buildPositioned,
        'Row': buildRow,
        'SingleChildScrollView': buildSingleChildScrollView,
        'SizedBox': buildSizedBox,
        'Stack': buildStack,
        'Text': buildText,
      },
      material: {
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
        'TextField': buildTextField,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf647: IconData(0xf647, fontFamily: 'MaterialIcons'),
        0xf738: IconData(0xf738, fontFamily: 'MaterialIcons'),
      },
    }, mirrored: {
      'MaterialIcons': {
        0xf57a: IconData(0xf57a,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
      },
    }),
  ),
);

LumenCancelResult _decodeLumenCancelResult(Map<String, Object?> result) {
  if (result.length != 2 ||
      !result.containsKey('note') ||
      !result.containsKey('reason')) {
    throw const FormatException('Unexpected flow result keys.');
  }
  final note = result['note'];
  if (note is! String) {
    throw const FormatException('Expected result field note to be String.');
  }
  final reason = result['reason'];
  if (reason is! String) {
    throw const FormatException('Expected result field reason to be String.');
  }
  return LumenCancelResult(note: note, reason: reason);
}

final class LumenCancelResult {
  const LumenCancelResult({required this.note, required this.reason});

  final String note;
  final String reason;
}

final _lumenCancelPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: lumenCancelRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'survey',
    'slug': 'lumen_cancel',
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
        'terminalResult': <String, Object?>{
          'note': 'string',
          'reason': 'string'
        },
        'lifecycle': <String, Object?>{},
        'surveyAnswers': <String, Object?>{'reason': 'string'},
        'subFlowResult': <String, Object?>{},
        'customEvents': <String, Object?>{}
      }
    }
  },
  vocabulary: lumenCancelRef.vocabulary,
);

final lumenCancelPlacementDefinition =
    () => _lumenCancelPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class LumenCancelSurface extends RestageFlowGraph<LumenCancelResult> {
  /// Mounts this flow at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const LumenCancelSurface({
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
        super(flow: lumenCancelRef);

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [LumenCancelSurface] for the default placement; no name is needed.
  const LumenCancelSurface.atPlacement(
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
        super(flow: lumenCancelRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: lumenCancelPlacementDefinition,
        name: _restagePlacementName,
      );
}
