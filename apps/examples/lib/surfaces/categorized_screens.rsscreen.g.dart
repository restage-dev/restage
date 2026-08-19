part of "categorized_screens.dart";

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

final generalStatusRef = SurfaceScreenRef<GeneralStatusEvent>.generated(
  slug: "general_status",
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  surface: Surface.general,
  contractFingerprint:
      "sha256:aa5da094aaf979ecd7abeee8f8962bf19fcc5ce3ef0bf8a8e6a9c9bd4134bfb5",
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

final messageNoticeRef = SurfaceScreenRef<MessageNoticeEvent>.generated(
  slug: "message_notice",
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  surface: Surface.message,
  contractFingerprint:
      "sha256:cb7253a22ff186fb080e57ec4373576b0089c4b4a49d0616122a3c3a84ed7092",
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

final onboardingWelcomeRef = SurfaceScreenRef<OnboardingWelcomeEvent>.generated(
  slug: "onboarding_welcome",
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  surface: Surface.onboarding,
  contractFingerprint:
      "sha256:925dc704ea85a5de9915215a6baac7303edaeb04f1be98d153b4aae674f4df1d",
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
