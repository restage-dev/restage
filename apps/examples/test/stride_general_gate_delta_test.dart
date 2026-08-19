import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage_shared/restage_shared.dart';

import '_support/bundled_artifacts.dart';

/// Proves the shape of the Stride v1→v2 delta on the **real generated
/// documents**: adding a screen is a structural change the typed active-render
/// gate refuses, but the general gate accepts. That is the whole point of
/// general delivery — a structural change (and its rollback) that a typed
/// contract would refuse is served, because delivery selects the general gate.
///
/// v1 is captured as a fixture (`test/fixtures/stride_first_run.v1.flow.json`)
/// — a snapshot of the generated artifact taken from the pre-`stride_goals`
/// source, before the structural change landed. To re-derive it for a future
/// version bump, snapshot `assets/onboarding/flows/stride_first_run.flow.json`
/// BEFORE making the next structural change (never hand-edit the fixture).
/// v2 is the live generated artifact. If the added screen ever stops being
/// typed-rejected, this test fails and its guarantee is void — that is a design
/// signal, not a test to relax.
void main() {
  final v1 = FlowDocumentCodec.decodeJson(
    File('test/fixtures/stride_first_run.v1.flow.json').readAsStringSync(),
  );
  final v2 = FlowDocumentCodec.decodeJson(
    readDeliveryText('assets/onboarding/flows/stride_first_run.flow.json'),
  );

  test('the fixtures are the intended general v1 and v2 documents', () {
    expect(v1.deliveryMode, FlowDeliveryMode.general);
    expect(v2.deliveryMode, FlowDeliveryMode.general);
    expect(v1.version, 1);
    expect(v2.version, 2);
    // The delta is the added screen (a topology change).
    expect(v1.screenArtifacts.containsKey('stride_goals'), isFalse);
    expect(v2.screenArtifacts.containsKey('stride_goals'), isTrue);
  });

  test('the typed active-render gate REJECTS the structural v1→v2 delta', () {
    final verdict = FlowActiveRenderGate.evaluate(client: v1, active: v2);

    expect(verdict.accepted, isFalse);
    expect(verdict, isA<FlowActiveRenderRejected>());
    expect(
      (verdict as FlowActiveRenderRejected).reason,
      FlowActiveRenderRejectionReason.contractSurfaceExpanded,
    );
  });

  test('the general render gate ACCEPTS the same structural delta', () {
    final verdict = GeneralFlowRenderGate.evaluate(client: v1, active: v2);

    expect(verdict.accepted, isTrue);
    expect(verdict, isA<FlowActiveRenderAccepted>());
  });
}
