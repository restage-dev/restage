part of '../get_started_screen.dart';

// ignore_for_file: type=lint, unnecessary_cast

sealed class GetStartedScreenSurfaceEvent {
  const GetStartedScreenSurfaceEvent();
}

final class GetStartedScreenSurfaceContinueEventEvent
    extends GetStartedScreenSurfaceEvent {
  const GetStartedScreenSurfaceContinueEventEvent(this.value);

  final String value;
}

final _getStartedScreenEvents =
    SurfaceScreenEventContract<GetStartedScreenSurfaceEvent>.generated(
      hash:
          'sha256:528895db4d56cf54e7293e34be342265bdf0d414f70213361a21084810bdf593',
      decodeValidated: _decodeValidatedGetStartedScreenSurfaceEvent,
    );

final _getStartedScreenProvenance = SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.onboarding,
  slug: 'get_started_screen',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 24,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      '{"schemaVersion":1,"events":[{"id":"continue","arguments":{"encoding":"value","shape":{"kind":"string"}}}]}',
  hostDataSchemaJson:
      '{"schemaVersion":1,"inputs":{"_hb227fda92b":{"kind":"nativeBinding","contract":{"type":"flutter.Key","nullable":false},"label":"const ValueKey(\'get-started-action\')"},"context":{"kind":"string"},"data":{"kind":"string"},"description":{"kind":"string"},"enabled":{"kind":"bool"},"itemContext":{"kind":"string"},"title":{"kind":"string"},"usage":{"kind":"string"}}}',
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {'Center': buildCenter, 'Text': buildText},
      material: {'ElevatedButton': buildElevatedButton},
    ),
  ),
);

final getStartedScreenRef =
    SurfaceScreenRef<
      GetStartedScreenSurfaceEvent
    >.generatedWithMeasurementPublicationDraftDigest(
      provenance: _getStartedScreenProvenance,
      eventContract: _getStartedScreenEvents,
      measurementPublicationDraftDigest:
          '0f285024e0b273cb31d26b74f1ad358b40633a24504d3b2129e67bdf0d5b8916',
    );

GetStartedScreenSurfaceEvent _decodeValidatedGetStartedScreenSurfaceEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case 'continue':
      return GetStartedScreenSurfaceContinueEventEvent(
        arguments['value'] as String,
      );
  }
  throw FormatException('Invalid GetStartedScreen event "$name".');
}

final _getStartedScreenPlacementDefinitionValue =
    RestageScreen.generatedPlacementDefinition(
      defaultSurface: getStartedScreenRef,
      defaultSurfaceLocatorJson: <String, Object?>{
        'surfaceType': 'onboarding',
        'slug': 'get_started_screen',
        'family': <String, Object?>{
          'kind': 'screenContract',
          'contractVersion': 1,
        },
      },
      hostContractJson: <String, Object?>{
        'schemaVersion': 1,
        'hosting': <String, Object?>{
          'contentKind': 'single',
          'presentation': 'inline',
        },
        'providedContext': <String, Object?>{
          'schemaVersion': 1,
          'inputs': <String, Object?>{
            '_hb227fda92b': <String, Object?>{
              'kind': 'nativeBinding',
              'contract': <String, Object?>{
                'type': 'flutter.Key',
                'nullable': false,
              },
              'label': 'const ValueKey(\'get-started-action\')',
            },
            'context': <String, Object?>{'kind': 'string'},
            'data': <String, Object?>{'kind': 'string'},
            'description': <String, Object?>{'kind': 'string'},
            'enabled': <String, Object?>{'kind': 'bool'},
            'itemContext': <String, Object?>{'kind': 'string'},
            'title': <String, Object?>{'kind': 'string'},
            'usage': <String, Object?>{'kind': 'string'},
          },
        },
        'handledEvents': <String, Object?>{
          'schemaVersion': 1,
          'events': <Object?>[
            <String, Object?>{
              'id': 'continue',
              'arguments': <String, Object?>{
                'encoding': 'value',
                'shape': <String, Object?>{'kind': 'string'},
              },
            },
          ],
        },
        'flowBoundary': null,
      },
      vocabulary: getStartedScreenRef.provenance.vocabulary,
      surfaceWidget: 'GetStartedScreenSurface',
    );

final getStartedScreenPlacementDefinition = () =>
    _getStartedScreenPlacementDefinitionValue;

const bool _getStartedScreenMountDefault2 = true;

const GetStartedScreenTone _getStartedScreenMountDefault3 =
    GetStartedScreenTone.calm;

const String _getStartedScreenMountDefault4 = 'Example data';

const String _getStartedScreenMountDefault5 = 'Example context';

const String _getStartedScreenMountDefault6 = 'Example item context';

const GetStartedScreenTone _getStartedScreenMountDefault7 =
    GetStartedScreenTone.calm;

const String _getStartedScreenMountDefault8 = 'Example description';

const String _getStartedScreenMountDefault9 = 'Example usage';

final class GetStartedScreenSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const GetStartedScreenSurface({
    super.key,
    required String title,
    bool enabled = _getStartedScreenMountDefault2,
    GetStartedScreenTone tone = _getStartedScreenMountDefault3,
    String data = _getStartedScreenMountDefault4,
    String context = _getStartedScreenMountDefault5,
    String itemContext = _getStartedScreenMountDefault6,
    GetStartedScreenTone restageA2uiStatus = _getStartedScreenMountDefault7,
    String description = _getStartedScreenMountDefault8,
    String usage = _getStartedScreenMountDefault9,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  }) : _restageStored1 = title,
       _restageStored2 = enabled,
       _restageStored4 = data,
       _restageStored5 = context,
       _restageStored6 = itemContext,
       _restageStored8 = description,
       _restageStored9 = usage,
       _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [GetStartedScreenSurface] for the default placement; no name is needed.
  const GetStartedScreenSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    required String title,
    bool enabled = _getStartedScreenMountDefault2,
    GetStartedScreenTone tone = _getStartedScreenMountDefault3,
    String data = _getStartedScreenMountDefault4,
    String context = _getStartedScreenMountDefault5,
    String itemContext = _getStartedScreenMountDefault6,
    GetStartedScreenTone restageA2uiStatus = _getStartedScreenMountDefault7,
    String description = _getStartedScreenMountDefault8,
    String usage = _getStartedScreenMountDefault9,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  }) : _restageStored1 = title,
       _restageStored2 = enabled,
       _restageStored4 = data,
       _restageStored5 = context,
       _restageStored6 = itemContext,
       _restageStored8 = description,
       _restageStored9 = usage,
       _restagePlacementName = restagePlacementId;

  final String _restageStored1;
  String get _restageArgument1 => _restageStored1;

  final bool _restageStored2;
  bool get _restageArgument2 => _restageStored2;

  final String _restageStored4;
  String get _restageArgument4 => _restageStored4;

  final String _restageStored5;
  String get _restageArgument5 => _restageStored5;

  final String _restageStored6;
  String get _restageArgument6 => _restageStored6;

  final String _restageStored8;
  String get _restageArgument8 => _restageStored8;

  final String _restageStored9;
  String get _restageArgument9 => _restageStored9;
  final String? _restagePlacementName;

  final ValueChanged<GetStartedScreenSurfaceEvent>? onEvent;

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
      return RestageNativeValues(
        bindings: _restageRecording.bindings(
          (key) => switch (key.split('#').first) {
            '_hb227fda92b' => NativeBindingContract(
              type: 'flutter.Key',
              nullable: false,
            ),
            _ => throw StateError(key),
          },
          {},
        ),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_hb227fda92b': 'const ValueKey(\'get-started-action\')',
              },
        child: RestageScreen<GetStartedScreenSurfaceEvent>(
          screen: getStartedScreenRef,
          placementBinding: RestageScreen.generatedPlacementBinding(
            definition: getStartedScreenPlacementDefinition,
            name: _restagePlacementName,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            'title': _restageArgument1,
            'enabled': _restageArgument2,
            'data': _restageArgument4,
            'context': _restageArgument5,
            'itemContext': _restageArgument6,
            'description': _restageArgument8,
            'usage': _restageArgument9,
            '_hb227fda92b': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_hb227fda92b',
              "type": 'flutter.Key',
              "nullable": false,
            },
          },
          fallbackBuilder: fallbackBuilder ?? ((_) => _restageBuilt),
          errorBuilder: errorBuilder,
          onUnavailable: onUnavailable,
          onEvent: onEvent,
          resolver: resolver,
          loadingBuilder: loadingBuilder,
        ),
      );
    }

    return (() {
      return _restageDesign(
        Center(
          child: ElevatedButton(
            key: _restageRecording.native(
              '_hb227fda92b',
              const ValueKey('get-started-action'),
              type: 'flutter.Key',
              nullable: false,
            ),
            onPressed: _restageRecording.surfaceEvent(
              GetStartedScreen.continueEvent,
              'preview',
            ),
            child: const Text('Get started'),
          ),
        ),
      );
    })();
  }
}
