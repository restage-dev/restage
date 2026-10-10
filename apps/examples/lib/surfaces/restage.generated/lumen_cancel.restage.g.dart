part of '../lumen_cancel.dart';

// ignore_for_file: type=lint

sealed class LumenCancelNoteScreenEvent {
  const LumenCancelNoteScreenEvent();
}

final class LumenCancelNoteScreenSendEvent extends LumenCancelNoteScreenEvent {
  const LumenCancelNoteScreenSendEvent(this.value);

  final String value;
}

final class LumenCancelNoteScreenSkipEvent extends LumenCancelNoteScreenEvent {
  const LumenCancelNoteScreenSkipEvent();
}

final _lumenCancelNoteScreenEvents =
    SurfaceScreenEventContract<LumenCancelNoteScreenEvent>.generated(
  hash:
      'sha256:845ed8018eaa74aee9fc9d2480d99f931510601bb1109f245111ef3237614ca1',
  decodeValidated: _decodeValidatedLumenCancelNoteScreenEvent,
);

final _lumenCancelNoteScreenProvenance =
    SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.survey,
  slug: 'lumen_cancel_note',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 9,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      '{"schemaVersion":1,"events":[{"id":"send","arguments":{"encoding":"value","shape":{"kind":"string"}}},{"id":"skip","arguments":{"encoding":"none"}}]}',
  bundle: SurfaceScreenBundleLocator(
    assetKey: 'assets/restage/bundles/lib/surfaces/lumen_cancel.rsbundle',
    packageName: 'restage_example',
    authoredLibraryPath: 'lib/surfaces/lumen_cancel.dart',
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/survey/screens/measurement/69385e84f6569c7c/lumen_cancel_note.rfw',
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 15247,
        sha256:
            'sha256:a93f2c562a28062e9a558545cbffc06de75f458ce976891d232a7d1574621d17',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/survey/screens/measurement/69385e84f6569c7c/lumen_cancel_note.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            'sha256:0f2d8643b397802065649971ea0d8505f1db202e1b1333c8600aeb66722001f8',
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
        'Scaffold': buildScaffold,
        'TextField': buildTextField,
      },
    ),
  ),
);

final lumenCancelNoteScreenRef = SurfaceScreenRef<
    LumenCancelNoteScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenCancelNoteScreenProvenance,
  eventContract: _lumenCancelNoteScreenEvents,
  measurementPublicationDraftDigest:
      'a8203581300236856fdad8ce10d80d2efb797e2e0650315617f16f2544275b6f',
);

LumenCancelNoteScreenEvent _decodeValidatedLumenCancelNoteScreenEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case 'send':
      return LumenCancelNoteScreenSendEvent(arguments['value'] as String);
    case 'skip':
      return const LumenCancelNoteScreenSkipEvent();
  }
  throw FormatException('Invalid LumenCancelNoteScreen event "$name".');
}

final _lumenCancelNoteScreenPlacementDefinitionValue =
    RestageScreen.generatedPlacementDefinition(
  defaultSurface: lumenCancelNoteScreenRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'survey',
    'slug': 'lumen_cancel_note',
    'family': <String, Object?>{'kind': 'screenContract', 'contractVersion': 1}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'inputs': <String, Object?>{},
      'schemaVersion': 1
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[
        <String, Object?>{
          'id': 'send',
          'arguments': <String, Object?>{
            'encoding': 'value',
            'shape': <String, Object?>{'kind': 'string'}
          }
        },
        <String, Object?>{
          'id': 'skip',
          'arguments': <String, Object?>{'encoding': 'none'}
        }
      ]
    },
    'flowBoundary': null
  },
  vocabulary: lumenCancelNoteScreenRef.provenance.vocabulary,
);

final lumenCancelNoteScreenPlacementDefinition =
    () => _lumenCancelNoteScreenPlacementDefinitionValue;

final class LumenCancelNoteScreenSurface extends StatelessWidget {
  const LumenCancelNoteScreenSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  const LumenCancelNoteScreenSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<LumenCancelNoteScreenEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<LumenCancelNoteScreenEvent>(
      screen: lumenCancelNoteScreenRef,
      placementBinding: RestageScreen.generatedPlacementBinding(
        definition: lumenCancelNoteScreenPlacementDefinition,
        name: _restagePlacementName,
      ),
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
        builder: (context, error) => LumenCancelNoteScreen(),
      ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}

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
    builtInFloor: 9,
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
        byteLength: 31032,
        sha256:
            'sha256:34621e861ea691c3923984c36e286fe70963b2121db1c81001b150d698320f9d',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/survey/screens/measurement/7986973e7d641fcd/lumen_cancel_reason.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            'sha256:d17ade863d32009dabbc6a17f4f6ae320cd1473bca5ffe037ce8e28acb1c4589',
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
      '7f25bb1f9c2084c8408ff13d82cb48baa7b980e071c7e375f16ad6ccafdf23f9',
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

final _lumenCancelReasonScreenPlacementDefinitionValue =
    RestageScreen.generatedPlacementDefinition(
  defaultSurface: lumenCancelReasonScreenRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'survey',
    'slug': 'lumen_cancel_reason',
    'family': <String, Object?>{'kind': 'screenContract', 'contractVersion': 1}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'inputs': <String, Object?>{},
      'schemaVersion': 1
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[
        <String, Object?>{
          'id': 'reason',
          'arguments': <String, Object?>{
            'encoding': 'value',
            'shape': <String, Object?>{'kind': 'string'}
          }
        },
        <String, Object?>{
          'id': 'skip',
          'arguments': <String, Object?>{'encoding': 'none'}
        }
      ]
    },
    'flowBoundary': null
  },
  vocabulary: lumenCancelReasonScreenRef.provenance.vocabulary,
);

final lumenCancelReasonScreenPlacementDefinition =
    () => _lumenCancelReasonScreenPlacementDefinitionValue;

final class LumenCancelReasonScreenSurface extends StatelessWidget {
  const LumenCancelReasonScreenSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  const LumenCancelReasonScreenSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<LumenCancelReasonScreenEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<LumenCancelReasonScreenEvent>(
      screen: lumenCancelReasonScreenRef,
      placementBinding: RestageScreen.generatedPlacementBinding(
        definition: lumenCancelReasonScreenPlacementDefinition,
        name: _restagePlacementName,
      ),
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
    builtInFloor: 9,
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
            'sha256:b6ca1c4aabcc1114d251b5ecfaa00d954bb4659b0a8e1bdd72d332f05975065e',
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
      'dc98d64b521bed9a74b1b275605619ed5cf354de63c8181b882dabe360db576c',
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

final _lumenCancelThanksScreenPlacementDefinitionValue =
    RestageScreen.generatedPlacementDefinition(
  defaultSurface: lumenCancelThanksScreenRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'survey',
    'slug': 'lumen_cancel_thanks',
    'family': <String, Object?>{'kind': 'screenContract', 'contractVersion': 1}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'inputs': <String, Object?>{},
      'schemaVersion': 1
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[
        <String, Object?>{
          'id': 'finish',
          'arguments': <String, Object?>{'encoding': 'none'}
        }
      ]
    },
    'flowBoundary': null
  },
  vocabulary: lumenCancelThanksScreenRef.provenance.vocabulary,
);

final lumenCancelThanksScreenPlacementDefinition =
    () => _lumenCancelThanksScreenPlacementDefinitionValue;

final class LumenCancelThanksScreenSurface extends StatelessWidget {
  const LumenCancelThanksScreenSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  const LumenCancelThanksScreenSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<LumenCancelThanksScreenEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<LumenCancelThanksScreenEvent>(
      screen: lumenCancelThanksScreenRef,
      placementBinding: RestageScreen.generatedPlacementBinding(
        definition: lumenCancelThanksScreenPlacementDefinition,
        name: _restagePlacementName,
      ),
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
