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
        byteLength: 18802,
        sha256:
            "sha256:b027ce5dbcaab207c84fda244c3c68c5ef588cd008e949570307f02edc9c8535",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/survey/screens/measurement/7986973e7d641fcd/lumen_cancel_reason.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:0948b1b9074c07ee062cf4ecdc0c6b2be80d043c1eaa18232490ac4f628bffe8",
      ),
    ],
  ),
);

final lumenCancelReasonScreenRef = SurfaceScreenRef<
    LumenCancelReasonScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenCancelReasonScreenProvenance,
  eventContract: _lumenCancelReasonScreenEvents,
  measurementPublicationDraftDigest:
      "d339e350f108b1993c3882d1fda5e7d5c163cdafca84b132b9af89a3c35aa2d1",
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
            "sha256:6f3e7b1ef0cbbdc132b631bd672156939d48e10c471a2e77b7b43326c62b867e",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/survey/screens/measurement/79821ca45fbefc0b/lumen_cancel_thanks.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:24404970702ad9bbe6f1ebd5bab84e9c4e171c52586311adba58512f0cd84d75",
      ),
    ],
  ),
);

final lumenCancelThanksScreenRef = SurfaceScreenRef<
    LumenCancelThanksScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenCancelThanksScreenProvenance,
  eventContract: _lumenCancelThanksScreenEvents,
  measurementPublicationDraftDigest:
      "835e853f7fae11fba2470e049f467af326489d0b31bcab806ae4c1d3baee9fbd",
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
