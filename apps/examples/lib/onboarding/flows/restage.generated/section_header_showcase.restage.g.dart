part of '../section_header_showcase.dart';

// ignore_for_file: type=lint

const sectionHeaderShowcaseFlowRef = SurfaceFlowRef<
    SectionHeaderShowcaseResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'section_header_showcase',
  version: 1,
  minClient: 9,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeSectionHeaderShowcaseFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"section_header_showcase","initial":"section_header_showcase","minClient":9,"outbound":{"customEvents":{"dismiss":{"fields":{}}}},"schemaVersion":1,"screenArtifacts":{"section_header_showcase":{"contentHash":"sha256:a19b24bfd19e74537a4a4f95b5d07d1d1be84bfc143966a2816d8c7417e2db58","minClient":9,"path":"section_header_showcase.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"section_header_showcase":{"kind":"screen","on":{"act":{"target":"done","type":"goto"}},"screen":"section_header_showcase"}},"version":1}',
    screens: {
      'section_header_showcase': SectionHeaderShowcaseScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      'a6ad6c053f49b4cc83dd0c87f0d2fb76a9aec826b93de8d9c81ca4345cf8b693',
  vocabulary: SurfaceVocabulary(
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
  ),
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

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class SectionHeaderShowcaseFlowSurface
    extends RestageFlowGraph<SectionHeaderShowcaseResult> {
  const SectionHeaderShowcaseFlowSurface({
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
  }) : super(flow: sectionHeaderShowcaseFlowRef);
}
