part of '../get_started_screen.dart';

// ignore_for_file: type=lint

sealed class GetStartedScreenEvent {
  const GetStartedScreenEvent();
}

final class GetStartedScreenContinueEventEvent extends GetStartedScreenEvent {
  const GetStartedScreenContinueEventEvent(this.value);

  final String value;
}

final _getStartedScreenEvents =
    SurfaceScreenEventContract<GetStartedScreenEvent>.generated(
      hash:
          'sha256:528895db4d56cf54e7293e34be342265bdf0d414f70213361a21084810bdf593',
      decodeValidated: _decodeValidatedGetStartedScreenEvent,
    );

final _getStartedScreenProvenance = SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.onboarding,
  slug: 'get_started_screen',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      '{"schemaVersion":1,"events":[{"id":"continue","arguments":{"encoding":"value","shape":{"kind":"string"}}}]}',
  hostDataSchemaJson:
      '{"schemaVersion":1,"inputs":{"context":{"kind":"string"},"data":{"kind":"string"},"description":{"kind":"string"},"enabled":{"kind":"bool"},"itemContext":{"kind":"string"},"title":{"kind":"string"},"usage":{"kind":"string"}}}',
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {'Center': buildCenter, 'Text': buildText},
      material: {'ElevatedButton': buildElevatedButton},
    ),
  ),
);

final getStartedScreenRef =
    SurfaceScreenRef<
      GetStartedScreenEvent
    >.generatedWithMeasurementPublicationDraftDigest(
      provenance: _getStartedScreenProvenance,
      eventContract: _getStartedScreenEvents,
      measurementPublicationDraftDigest:
          '7f2489841a7737ed05008ce9c08cb4644704c9de28050d7283bcddf2c16a1e18',
    );

GetStartedScreenEvent _decodeValidatedGetStartedScreenEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case 'continue':
      return GetStartedScreenContinueEventEvent(arguments['value'] as String);
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
          'inputs': <String, Object?>{
            'context': <String, Object?>{'kind': 'string'},
            'data': <String, Object?>{'kind': 'string'},
            'description': <String, Object?>{'kind': 'string'},
            'enabled': <String, Object?>{'kind': 'bool'},
            'itemContext': <String, Object?>{'kind': 'string'},
            'title': <String, Object?>{'kind': 'string'},
            'usage': <String, Object?>{'kind': 'string'},
          },
          'schemaVersion': 1,
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
    this.unavailable,
  }) : _restageArgument1 = title,
       _restageArgument2 = enabled,
       _restageArgument3 = tone,
       _restageArgument4 = data,
       _restageArgument5 = context,
       _restageArgument6 = itemContext,
       _restageArgument7 = restageA2uiStatus,
       _restageArgument8 = description,
       _restageArgument9 = usage,
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
    this.unavailable,
  }) : _restageArgument1 = title,
       _restageArgument2 = enabled,
       _restageArgument3 = tone,
       _restageArgument4 = data,
       _restageArgument5 = context,
       _restageArgument6 = itemContext,
       _restageArgument7 = restageA2uiStatus,
       _restageArgument8 = description,
       _restageArgument9 = usage,
       _restagePlacementName = restagePlacementId;

  final String _restageArgument1;

  final bool _restageArgument2;

  final GetStartedScreenTone _restageArgument3;

  final String _restageArgument4;

  final String _restageArgument5;

  final String _restageArgument6;

  final GetStartedScreenTone _restageArgument7;

  final String _restageArgument8;

  final String _restageArgument9;
  final String? _restagePlacementName;

  final ValueChanged<GetStartedScreenEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  final SurfaceScreenUnavailablePolicy? unavailable;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<GetStartedScreenEvent>(
      screen: getStartedScreenRef,
      placementBinding: RestageScreen.generatedPlacementBinding(
        definition: getStartedScreenPlacementDefinition,
        name: _restagePlacementName,
      ),
      context: <String, Object?>{
        'title': _restageArgument1,
        'enabled': _restageArgument2,
        'data': _restageArgument4,
        'context': _restageArgument5,
        'itemContext': _restageArgument6,
        'description': _restageArgument8,
        'usage': _restageArgument9,
      },
      unavailable:
          unavailable ??
          SurfaceScreenUnavailablePolicy.fallback(
            builder: (context, error) => GetStartedScreen(
              title: _restageArgument1,
              enabled: _restageArgument2,
              tone: _restageArgument3,
              data: _restageArgument4,
              context: _restageArgument5,
              itemContext: _restageArgument6,
              restageA2uiStatus: _restageArgument7,
              description: _restageArgument8,
              usage: _restageArgument9,
            ),
          ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}
