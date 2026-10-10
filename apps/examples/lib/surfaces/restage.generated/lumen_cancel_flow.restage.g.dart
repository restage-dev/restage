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
        '{"flow":"lumen_cancel","flowState":{"note":{"classification":"exportable","type":"string"},"reason":{"classification":"exportable","type":"string"}},"initial":"lumen_cancel_reason","minClient":10,"outbound":{"surveyAnswers":{"fields":{"reason":{"ref":{"state":"reason"},"type":"string"}}},"terminalResult":{"fields":{"note":{"ref":{"state":"note"},"type":"string"},"reason":{"ref":{"state":"reason"},"type":"string"}}}},"schemaVersion":2,"screenArtifacts":{"lumen_cancel_note":{"contentHash":"sha256:88d64768cfab3b96b88c7dafdc83085888484e5487fb8940a253e5d90779e9e1","minClient":10,"path":"measurement/102ed2ac499caf5b/lumen_cancel_note.rfw","schemaVersion":1,"version":1},"lumen_cancel_reason":{"contentHash":"sha256:03f9470af6327caa36e0ed77acaaba28ad07161966a0dc2e68f0b055143666e1","minClient":10,"path":"measurement/102ed2ac499caf5b/lumen_cancel_reason.rfw","schemaVersion":1,"version":1},"lumen_cancel_thanks":{"contentHash":"sha256:2c68bfbac0f65a0e9c05564cdfcd1fbc4ef697ef79a2729216dadef73d857221","minClient":10,"path":"measurement/102ed2ac499caf5b/lumen_cancel_thanks.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"lumen_cancel_note":{"kind":"screen","on":{"send":{"set":{"note":{"type":"string","value":{"ref":{"event":"value"}}}},"target":"lumen_cancel_thanks","type":"goto"},"skip":{"target":"lumen_cancel_thanks","type":"goto"}},"screen":"lumen_cancel_note"},"lumen_cancel_reason":{"kind":"screen","on":{"reason":{"set":{"reason":{"type":"string","value":{"ref":{"event":"value"}}}},"target":"lumen_cancel_note","type":"goto"},"skip":{"target":"done","type":"goto"}},"screen":"lumen_cancel_reason"},"lumen_cancel_thanks":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"lumen_cancel_thanks"}},"surveyQuestionOrder":["reason"],"version":1}',
    screens: {
      'lumen_cancel_note': LumenCancelNoteScreen.new,
      'lumen_cancel_reason': LumenCancelReasonScreen.new,
      'lumen_cancel_thanks': LumenCancelThanksScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '50b09020baec0b49878fadc2923bedbf84552b1be2c41b3a07298dceb55f93de',
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
