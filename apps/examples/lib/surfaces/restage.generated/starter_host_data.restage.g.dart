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
            "sha256:2e7c3d2ecae6516be1196ec18b54e172e6d06174131c8f128cac1b6c293232ba",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath: "assets/general/screens/starter_checklist.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:af3085588b6d80e78109b3da17779f5f8ab0ba5b41e1ebf160d4c7421af0d690",
      ),
    ],
  ),
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Container': buildContainer,
        'Expanded': buildExpanded,
        'Padding': buildPadding,
        'Row': buildRow,
        'SafeArea': buildSafeArea,
        'SizedBox': buildSizedBox,
        'Text': buildText,
        'TextRich': buildTextRich,
      },
      material: {
        'AppBar': buildAppBar,
        'InkWell': buildInkWell,
        'Scaffold': buildScaffold,
      },
    ),
  ),
);

final starterChecklistRef = SurfaceScreenRef<
    StarterChecklistEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _starterChecklistProvenance,
  eventContract: _starterChecklistEvents,
  measurementPublicationDraftDigest:
      "bc51c428e3fa0151ac854fc45b68ffd8bfab22a9adadfdb40454e70b56607ff2",
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
