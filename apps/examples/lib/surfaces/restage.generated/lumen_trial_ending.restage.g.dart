part of '../lumen_trial_ending.dart';

// ignore_for_file: type=lint

sealed class LumenTrialEndingScreenEvent {
  const LumenTrialEndingScreenEvent();
}

final class LumenTrialEndingScreenLaterEvent
    extends LumenTrialEndingScreenEvent {
  const LumenTrialEndingScreenLaterEvent();
}

final class LumenTrialEndingScreenOpenOfferEvent
    extends LumenTrialEndingScreenEvent {
  const LumenTrialEndingScreenOpenOfferEvent();
}

final _lumenTrialEndingScreenEvents =
    SurfaceScreenEventContract<LumenTrialEndingScreenEvent>.generated(
  hash:
      'sha256:c873ccfbaabb443865b81010c061e6321c2a6acf0488747e8cdc68debb658508',
  decodeValidated: _decodeValidatedLumenTrialEndingScreenEvent,
);

final _lumenTrialEndingScreenProvenance =
    SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.message,
  slug: 'lumen_trial_ending',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 9,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      '{"schemaVersion":1,"events":[{"id":"later","arguments":{"encoding":"none"}},{"id":"open_offer","arguments":{"encoding":"none"}}]}',
  bundle: SurfaceScreenBundleLocator(
    assetKey: 'assets/restage/bundles/lib/surfaces/lumen_trial_ending.rsbundle',
    packageName: 'restage_example',
    authoredLibraryPath: 'lib/surfaces/lumen_trial_ending.dart',
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/message/screens/measurement/d2a9dd6bcb9f4c2c/lumen_trial_ending.rfw',
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 21460,
        sha256:
            'sha256:c6de1c6c400018f8936fd372691b5ead040a7ceee8ddbb1b2fda7959beddae40',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/message/screens/measurement/d2a9dd6bcb9f4c2c/lumen_trial_ending.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            'sha256:71fbdf23d1ab1e0d3e03ab3146543190d1d97a77576ce6c07801b4ddf2a65ccc',
      ),
    ],
  ),
  vocabulary: const SurfaceVocabulary(
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
        0xf0027: IconData(0xf0027, fontFamily: 'MaterialIcons'),
      },
    }),
  ),
);

final lumenTrialEndingScreenRef = SurfaceScreenRef<
    LumenTrialEndingScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenTrialEndingScreenProvenance,
  eventContract: _lumenTrialEndingScreenEvents,
  measurementPublicationDraftDigest:
      'f676e8ac5dca209f82cf5d2cc045f97a26938a007a9ebd3937614d193df8e33b',
);

LumenTrialEndingScreenEvent _decodeValidatedLumenTrialEndingScreenEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case 'later':
      return const LumenTrialEndingScreenLaterEvent();
    case 'open_offer':
      return const LumenTrialEndingScreenOpenOfferEvent();
  }
  throw FormatException('Invalid LumenTrialEndingScreen event "$name".');
}

final _lumenTrialEndingScreenPlacementDefinitionValue =
    RestageScreen.generatedPlacementDefinition(
  defaultSurface: lumenTrialEndingScreenRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'message',
    'slug': 'lumen_trial_ending',
    'family': <String, Object?>{'kind': 'screenContract', 'contractVersion': 1}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'inputs': <String, Object?>{},
      'schemaVersion': 1
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[
        <String, Object?>{
          'id': 'later',
          'arguments': <String, Object?>{'encoding': 'none'}
        },
        <String, Object?>{
          'id': 'open_offer',
          'arguments': <String, Object?>{'encoding': 'none'}
        }
      ]
    },
    'flowBoundary': null
  },
  vocabulary: lumenTrialEndingScreenRef.provenance.vocabulary,
);

final lumenTrialEndingScreenPlacementDefinition =
    () => _lumenTrialEndingScreenPlacementDefinitionValue;

final class LumenTrialEndingScreenSurface extends StatelessWidget {
  const LumenTrialEndingScreenSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  const LumenTrialEndingScreenSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<LumenTrialEndingScreenEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<LumenTrialEndingScreenEvent>(
      screen: lumenTrialEndingScreenRef,
      placementBinding: RestageScreen.generatedPlacementBinding(
        definition: lumenTrialEndingScreenPlacementDefinition,
        name: _restagePlacementName,
      ),
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
        builder: (context, error) => LumenTrialEndingScreen(),
      ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}
