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
            "sha256:3af473fba9c2c9ad98a35fd9e20087e7101c571caa807cd125979878b8825dfc",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/general/screens/measurement/d53671985f67f2f1/general_status.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:977d3e8da7a15cd417b8fd24f173e34c0d64fccad81b1c9abb7d016f46ca106a",
      ),
    ],
  ),
);

final generalStatusRef = SurfaceScreenRef<
    GeneralStatusEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _generalStatusProvenance,
  eventContract: _generalStatusEvents,
  measurementPublicationDraftDigest:
      "1101cbfde80cf913928c1fa9338a62f1ce7668a866705218101c4598b8505ec8",
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
            "sha256:8b00ce19062f1ffa029ccf76c63201aeb7bc000caaed9173de92052c12754c5c",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/message/screens/measurement/7dd571bceb502385/message_notice.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:81f8ab66fa290468827280d5ec941a2c1124c304eda933004892f1afb889a2a2",
      ),
    ],
  ),
);

final messageNoticeRef = SurfaceScreenRef<
    MessageNoticeEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _messageNoticeProvenance,
  eventContract: _messageNoticeEvents,
  measurementPublicationDraftDigest:
      "a5da923a6d10120de9315f5d9690d5dda1ce92d1a05be57311f77b7fdeb11e4f",
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
            "sha256:bc413efac9775c2f8f46c787b28f459560dfbd62c59dbb520e99736f24327709",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/onboarding/screens/onboarding_welcome.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:15cb052102a9f72fb3d5abcdfd16e33cea35ed57abda02a0c8dfd41c08150d33",
      ),
    ],
  ),
);

final onboardingWelcomeRef = SurfaceScreenRef<
    OnboardingWelcomeEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _onboardingWelcomeProvenance,
  eventContract: _onboardingWelcomeEvents,
  measurementPublicationDraftDigest:
      "4d3d926e7ee679cb7eb77919d9b2a879683778e45479f083f10cd58ee35a7054",
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
