part of '../get_started_screen.dart';

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
  bundle: SurfaceScreenBundleLocator(
    assetKey:
        'assets/restage/bundles/lib/onboarding/screens/get_started_screen.rsbundle',
    packageName: 'restage_widgetbook_example',
    authoredLibraryPath: 'lib/onboarding/screens/get_started_screen.dart',
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath: 'assets/onboarding/screens/get_started_screen.rfw',
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 1747,
        sha256:
            'sha256:6de6f52ac71212a2a79391f6871f1eccf5645066bb6d7e6798aacbac29b3d355',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/onboarding/screens/get_started_screen.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            'sha256:7640f8efacf15a352bc9da2b4d2cfb77ccf99d463956a37df63d3d9fdcca0e30',
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

final getStartedScreenRef = SurfaceScreenRef<
    GetStartedScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _getStartedScreenProvenance,
  eventContract: _getStartedScreenEvents,
  measurementPublicationDraftDigest:
      '1e31372e4267dbd073fdcaacbbb907c8a1a158892c9a7c053f435fd21dc1a7ae',
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

  final GetStartedScreenTone _restageArgument3;

  final String _restageArgument4;

  final String _restageArgument5;

  final String _restageArgument6;

  final GetStartedScreenTone _restageArgument7;

  final String _restageArgument8;

  final String _restageArgument9;

  final ValueChanged<GetStartedScreenEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<GetStartedScreenEvent>(
      screen: getStartedScreenRef,
      context: <String, Object?>{
        'title': _restageArgument1,
        'enabled': _restageArgument2,
        'data': _restageArgument4,
        'context': _restageArgument5,
        'itemContext': _restageArgument6,
        'description': _restageArgument8,
        'usage': _restageArgument9,
      },
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
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
