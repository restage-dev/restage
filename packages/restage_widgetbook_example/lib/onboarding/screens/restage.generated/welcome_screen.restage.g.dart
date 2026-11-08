part of '../welcome_screen.dart';

// ignore_for_file: type=lint, unnecessary_cast

sealed class WelcomeScreenSurfaceEvent {
  const WelcomeScreenSurfaceEvent();
}

final class WelcomeScreenSurfaceContinueEventEvent
    extends WelcomeScreenSurfaceEvent {
  const WelcomeScreenSurfaceContinueEventEvent(this.value);

  final String value;
}

final _welcomeScreenEvents =
    SurfaceScreenEventContract<WelcomeScreenSurfaceEvent>.generated(
      hash:
          'sha256:528895db4d56cf54e7293e34be342265bdf0d414f70213361a21084810bdf593',
      decodeValidated: _decodeValidatedWelcomeScreenSurfaceEvent,
    );

final _welcomeScreenProvenance = SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.onboarding,
  slug: 'welcome_screen',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      '{"schemaVersion":1,"events":[{"id":"continue","arguments":{"encoding":"value","shape":{"kind":"string"}}}]}',
  hostDataSchemaJson:
      '{"schemaVersion":1,"inputs":{"title":{"kind":"string"}}}',
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {'Center': buildCenter, 'Text': buildText},
      material: {'ElevatedButton': buildElevatedButton},
    ),
  ),
);

final welcomeScreenRef =
    SurfaceScreenRef<
      WelcomeScreenSurfaceEvent
    >.generatedWithMeasurementPublicationDraftDigest(
      provenance: _welcomeScreenProvenance,
      eventContract: _welcomeScreenEvents,
      measurementPublicationDraftDigest:
          'f2b401096b496bd20ff27f0dc732ca6a522463872bc5e19049927fe57e42cbe3',
    );

WelcomeScreenSurfaceEvent _decodeValidatedWelcomeScreenSurfaceEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case 'continue':
      return WelcomeScreenSurfaceContinueEventEvent(
        arguments['value'] as String,
      );
  }
  throw FormatException('Invalid WelcomeScreen event "$name".');
}

final _welcomeScreenPlacementDefinitionValue =
    RestageScreen.generatedPlacementDefinition(
      defaultSurface: welcomeScreenRef,
      defaultSurfaceLocatorJson: <String, Object?>{
        'surfaceType': 'onboarding',
        'slug': 'welcome_screen',
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
            'title': <String, Object?>{'kind': 'string'},
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
      vocabulary: welcomeScreenRef.provenance.vocabulary,
      surfaceWidget: 'WelcomeScreenSurface',
    );

final welcomeScreenPlacementDefinition = () =>
    _welcomeScreenPlacementDefinitionValue;

const WelcomeScreenTone _welcomeScreenMountDefault2 = WelcomeScreenTone.calm;

final class WelcomeScreenSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const WelcomeScreenSurface({
    super.key,
    required String title,
    WelcomeScreenTone tone = _welcomeScreenMountDefault2,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  }) : _restageStored1 = title,
       _restageStored2 = tone,
       _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [WelcomeScreenSurface] for the default placement; no name is needed.
  const WelcomeScreenSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    required String title,
    WelcomeScreenTone tone = _welcomeScreenMountDefault2,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  }) : _restageStored1 = title,
       _restageStored2 = tone,
       _restagePlacementName = restagePlacementId;

  final String _restageStored1;
  String get _restageArgument1 => _restageStored1;

  final WelcomeScreenTone _restageStored2;
  WelcomeScreenTone get _restageArgument2 => _restageStored2;
  final String? _restagePlacementName;

  final ValueChanged<WelcomeScreenSurfaceEvent>? onEvent;

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
      return RestageScreen<WelcomeScreenSurfaceEvent>(
        screen: welcomeScreenRef,
        placementBinding: RestageScreen.generatedPlacementBinding(
          definition: welcomeScreenPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'title': _restageArgument1,
        },
        fallbackBuilder: fallbackBuilder ?? ((_) => _restageBuilt),
        errorBuilder: errorBuilder,
        onUnavailable: onUnavailable,
        onEvent: onEvent,
        resolver: resolver,
        loadingBuilder: loadingBuilder,
      );
    }

    return (() => _restageDesign(
      WelcomeScreen(title: _restageArgument1, tone: _restageArgument2),
    ))();
  }
}
