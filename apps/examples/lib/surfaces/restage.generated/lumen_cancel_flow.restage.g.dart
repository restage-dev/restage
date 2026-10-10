part of '../lumen_cancel_flow.dart';

const lumenCancelRef = SurfaceFlowRef<
    LumenCancelResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'lumen_cancel',
  version: 1,
  minClient: 6,
  surface: Surface.survey,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeLumenCancelResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"lumen_cancel","flowState":{"reason":{"classification":"exportable","type":"string"}},"initial":"lumen_cancel_reason","minClient":6,"outbound":{"surveyAnswers":{"fields":{"reason":{"ref":{"state":"reason"},"type":"string"}}},"terminalResult":{"fields":{"reason":{"ref":{"state":"reason"},"type":"string"}}}},"schemaVersion":2,"screenArtifacts":{"lumen_cancel_reason":{"contentHash":"sha256:68d306c22d7d68b54e65d4097d3f4abbb7f594e392561f74f74cd15b1517fa07","minClient":6,"path":"measurement/102ed2ac499caf5b/lumen_cancel_reason.rfw","schemaVersion":1,"version":1},"lumen_cancel_thanks":{"contentHash":"sha256:fab6de29217abe91996bef532f3db63200d55367a953529b299c51fd129eff26","minClient":6,"path":"measurement/102ed2ac499caf5b/lumen_cancel_thanks.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"lumen_cancel_reason":{"kind":"screen","on":{"reason":{"set":{"reason":{"type":"string","value":{"ref":{"event":"value"}}}},"target":"lumen_cancel_thanks","type":"goto"},"skip":{"target":"done","type":"goto"}},"screen":"lumen_cancel_reason"},"lumen_cancel_thanks":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"lumen_cancel_thanks"}},"surveyQuestionOrder":["reason"],"version":1}',
    screens: {
      'lumen_cancel_reason': LumenCancelReasonScreen.new,
      'lumen_cancel_thanks': LumenCancelThanksScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '1571ea7d31708f8d385f0f6c923c4927be496504685de68d621f7af80923adb0',
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
  if (result.length != 1 || !result.containsKey('reason')) {
    throw const FormatException('Unexpected flow result keys.');
  }
  final reason = result['reason'];
  if (reason is! String) {
    throw const FormatException('Expected result field reason to be String.');
  }
  return LumenCancelResult(reason: reason);
}

final class LumenCancelResult {
  const LumenCancelResult({required this.reason});

  final String reason;
}

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class LumenCancelSurface extends RestageFlowGraph<LumenCancelResult> {
  const LumenCancelSurface({
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
  }) : super(flow: lumenCancelRef);
}
