part of '../lumen_cancel.dart';

sealed class LumenCancelReasonScreenEvent {
  const LumenCancelReasonScreenEvent();
}

final class LumenCancelReasonScreenReasonEvent
    extends LumenCancelReasonScreenEvent {
  const LumenCancelReasonScreenReasonEvent(this.value);

  final String value;
}

final class LumenCancelReasonScreenSkipEvent
    extends LumenCancelReasonScreenEvent {
  const LumenCancelReasonScreenSkipEvent();
}

final _lumenCancelReasonScreenEvents =
    SurfaceScreenEventContract<LumenCancelReasonScreenEvent>.generated(
  hash:
      'sha256:55bb77c38f6e53b2258a45594521bc78c955d54ae17505b1633c04fbba822784',
  decodeValidated: _decodeValidatedLumenCancelReasonScreenEvent,
);

final _lumenCancelReasonScreenProvenance =
    SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.survey,
  slug: 'lumen_cancel_reason',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 6,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      '{"schemaVersion":1,"events":[{"id":"reason","arguments":{"encoding":"value","shape":{"kind":"string"}}},{"id":"skip","arguments":{"encoding":"none"}}]}',
  bundle: SurfaceScreenBundleLocator(
    assetKey: 'assets/restage/bundles/lib/surfaces/lumen_cancel.rsbundle',
    packageName: 'restage_example',
    authoredLibraryPath: 'lib/surfaces/lumen_cancel.dart',
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/survey/screens/measurement/7986973e7d641fcd/lumen_cancel_reason.rfw',
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 31033,
        sha256:
            'sha256:77035f814368eac249350e9ef013a66d09cbadf2beb4df30e0400b9100e3f1d4',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/survey/screens/measurement/7986973e7d641fcd/lumen_cancel_reason.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            'sha256:842945bf0edd5e37793f969646542b1a45f231d4159359075f7aa507d8e42562',
      ),
    ],
  ),
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Center': buildCenter,
        'Column': buildColumn,
        'Container': buildContainer,
        'Expanded': buildExpanded,
        'GestureDetector': buildGestureDetector,
        'Padding': buildPadding,
        'Positioned': buildPositioned,
        'Row': buildRow,
        'SingleChildScrollView': buildSingleChildScrollView,
        'SizedBox': buildSizedBox,
        'Stack': buildStack,
        'Text': buildText,
      },
      material: {
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf647: IconData(0xf647, fontFamily: 'MaterialIcons'),
      },
    }, mirrored: {
      'MaterialIcons': {
        0xf57a: IconData(0xf57a,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
      },
    }),
  ),
);

final lumenCancelReasonScreenRef = SurfaceScreenRef<
    LumenCancelReasonScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenCancelReasonScreenProvenance,
  eventContract: _lumenCancelReasonScreenEvents,
  measurementPublicationDraftDigest:
      '52c2ecfca9418be09334ede0343458cc5e8883268dcd711f8effd57c056ae03c',
);

LumenCancelReasonScreenEvent _decodeValidatedLumenCancelReasonScreenEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case 'reason':
      return LumenCancelReasonScreenReasonEvent(arguments['value'] as String);
    case 'skip':
      return const LumenCancelReasonScreenSkipEvent();
  }
  throw FormatException('Invalid LumenCancelReasonScreen event "$name".');
}

final class LumenCancelReasonScreenSurface extends StatelessWidget {
  const LumenCancelReasonScreenSurface({
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  });

  final ValueChanged<LumenCancelReasonScreenEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<LumenCancelReasonScreenEvent>(
      screen: lumenCancelReasonScreenRef,
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
        builder: (context, error) => LumenCancelReasonScreen(),
      ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}

sealed class LumenCancelThanksScreenEvent {
  const LumenCancelThanksScreenEvent();
}

final class LumenCancelThanksScreenFinishEvent
    extends LumenCancelThanksScreenEvent {
  const LumenCancelThanksScreenFinishEvent();
}

final _lumenCancelThanksScreenEvents =
    SurfaceScreenEventContract<LumenCancelThanksScreenEvent>.generated(
  hash:
      'sha256:ca846c32a23d2d98fb3ca253fc69fb1ccef2fa2ee9fa5397947d5e5c2e03bc31',
  decodeValidated: _decodeValidatedLumenCancelThanksScreenEvent,
);

final _lumenCancelThanksScreenProvenance =
    SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.survey,
  slug: 'lumen_cancel_thanks',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 6,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      '{"schemaVersion":1,"events":[{"id":"finish","arguments":{"encoding":"none"}}]}',
  bundle: SurfaceScreenBundleLocator(
    assetKey: 'assets/restage/bundles/lib/surfaces/lumen_cancel.rsbundle',
    packageName: 'restage_example',
    authoredLibraryPath: 'lib/surfaces/lumen_cancel.dart',
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/survey/screens/measurement/79821ca45fbefc0b/lumen_cancel_thanks.rfw',
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 14841,
        sha256:
            'sha256:2e9886ce18c307dfbe468374f69c1c575ba5a842ff434bc13af345df1a69840c',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/survey/screens/measurement/79821ca45fbefc0b/lumen_cancel_thanks.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            'sha256:5558712cf4051dde71973c8129f1302cabae214a26df5d741e734842eaf555c4',
      ),
    ],
  ),
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Center': buildCenter,
        'Column': buildColumn,
        'Container': buildContainer,
        'Expanded': buildExpanded,
        'GestureDetector': buildGestureDetector,
        'Padding': buildPadding,
        'Positioned': buildPositioned,
        'SingleChildScrollView': buildSingleChildScrollView,
        'SizedBox': buildSizedBox,
        'Stack': buildStack,
        'Text': buildText,
      },
      material: {
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf738: IconData(0xf738, fontFamily: 'MaterialIcons'),
      },
    }),
  ),
);

final lumenCancelThanksScreenRef = SurfaceScreenRef<
    LumenCancelThanksScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenCancelThanksScreenProvenance,
  eventContract: _lumenCancelThanksScreenEvents,
  measurementPublicationDraftDigest:
      'f43a599344d8d51cb7bfa9c8a09b0272a9711773902091c7f1dc5d6f41dfaee0',
);

LumenCancelThanksScreenEvent _decodeValidatedLumenCancelThanksScreenEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case 'finish':
      return const LumenCancelThanksScreenFinishEvent();
  }
  throw FormatException('Invalid LumenCancelThanksScreen event "$name".');
}

final class LumenCancelThanksScreenSurface extends StatelessWidget {
  const LumenCancelThanksScreenSurface({
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  });

  final ValueChanged<LumenCancelThanksScreenEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<LumenCancelThanksScreenEvent>(
      screen: lumenCancelThanksScreenRef,
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
        builder: (context, error) => LumenCancelThanksScreen(),
      ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}
