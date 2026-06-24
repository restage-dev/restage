import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  test('constructs a blob paywall payload', () {
    final variant = ResolvedVariant(
      bytes: Uint8List.fromList([1, 2, 3]),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 7,
    );

    final payload = BlobPaywallPayload(variant);

    expect(payload.variant, same(variant));
  });

  test('constructs a flow paywall payload', () {
    final flow = _resolvedFlow();

    final payload = FlowPaywallPayload(
      flow: flow,
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 7,
    );

    expect(payload.flow, same(flow));
    expect(payload.paywallId, 'pro_upgrade');
    expect(payload.paywallPublishedVersion, 7);
  });

  test('supports exhaustive switches over payload variants', () {
    final blob = BlobPaywallPayload(
      ResolvedVariant(
        bytes: Uint8List.fromList([1]),
        paywallId: 'blob_paywall',
      ),
    );
    final flow = FlowPaywallPayload(
      flow: _resolvedFlow(),
      paywallId: 'flow_paywall',
    );

    expect(_describe(blob), 'blob:blob_paywall');
    expect(_describe(flow), 'flow:flow_paywall');
  });
}

String _describe(ResolvedPaywallPayload payload) {
  return switch (payload) {
    BlobPaywallPayload(:final variant) => 'blob:${variant.paywallId}',
    FlowPaywallPayload(:final paywallId) => 'flow:$paywallId',
  };
}

ResolvedFlow _resolvedFlow() {
  final screenBytes = Uint8List.fromList([1, 2, 3]);
  return ResolvedFlow(
    document: FlowDocument(
      flow: 'pro_upgrade',
      version: 1,
      schemaVersion: 1,
      minClient: 3,
      initial: 'welcome',
      actions: const {},
      screenArtifacts: {
        'welcome': ScreenArtifact(
          path: 'paywall_pro_upgrade.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: 3,
          contentHash: FlowContentHash.compute(screenBytes),
        ),
      },
      states: const {
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: {'next': FlowTransition.goto('done')},
        ),
        'done': EndFlowState(result: {'completed': true}),
      },
    ),
    screenBlobs: {'welcome': screenBytes},
    cacheHit: false,
  );
}
