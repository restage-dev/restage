part of '../minimal_onboarding.dart';

// ignore_for_file: type=lint

const minimalOnboardingFlowRef = SurfaceFlowRef<
    MinimalOnboardingResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'minimal_onboarding',
  version: 1,
  minClient: 9,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeMinimalOnboardingFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"minimal_onboarding","flowState":{"mode":{"classification":"internal","type":"string"}},"initial":"starter_welcome","minClient":9,"schemaVersion":1,"screenArtifacts":{"starter_done_explore":{"contentHash":"sha256:187d6878fc8e6f175dde3dbc0a072a5d33acee67c1e8317b152ee59f8834dd88","minClient":9,"path":"starter_done_explore.rfw","schemaVersion":1,"version":1},"starter_done_guided":{"contentHash":"sha256:7019e80189a7ff7734869c98dc161ca7b78a2326d776566fc0e85d2e5ad2b9bf","minClient":9,"path":"starter_done_guided.rfw","schemaVersion":1,"version":1},"starter_question":{"contentHash":"sha256:c4a04b006e2e31422fb275cbe7e4cf0838602e7a5696fef0baff46ae55116aa3","minClient":9,"path":"starter_question.rfw","schemaVersion":1,"version":1},"starter_welcome":{"contentHash":"sha256:056c661c950a1620b46a4fa16a1a32abe8744ff0819242b8f1a3f65fd90df674","minClient":1,"path":"starter_welcome.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"route":{"branches":[{"goto":"starter_done_guided","when":{"mode":{"eq":{"literal":"guided","type":"string"}}}}],"default":{"goto":"starter_done_explore"},"kind":"decision"},"starter_done_explore":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"starter_done_explore"},"starter_done_guided":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"starter_done_guided"},"starter_question":{"kind":"screen","on":{"explore":{"set":{"mode":{"type":"string","value":{"literal":"explore","type":"string"}}},"target":"route","type":"goto"},"guided":{"set":{"mode":{"type":"string","value":{"literal":"guided","type":"string"}}},"target":"route","type":"goto"}},"screen":"starter_question"},"starter_welcome":{"kind":"screen","on":{"next":{"target":"starter_question","type":"goto"}},"screen":"starter_welcome"}},"version":1}',
    screens: {
      'starter_welcome': StarterWelcomeScreen.new,
      'starter_question': StarterQuestionScreen.new,
      'starter_done_guided': StarterDoneGuidedScreen.new,
      'starter_done_explore': StarterDoneExploreScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '15f8a84d01988de46f5acebd40ba2ffcd65ab565c42d25c9d4d01151f602b914',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Container': buildContainer,
        'Expanded': buildExpanded,
        'GestureDetector': buildGestureDetector,
        'Padding': buildPadding,
        'Row': buildRow,
        'SafeArea': buildSafeArea,
        'SizedBox': buildSizedBox,
        'Spacer': buildSpacer,
        'Text': buildText,
      },
      material: {
        'AppBar': buildAppBar,
        'FilledButton': buildFilledButton,
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf724: IconData(0xf724, fontFamily: 'MaterialIcons'),
        0xf0377: IconData(0xf0377, fontFamily: 'MaterialIcons'),
      },
    }, mirrored: {
      'MaterialIcons': {
        0xf63b: IconData(0xf63b,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
      },
    }),
  ),
);

MinimalOnboardingResult _decodeMinimalOnboardingFlowResult(
    Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const MinimalOnboardingResult();
}

@Deprecated('Use minimalOnboardingFlowRef')
abstract final class MinimalOnboardingFlowDescriptor {
  const MinimalOnboardingFlowDescriptor._();

  static const SurfaceFlowRef<MinimalOnboardingResult> ref =
      minimalOnboardingFlowRef;
}

final class MinimalOnboardingResult {
  const MinimalOnboardingResult();
}

final class MinimalOnboardingActions {
  const MinimalOnboardingActions();
}

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class MinimalOnboardingFlowSurface
    extends RestageFlowGraph<MinimalOnboardingResult> {
  const MinimalOnboardingFlowSurface({
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
  }) : super(flow: minimalOnboardingFlowRef);
}
