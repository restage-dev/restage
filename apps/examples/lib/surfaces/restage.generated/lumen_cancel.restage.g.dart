part of '../lumen_cancel.dart';

sealed class LumenCancelReasonScreenEvent {
  const LumenCancelReasonScreenEvent();
}

final class LumenCancelReasonScreenReasonEvent
    extends LumenCancelReasonScreenEvent {
  const LumenCancelReasonScreenReasonEvent(this.value);

  final String value;
}

final class LumenCancelReasonScreenSkipEvent
    extends LumenCancelReasonScreenEvent {
  const LumenCancelReasonScreenSkipEvent();
}

final _lumenCancelReasonScreenEvents =
    SurfaceScreenEventContract<LumenCancelReasonScreenEvent>.generated(
  hash:
      "sha256:55bb77c38f6e53b2258a45594521bc78c955d54ae17505b1633c04fbba822784",
  decodeValidated: _decodeValidatedLumenCancelReasonScreenEvent,
);

final _lumenCancelReasonScreenProvenance =
    SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.survey,
  slug: "lumen_cancel_reason",
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      "{\"schemaVersion\":1,\"events\":[{\"id\":\"reason\",\"arguments\":{\"encoding\":\"value\",\"shape\":{\"kind\":\"string\"}}},{\"id\":\"skip\",\"arguments\":{\"encoding\":\"none\"}}]}",
  bundle: SurfaceScreenBundleLocator(
    assetKey: "assets/restage/bundles/lib/surfaces/lumen_cancel.rsbundle",
    packageName: "restage_example",
    authoredLibraryPath: "lib/surfaces/lumen_cancel.dart",
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/survey/screens/measurement/7986973e7d641fcd/lumen_cancel_reason.rfw",
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 30878,
        sha256:
            "sha256:61f93a84912c24769868758da2eda068d4efa575925cb6b6696fa58a9a41147b",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/survey/screens/measurement/7986973e7d641fcd/lumen_cancel_reason.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:d7abc48cbfc14590e851d050775951956a46c2e0d83bacfbe890cb40a3e88d7e",
      ),
    ],
  ),
);

final lumenCancelReasonScreenRef = SurfaceScreenRef<
    LumenCancelReasonScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenCancelReasonScreenProvenance,
  eventContract: _lumenCancelReasonScreenEvents,
  measurementPublicationDraftDigest:
      "0822652e997bf2bbb2dc34e3b40da6c3ddb4806a7ece5a68a8a5cdf7bee98561",
);

LumenCancelReasonScreenEvent _decodeValidatedLumenCancelReasonScreenEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case "reason":
      return LumenCancelReasonScreenReasonEvent(arguments['value'] as String);
    case "skip":
      return const LumenCancelReasonScreenSkipEvent();
  }
  throw FormatException(
      "Invalid LumenCancelReasonScreen event \"" + name + "\".");
}

final class LumenCancelReasonScreenSurface extends StatelessWidget {
  const LumenCancelReasonScreenSurface({
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  });

  final ValueChanged<LumenCancelReasonScreenEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<LumenCancelReasonScreenEvent>(
      screen: lumenCancelReasonScreenRef,
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
        builder: (context, error) => LumenCancelReasonScreen(),
      ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}

sealed class LumenCancelThanksScreenEvent {
  const LumenCancelThanksScreenEvent();
}

final class LumenCancelThanksScreenFinishEvent
    extends LumenCancelThanksScreenEvent {
  const LumenCancelThanksScreenFinishEvent();
}

final _lumenCancelThanksScreenEvents =
    SurfaceScreenEventContract<LumenCancelThanksScreenEvent>.generated(
  hash:
      "sha256:ca846c32a23d2d98fb3ca253fc69fb1ccef2fa2ee9fa5397947d5e5c2e03bc31",
  decodeValidated: _decodeValidatedLumenCancelThanksScreenEvent,
);

final _lumenCancelThanksScreenProvenance =
    SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.survey,
  slug: "lumen_cancel_thanks",
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      "{\"schemaVersion\":1,\"events\":[{\"id\":\"finish\",\"arguments\":{\"encoding\":\"none\"}}]}",
  bundle: SurfaceScreenBundleLocator(
    assetKey: "assets/restage/bundles/lib/surfaces/lumen_cancel.rsbundle",
    packageName: "restage_example",
    authoredLibraryPath: "lib/surfaces/lumen_cancel.dart",
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/survey/screens/measurement/79821ca45fbefc0b/lumen_cancel_thanks.rfw",
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 14841,
        sha256:
            "sha256:29de7b441147fda8a729a9f9cdbffa7a29b8235b47a85a6e7e9afdd6fb742a8d",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/survey/screens/measurement/79821ca45fbefc0b/lumen_cancel_thanks.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:f0e33af6112daf8b190c55ff3c199a878d26a487bd17d526fa3bac4cbdbbcb55",
      ),
    ],
  ),
);

final lumenCancelThanksScreenRef = SurfaceScreenRef<
    LumenCancelThanksScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenCancelThanksScreenProvenance,
  eventContract: _lumenCancelThanksScreenEvents,
  measurementPublicationDraftDigest:
      "f9573ad11fd4dd46bf3e2108f1e14a6199b68ba4ad3e418ff61a19a63c53457a",
);

LumenCancelThanksScreenEvent _decodeValidatedLumenCancelThanksScreenEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case "finish":
      return const LumenCancelThanksScreenFinishEvent();
  }
  throw FormatException(
      "Invalid LumenCancelThanksScreen event \"" + name + "\".");
}

final class LumenCancelThanksScreenSurface extends StatelessWidget {
  const LumenCancelThanksScreenSurface({
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  });

  final ValueChanged<LumenCancelThanksScreenEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<LumenCancelThanksScreenEvent>(
      screen: lumenCancelThanksScreenRef,
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
        builder: (context, error) => LumenCancelThanksScreen(),
      ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}
