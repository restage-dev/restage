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
        logicalPath: "assets/general/screens/general_status.rfw",
        role: RestageBundleEntryRoleV1.screenBlob,
        byteLength: 294,
        sha256:
            "sha256:1ae8f2705bb19f252828dcee6ebf290eae269a5dee6b25a54931920d168ebcd3",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath: "assets/general/screens/general_status.capability.json",
        role: RestageBundleEntryRoleV1.capabilitySidecar,
        byteLength: 165,
        sha256:
            "sha256:89e64f177e966fc319d3c51c6dd669bacffdbdb157c2778d0e2059f3d13a53bb",
      ),
    ],
  ),
);

final generalStatusRef = SurfaceScreenRef<GeneralStatusEvent>.generated(
  provenance: _generalStatusProvenance,
  eventContract: _generalStatusEvents,
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

abstract final class GeneralStatusDescriptor {
  const GeneralStatusDescriptor._();

  static const NeutralFlowScreenRef ref = NeutralFlowScreenRef(
    id: 'general_status',
    artifactPath: 'general_status.rfw',
    version: 1,
    minClient: 1,
  );
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
        logicalPath: "assets/message/screens/message_notice.rfw",
        role: RestageBundleEntryRoleV1.screenBlob,
        byteLength: 304,
        sha256:
            "sha256:7b8dec85c690f81ab2ef4ded9e73965d6993a6ce424e80230eb94735d4b68ea4",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath: "assets/message/screens/message_notice.capability.json",
        role: RestageBundleEntryRoleV1.capabilitySidecar,
        byteLength: 165,
        sha256:
            "sha256:8d950cdbcb7265b9849492b15461d92033e8e6b3a9b38d63bc85f3573a3779d2",
      ),
    ],
  ),
);

final messageNoticeRef = SurfaceScreenRef<MessageNoticeEvent>.generated(
  provenance: _messageNoticeProvenance,
  eventContract: _messageNoticeEvents,
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

abstract final class MessageNoticeDescriptor {
  const MessageNoticeDescriptor._();

  static const NeutralFlowScreenRef ref = NeutralFlowScreenRef(
    id: 'message_notice',
    artifactPath: 'message_notice.rfw',
    version: 1,
    minClient: 1,
  );
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
        role: RestageBundleEntryRoleV1.screenBlob,
        byteLength: 300,
        sha256:
            "sha256:2001e30b617bd2b5f1a5c374b65e06f0d1ca6466d285f1ad7e451af4dc5cd9e4",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/onboarding/screens/onboarding_welcome.capability.json",
        role: RestageBundleEntryRoleV1.capabilitySidecar,
        byteLength: 165,
        sha256:
            "sha256:af0e5bfbdf4b1978c046f46bfecc34911059b21cdb879281c9d1a87085279192",
      ),
    ],
  ),
);

final onboardingWelcomeRef = SurfaceScreenRef<OnboardingWelcomeEvent>.generated(
  provenance: _onboardingWelcomeProvenance,
  eventContract: _onboardingWelcomeEvents,
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

abstract final class OnboardingWelcomeDescriptor {
  const OnboardingWelcomeDescriptor._();

  static const NeutralFlowScreenRef ref = NeutralFlowScreenRef(
    id: 'onboarding_welcome',
    artifactPath: 'onboarding_welcome.rfw',
    version: 1,
    minClient: 1,
  );
}
