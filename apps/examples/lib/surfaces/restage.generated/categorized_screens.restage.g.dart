part of '../categorized_screens.dart';

sealed class GeneralStatusEvent {
  const GeneralStatusEvent();
}

final class GeneralStatusFinishEvent extends GeneralStatusEvent {
  const GeneralStatusFinishEvent();
}

final _generalStatusEvents =
    SurfaceScreenEventContract<GeneralStatusEvent>.generated(
  hash:
      "sha256:ca846c32a23d2d98fb3ca253fc69fb1ccef2fa2ee9fa5397947d5e5c2e03bc31",
  decodeValidated: _decodeValidatedGeneralStatusEvent,
);

final _generalStatusProvenance = SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.general,
  slug: "general_status",
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      "{\"schemaVersion\":1,\"events\":[{\"id\":\"finish\",\"arguments\":{\"encoding\":\"none\"}}]}",
  bundle: SurfaceScreenBundleLocator(
    assetKey:
        "assets/restage/bundles/lib/surfaces/categorized_screens.rsbundle",
    packageName: "restage_example",
    authoredLibraryPath: "lib/surfaces/categorized_screens.dart",
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/general/screens/measurement/d53671985f67f2f1/general_status.rfw",
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 1384,
        sha256:
            "sha256:6ef86f0e643976a8120650d4b33d675afdd7e1e146369c98f23a38f329a86293",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/general/screens/measurement/d53671985f67f2f1/general_status.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:002c7a94981d7a714fc40f0c2d9e5538ab00e8a21d443c4ac3bee013a837ef40",
      ),
    ],
  ),
);

final generalStatusRef = SurfaceScreenRef<
    GeneralStatusEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _generalStatusProvenance,
  eventContract: _generalStatusEvents,
  measurementPublicationDraftDigest:
      "d252a4d6e146a816d888ccf8762459f19054260d9656162f20eeb7a98b66c60f",
);

GeneralStatusEvent _decodeValidatedGeneralStatusEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case "finish":
      return const GeneralStatusFinishEvent();
  }
  throw FormatException("Invalid GeneralStatus event \"" + name + "\".");
}

final class GeneralStatusSurface extends StatelessWidget {
  const GeneralStatusSurface({
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  });

  final ValueChanged<GeneralStatusEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<GeneralStatusEvent>(
      screen: generalStatusRef,
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
      "sha256:179c12fb27777408d1211a67a2e68e33c1d1abb5b306a9416c2208c99c853b18",
  decodeValidated: _decodeValidatedMessageNoticeEvent,
);

final _messageNoticeProvenance = SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.message,
  slug: "message_notice",
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      "{\"schemaVersion\":1,\"events\":[{\"id\":\"open_offer\",\"arguments\":{\"encoding\":\"none\"}}]}",
  bundle: SurfaceScreenBundleLocator(
    assetKey:
        "assets/restage/bundles/lib/surfaces/categorized_screens.rsbundle",
    packageName: "restage_example",
    authoredLibraryPath: "lib/surfaces/categorized_screens.dart",
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/message/screens/measurement/7dd571bceb502385/message_notice.rfw",
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 1394,
        sha256:
            "sha256:ec5b156e1f8cc830147691f03a4082306d9171b445ebdd9a495a8a4c4f8e51fe",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/message/screens/measurement/7dd571bceb502385/message_notice.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:515c0ecf297e12fb7c4719536e260b09371cfe83d474d880e0cf39bfee6b0fd8",
      ),
    ],
  ),
);

final messageNoticeRef = SurfaceScreenRef<
    MessageNoticeEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _messageNoticeProvenance,
  eventContract: _messageNoticeEvents,
  measurementPublicationDraftDigest:
      "3b9b24a5082b1a4c5300341fb2678a3df0a633705c7b94a853b0790817893ebe",
);

MessageNoticeEvent _decodeValidatedMessageNoticeEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case "open_offer":
      return const MessageNoticeOpenOfferEvent();
  }
  throw FormatException("Invalid MessageNotice event \"" + name + "\".");
}

final class MessageNoticeSurface extends StatelessWidget {
  const MessageNoticeSurface({
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  });

  final ValueChanged<MessageNoticeEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<MessageNoticeEvent>(
      screen: messageNoticeRef,
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
      "sha256:72daff87223b7d45852a98ceb57a5dc83702eede99b8f045f2619af0062e9bc3",
  decodeValidated: _decodeValidatedOnboardingWelcomeEvent,
);

final _onboardingWelcomeProvenance = SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.onboarding,
  slug: "onboarding_welcome",
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      "{\"schemaVersion\":1,\"events\":[{\"id\":\"continue\",\"arguments\":{\"encoding\":\"none\"}}]}",
  bundle: SurfaceScreenBundleLocator(
    assetKey:
        "assets/restage/bundles/lib/surfaces/categorized_screens.rsbundle",
    packageName: "restage_example",
    authoredLibraryPath: "lib/surfaces/categorized_screens.dart",
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath: "assets/onboarding/screens/onboarding_welcome.rfw",
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 1390,
        sha256:
            "sha256:7f41d4cc414d99ff4a002d35a0a7f98087feb78cc7207ef95ad438e7f15595fd",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/onboarding/screens/onboarding_welcome.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:e345388e9b0ff6e101b8c14f4eff40f0e26786347f9c1ee71aaaa01ab68f2f4d",
      ),
    ],
  ),
);

final onboardingWelcomeRef = SurfaceScreenRef<
    OnboardingWelcomeEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _onboardingWelcomeProvenance,
  eventContract: _onboardingWelcomeEvents,
  measurementPublicationDraftDigest:
      "e56d2cd725bdd2e46701966822e059fa8cf8b193c76bdac9db744333f5f67788",
);

OnboardingWelcomeEvent _decodeValidatedOnboardingWelcomeEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case "continue":
      return const OnboardingWelcomeContinueFlowEvent();
  }
  throw FormatException("Invalid OnboardingWelcome event \"" + name + "\".");
}

final class OnboardingWelcomeSurface extends StatelessWidget {
  const OnboardingWelcomeSurface({
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  });

  final ValueChanged<OnboardingWelcomeEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<OnboardingWelcomeEvent>(
      screen: onboardingWelcomeRef,
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
