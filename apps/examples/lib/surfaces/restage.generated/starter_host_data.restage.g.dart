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
    builtInFloor: 9,
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
        byteLength: 7347,
        sha256:
            'sha256:27510da1ae5d62e181baaa66bef848c73c8de7369d860ab22d0e75adbdb96577',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath: 'assets/general/screens/starter_checklist.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            'sha256:198d7880f40c4036212f7078fbc19a359bf7cadcf24d5b3cc97f3e880be7196e',
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
      'e9e783e3f132de5897bf76153c94a31a376cdbe389e56900a820e67364fd39ab',
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
  const StarterChecklistSurface({
    required String owner,
    required List<ChecklistItem> items,
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  })  : _restageArgument0 = owner,
        _restageArgument1 = items,
        _restagePlacementName = placement;

  const StarterChecklistSurface.atPlacement(
    String restagePlacementId, {
    required String owner,
    required List<ChecklistItem> items,
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
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
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
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
