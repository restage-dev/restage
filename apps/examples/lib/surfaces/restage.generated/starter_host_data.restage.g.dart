part of '../starter_host_data.dart';

sealed class StarterChecklistEvent {
  const StarterChecklistEvent();
}

final class StarterChecklistToggleEvent extends StarterChecklistEvent {
  const StarterChecklistToggleEvent(this.value);

  final String value;
}

final _starterChecklistEvents =
    SurfaceScreenEventContract<StarterChecklistEvent>.generated(
  hash:
      "sha256:a7ada2e8b71a3ea880d9a08f8f6611049ca39921c9ef6ae9fd6ebef981c3dbe0",
  decodeValidated: _decodeValidatedStarterChecklistEvent,
);

final _starterChecklistProvenance = SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.general,
  slug: "starter_checklist",
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      "{\"schemaVersion\":1,\"events\":[{\"id\":\"toggle\",\"arguments\":{\"encoding\":\"value\",\"shape\":{\"kind\":\"string\"}}}]}",
  hostDataSchemaJson:
      "{\"schemaVersion\":1,\"inputs\":{\"items\":{\"kind\":\"list\",\"items\":{\"kind\":\"object\",\"fields\":{\"id\":{\"kind\":\"string\"},\"status\":{\"kind\":\"string\"},\"title\":{\"kind\":\"string\"}}}},\"owner\":{\"kind\":\"string\"}}}",
  bundle: SurfaceScreenBundleLocator(
    assetKey: "assets/restage/bundles/lib/surfaces/starter_host_data.rsbundle",
    packageName: "restage_example",
    authoredLibraryPath: "lib/surfaces/starter_host_data.dart",
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath: "assets/general/screens/starter_checklist.rfw",
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 7269,
        sha256:
            "sha256:9599731c37091dc1d77545c2f83a86e197ea58901c2a466c1567ecdd205038dd",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath: "assets/general/screens/starter_checklist.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:3d98c8f31bae841b9ad2e0339f79081e9df83df0c5b7c2de423c1dedec003dd9",
      ),
    ],
  ),
);

final starterChecklistRef = SurfaceScreenRef<
    StarterChecklistEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _starterChecklistProvenance,
  eventContract: _starterChecklistEvents,
  measurementPublicationDraftDigest:
      "72c49fc7f3f51619b903f932c62be98644425140e3313112094e29513d28c690",
);

StarterChecklistEvent _decodeValidatedStarterChecklistEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case "toggle":
      return StarterChecklistToggleEvent(arguments['value'] as String);
  }
  throw FormatException("Invalid StarterChecklist event \"" + name + "\".");
}

final class StarterChecklistSurface extends StatelessWidget {
  const StarterChecklistSurface({
    required String owner,
    required List<ChecklistItem> items,
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  })  : _restageArgument0 = owner,
        _restageArgument1 = items;

  final String _restageArgument0;

  final List<ChecklistItem> _restageArgument1;

  final ValueChanged<StarterChecklistEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<StarterChecklistEvent>(
      screen: starterChecklistRef,
      context: <String, Object?>{
        "owner": this._restageArgument0,
        "items": <Object?>[
          for (final _restageValue0 in this._restageArgument1)
            <String, Object?>{
              "id": _restageValue0.id,
              "title": _restageValue0.title,
              "status": _restageValue0.status
            }
        ],
      },
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
        builder: (context, error) => StarterChecklist(
          owner: this._restageArgument0,
          items: this._restageArgument1,
        ),
      ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}
