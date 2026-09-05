part of '../lumen_cancel.dart';

sealed class LumenCancelReasonScreenEvent {
  const LumenCancelReasonScreenEvent();
}

final class LumenCancelReasonScreenReasonEvent
    extends LumenCancelReasonScreenEvent {
  const LumenCancelReasonScreenReasonEvent(this.value);

  final String value;
}

final _lumenCancelReasonScreenEvents =
    SurfaceScreenEventContract<LumenCancelReasonScreenEvent>.generated(
  hash:
      "sha256:e25d96c534ebc7ec3564efb7139e1831d07efa017eb30f377ba275931befe1d2",
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
      "{\"schemaVersion\":1,\"events\":[{\"id\":\"reason\",\"arguments\":{\"encoding\":\"value\",\"shape\":{\"kind\":\"string\"}}}]}",
  bundle: SurfaceScreenBundleLocator(
    assetKey: "assets/restage/bundles/lib/surfaces/lumen_cancel.rsbundle",
    packageName: "restage_example",
    authoredLibraryPath: "lib/surfaces/lumen_cancel.dart",
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/survey/screens/measurement/7986973e7d641fcd/lumen_cancel_reason.rfw",
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 18143,
        sha256:
            "sha256:4abb516a4ca591d69507a5a4f144764a743680268ff95bc2d89519b5385b775d",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/survey/screens/measurement/7986973e7d641fcd/lumen_cancel_reason.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:15f70cfb5866d27f37f4c85025ce25262398436e9ee9eed45a13e70e7bc2104d",
      ),
    ],
  ),
);

final lumenCancelReasonScreenRef = SurfaceScreenRef<
    LumenCancelReasonScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenCancelReasonScreenProvenance,
  eventContract: _lumenCancelReasonScreenEvents,
  measurementPublicationDraftDigest:
      "a79f9ca188ad6994c87631bbca85395cedd293f3124d530c9c2a87496a94c73b",
);

LumenCancelReasonScreenEvent _decodeValidatedLumenCancelReasonScreenEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case "reason":
      return LumenCancelReasonScreenReasonEvent(arguments['value'] as String);
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
        byteLength: 8151,
        sha256:
            "sha256:d0db5008770bf18da911e19db90e3d5ac8fe8832752c6b20c66c78688962d40a",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/survey/screens/measurement/79821ca45fbefc0b/lumen_cancel_thanks.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:3ee0d9139c793840ce9bfdb669c25ba49d026f232aa0f15562dc3f5e5d051bf8",
      ),
    ],
  ),
);

final lumenCancelThanksScreenRef = SurfaceScreenRef<
    LumenCancelThanksScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenCancelThanksScreenProvenance,
  eventContract: _lumenCancelThanksScreenEvents,
  measurementPublicationDraftDigest:
      "c1e3a1c892520dcd361cbe5557e714d30844ed697418466ac10023fe35c548cd",
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
