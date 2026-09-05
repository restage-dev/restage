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
            "sha256:8366cd1cb2713e75cd8c022f5be906ec186eced354bc5458cc46a319e83ce115",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/survey/screens/measurement/7986973e7d641fcd/lumen_cancel_reason.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:3ce4aba65d728c89653633437c6430a49987b1561086c772de02dd674c439848",
      ),
    ],
  ),
);

final lumenCancelReasonScreenRef = SurfaceScreenRef<
    LumenCancelReasonScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenCancelReasonScreenProvenance,
  eventContract: _lumenCancelReasonScreenEvents,
  measurementPublicationDraftDigest:
      "2b1a2d0058ddd8c0a90224a0470271938c621c6df13accb427d82e11564e2711",
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
            "sha256:d5350c4ed384691071e8fdeedae0187939952ddb541113ca3ac91918b381780b",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/survey/screens/measurement/79821ca45fbefc0b/lumen_cancel_thanks.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:48b8276329bb2348eb30be856df076caf36265e69260c08cb6a2c127b6579b3e",
      ),
    ],
  ),
);

final lumenCancelThanksScreenRef = SurfaceScreenRef<
    LumenCancelThanksScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenCancelThanksScreenProvenance,
  eventContract: _lumenCancelThanksScreenEvents,
  measurementPublicationDraftDigest:
      "821b7adc7f2ac7b76b04d5354c687d2b39b73d9436890007fa699b6aa70bc75e",
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
