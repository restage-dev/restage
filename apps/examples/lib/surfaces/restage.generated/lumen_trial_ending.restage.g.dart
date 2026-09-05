part of '../lumen_trial_ending.dart';

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
      "sha256:c873ccfbaabb443865b81010c061e6321c2a6acf0488747e8cdc68debb658508",
  decodeValidated: _decodeValidatedLumenTrialEndingScreenEvent,
);

final _lumenTrialEndingScreenProvenance =
    SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.message,
  slug: "lumen_trial_ending",
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      "{\"schemaVersion\":1,\"events\":[{\"id\":\"later\",\"arguments\":{\"encoding\":\"none\"}},{\"id\":\"open_offer\",\"arguments\":{\"encoding\":\"none\"}}]}",
  bundle: SurfaceScreenBundleLocator(
    assetKey: "assets/restage/bundles/lib/surfaces/lumen_trial_ending.rsbundle",
    packageName: "restage_example",
    authoredLibraryPath: "lib/surfaces/lumen_trial_ending.dart",
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/message/screens/measurement/d2a9dd6bcb9f4c2c/lumen_trial_ending.rfw",
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 21460,
        sha256:
            "sha256:f44e2aaba46fe1a62b7ed0812c9fb8f5b5c59437f99e97a2c0f6d0e0173f31a5",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/message/screens/measurement/d2a9dd6bcb9f4c2c/lumen_trial_ending.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:f39890b189cfaf31f1b72546e69b82d17366ec5de4977e46f323722da489b832",
      ),
    ],
  ),
);

final lumenTrialEndingScreenRef = SurfaceScreenRef<
    LumenTrialEndingScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenTrialEndingScreenProvenance,
  eventContract: _lumenTrialEndingScreenEvents,
  measurementPublicationDraftDigest:
      "5bc664ec75d0469bf406787b68115e92bf2eca72cc6255d9c7a801020deaa1e7",
);

LumenTrialEndingScreenEvent _decodeValidatedLumenTrialEndingScreenEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case "later":
      return const LumenTrialEndingScreenLaterEvent();
    case "open_offer":
      return const LumenTrialEndingScreenOpenOfferEvent();
  }
  throw FormatException(
      "Invalid LumenTrialEndingScreen event \"" + name + "\".");
}

final class LumenTrialEndingScreenSurface extends StatelessWidget {
  const LumenTrialEndingScreenSurface({
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  });

  final ValueChanged<LumenTrialEndingScreenEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<LumenTrialEndingScreenEvent>(
      screen: lumenTrialEndingScreenRef,
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
