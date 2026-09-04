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
        byteLength: 6796,
        sha256:
            "sha256:e26ea22774218c731e03d5d6fa3b0d52fa4f1e51bd70dd69a48f981d80c35049",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath: "assets/general/screens/starter_checklist.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:3649fce5f00ec80f1641617641e239910716983ef62e0541d6adb562600578cf",
      ),
    ],
  ),
);

final starterChecklistRef = SurfaceScreenRef<
    StarterChecklistEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _starterChecklistProvenance,
  eventContract: _starterChecklistEvents,
  measurementPublicationDraftDigest:
      "8d34e9bb0f2e739e3608205d29889a5797c94fce9e06ca1b6da1e4521dbfcc3a",
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
