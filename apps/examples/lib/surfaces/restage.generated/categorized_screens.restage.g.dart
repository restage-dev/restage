part of '../categorized_screens.dart';

// ignore_for_file: type=lint

sealed class GeneralStatusEvent {
  const GeneralStatusEvent();
}

final class GeneralStatusFinishEvent extends GeneralStatusEvent {
  const GeneralStatusFinishEvent();
}

final _generalStatusEvents =
    SurfaceScreenEventContract<GeneralStatusEvent>.generated(
  hash:
      'sha256:ca846c32a23d2d98fb3ca253fc69fb1ccef2fa2ee9fa5397947d5e5c2e03bc31',
  decodeValidated: _decodeValidatedGeneralStatusEvent,
);

final _generalStatusProvenance = SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.general,
  slug: 'general_status',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      '{"schemaVersion":1,"events":[{"id":"finish","arguments":{"encoding":"none"}}]}',
  bundle: SurfaceScreenBundleLocator(
    assetKey:
        'assets/restage/bundles/lib/surfaces/categorized_screens.rsbundle',
    packageName: 'restage_example',
    authoredLibraryPath: 'lib/surfaces/categorized_screens.dart',
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/general/screens/measurement/d53671985f67f2f1/general_status.rfw',
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 1384,
        sha256:
            'sha256:f988437768258f4d3820f9cddfd0d2fd166e40fabe567b678613c16368da8fce',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/general/screens/measurement/d53671985f67f2f1/general_status.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            'sha256:9cf8d557208388392f225353ec6983171f5702d6e23230a1540645e3faf56ddb',
      ),
    ],
  ),
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
      material: {
        'FilledButton': buildFilledButton,
      },
    ),
  ),
);

final generalStatusRef = SurfaceScreenRef<
    GeneralStatusEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _generalStatusProvenance,
  eventContract: _generalStatusEvents,
  measurementPublicationDraftDigest:
      'd9b94b215f9f25289329d3fa78141998bd0cf68c4a86eb8e04dc7c22b7963e88',
);

GeneralStatusEvent _decodeValidatedGeneralStatusEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case 'finish':
      return const GeneralStatusFinishEvent();
  }
  throw FormatException('Invalid GeneralStatus event "$name".');
}

final _generalStatusPlacementDefinitionValue =
    RestageScreen.generatedPlacementDefinition(
  defaultSurface: generalStatusRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'general',
    'slug': 'general_status',
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
          'id': 'finish',
          'arguments': <String, Object?>{'encoding': 'none'}
        }
      ]
    },
    'flowBoundary': null
  },
  vocabulary: generalStatusRef.provenance.vocabulary,
);

final generalStatusPlacementDefinition =
    () => _generalStatusPlacementDefinitionValue;

final class GeneralStatusSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const GeneralStatusSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.unavailable,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [GeneralStatusSurface] for the default placement; no name is needed.
  const GeneralStatusSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.unavailable,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<GeneralStatusEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  final SurfaceScreenUnavailablePolicy? unavailable;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<GeneralStatusEvent>(
      screen: generalStatusRef,
      placementBinding: RestageScreen.generatedPlacementBinding(
        definition: generalStatusPlacementDefinition,
        name: _restagePlacementName,
      ),
      unavailable: unavailable ??
          SurfaceScreenUnavailablePolicy.fallback(
            builder: (context, error) => GeneralStatus(),
          ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}

sealed class MessageNoticeEvent {
  const MessageNoticeEvent();
}

final class MessageNoticeOpenOfferEvent extends MessageNoticeEvent {
  const MessageNoticeOpenOfferEvent();
}

final _messageNoticeEvents =
    SurfaceScreenEventContract<MessageNoticeEvent>.generated(
  hash:
      'sha256:179c12fb27777408d1211a67a2e68e33c1d1abb5b306a9416c2208c99c853b18',
  decodeValidated: _decodeValidatedMessageNoticeEvent,
);

final _messageNoticeProvenance = SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.message,
  slug: 'message_notice',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      '{"schemaVersion":1,"events":[{"id":"open_offer","arguments":{"encoding":"none"}}]}',
  bundle: SurfaceScreenBundleLocator(
    assetKey:
        'assets/restage/bundles/lib/surfaces/categorized_screens.rsbundle',
    packageName: 'restage_example',
    authoredLibraryPath: 'lib/surfaces/categorized_screens.dart',
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/message/screens/measurement/7dd571bceb502385/message_notice.rfw',
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 1394,
        sha256:
            'sha256:9fdeafc7e89da50f7b50753826684f0bd1cda09851bc289c32448ff23db41235',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/message/screens/measurement/7dd571bceb502385/message_notice.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            'sha256:e2818f97ad3b42ee1ce9234cf698cadfc3dc3b20f1ec6076524ad6d66e2e3d83',
      ),
    ],
  ),
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
      material: {
        'FilledButton': buildFilledButton,
      },
    ),
  ),
);

final messageNoticeRef = SurfaceScreenRef<
    MessageNoticeEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _messageNoticeProvenance,
  eventContract: _messageNoticeEvents,
  measurementPublicationDraftDigest:
      'eaa2e5ed954e5ba9066287aa20a5b4150c9c8a97cc10f0dba87456598a9eaa43',
);

MessageNoticeEvent _decodeValidatedMessageNoticeEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case 'open_offer':
      return const MessageNoticeOpenOfferEvent();
  }
  throw FormatException('Invalid MessageNotice event "$name".');
}

final _messageNoticePlacementDefinitionValue =
    RestageScreen.generatedPlacementDefinition(
  defaultSurface: messageNoticeRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'message',
    'slug': 'message_notice',
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
          'id': 'open_offer',
          'arguments': <String, Object?>{'encoding': 'none'}
        }
      ]
    },
    'flowBoundary': null
  },
  vocabulary: messageNoticeRef.provenance.vocabulary,
);

final messageNoticePlacementDefinition =
    () => _messageNoticePlacementDefinitionValue;

final class MessageNoticeSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const MessageNoticeSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.unavailable,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [MessageNoticeSurface] for the default placement; no name is needed.
  const MessageNoticeSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.unavailable,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<MessageNoticeEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  final SurfaceScreenUnavailablePolicy? unavailable;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<MessageNoticeEvent>(
      screen: messageNoticeRef,
      placementBinding: RestageScreen.generatedPlacementBinding(
        definition: messageNoticePlacementDefinition,
        name: _restagePlacementName,
      ),
      unavailable: unavailable ??
          SurfaceScreenUnavailablePolicy.fallback(
            builder: (context, error) => MessageNotice(),
          ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}

sealed class OnboardingWelcomeEvent {
  const OnboardingWelcomeEvent();
}

final class OnboardingWelcomeContinueFlowEvent extends OnboardingWelcomeEvent {
  const OnboardingWelcomeContinueFlowEvent();
}

final _onboardingWelcomeEvents =
    SurfaceScreenEventContract<OnboardingWelcomeEvent>.generated(
  hash:
      'sha256:72daff87223b7d45852a98ceb57a5dc83702eede99b8f045f2619af0062e9bc3',
  decodeValidated: _decodeValidatedOnboardingWelcomeEvent,
);

final _onboardingWelcomeProvenance = SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.onboarding,
  slug: 'onboarding_welcome',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      '{"schemaVersion":1,"events":[{"id":"continue","arguments":{"encoding":"none"}}]}',
  bundle: SurfaceScreenBundleLocator(
    assetKey:
        'assets/restage/bundles/lib/surfaces/categorized_screens.rsbundle',
    packageName: 'restage_example',
    authoredLibraryPath: 'lib/surfaces/categorized_screens.dart',
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath: 'assets/onboarding/screens/onboarding_welcome.rfw',
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 1390,
        sha256:
            'sha256:05dd0da36c74eb9542cc99472bdf2ff157ddd8fc20b9bddc87d0d1ec141fe55e',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/onboarding/screens/onboarding_welcome.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            'sha256:7adda844bd01bd65aad193f8d55ecc70b9d8cf02c8c955a6903495432f60039a',
      ),
    ],
  ),
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
      material: {
        'FilledButton': buildFilledButton,
      },
    ),
  ),
);

final onboardingWelcomeRef = SurfaceScreenRef<
    OnboardingWelcomeEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _onboardingWelcomeProvenance,
  eventContract: _onboardingWelcomeEvents,
  measurementPublicationDraftDigest:
      '8e9a37f24b46bbd1b026066e8658e002519c899ab25d5ce6b7824cfbf9b2eb57',
);

OnboardingWelcomeEvent _decodeValidatedOnboardingWelcomeEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case 'continue':
      return const OnboardingWelcomeContinueFlowEvent();
  }
  throw FormatException('Invalid OnboardingWelcome event "$name".');
}

final _onboardingWelcomePlacementDefinitionValue =
    RestageScreen.generatedPlacementDefinition(
  defaultSurface: onboardingWelcomeRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'onboarding',
    'slug': 'onboarding_welcome',
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
          'id': 'continue',
          'arguments': <String, Object?>{'encoding': 'none'}
        }
      ]
    },
    'flowBoundary': null
  },
  vocabulary: onboardingWelcomeRef.provenance.vocabulary,
);

final onboardingWelcomePlacementDefinition =
    () => _onboardingWelcomePlacementDefinitionValue;

final class OnboardingWelcomeSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const OnboardingWelcomeSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.unavailable,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [OnboardingWelcomeSurface] for the default placement; no name is needed.
  const OnboardingWelcomeSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.unavailable,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<OnboardingWelcomeEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  final SurfaceScreenUnavailablePolicy? unavailable;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<OnboardingWelcomeEvent>(
      screen: onboardingWelcomeRef,
      placementBinding: RestageScreen.generatedPlacementBinding(
        definition: onboardingWelcomePlacementDefinition,
        name: _restagePlacementName,
      ),
      unavailable: unavailable ??
          SurfaceScreenUnavailablePolicy.fallback(
            builder: (context, error) => OnboardingWelcome(),
          ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}
