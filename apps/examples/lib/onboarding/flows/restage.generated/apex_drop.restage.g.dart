part of '../apex_drop.dart';

const apexDropFlowRef = SurfaceFlowRef<
    ApexDropResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'apex_drop',
  version: 1,
  minClient: 6,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeApexDropFlowResult,
  compiled: CompiledFlow(
    documentJson:
        "{\"flow\":\"apex_drop\",\"initial\":\"apex_drop\",\"minClient\":6,\"outbound\":{\"customEvents\":{\"dismiss\":{\"fields\":{}}}},\"schemaVersion\":1,\"screenArtifacts\":{\"apex_drop\":{\"contentHash\":\"sha256:168370446c1565cb995288ab68dfa5c14c9df33d6bece98302dda72cf835fc98\",\"minClient\":6,\"path\":\"apex_drop.rfw\",\"schemaVersion\":1,\"version\":1}},\"states\":{\"apex_drop\":{\"kind\":\"screen\",\"on\":{\"act\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"apex_drop\"},\"done\":{\"kind\":\"end\",\"result\":{}}},\"version\":1}",
    screens: {
      "apex_drop": ApexDropScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      'd6b9d02058ecf6782ebc2f556c4d3c0f22b49e9f6d6c820159e23af53a9235c7',
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

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class ApexDropFlowSurface extends RestageFlowGraph<ApexDropResult> {
  const ApexDropFlowSurface({
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
  }) : super(flow: apexDropFlowRef);
}
