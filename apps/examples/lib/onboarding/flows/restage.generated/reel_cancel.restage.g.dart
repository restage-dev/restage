part of '../reel_cancel.dart';

// ignore_for_file: type=lint

const reelCancelFlowRef = SurfaceFlowRef<
    ReelCancelResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'reel_cancel',
  version: 1,
  minClient: 17,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeReelCancelFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"actions":{"redeemOffer":{"actionName":"redeemOffer","argsSchema":{"fields":{},"kind":"object"},"argsSchemaHash":"sha256:590f015bf5e877b53e3501b7e12ad48a11158d4c5b696f9a82593c4f3272411a","contractVersion":1,"idempotent":false,"minClient":6,"resultSchema":{"fields":{"redeemed":{"required":true,"schema":{"kind":"bool"}}},"kind":"object"},"resultSchemaHash":"sha256:cdba58b8037dcf2c43d7add16c74558a786b6b1dede9d095ac4c00399ddaaaae"}},"flow":"reel_cancel","flowState":{"retained":{"classification":"exportable","type":"bool"}},"initial":"reel_reason","minClient":17,"outbound":{"customEvents":{"cancel":{"fields":{}}},"terminalResult":{"fields":{"retained":{"ref":{"state":"retained"},"type":"bool"}}}},"schemaVersion":1,"screenArtifacts":{"reel_frequency":{"contentHash":"sha256:cfa66f8b1657c782348eeabe529d61d68b5f127747a73acb7d3abc79f1dc9220","minClient":17,"path":"reel_frequency.rfw","schemaVersion":1,"version":1},"reel_kept":{"contentHash":"sha256:1c4aa2a894624cb31b0a2aa3996fe0766e1b67da3966e203de0f96dbce364d11","minClient":17,"path":"reel_kept.rfw","schemaVersion":1,"version":1},"reel_offer":{"contentHash":"sha256:10cfe43bda99cb82475193dd95698facd99e1778f5481ce1c5b529071ab07e2c","minClient":17,"path":"reel_offer.rfw","schemaVersion":1,"version":1},"reel_reason":{"contentHash":"sha256:323adb1820f631caeace78e7afdad99fa3b90ee04fa3c496c5c5fed9a20d6971","minClient":17,"path":"reel_reason.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{"retained":true}},"reel_frequency":{"kind":"screen","on":{"next":{"target":"reel_offer","type":"goto"}},"screen":"reel_frequency"},"reel_kept":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"reel_kept"},"reel_offer":{"kind":"screen","on":{"keep":{"action":"redeemOffer","resultPredicate":{"field":"redeemed","kind":"objectBoolFieldEquals","value":true},"target":"reel_kept","type":"action"}},"screen":"reel_offer"},"reel_reason":{"kind":"screen","on":{"next":{"target":"reel_frequency","type":"goto"}},"screen":"reel_reason"}},"version":1}',
    screens: {
      'reel_reason': ReelReasonScreen.new,
      'reel_frequency': ReelFrequencyScreen.new,
      'reel_offer': ReelOfferScreen.new,
      'reel_kept': ReelKeptScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '057157cac2db926ca766bbb7e629704b01e201dd2caf433b9724fa1b16275cba',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Container': buildContainer,
        'Expanded': buildExpanded,
        'GestureDetector': buildGestureDetector,
        'Padding': buildPadding,
        'Row': buildRow,
        'SafeArea': buildSafeArea,
        'SizedBox': buildSizedBox,
        'Text': buildText,
      },
      material: {
        'AppBar': buildAppBar,
        'FilledButton': buildFilledButton,
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
        'TextButton': buildTextButton,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf636: IconData(0xf636, fontFamily: 'MaterialIcons'),
      },
    }, mirrored: {
      'MaterialIcons': {
        0xf63b: IconData(0xf63b,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
      },
    }),
  ),
);

ReelCancelResult _decodeReelCancelFlowResult(Map<String, Object?> result) {
  if (result.length != 1 || !result.containsKey('retained')) {
    throw const FormatException('Unexpected flow result keys.');
  }
  final retained = result['retained'];
  if (retained is! bool) {
    throw const FormatException('Expected result field retained to be bool.');
  }
  return ReelCancelResult(retained: retained);
}

@Deprecated('Use reelCancelFlowRef')
abstract final class ReelCancelFlowDescriptor {
  const ReelCancelFlowDescriptor._();

  static const SurfaceFlowRef<ReelCancelResult> ref = reelCancelFlowRef;
}

final class ReelCancelResult {
  const ReelCancelResult({required this.retained});
  final bool retained;
}

final class ReelCancelActions implements FlowActionRegistry {
  ReelCancelActions({
    required FlowActionHandler<void, OfferDecision> redeemOffer,
  }) : flowActionBindings =
            Map<String, FlowActionBinding<dynamic, dynamic>>.unmodifiable({
          'redeemOffer': FlowActionBinding<void, OfferDecision>(
            descriptor: redeemOfferDescriptor,
            actionName: redeemOfferDescriptor.actionName,
            contractVersion: redeemOfferDescriptor.contractVersion,
            argsSchema: redeemOfferDescriptor.argsSchema,
            resultSchema: redeemOfferDescriptor.resultSchema,
            minClient: redeemOfferDescriptor.minClient,
            idempotent: redeemOfferDescriptor.idempotent,
            handler: redeemOffer,
            decodeArgs: (_) {},
            encodeResult: (value) => {'redeemed': value.redeemed},
          ),
        });

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;

  static final FlowActionDescriptor<void, OfferDecision> redeemOfferDescriptor =
      FlowActionDescriptor<void, OfferDecision>(
    actionName: 'redeemOffer',
    contractVersion: 1,
    argsSchema: const FlowActionSchema.object({}),
    resultSchema: const FlowActionSchema.object({
      'redeemed': FlowActionSchemaField(
        required: true,
        schema: FlowActionSchema.bool(),
      )
    }),
    minClient: 6,
    idempotent: false,
  );
}

final _reelCancelFlowPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: reelCancelFlowRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'onboarding',
    'slug': 'reel_cancel',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'flow',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'inputs': <String, Object?>{},
      'schemaVersion': 1
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': <String, Object?>{
      'schemaVersion': 1,
      'deliveryMode': 'typed',
      'hostSeedableState': <String, Object?>{},
      'actions': <String, Object?>{
        'redeemOffer': <String, Object?>{
          'actionName': 'redeemOffer',
          'contractVersion': 1,
          'argsSchema': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{}
          },
          'resultSchema': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'redeemed': <String, Object?>{
                'required': true,
                'schema': <String, Object?>{'kind': 'bool'}
              }
            }
          },
          'minClient': 6,
          'idempotent': false
        }
      },
      'signals': <Object?>['cancel'],
      'outbound': <String, Object?>{
        'actionArgs': <String, Object?>{},
        'terminalResult': <String, Object?>{'retained': 'bool'},
        'lifecycle': <String, Object?>{},
        'surveyAnswers': <String, Object?>{},
        'subFlowResult': <String, Object?>{},
        'customEvents': <String, Object?>{'cancel': <String, Object?>{}}
      }
    }
  },
  vocabulary: reelCancelFlowRef.vocabulary,
);

final reelCancelFlowPlacementDefinition =
    () => _reelCancelFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class ReelCancelFlowSurface extends RestageFlowGraph<ReelCancelResult> {
  /// Mounts this flow at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReelCancelFlowSurface({
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
        super(flow: reelCancelFlowRef);

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReelCancelFlowSurface] for the default placement; no name is needed.
  const ReelCancelFlowSurface.atPlacement(
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
        super(flow: reelCancelFlowRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: reelCancelFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}
