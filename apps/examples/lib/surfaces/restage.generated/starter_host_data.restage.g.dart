part of '../starter_host_data.dart';

// ignore_for_file: type=lint

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
      'sha256:a7ada2e8b71a3ea880d9a08f8f6611049ca39921c9ef6ae9fd6ebef981c3dbe0',
  decodeValidated: _decodeValidatedStarterChecklistEvent,
);

final _starterChecklistProvenance = SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.general,
  slug: 'starter_checklist',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 12,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      '{"schemaVersion":1,"events":[{"id":"toggle","arguments":{"encoding":"value","shape":{"kind":"string"}}}]}',
  hostDataSchemaJson:
      '{"schemaVersion":1,"inputs":{"items":{"kind":"list","items":{"kind":"object","fields":{"id":{"kind":"string"},"status":{"kind":"string"},"title":{"kind":"string"}}}},"owner":{"kind":"string"}}}',
  bundle: SurfaceScreenBundleLocator(
    assetKey: 'assets/restage/bundles/lib/surfaces/starter_host_data.rsbundle',
    packageName: 'restage_example',
    authoredLibraryPath: 'lib/surfaces/starter_host_data.dart',
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath: 'assets/general/screens/starter_checklist.rfw',
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 7774,
        sha256:
            'sha256:ebd22440bbac209d592ddeff2b0799fc87d1557ec787bbb4ac6f0e5b68281f83',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath: 'assets/general/screens/starter_checklist.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 142,
        sha256:
            'sha256:24f72b105eea8f9e624f0ef233c611854668ebd133c5198a5a5371b087b75777',
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
      '841c9b32ad83517b1e60b29dacf2e7af1efccf40044a2e7dc74e9ba3eb436da0',
);

StarterChecklistEvent _decodeValidatedStarterChecklistEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case 'toggle':
      return StarterChecklistToggleEvent(arguments['value'] as String);
  }
  throw FormatException('Invalid StarterChecklist event "$name".');
}

final _starterChecklistPlacementDefinitionValue =
    RestageScreen.generatedPlacementDefinition(
  defaultSurface: starterChecklistRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'general',
    'slug': 'starter_checklist',
    'family': <String, Object?>{'kind': 'screenContract', 'contractVersion': 1}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'inputs': <String, Object?>{
        'items': <String, Object?>{
          'items': <String, Object?>{
            'fields': <String, Object?>{
              'id': <String, Object?>{'kind': 'string'},
              'status': <String, Object?>{'kind': 'string'},
              'title': <String, Object?>{'kind': 'string'}
            },
            'kind': 'object'
          },
          'kind': 'list'
        },
        'owner': <String, Object?>{'kind': 'string'}
      },
      'schemaVersion': 1
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[
        <String, Object?>{
          'id': 'toggle',
          'arguments': <String, Object?>{
            'encoding': 'value',
            'shape': <String, Object?>{'kind': 'string'}
          }
        }
      ]
    },
    'flowBoundary': null
  },
  vocabulary: starterChecklistRef.provenance.vocabulary,
);

final starterChecklistPlacementDefinition =
    () => _starterChecklistPlacementDefinitionValue;

final class StarterChecklistSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const StarterChecklistSurface({
    required String owner,
    required List<ChecklistItem> items,
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.unavailable,
  })  : _restageArgument0 = owner,
        _restageArgument1 = items,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [StarterChecklistSurface] for the default placement; no name is needed.
  const StarterChecklistSurface.atPlacement(
    String restagePlacementId, {
    required String owner,
    required List<ChecklistItem> items,
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.unavailable,
  })  : _restageArgument0 = owner,
        _restageArgument1 = items,
        _restagePlacementName = restagePlacementId;

  final String _restageArgument0;

  final List<ChecklistItem> _restageArgument1;
  final String? _restagePlacementName;

  final ValueChanged<StarterChecklistEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  final SurfaceScreenUnavailablePolicy? unavailable;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<StarterChecklistEvent>(
      screen: starterChecklistRef,
      placementBinding: RestageScreen.generatedPlacementBinding(
        definition: starterChecklistPlacementDefinition,
        name: _restagePlacementName,
      ),
      context: <String, Object?>{
        'owner': _restageArgument0,
        'items': <Object?>[
          for (final restageValue0 in _restageArgument1)
            <String, Object?>{
              'id': restageValue0.id,
              'title': restageValue0.title,
              'status': restageValue0.status
            }
        ],
      },
      unavailable: unavailable ??
          SurfaceScreenUnavailablePolicy.fallback(
            builder: (context, error) => StarterChecklist(
              owner: _restageArgument0,
              items: _restageArgument1,
            ),
          ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}
