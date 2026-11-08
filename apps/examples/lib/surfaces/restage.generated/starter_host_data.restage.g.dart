part of '../starter_host_data.dart';

// ignore_for_file: type=lint, unnecessary_cast

sealed class StarterChecklistSurfaceEvent {
  const StarterChecklistSurfaceEvent();
}

final class StarterChecklistSurfaceToggleEvent
    extends StarterChecklistSurfaceEvent {
  const StarterChecklistSurfaceToggleEvent(this.value);

  final String value;
}

final _starterChecklistEvents =
    SurfaceScreenEventContract<StarterChecklistSurfaceEvent>.generated(
  hash:
      'sha256:a7ada2e8b71a3ea880d9a08f8f6611049ca39921c9ef6ae9fd6ebef981c3dbe0',
  decodeValidated: _decodeValidatedStarterChecklistSurfaceEvent,
);

final _starterChecklistProvenance = SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.general,
  slug: 'starter_checklist',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 17,
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
        byteLength: 7924,
        sha256:
            'sha256:8e11cb3d5ea451ad9594c5483c01c2aa68c20ca818c7265b518eda5b2d99eef4',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath: 'assets/general/screens/starter_checklist.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 142,
        sha256:
            'sha256:46ba687973d4cc96cfb99cc3a74ab3704f5531ff25ef64bf7605d1af241b794f',
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
    StarterChecklistSurfaceEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _starterChecklistProvenance,
  eventContract: _starterChecklistEvents,
  measurementPublicationDraftDigest:
      'cfe5436ee0dbd30f22db2d67782ef300d6625d76e0797cd5c682e3e2aca08079',
);

StarterChecklistSurfaceEvent _decodeValidatedStarterChecklistSurfaceEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case 'toggle':
      return StarterChecklistSurfaceToggleEvent(arguments['value'] as String);
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
      'schemaVersion': 1,
      'inputs': <String, Object?>{
        'items': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'id': <String, Object?>{'kind': 'string'},
              'status': <String, Object?>{'kind': 'string'},
              'title': <String, Object?>{'kind': 'string'}
            }
          }
        },
        'owner': <String, Object?>{'kind': 'string'}
      }
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
  surfaceWidget: 'StarterChecklistSurface',
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
    this.fallbackBuilder,
    this.errorBuilder,
  })  : _restageStored0 = owner,
        _restageStored1 = items,
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
    this.fallbackBuilder,
    this.errorBuilder,
  })  : _restageStored0 = owner,
        _restageStored1 = items,
        _restagePlacementName = restagePlacementId;

  final String _restageStored0;
  String get _restageArgument0 => _restageStored0;

  final List<ChecklistItem> _restageStored1;
  List<ChecklistItem> get _restageArgument1 => _restageStored1;
  final String? _restagePlacementName;

  final ValueChanged<StarterChecklistSurfaceEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  final WidgetBuilder? fallbackBuilder;

  final Widget Function(BuildContext, SurfaceScreenUnavailableError)?
      errorBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording();
    Widget _restageDesign(Widget _restageBuilt) {
      return RestageScreen<StarterChecklistSurfaceEvent>(
        screen: starterChecklistRef,
        placementBinding: RestageScreen.generatedPlacementBinding(
          definition: starterChecklistPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
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
        fallbackBuilder: fallbackBuilder ?? ((_) => _restageBuilt),
        errorBuilder: errorBuilder,
        onUnavailable: onUnavailable,
        onEvent: onEvent,
        resolver: resolver,
        loadingBuilder: loadingBuilder,
      );
    }

    return (() => _restageDesign(StarterChecklist(
        owner: _restageArgument0, items: _restageArgument1)))();
  }
}
