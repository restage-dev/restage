part of '../lumen_cancel.dart';

// ignore_for_file: type=lint, unnecessary_cast

sealed class LumenCancelNoteScreenSurfaceEvent {
  const LumenCancelNoteScreenSurfaceEvent();
}

final class LumenCancelNoteScreenSurfaceSendEvent
    extends LumenCancelNoteScreenSurfaceEvent {
  const LumenCancelNoteScreenSurfaceSendEvent(this.value);

  final String value;
}

final class LumenCancelNoteScreenSurfaceSkipEvent
    extends LumenCancelNoteScreenSurfaceEvent {
  const LumenCancelNoteScreenSurfaceSkipEvent();
}

final _lumenCancelNoteScreenEvents =
    SurfaceScreenEventContract<LumenCancelNoteScreenSurfaceEvent>.generated(
  hash:
      'sha256:845ed8018eaa74aee9fc9d2480d99f931510601bb1109f245111ef3237614ca1',
  decodeValidated: _decodeValidatedLumenCancelNoteScreenSurfaceEvent,
);

final _lumenCancelNoteScreenProvenance =
    SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.survey,
  slug: 'lumen_cancel_note',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 17,
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
        byteLength: 15347,
        sha256:
            'sha256:820709309801b61f1f714563789e1f485f85be75038a470418e2ab55802171b3',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/survey/screens/measurement/69385e84f6569c7c/lumen_cancel_note.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 142,
        sha256:
            'sha256:2a04988b44261ecd51a57a908c9a8717253e31e62045cb26bfbc862e64cea54b',
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
    LumenCancelNoteScreenSurfaceEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenCancelNoteScreenProvenance,
  eventContract: _lumenCancelNoteScreenEvents,
  measurementPublicationDraftDigest:
      'e621d2f54acb88952f37d5d975bf366b086e8b94fcd40ece1b5f3f8e4685ca63',
);

LumenCancelNoteScreenSurfaceEvent
    _decodeValidatedLumenCancelNoteScreenSurfaceEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case 'send':
      return LumenCancelNoteScreenSurfaceSendEvent(
          arguments['value'] as String);
    case 'skip':
      return const LumenCancelNoteScreenSurfaceSkipEvent();
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
      'schemaVersion': 1,
      'inputs': <String, Object?>{}
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
  surfaceWidget: 'LumenCancelNoteScreenSurface',
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

  final ValueChanged<LumenCancelNoteScreenSurfaceEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  final SurfaceScreenUnavailablePolicy? unavailable;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording();
    Widget _restageDesign(Widget _restageBuilt) {
      return RestageScreen<LumenCancelNoteScreenSurfaceEvent>(
        screen: lumenCancelNoteScreenRef,
        placementBinding: RestageScreen.generatedPlacementBinding(
          definition: lumenCancelNoteScreenPlacementDefinition,
          name: _restagePlacementName,
        ),
        unavailable: unavailable ??
            SurfaceScreenUnavailablePolicy.fallback(
              builder: (_, error) => _restageBuilt,
            ),
        onEvent: onEvent,
        resolver: resolver,
        onUnavailable: onUnavailable,
        loadingBuilder: loadingBuilder,
      );
    }

    return (() => _restageDesign(LumenCancelNoteScreen()))();
  }
}

sealed class LumenCancelReasonScreenSurfaceEvent {
  const LumenCancelReasonScreenSurfaceEvent();
}

final class LumenCancelReasonScreenSurfaceReasonEvent
    extends LumenCancelReasonScreenSurfaceEvent {
  const LumenCancelReasonScreenSurfaceReasonEvent(this.value);

  final String value;
}

final class LumenCancelReasonScreenSurfaceSkipEvent
    extends LumenCancelReasonScreenSurfaceEvent {
  const LumenCancelReasonScreenSurfaceSkipEvent();
}

final _lumenCancelReasonScreenEvents =
    SurfaceScreenEventContract<LumenCancelReasonScreenSurfaceEvent>.generated(
  hash:
      'sha256:55bb77c38f6e53b2258a45594521bc78c955d54ae17505b1633c04fbba822784',
  decodeValidated: _decodeValidatedLumenCancelReasonScreenSurfaceEvent,
);

final _lumenCancelReasonScreenProvenance =
    SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.survey,
  slug: 'lumen_cancel_reason',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 17,
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
        byteLength: 31332,
        sha256:
            'sha256:add242e3b9ac77811784093e9acb7c796501da3b5e18559080d232bcdcece13e',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/survey/screens/measurement/7986973e7d641fcd/lumen_cancel_reason.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 142,
        sha256:
            'sha256:a0fede5d0a4d260fbd94923a7a29b2a8acb091324e19b7f0e38173d3bd452e11',
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
    LumenCancelReasonScreenSurfaceEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenCancelReasonScreenProvenance,
  eventContract: _lumenCancelReasonScreenEvents,
  measurementPublicationDraftDigest:
      '046216f4320c29d2ca2c25345011904aee226b7579687d14e1ff5ce179e8161e',
);

LumenCancelReasonScreenSurfaceEvent
    _decodeValidatedLumenCancelReasonScreenSurfaceEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case 'reason':
      return LumenCancelReasonScreenSurfaceReasonEvent(
          arguments['value'] as String);
    case 'skip':
      return const LumenCancelReasonScreenSurfaceSkipEvent();
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
      'schemaVersion': 1,
      'inputs': <String, Object?>{}
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
  surfaceWidget: 'LumenCancelReasonScreenSurface',
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

  final ValueChanged<LumenCancelReasonScreenSurfaceEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  final SurfaceScreenUnavailablePolicy? unavailable;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording();
    Widget _restageDesign(Widget _restageBuilt) {
      return RestageScreen<LumenCancelReasonScreenSurfaceEvent>(
        screen: lumenCancelReasonScreenRef,
        placementBinding: RestageScreen.generatedPlacementBinding(
          definition: lumenCancelReasonScreenPlacementDefinition,
          name: _restagePlacementName,
        ),
        unavailable: unavailable ??
            SurfaceScreenUnavailablePolicy.fallback(
              builder: (_, error) => _restageBuilt,
            ),
        onEvent: onEvent,
        resolver: resolver,
        onUnavailable: onUnavailable,
        loadingBuilder: loadingBuilder,
      );
    }

    return (() => _restageDesign(LumenCancelReasonScreen()))();
  }
}

sealed class LumenCancelThanksScreenSurfaceEvent {
  const LumenCancelThanksScreenSurfaceEvent();
}

final class LumenCancelThanksScreenSurfaceFinishEvent
    extends LumenCancelThanksScreenSurfaceEvent {
  const LumenCancelThanksScreenSurfaceFinishEvent();
}

final _lumenCancelThanksScreenEvents =
    SurfaceScreenEventContract<LumenCancelThanksScreenSurfaceEvent>.generated(
  hash:
      'sha256:ca846c32a23d2d98fb3ca253fc69fb1ccef2fa2ee9fa5397947d5e5c2e03bc31',
  decodeValidated: _decodeValidatedLumenCancelThanksScreenSurfaceEvent,
);

final _lumenCancelThanksScreenProvenance =
    SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.survey,
  slug: 'lumen_cancel_thanks',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 17,
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
        byteLength: 14941,
        sha256:
            'sha256:95193db36d106a8896a9063d3b2b55b4c45f7e00fcb566e68f7ae288d525dd15',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/survey/screens/measurement/79821ca45fbefc0b/lumen_cancel_thanks.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 142,
        sha256:
            'sha256:741362304db11f888369126e7f76f66110dfe73fad4bba5666447d6acbdac5a4',
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
    LumenCancelThanksScreenSurfaceEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenCancelThanksScreenProvenance,
  eventContract: _lumenCancelThanksScreenEvents,
  measurementPublicationDraftDigest:
      '61a0b43a79a63f3513dba0e5afabb3bab4315688110977b480a4845e5ff3f644',
);

LumenCancelThanksScreenSurfaceEvent
    _decodeValidatedLumenCancelThanksScreenSurfaceEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case 'finish':
      return const LumenCancelThanksScreenSurfaceFinishEvent();
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
      'schemaVersion': 1,
      'inputs': <String, Object?>{}
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
  surfaceWidget: 'LumenCancelThanksScreenSurface',
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

  final ValueChanged<LumenCancelThanksScreenSurfaceEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  final SurfaceScreenUnavailablePolicy? unavailable;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording();
    Widget _restageDesign(Widget _restageBuilt) {
      return RestageScreen<LumenCancelThanksScreenSurfaceEvent>(
        screen: lumenCancelThanksScreenRef,
        placementBinding: RestageScreen.generatedPlacementBinding(
          definition: lumenCancelThanksScreenPlacementDefinition,
          name: _restagePlacementName,
        ),
        unavailable: unavailable ??
            SurfaceScreenUnavailablePolicy.fallback(
              builder: (_, error) => _restageBuilt,
            ),
        onEvent: onEvent,
        resolver: resolver,
        onUnavailable: onUnavailable,
        loadingBuilder: loadingBuilder,
      );
    }

    return (() => _restageDesign(LumenCancelThanksScreen()))();
  }
}
