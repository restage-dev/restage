part of '../reel_cancel.dart';

const reelCancelFlowRef = SurfaceFlowRef<
    ReelCancelResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'reel_cancel',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeReelCancelFlowResult,
  measurementPublicationDraftDigest:
      '53375d06b94ee3d1104d1113752ef907489c64df92970d7a72fcb6fd8c342e8b',
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
    minClient: 1,
    idempotent: false,
  );
}
