part of '../opaque_screen_proof.dart';

sealed class OpaqueScreenProofEvent {
  const OpaqueScreenProofEvent();
}

final class OpaqueScreenProofContinueEventEvent extends OpaqueScreenProofEvent {
  const OpaqueScreenProofContinueEventEvent(this.value);

  final String value;
}

final _opaqueScreenProofEvents =
    SurfaceScreenEventContract<OpaqueScreenProofEvent>.generated(
  hash:
      "sha256:528895db4d56cf54e7293e34be342265bdf0d414f70213361a21084810bdf593",
  decodeValidated: _decodeValidatedOpaqueScreenProofEvent,
);

final _opaqueScreenProofProvenance = SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.onboarding,
  slug: "opaque_screen_proof",
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      "{\"schemaVersion\":1,\"events\":[{\"id\":\"continue\",\"arguments\":{\"encoding\":\"value\",\"shape\":{\"kind\":\"string\"}}}]}",
  bundle: SurfaceScreenBundleLocator(
    assetKey:
        "assets/restage/bundles/lib/onboarding/screens/opaque_screen_proof.rsbundle",
    packageName: "restage_widgetbook_example",
    authoredLibraryPath: "lib/onboarding/screens/opaque_screen_proof.dart",
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath: "assets/onboarding/screens/opaque_screen_proof.rfw",
        role: RestageBundleEntryRoleV1.screenBlob,
        byteLength: 378,
        sha256:
            "sha256:52a780c74fe59fd5f8d61b8e8e9039ad031fe99529416ed4c4d5746bb3a074bd",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/onboarding/screens/opaque_screen_proof.capability.json",
        role: RestageBundleEntryRoleV1.capabilitySidecar,
        byteLength: 165,
        sha256:
            "sha256:f470665b7fa83785910bb6a81165146ef3f65ffbb88d3f1cbd0698b74304a969",
      ),
    ],
  ),
);

final opaqueScreenProofRef = SurfaceScreenRef<OpaqueScreenProofEvent>.generated(
  provenance: _opaqueScreenProofProvenance,
  eventContract: _opaqueScreenProofEvents,
);

OpaqueScreenProofEvent _decodeValidatedOpaqueScreenProofEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case "continue":
      return OpaqueScreenProofContinueEventEvent(arguments['value'] as String);
  }
  throw FormatException("Invalid OpaqueScreenProof event \"" + name + "\".");
}

abstract final class OpaqueScreenProofDescriptor {
  const OpaqueScreenProofDescriptor._();

  static const NeutralFlowScreenRef ref = NeutralFlowScreenRef(
    id: 'opaque_screen_proof',
    artifactPath: 'opaque_screen_proof.rfw',
    version: 1,
    minClient: 1,
  );
}
