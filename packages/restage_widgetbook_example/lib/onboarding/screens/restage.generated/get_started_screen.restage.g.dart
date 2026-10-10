part of '../get_started_screen.dart';

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
  hostDataSchemaJson:
      "{\"schemaVersion\":1,\"inputs\":{\"context\":{\"kind\":\"string\"},\"data\":{\"kind\":\"string\"},\"description\":{\"kind\":\"string\"},\"enabled\":{\"kind\":\"bool\"},\"itemContext\":{\"kind\":\"string\"},\"title\":{\"kind\":\"string\"},\"usage\":{\"kind\":\"string\"}}}",
  bundle: SurfaceScreenBundleLocator(
    assetKey:
        "assets/restage/bundles/lib/onboarding/screens/get_started_screen.rsbundle",
    packageName: "restage_widgetbook_example",
    authoredLibraryPath: "lib/onboarding/screens/get_started_screen.dart",
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath: "assets/onboarding/screens/opaque_screen_proof.rfw",
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 1755,
        sha256:
            "sha256:8cc8b91acac4f019533b9b6f5d38c8aed5fbb1e23edb9a1b23fe2883269aa71b",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/onboarding/screens/opaque_screen_proof.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:4d6d51b9ffb9050f4dd471ba0c198eda72adc62dffad4c043a43a9c98e17cbf1",
      ),
    ],
  ),
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Center': buildCenter,
        'Text': buildText,
      },
      material: {
        'ElevatedButton': buildElevatedButton,
      },
    ),
  ),
);

final opaqueScreenProofRef = SurfaceScreenRef<
    OpaqueScreenProofEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _opaqueScreenProofProvenance,
  eventContract: _opaqueScreenProofEvents,
  measurementPublicationDraftDigest:
      "996960781c1ced5ed4805bd8f0dfc0653ca3ae0cc7f945fc2f436d5cb30127f4",
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

const bool _opaqueScreenProofMountDefault2 = true;

const OpaqueScreenProofTone _opaqueScreenProofMountDefault3 =
    OpaqueScreenProofTone.calm;

const String _opaqueScreenProofMountDefault4 = 'Example data';

const String _opaqueScreenProofMountDefault5 = 'Example context';

const String _opaqueScreenProofMountDefault6 = 'Example item context';

const OpaqueScreenProofTone _opaqueScreenProofMountDefault7 =
    OpaqueScreenProofTone.calm;

const String _opaqueScreenProofMountDefault8 = 'Example description';

const String _opaqueScreenProofMountDefault9 = 'Example usage';

final class OpaqueScreenProofSurface extends StatelessWidget {
  const OpaqueScreenProofSurface({
    super.key,
    required String title,
    bool enabled = _opaqueScreenProofMountDefault2,
    OpaqueScreenProofTone tone = _opaqueScreenProofMountDefault3,
    String data = _opaqueScreenProofMountDefault4,
    String context = _opaqueScreenProofMountDefault5,
    String itemContext = _opaqueScreenProofMountDefault6,
    OpaqueScreenProofTone restageA2uiStatus = _opaqueScreenProofMountDefault7,
    String description = _opaqueScreenProofMountDefault8,
    String usage = _opaqueScreenProofMountDefault9,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  })  : _restageArgument1 = title,
        _restageArgument2 = enabled,
        _restageArgument3 = tone,
        _restageArgument4 = data,
        _restageArgument5 = context,
        _restageArgument6 = itemContext,
        _restageArgument7 = restageA2uiStatus,
        _restageArgument8 = description,
        _restageArgument9 = usage;

  final String _restageArgument1;

  final bool _restageArgument2;

  final OpaqueScreenProofTone _restageArgument3;

  final String _restageArgument4;

  final String _restageArgument5;

  final String _restageArgument6;

  final OpaqueScreenProofTone _restageArgument7;

  final String _restageArgument8;

  final String _restageArgument9;

  final ValueChanged<OpaqueScreenProofEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<OpaqueScreenProofEvent>(
      screen: opaqueScreenProofRef,
      context: <String, Object?>{
        "title": this._restageArgument1,
        "enabled": this._restageArgument2,
        "data": this._restageArgument4,
        "context": this._restageArgument5,
        "itemContext": this._restageArgument6,
        "description": this._restageArgument8,
        "usage": this._restageArgument9,
      },
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
        builder: (context, error) => OpaqueScreenProof(
          title: this._restageArgument1,
          enabled: this._restageArgument2,
          tone: this._restageArgument3,
          data: this._restageArgument4,
          context: this._restageArgument5,
          itemContext: this._restageArgument6,
          restageA2uiStatus: this._restageArgument7,
          description: this._restageArgument8,
          usage: this._restageArgument9,
        ),
      ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}
