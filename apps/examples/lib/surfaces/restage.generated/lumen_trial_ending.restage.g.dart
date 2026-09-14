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
            "sha256:eb77aa592ebf2c417cc1f7a41aa07f253e3067c930de5e43911ac6212e4046e1",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/message/screens/measurement/d2a9dd6bcb9f4c2c/lumen_trial_ending.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:3452b4e669d9b44103cc33b6c5823bac46b9f290821946183979338161574b41",
      ),
    ],
  ),
);

final lumenTrialEndingScreenRef = SurfaceScreenRef<
    LumenTrialEndingScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenTrialEndingScreenProvenance,
  eventContract: _lumenTrialEndingScreenEvents,
  measurementPublicationDraftDigest:
      "c7faf99aa594711a294c1466ec70b7c11659190653c5d1bc98961488192287a0",
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
