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
            'sha256:39f623b21a0e683883996a7b6fe4ed947db26cae6065cb992e5bd11454993a20',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/general/screens/measurement/d53671985f67f2f1/general_status.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            'sha256:6b9f45300ad195e10c0bea8a96f165f6c408846e439e69eb9db291cdb5201c38',
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
      '1b4ebdb30c434ffbe24cf35985c6a0ddaf3b411e3deb70465a49e24873888e2e',
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
  const GeneralStatusSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  const GeneralStatusSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<GeneralStatusEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<GeneralStatusEvent>(
      screen: generalStatusRef,
      placementBinding: RestageScreen.generatedPlacementBinding(
        definition: generalStatusPlacementDefinition,
        name: _restagePlacementName,
      ),
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
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
            'sha256:794c4d708993e2a24aeee80232308c68adea438dd6059e14e9320c4063e4624f',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/message/screens/measurement/7dd571bceb502385/message_notice.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            'sha256:7a2743c7a1d8e1906120fdb2c3f0a560525cc9b6c1ad54db58b51a91e8e6d271',
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
      '349d4d2dae20f6322b09e371bb754bd478e2edd2f2388d582d2d0e8fdb4dd159',
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
  const MessageNoticeSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  const MessageNoticeSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<MessageNoticeEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<MessageNoticeEvent>(
      screen: messageNoticeRef,
      placementBinding: RestageScreen.generatedPlacementBinding(
        definition: messageNoticePlacementDefinition,
        name: _restagePlacementName,
      ),
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
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
            'sha256:6644085554f3d2fbe2946e0083ba8907178a5ce3c9048d548a093666a1e4d673',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/onboarding/screens/onboarding_welcome.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            'sha256:6d04c468bf79ef805ffe30b7cc174988dc72d0fb4c267afe57a9925a0c400b94',
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
      'e6bfbd00cfdb651f09a35d85de0a54086516646d5b7f861fe5e9e55e17f87d9e',
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
  const OnboardingWelcomeSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  const OnboardingWelcomeSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<OnboardingWelcomeEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<OnboardingWelcomeEvent>(
      screen: onboardingWelcomeRef,
      placementBinding: RestageScreen.generatedPlacementBinding(
        definition: onboardingWelcomePlacementDefinition,
        name: _restagePlacementName,
      ),
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
        builder: (context, error) => OnboardingWelcome(),
      ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}
