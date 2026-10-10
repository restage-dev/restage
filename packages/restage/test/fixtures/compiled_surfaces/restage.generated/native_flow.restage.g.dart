part of '../native_flow.dart';

// ignore_for_file: type=lint

final class NativeOfferSurface extends StatelessWidget {
  const NativeOfferSurface({
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  });

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    const SurfaceVocabulary(
      widgets: RestageWidgetLibraries.fromVocabulary(
        core: {
          'Text': buildText,
        },
        material: {
          'TextButton': buildTextButton,
        },
      ),
    ).addToInstalled();
    return RestagePaywall(
      id: 'native_offer',
      fallbackBuilder: (context) => NativeOffer(),
      onEvent: onEvent,
      resolver: resolver,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
    );
  }
}

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
        '{"flow":"native_class_flow","initial":"native_preferences","minClient":1,"outbound":{},"schemaVersion":1,"screenArtifacts":{"native_preferences":{"contentHash":"sha256:9ae057f289fb63c2465521b12b0962e937640c6890da3c2e794c06b76ad6f71f","minClient":1,"path":"measurement/fd61b201e0ea5991/native_preferences.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"native_preferences":{"kind":"screen","on":{"done":{"target":"done","type":"goto"}},"screen":"native_preferences"}},"version":1}',
    screens: {
      'native_preferences': NativePreferences.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '787298cc311a0327d2e483babf91af0b06f76ef35c19f7b23ed1f6933a11eaa3',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
      material: {
        'TextButton': buildTextButton,
      },
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

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class NativeClassFlowSurface extends RestageFlowGraph<NativeClassResult> {
  const NativeClassFlowSurface({
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
  }) : super(flow: nativeClassFlowRef);
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
        '{"flow":"native_named_flow","initial":"native_named","minClient":1,"outbound":{},"schemaVersion":1,"screenArtifacts":{"native_named":{"contentHash":"sha256:dc4e3a2a6a70edbd880c5f7767a39b1395cc62008af5ca15d261ffd4b1a50661","minClient":1,"path":"native_named.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"native_named":{"kind":"screen","on":{"done":{"target":"done","type":"goto"}},"screen":"native_named"}},"version":1}',
    screens: {},
    children: {},
  ),
  measurementPublicationDraftDigest:
      '0071e411238db09b083d1809fef6ec2d577d25fd58c732cc4fee03f0b2cedb06',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
      material: {
        'TextButton': buildTextButton,
      },
    ),
  ),
);

NativeNamedFlowResult _decodeNativeNamedFlowResult(
    Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const NativeNamedFlowResult();
}

final class NativeNamedFlowResult {
  const NativeNamedFlowResult();
}

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class NativeNamedFlowSurface
    extends RestageFlowGraph<NativeNamedFlowResult> {
  NativeNamedFlowSurface({
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
  }) : super(flow: nativeNamedFlowRef, screenBuilders: {
          'native_named': nativeNamedScreenBuilder,
        });
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
        '{"flow":"native_offer_flow","initial":"paywall_native_offer","minClient":1,"outbound":{},"schemaVersion":1,"screenArtifacts":{"paywall_native_offer":{"contentHash":"sha256:12fd4ee3f3902ac88912d7a1bf2170c65723399d424d23621a1a6a2b73fe68fc","minClient":1,"path":"paywall_native_offer.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"paywall_native_offer":{"kind":"screen","on":{"skip":{"target":"done","type":"goto"}},"screen":"paywall_native_offer"}},"version":1}',
    screens: {
      'paywall_native_offer': NativeOffer.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '2758e2f7e6783df247a1144d95a145d3e848855bf1323863243a9f20d6daec8f',
);

NativeOfferFlowResult _decodeNativeOfferFlowResult(
    Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const NativeOfferFlowResult();
}

final class NativeOfferFlowResult {
  const NativeOfferFlowResult();
}

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class NativeOfferFlowSurface
    extends RestageFlowGraph<NativeOfferFlowResult> {
  const NativeOfferFlowSurface({
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
  }) : super(flow: nativeOfferFlowRef);
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
        '{"actions":{"permission":{"actionName":"permission","argsSchema":{"fields":{},"kind":"object"},"argsSchemaHash":"sha256:590f015bf5e877b53e3501b7e12ad48a11158d4c5b696f9a82593c4f3272411a","contractVersion":1,"idempotent":false,"minClient":1,"resultSchema":{"kind":"bool"},"resultSchemaHash":"sha256:b381695502a4099cf3610d182b471a2562086e5e8bdb11f4426f63ba512542b3"}},"flow":"native_welcome_flow","flowState":{"completed":{"classification":"exportable","default":false,"type":"bool"}},"initial":"native_welcome","minClient":1,"outbound":{"terminalResult":{"fields":{"completed":{"ref":{"state":"completed"},"type":"bool"}}}},"schemaVersion":1,"screenArtifacts":{"native_preferences":{"contentHash":"sha256:e7a48425c6c17f16d1fe601ab4c7359bdabf2a5cb3c0a879baeb6706fafe884b","minClient":1,"path":"measurement/8e5c98f316d3660d/native_preferences.rfw","schemaVersion":1,"version":1},"native_welcome":{"contentHash":"sha256:19413a95a7e05cc141ab53a78bd915f91bd766d939ac3d59f9cd7cf3ce8ea624","minClient":1,"path":"native_welcome.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{"completed":true}},"native_preferences":{"kind":"screen","on":{"done":{"set":{"completed":{"type":"bool","value":{"literal":true,"type":"bool"}}},"target":"offer","type":"goto"}},"screen":"native_preferences"},"native_welcome":{"kind":"screen","on":{"next":{"action":"permission","resultPredicate":{"kind":"boolEquals","value":true},"target":"native_preferences","type":"action"}},"screen":"native_welcome"},"offer":{"contentHash":"sha256:518bfcf28ea7e8207c51545406b3094f851cfe941107a2b79119408521a5069c","default":{"goto":"done"},"flow":"native_offer_flow","kind":"subFlow","minClient":1,"onComplete":[{"goto":"done","when":{}}],"schemaVersion":1,"version":1}},"version":1}',
    screens: {
      'native_preferences': NativePreferences.new,
      'native_welcome': NativeWelcome.new,
    },
    children: {
      'native_offer_flow': CompiledFlow(
        documentJson:
            '{"flow":"native_offer_flow","initial":"paywall_native_offer","minClient":1,"outbound":{},"schemaVersion":1,"screenArtifacts":{"paywall_native_offer":{"contentHash":"sha256:12fd4ee3f3902ac88912d7a1bf2170c65723399d424d23621a1a6a2b73fe68fc","minClient":1,"path":"paywall_native_offer.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"paywall_native_offer":{"kind":"screen","on":{"skip":{"target":"done","type":"goto"}},"screen":"paywall_native_offer"}},"version":1}',
        screens: {
          'paywall_native_offer': NativeOffer.new,
        },
        children: {},
      ),
    },
  ),
  measurementPublicationDraftDigest:
      'e9b9c72fe42eda529a3179889a6b648231e40c6f1bd0e982a37b08e52021b108',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
      material: {
        'TextButton': buildTextButton,
      },
    ),
  ),
  subFlows: [nativeOfferFlowRef],
);

NativeWelcomeFlowResult _decodeNativeWelcomeFlowResult(
    Map<String, Object?> result) {
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

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class NativeWelcomeFlowSurface
    extends RestageFlowGraph<NativeWelcomeFlowResult> {
  const NativeWelcomeFlowSurface({
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
  }) : super(flow: nativeWelcomeFlowRef);
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
