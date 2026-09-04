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
            "sha256:9bd510626971079d0843cddade7907a1a6b5998a9866b60f286f6a16e4492ba3",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/general/screens/measurement/d53671985f67f2f1/general_status.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:73d685423ad52506cd9d40545997ed889ea99217e1ab3662d894b3e1a3c9490f",
      ),
    ],
  ),
);

final generalStatusRef = SurfaceScreenRef<
    GeneralStatusEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _generalStatusProvenance,
  eventContract: _generalStatusEvents,
  measurementPublicationDraftDigest:
      "5d5d00d87fb1c872b6e84596518674e876b020cdf6f1ad748023650adb44d553",
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
            "sha256:1b2c04e4cf5c3c7f95047cfbebfd7e7407132768ceb2e2f5ed00d3d85b347997",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/message/screens/measurement/7dd571bceb502385/message_notice.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:6705bf9edd36cc0948a96c45d1cbd01b7c950befdda4ed698649ddf3cd39d4c9",
      ),
    ],
  ),
);

final messageNoticeRef = SurfaceScreenRef<
    MessageNoticeEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _messageNoticeProvenance,
  eventContract: _messageNoticeEvents,
  measurementPublicationDraftDigest:
      "1eb2128ae924a21274d5fffbe200a8f590e4e18c06a70a9cd022eca3bb0d953b",
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
            "sha256:667cabaddede2c48d7b234acc448272d4019a7bbc6fe7278eeb324a52ebbef4f",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/onboarding/screens/onboarding_welcome.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:03f299c0b9facc1dae3e5e95e95a63e66fd8a10313e13b27daf67aa2ae7b79d0",
      ),
    ],
  ),
);

final onboardingWelcomeRef = SurfaceScreenRef<
    OnboardingWelcomeEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _onboardingWelcomeProvenance,
  eventContract: _onboardingWelcomeEvents,
  measurementPublicationDraftDigest:
      "52d44bf8e889993d0fd4ab5117362366ee6ad075aaf552defaa871cda757bba3",
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
