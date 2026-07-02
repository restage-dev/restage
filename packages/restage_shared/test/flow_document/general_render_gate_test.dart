import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('GeneralFlowRenderGate.evaluate', () {
    test('accepts a general-on-general structural change', () {
      final verdict = GeneralFlowRenderGate.evaluate(
        client: _doc(mode: FlowDeliveryMode.general),
        active: _docWithExtraScreen(mode: FlowDeliveryMode.general),
      );

      expect(verdict, isA<FlowActiveRenderAccepted>());
    });

    test('refuses a typed active document', () {
      final verdict = GeneralFlowRenderGate.evaluate(
        client: _doc(mode: FlowDeliveryMode.general),
        active: _doc(mode: FlowDeliveryMode.typed),
      );

      _expectDocumentInvalid(verdict);
    });

    test('refuses a typed client document', () {
      final verdict = GeneralFlowRenderGate.evaluate(
        client: _doc(mode: FlowDeliveryMode.typed),
        active: _doc(mode: FlowDeliveryMode.general),
      );

      _expectDocumentInvalid(verdict);
    });
  });
}

FlowDocument _doc({required FlowDeliveryMode mode}) {
  return FlowDocument(
    flow: 'welcome',
    version: 1,
    schemaVersion: 1,
    minClient: 1,
    initial: 'start',
    screenArtifacts: {
      'start': ScreenArtifact(
        path: 'start.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 1,
        contentHash: FlowContentHash.compute(<int>[1, 2, 3]),
      ),
    },
    states: const {
      'start': ScreenFlowState(
        screen: 'start',
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
    deliveryMode: mode,
  );
}

FlowDocument _docWithExtraScreen({required FlowDeliveryMode mode}) {
  return FlowDocument(
    flow: 'welcome',
    version: 2,
    schemaVersion: 1,
    minClient: 1,
    initial: 'start',
    screenArtifacts: {
      'start': ScreenArtifact(
        path: 'start.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 1,
        contentHash: FlowContentHash.compute(<int>[1, 2, 3]),
      ),
      'details': ScreenArtifact(
        path: 'details.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 1,
        contentHash: FlowContentHash.compute(<int>[4, 5, 6]),
      ),
    },
    states: const {
      'start': ScreenFlowState(
        screen: 'start',
        on: {'next': FlowTransition.goto('details')},
      ),
      'details': ScreenFlowState(
        screen: 'details',
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
    deliveryMode: mode,
  );
}

void _expectDocumentInvalid(FlowActiveRenderVerdict verdict) {
  expect(verdict.accepted, isFalse);
  expect(
    verdict,
    isA<FlowActiveRenderRejected>().having(
      (rejected) => rejected.reason,
      'reason',
      FlowActiveRenderRejectionReason.documentInvalid,
    ),
  );
}
