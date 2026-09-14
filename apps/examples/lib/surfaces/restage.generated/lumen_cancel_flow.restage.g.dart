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
        "{\"flow\":\"lumen_cancel\",\"flowState\":{\"reason\":{\"classification\":\"exportable\",\"type\":\"string\"}},\"initial\":\"lumen_cancel_reason\",\"minClient\":6,\"outbound\":{\"surveyAnswers\":{\"fields\":{\"reason\":{\"ref\":{\"state\":\"reason\"},\"type\":\"string\"}}},\"terminalResult\":{\"fields\":{\"reason\":{\"ref\":{\"state\":\"reason\"},\"type\":\"string\"}}}},\"schemaVersion\":2,\"screenArtifacts\":{\"lumen_cancel_reason\":{\"contentHash\":\"sha256:3cb0f6062e543a0b6888b915f5f7be265689a06d934f079b7df05e88fc5d946f\",\"minClient\":6,\"path\":\"lumen_cancel_reason.rfw\",\"schemaVersion\":1,\"version\":1},\"lumen_cancel_thanks\":{\"contentHash\":\"sha256:01cf3e5e09be6898346464f29565259b6d4966c94c665b75d69d9cb0591a366e\",\"minClient\":6,\"path\":\"lumen_cancel_thanks.rfw\",\"schemaVersion\":1,\"version\":1}},\"states\":{\"done\":{\"kind\":\"end\",\"result\":{}},\"lumen_cancel_reason\":{\"kind\":\"screen\",\"on\":{\"reason\":{\"set\":{\"reason\":{\"type\":\"string\",\"value\":{\"ref\":{\"event\":\"value\"}}}},\"target\":\"lumen_cancel_thanks\",\"type\":\"goto\"},\"skip\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"lumen_cancel_reason\"},\"lumen_cancel_thanks\":{\"kind\":\"screen\",\"on\":{\"finish\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"lumen_cancel_thanks\"}},\"surveyQuestionOrder\":[\"reason\"],\"version\":1}",
    screens: {
      "lumen_cancel_reason": LumenCancelReasonScreen.new,
      "lumen_cancel_thanks": LumenCancelThanksScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '9214d67afedea335011b51c878558e0eaa22f7761384c3abc5eadc3ba21c6142',
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
  if (result.length != 1 || !result.containsKey("reason")) {
    throw const FormatException('Unexpected flow result keys.');
  }
  final reason = result["reason"];
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
