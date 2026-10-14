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
    builtInFloor: 10,
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
            'sha256:b49ff57988cf807086a8d5887cb5f3d8866a97c93b82409d670c273f5f54f469',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/survey/screens/measurement/69385e84f6569c7c/lumen_cancel_note.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 142,
        sha256:
            'sha256:c3726e6cee1fafb7aab7c5c52fea554a22762923be26f22c9b3e958939abade7',
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
      'b6ff67cfdc5f81f80c16703da43f0de66eb18313e0a2427c67b2cef9f1606fce',
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
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const LumenCancelNoteScreenSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.unavailable,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [LumenCancelNoteScreenSurface] for the default placement; no name is needed.
  const LumenCancelNoteScreenSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.unavailable,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<LumenCancelNoteScreenEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  final SurfaceScreenUnavailablePolicy? unavailable;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<LumenCancelNoteScreenEvent>(
      screen: lumenCancelNoteScreenRef,
      placementBinding: RestageScreen.generatedPlacementBinding(
        definition: lumenCancelNoteScreenPlacementDefinition,
        name: _restagePlacementName,
      ),
      unavailable: unavailable ??
          SurfaceScreenUnavailablePolicy.fallback(
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
    builtInFloor: 10,
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
            'sha256:ba11a30fab16aecb6dc019267954d683f6afc2f4f9030bb6eef14afa47b7f84f',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/survey/screens/measurement/7986973e7d641fcd/lumen_cancel_reason.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 142,
        sha256:
            'sha256:3b6cf6c5cee100db6fa9610c4fa4bf02acd9b5a455b3e156fe9bfb83fe36b1b8',
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
      '227c7c57f45881f96f3d447bc4e061f1847013c85fce3b3a49d3f6c795c0916f',
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
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const LumenCancelReasonScreenSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.unavailable,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [LumenCancelReasonScreenSurface] for the default placement; no name is needed.
  const LumenCancelReasonScreenSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.unavailable,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<LumenCancelReasonScreenEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  final SurfaceScreenUnavailablePolicy? unavailable;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<LumenCancelReasonScreenEvent>(
      screen: lumenCancelReasonScreenRef,
      placementBinding: RestageScreen.generatedPlacementBinding(
        definition: lumenCancelReasonScreenPlacementDefinition,
        name: _restagePlacementName,
      ),
      unavailable: unavailable ??
          SurfaceScreenUnavailablePolicy.fallback(
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
    builtInFloor: 10,
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
            'sha256:4576781a03576123949c809ff3793162ccccacef0cd268a0c6b7660be15be0d6',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/survey/screens/measurement/79821ca45fbefc0b/lumen_cancel_thanks.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 142,
        sha256:
            'sha256:e886e65d128754d47807c89d19ac6f7c3efe3d81c4c12c3ae32f46747047ff90',
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
      '2922da4dc4a30d7e5ea8b82925369b9c5d5d71c73f7bb063ffd7ba7c2d0fa6b6',
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
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const LumenCancelThanksScreenSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.unavailable,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [LumenCancelThanksScreenSurface] for the default placement; no name is needed.
  const LumenCancelThanksScreenSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.unavailable,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<LumenCancelThanksScreenEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  final SurfaceScreenUnavailablePolicy? unavailable;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<LumenCancelThanksScreenEvent>(
      screen: lumenCancelThanksScreenRef,
      placementBinding: RestageScreen.generatedPlacementBinding(
        definition: lumenCancelThanksScreenPlacementDefinition,
        name: _restagePlacementName,
      ),
      unavailable: unavailable ??
          SurfaceScreenUnavailablePolicy.fallback(
            builder: (context, error) => LumenCancelThanksScreen(),
          ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}
