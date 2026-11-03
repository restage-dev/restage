import 'dart:io';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/src/surface_delivery/delivery_signing_testing.dart';
import 'package:test/test.dart';

void main() {
  final fixture = requireCanonicalObject(
    CanonicalJsonCodec.decode(
      File('test/fixtures/placements/shared_blob_two_mounts_v1.json')
          .readAsBytesSync(),
    ),
    'fixture',
  );
  final target = TargetCoordinate.fromJson(
    requireCanonicalObject(fixture['expectedTarget'], 'expectedTarget'),
  );
  final request = PlacementBatchRequestV1.fromJson(fixture['request']);
  final content = {
    for (final artifact in fixture['artifacts']! as List)
      PlacementBatchArtifactV1.fromJson(artifact).identity:
          PlacementBatchArtifactV1.fromJson(artifact),
  };

  PlacementBatchAvailableV1 decision(String? fitRequirementHash) {
    final response = Map<String, Object?>.from(fixture['response']! as Map);
    final decisions = [
      for (final entry in response['decisions']! as List)
        Map<String, Object?>.from(entry as Map)
          ..['artifactClosure'] = [
            for (final reference in entry['artifactClosure'] as List)
              {
                ...(reference as Map<String, Object?>),
                'descriptor': TestDeliverySigner().signJson({
                  ...(reference['descriptor']! as Map<String, Object?>)
                    ..remove('fitRequirementHash'),
                  if (fitRequirementHash != null)
                    'fitRequirementHash': fitRequirementHash,
                }),
              },
          ],
    ];
    return (PlacementBatchResponseV1.fromJson(
      {...response, 'decisions': decisions},
      request: request,
      expectedTarget: target,
    ) as PlacementBatchResolvedV1)
        .decisions
        .first as PlacementBatchAvailableV1;
  }

  test('the served fit requirement must be the signed one', () {
    final served = (fixture['response']! as Map)['decisions'] as List;
    final hash = SurfaceFitRequirementV1.fromJson(
      ((served.first as Map)['publicDelivery'] as Map)['fitRequirement'],
    ).contentHash;
    expect(validatePlacementRowContent(decision(hash), content), isPositive);
    for (final other in [null, 'sha256:${'0' * 64}']) {
      expect(
        () => validatePlacementRowContent(decision(other), content),
        throwsA(isA<CanonicalFormatException>()),
      );
    }
  });
}
