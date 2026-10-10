part of '../native_flow.dart';

// ignore_for_file: type=lint

const nativeClassFlowRef = SurfaceFlowRef<
    NativeClassResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'native_class_flow',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeNativeClassFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"native_class_flow","initial":"native_preferences","minClient":1,"outbound":{},"schemaVersion":1,"screenArtifacts":{"native_preferences":{"contentHash":"sha256:7b2f445875903b6606b1aeccdb8990d03cff2cbdd219d912dd15a2bf0522d784","minClient":1,"path":"measurement/fd61b201e0ea5991/native_preferences.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"native_preferences":{"kind":"screen","on":{"done":{"target":"done","type":"goto"}},"screen":"native_preferences"}},"version":1}',
    screens: {'native_preferences': NativePreferences.new},
    children: {},
  ),
  measurementPublicationDraftDigest:
      '580d59fcf4c4d78991c7c3291240b8ff2d9e6debaadd74e9257a95cff9bc9d2b',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {'Text': buildText},
      material: {'TextButton': buildTextButton},
    ),
  ),
);

NativeClassResult _decodeNativeClassFlowResult(Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const NativeClassResult();
}

@Deprecated('Use nativeClassFlowRef')
abstract final class NativeClassFlowDescriptor {
  const NativeClassFlowDescriptor._();

  static const SurfaceFlowRef<NativeClassResult> ref = nativeClassFlowRef;
}

final class NativeClassResult {
  const NativeClassResult();
}

final class NativeClassActions {
  const NativeClassActions();
}

final _nativeClassFlowPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: nativeClassFlowRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'onboarding',
    'slug': 'native_class_flow',
    'family': <String, Object?>{'kind': 'general'},
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'flow',
      'presentation': 'inline',
    },
    'providedContext': <String, Object?>{
      'inputs': <String, Object?>{},
      'schemaVersion': 1,
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[],
    },
    'flowBoundary': <String, Object?>{
      'schemaVersion': 1,
      'deliveryMode': 'typed',
      'hostSeedableState': <String, Object?>{},
      'actions': <String, Object?>{},
      'signals': <Object?>[],
      'outbound': <String, Object?>{
        'actionArgs': <String, Object?>{},
        'terminalResult': <String, Object?>{},
        'lifecycle': <String, Object?>{},
        'surveyAnswers': <String, Object?>{},
        'subFlowResult': <String, Object?>{},
        'customEvents': <String, Object?>{},
      },
    },
  },
  vocabulary: nativeClassFlowRef.vocabulary,
);

final nativeClassFlowPlacementDefinition =
    () => _nativeClassFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class NativeClassFlowSurface extends RestageFlowGraph<NativeClassResult> {
  const NativeClassFlowSurface({
    super.key,
    String? placement,
    super.initialState,
    super.actions,
    super.installedSignalNames,
    super.resolver,
    super.onFlowUnavailable,
    super.onComplete,
    super.loadingBuilder,
    super.transition,
    super.systemBack,
    super.liveRefresh,
    super.context,
    super.unavailable = const FlowUnavailablePolicy.hide(),
  })  : _restagePlacementName = placement,
        super(flow: nativeClassFlowRef);

  const NativeClassFlowSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    super.initialState,
    super.actions,
    super.installedSignalNames,
    super.resolver,
    super.onFlowUnavailable,
    super.onComplete,
    super.loadingBuilder,
    super.transition,
    super.systemBack,
    super.liveRefresh,
    super.context,
    super.unavailable = const FlowUnavailablePolicy.hide(),
  })  : _restagePlacementName = restagePlacementId,
        super(flow: nativeClassFlowRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: nativeClassFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}

const nativeNamedFlowRef = SurfaceFlowRef<
    NativeNamedFlowResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'native_named_flow',
  version: 1,
  minClient: 1,
  surface: Surface.general,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeNativeNamedFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"native_named_flow","initial":"native_named","minClient":1,"outbound":{},"schemaVersion":1,"screenArtifacts":{"native_named":{"contentHash":"sha256:4f4ebdb7219fabdfb3922c9dada13e0bb555a5ed86c79f4330d5e78224c0bb47","minClient":1,"path":"native_named.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"native_named":{"kind":"screen","on":{"done":{"target":"done","type":"goto"}},"screen":"native_named"}},"version":1}',
    screens: {},
    children: {},
  ),
  measurementPublicationDraftDigest:
      'c17374675b37c0cac715eb8b9ca539c064611fc8755d62eb3a9d2857275a3c30',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {'Text': buildText},
      material: {'TextButton': buildTextButton},
    ),
  ),
);

NativeNamedFlowResult _decodeNativeNamedFlowResult(
  Map<String, Object?> result,
) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const NativeNamedFlowResult();
}

final class NativeNamedFlowResult {
  const NativeNamedFlowResult();
}

final _nativeNamedFlowPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: nativeNamedFlowRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'general',
    'slug': 'native_named_flow',
    'family': <String, Object?>{'kind': 'general'},
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'flow',
      'presentation': 'inline',
    },
    'providedContext': <String, Object?>{
      'inputs': <String, Object?>{},
      'schemaVersion': 1,
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[],
    },
    'flowBoundary': <String, Object?>{
      'schemaVersion': 1,
      'deliveryMode': 'typed',
      'hostSeedableState': <String, Object?>{},
      'actions': <String, Object?>{},
      'signals': <Object?>[],
      'outbound': <String, Object?>{
        'actionArgs': <String, Object?>{},
        'terminalResult': <String, Object?>{},
        'lifecycle': <String, Object?>{},
        'surveyAnswers': <String, Object?>{},
        'subFlowResult': <String, Object?>{},
        'customEvents': <String, Object?>{},
      },
    },
  },
  vocabulary: nativeNamedFlowRef.vocabulary,
);

final nativeNamedFlowPlacementDefinition =
    () => _nativeNamedFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class NativeNamedFlowSurface
    extends RestageFlowGraph<NativeNamedFlowResult> {
  NativeNamedFlowSurface({
    super.key,
    required CompiledFlowScreenBuilder nativeNamedScreenBuilder,
    String? placement,
    super.initialState,
    super.actions,
    super.installedSignalNames,
    super.resolver,
    super.onFlowUnavailable,
    super.onComplete,
    super.loadingBuilder,
    super.transition,
    super.systemBack,
    super.liveRefresh,
    super.context,
    super.unavailable = const FlowUnavailablePolicy.hide(),
  })  : _restagePlacementName = placement,
        super(
          flow: nativeNamedFlowRef,
          screenBuilders: {'native_named': nativeNamedScreenBuilder},
        );

  NativeNamedFlowSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    required CompiledFlowScreenBuilder nativeNamedScreenBuilder,
    super.initialState,
    super.actions,
    super.installedSignalNames,
    super.resolver,
    super.onFlowUnavailable,
    super.onComplete,
    super.loadingBuilder,
    super.transition,
    super.systemBack,
    super.liveRefresh,
    super.context,
    super.unavailable = const FlowUnavailablePolicy.hide(),
  })  : _restagePlacementName = restagePlacementId,
        super(
          flow: nativeNamedFlowRef,
          screenBuilders: {'native_named': nativeNamedScreenBuilder},
        );

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: nativeNamedFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}

const nativeNamedRef = NeutralFlowScreenRef(
  id: 'native_named',
  artifactPath: 'native_named.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use nativeNamedRef')
abstract final class NativeNamedDescriptor {
  const NativeNamedDescriptor._();

  static const NeutralFlowScreenRef ref = nativeNamedRef;
}

const nativeOfferFlowRef = SurfaceFlowRef<
    NativeOfferFlowResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'native_offer_flow',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeNativeOfferFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"native_offer_flow","initial":"paywall_native_offer","minClient":1,"outbound":{},"schemaVersion":1,"screenArtifacts":{"paywall_native_offer":{"contentHash":"sha256:b978355ee4e61bf490296ace8cf3cb0578387ce36d5272e85ee09dce8a7afdc4","minClient":1,"path":"paywall_native_offer.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"paywall_native_offer":{"kind":"screen","on":{"skip":{"target":"done","type":"goto"}},"screen":"paywall_native_offer"}},"version":1}',
    screens: {'paywall_native_offer': NativeOffer.new},
    children: {},
  ),
  measurementPublicationDraftDigest:
      'd9b54a8c7e7b481c531d7f963ef14b1c47ab9ee289ec50b11b583904febe2236',
);

NativeOfferFlowResult _decodeNativeOfferFlowResult(
  Map<String, Object?> result,
) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const NativeOfferFlowResult();
}

final class NativeOfferFlowResult {
  const NativeOfferFlowResult();
}

final _nativeOfferFlowPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: nativeOfferFlowRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'onboarding',
    'slug': 'native_offer_flow',
    'family': <String, Object?>{'kind': 'general'},
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'flow',
      'presentation': 'inline',
    },
    'providedContext': <String, Object?>{
      'inputs': <String, Object?>{},
      'schemaVersion': 1,
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[],
    },
    'flowBoundary': <String, Object?>{
      'schemaVersion': 1,
      'deliveryMode': 'typed',
      'hostSeedableState': <String, Object?>{},
      'actions': <String, Object?>{},
      'signals': <Object?>[],
      'outbound': <String, Object?>{
        'actionArgs': <String, Object?>{},
        'terminalResult': <String, Object?>{},
        'lifecycle': <String, Object?>{},
        'surveyAnswers': <String, Object?>{},
        'subFlowResult': <String, Object?>{},
        'customEvents': <String, Object?>{},
      },
    },
  },
  vocabulary: nativeOfferFlowRef.vocabulary,
);

final nativeOfferFlowPlacementDefinition =
    () => _nativeOfferFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class NativeOfferFlowSurface
    extends RestageFlowGraph<NativeOfferFlowResult> {
  const NativeOfferFlowSurface({
    super.key,
    String? placement,
    super.initialState,
    super.actions,
    super.installedSignalNames,
    super.resolver,
    super.onFlowUnavailable,
    super.onComplete,
    super.loadingBuilder,
    super.transition,
    super.systemBack,
    super.liveRefresh,
    super.context,
    super.unavailable = const FlowUnavailablePolicy.hide(),
  })  : _restagePlacementName = placement,
        super(flow: nativeOfferFlowRef);

  const NativeOfferFlowSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    super.initialState,
    super.actions,
    super.installedSignalNames,
    super.resolver,
    super.onFlowUnavailable,
    super.onComplete,
    super.loadingBuilder,
    super.transition,
    super.systemBack,
    super.liveRefresh,
    super.context,
    super.unavailable = const FlowUnavailablePolicy.hide(),
  })  : _restagePlacementName = restagePlacementId,
        super(flow: nativeOfferFlowRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: nativeOfferFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}

const nativePreferencesRef = NeutralFlowScreenRef(
  id: 'native_preferences',
  artifactPath: 'native_preferences.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use nativePreferencesRef')
abstract final class NativePreferencesDescriptor {
  const NativePreferencesDescriptor._();

  static const NeutralFlowScreenRef ref = nativePreferencesRef;
}

const nativeWelcomeFlowRef = SurfaceFlowRef<
    NativeWelcomeFlowResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'native_welcome_flow',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeNativeWelcomeFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"actions":{"permission":{"actionName":"permission","argsSchema":{"fields":{},"kind":"object"},"argsSchemaHash":"sha256:590f015bf5e877b53e3501b7e12ad48a11158d4c5b696f9a82593c4f3272411a","contractVersion":1,"idempotent":false,"minClient":1,"resultSchema":{"kind":"bool"},"resultSchemaHash":"sha256:b381695502a4099cf3610d182b471a2562086e5e8bdb11f4426f63ba512542b3"}},"flow":"native_welcome_flow","flowState":{"completed":{"classification":"exportable","default":false,"type":"bool"}},"initial":"native_welcome","minClient":1,"outbound":{"terminalResult":{"fields":{"completed":{"ref":{"state":"completed"},"type":"bool"}}}},"schemaVersion":1,"screenArtifacts":{"native_preferences":{"contentHash":"sha256:345b1a6bd546e2f204421593afc162b6238c338e1a5eac7ccc42844c0cafd167","minClient":1,"path":"measurement/8e5c98f316d3660d/native_preferences.rfw","schemaVersion":1,"version":1},"native_welcome":{"contentHash":"sha256:2f02b1c62505f4f57af1d256aa3545735721c80f0dead6e599515260b25ec40b","minClient":1,"path":"native_welcome.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{"completed":true}},"native_preferences":{"kind":"screen","on":{"done":{"set":{"completed":{"type":"bool","value":{"literal":true,"type":"bool"}}},"target":"offer","type":"goto"}},"screen":"native_preferences"},"native_welcome":{"kind":"screen","on":{"next":{"action":"permission","resultPredicate":{"kind":"boolEquals","value":true},"target":"native_preferences","type":"action"}},"screen":"native_welcome"},"offer":{"contentHash":"sha256:edb947a61e9f8ec415e0b8eca141ce1fa0cd62932f99aebfa9976cd47d354208","default":{"goto":"done"},"flow":"native_offer_flow","kind":"subFlow","minClient":1,"onComplete":[{"goto":"done","when":{}}],"schemaVersion":1,"version":1}},"version":1}',
    screens: {
      'native_preferences': NativePreferences.new,
      'native_welcome': NativeWelcome.new,
    },
    children: {
      'native_offer_flow': CompiledFlow(
        documentJson:
            '{"flow":"native_offer_flow","initial":"paywall_native_offer","minClient":1,"outbound":{},"schemaVersion":1,"screenArtifacts":{"paywall_native_offer":{"contentHash":"sha256:b978355ee4e61bf490296ace8cf3cb0578387ce36d5272e85ee09dce8a7afdc4","minClient":1,"path":"paywall_native_offer.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"paywall_native_offer":{"kind":"screen","on":{"skip":{"target":"done","type":"goto"}},"screen":"paywall_native_offer"}},"version":1}',
        screens: {'paywall_native_offer': NativeOffer.new},
        children: {},
      ),
    },
  ),
  measurementPublicationDraftDigest:
      '316e98ebfb4bc957fab632176b6a8c1ef7a2e04fe46737c33f62317db9069143',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {'Text': buildText},
      material: {'TextButton': buildTextButton},
    ),
  ),
  subFlows: [nativeOfferFlowRef],
);

NativeWelcomeFlowResult _decodeNativeWelcomeFlowResult(
  Map<String, Object?> result,
) {
  if (result.length != 1 || !result.containsKey('completed')) {
    throw const FormatException('Unexpected flow result keys.');
  }
  final completed = result['completed'];
  if (completed is! bool) {
    throw const FormatException('Expected result field completed to be bool.');
  }
  return NativeWelcomeFlowResult(completed: completed);
}

final class NativeWelcomeFlowResult {
  const NativeWelcomeFlowResult({required this.completed});

  final bool completed;
}

final _nativeWelcomeFlowPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: nativeWelcomeFlowRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'onboarding',
    'slug': 'native_welcome_flow',
    'family': <String, Object?>{'kind': 'general'},
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'flow',
      'presentation': 'inline',
    },
    'providedContext': <String, Object?>{
      'inputs': <String, Object?>{},
      'schemaVersion': 1,
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[],
    },
    'flowBoundary': <String, Object?>{
      'schemaVersion': 1,
      'deliveryMode': 'typed',
      'hostSeedableState': <String, Object?>{},
      'actions': <String, Object?>{
        'permission': <String, Object?>{
          'actionName': 'permission',
          'contractVersion': 1,
          'argsSchema': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{},
          },
          'resultSchema': <String, Object?>{'kind': 'bool'},
          'minClient': 1,
          'idempotent': false,
        },
      },
      'signals': <Object?>[],
      'outbound': <String, Object?>{
        'actionArgs': <String, Object?>{},
        'terminalResult': <String, Object?>{'completed': 'bool'},
        'lifecycle': <String, Object?>{},
        'surveyAnswers': <String, Object?>{},
        'subFlowResult': <String, Object?>{},
        'customEvents': <String, Object?>{},
      },
    },
  },
  vocabulary: nativeWelcomeFlowRef.vocabulary,
);

final nativeWelcomeFlowPlacementDefinition =
    () => _nativeWelcomeFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class NativeWelcomeFlowSurface
    extends RestageFlowGraph<NativeWelcomeFlowResult> {
  const NativeWelcomeFlowSurface({
    super.key,
    String? placement,
    super.initialState,
    super.actions,
    super.installedSignalNames,
    super.resolver,
    super.onFlowUnavailable,
    super.onComplete,
    super.loadingBuilder,
    super.transition,
    super.systemBack,
    super.liveRefresh,
    super.context,
    super.unavailable = const FlowUnavailablePolicy.hide(),
  })  : _restagePlacementName = placement,
        super(flow: nativeWelcomeFlowRef);

  const NativeWelcomeFlowSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    super.initialState,
    super.actions,
    super.installedSignalNames,
    super.resolver,
    super.onFlowUnavailable,
    super.onComplete,
    super.loadingBuilder,
    super.transition,
    super.systemBack,
    super.liveRefresh,
    super.context,
    super.unavailable = const FlowUnavailablePolicy.hide(),
  })  : _restagePlacementName = restagePlacementId,
        super(flow: nativeWelcomeFlowRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: nativeWelcomeFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}

final class NativeWelcomeFlowActions implements FlowActionRegistry {
  NativeWelcomeFlowActions({
    required FlowActionHandler<Object?, Object?> permission,
  }) : flowActionBindings =
            Map<String, FlowActionBinding<dynamic, dynamic>>.unmodifiable({
          'permission': FlowActionBinding<Object?, Object?>(
            descriptor: permissionDescriptor,
            actionName: permissionDescriptor.actionName,
            contractVersion: permissionDescriptor.contractVersion,
            argsSchema: permissionDescriptor.argsSchema,
            resultSchema: permissionDescriptor.resultSchema,
            minClient: permissionDescriptor.minClient,
            idempotent: permissionDescriptor.idempotent,
            handler: permission,
            decodeArgs: (value) => value,
            encodeResult: (value) => value,
          ),
        });

  static final FlowActionDescriptor<Object?, Object?> permissionDescriptor =
      FlowActionDescriptor<Object?, Object?>(
    actionName: 'permission',
    contractVersion: 1,
    argsSchema: const FlowActionSchema.object({}),
    resultSchema: const FlowActionSchema.bool(),
    minClient: 1,
    idempotent: false,
  );

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;
}

const nativeWelcomeRef = NeutralFlowScreenRef(
  id: 'native_welcome',
  artifactPath: 'native_welcome.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use nativeWelcomeRef')
abstract final class NativeWelcomeDescriptor {
  const NativeWelcomeDescriptor._();

  static const NeutralFlowScreenRef ref = nativeWelcomeRef;
}

final _nativeNoticeEvents = const SurfaceScreenEventContract<Never>.none(
  hash:
      'sha256:de41f956f53085c222576ac5f4c25b26644aa34a3e33830c3b5f04cce6656ab5',
);

final _nativeNoticeProvenance = SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.general,
  slug: 'native_notice',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const [],
  ),
  eventSchemaJson: '{"schemaVersion":1,"events":[]}',
  hostDataSchemaJson:
      '{"schemaVersion":1,"inputs":{"count":{"kind":"int"},"title":{"kind":"string"}}}',
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(core: {'Text': buildText}),
  ),
);

final nativeNoticeRef =
    SurfaceScreenRef<Never>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _nativeNoticeProvenance,
  eventContract: _nativeNoticeEvents,
  measurementPublicationDraftDigest:
      'f3201ddb8a9a582eb93101863f52ce35e484ed135e5f41197ccd583ae786b62f',
);

final _nativeNoticePlacementDefinitionValue =
    RestageScreen.generatedPlacementDefinition(
  defaultSurface: nativeNoticeRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'general',
    'slug': 'native_notice',
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
        'count': <String, Object?>{'kind': 'int'},
        'title': <String, Object?>{'kind': 'string'},
      },
      'schemaVersion': 1,
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[],
    },
    'flowBoundary': null,
  },
  vocabulary: nativeNoticeRef.provenance.vocabulary,
);

final nativeNoticePlacementDefinition =
    () => _nativeNoticePlacementDefinitionValue;

const int _nativeNoticeMountDefault1 = 2;

final class NativeNoticeSurface extends StatelessWidget {
  const NativeNoticeSurface(
    String title, [
    int count = _nativeNoticeMountDefault1,
    Key? key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  ])  : _restageArgument0 = title,
        _restageArgument1 = count,
        _restagePlacementName = null,
        super(key: key);

  const NativeNoticeSurface.atPlacement(
    String restagePlacementId,
    String title, [
    int count = _nativeNoticeMountDefault1,
    Key? key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  ])  : _restageArgument0 = title,
        _restageArgument1 = count,
        _restagePlacementName = restagePlacementId,
        super(key: key);

  final String _restageArgument0;

  final int _restageArgument1;
  final String? _restagePlacementName;

  final ValueChanged<Never>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<Never>(
      screen: nativeNoticeRef,
      placementBinding: RestageScreen.generatedPlacementBinding(
        definition: nativeNoticePlacementDefinition,
        name: _restagePlacementName,
      ),
      context: <String, Object?>{
        'title': _restageArgument0,
        'count': _restageArgument1,
      },
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
        builder: (context, error) =>
            NativeNotice(_restageArgument0, _restageArgument1),
      ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}

final _nativeOfferPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'native_offer',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'native_offer',
    'family': <String, Object?>{'kind': 'general'},
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline',
    },
    'providedContext': <String, Object?>{
      'inputs': <String, Object?>{},
      'schemaVersion': 1,
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[],
    },
    'flowBoundary': null,
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {'Text': buildText},
      material: {'TextButton': buildTextButton},
    ),
  ),
);

final nativeOfferPlacementDefinition =
    () => _nativeOfferPlacementDefinitionValue;

final class NativeOfferSurface extends StatelessWidget {
  const NativeOfferSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  const NativeOfferSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    const SurfaceVocabulary(
      widgets: RestageWidgetLibraries.fromVocabulary(
        core: {'Text': buildText},
        material: {'TextButton': buildTextButton},
      ),
    ).addToInstalled();
    return RestagePaywall(
      id: 'native_offer',
      placementBinding: RestagePaywall.generatedPlacementBinding(
        definition: nativeOfferPlacementDefinition,
        name: _restagePlacementName,
      ),
      fallbackBuilder: (context) => NativeOffer(),
      onEvent: onEvent,
      resolver: resolver,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
    );
  }
}
