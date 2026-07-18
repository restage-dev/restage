import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  group('FlowAssignment', () {
    test('carries the complete server-selected arm', () {
      const assignment = FlowAssignment(
        experimentId: 'exp1',
        variantId: 'variant-b',
        experimentEpoch: 2,
      );
      expect(assignment.experimentId, 'exp1');
      expect(assignment.variantId, 'variant-b');
      expect(assignment.experimentEpoch, 2);
    });

    test('value equality over the three fields', () {
      const a = FlowAssignment(
        experimentId: 'exp1',
        variantId: 'v',
        experimentEpoch: 3,
      );
      const b = FlowAssignment(
        experimentId: 'exp1',
        variantId: 'v',
        experimentEpoch: 3,
      );
      const c = FlowAssignment(
        experimentId: 'exp1',
        variantId: 'v',
        experimentEpoch: 4,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('ResolvedFlow.assignment', () {
    ResolvedFlow build({FlowAssignment? assignment}) => ResolvedFlow(
          document: _doc(),
          screenBlobs: {
            'welcome': Uint8List.fromList([1, 2, 3])
          },
          contentHash: null,
          cacheHit: false,
          assignment: assignment,
        );

    test('defaults to null (an artifact with no experiment)', () {
      expect(build().assignment, isNull);
    });

    test('carries the artifact-owned assignment when present', () {
      const assignment = FlowAssignment(
        experimentId: 'exp1',
        variantId: 'variant-b',
        experimentEpoch: 2,
      );
      final resolved = build(assignment: assignment);
      expect(resolved.assignment, equals(assignment));
    });
  });
}

FlowDocument _doc() => FlowDocument(
      flow: 'first_run',
      version: 1,
      schemaVersion: 1,
      minClient: 1,
      initial: 'welcome',
      actions: const {},
      screenArtifacts: {
        'welcome': ScreenArtifact(
          path: 'welcome.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: 1,
          contentHash: FlowContentHash.compute(Uint8List.fromList([1, 2, 3])),
        ),
      },
      states: const {
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: {'next': FlowTransition.goto('done')},
        ),
        'done': EndFlowState(result: {'completed': true}),
      },
    );
