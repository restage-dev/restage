import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_mcp/src/api_runner.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:test/test.dart';

import '_support/delivery_fixtures.dart';

void main() {
  test(
    'review-required errors retain the complete safe server review',
    () async {
      final impact = DeliveryMeasurementImpactReviewV1.fromJson(
        warningImpact(surfaceScope()).toJson()..['operation'] = 'surfaceKill',
      );
      final review = DeliveryMeasurementMutationReviewV1(
        operation: 'surfaceKill',
        reviews: [impact],
        dependencyDigest: CanonicalDigest('c' * 64),
      );
      final result = await guardErrors('killing the surface', () async {
        reviewedDeliveryMeasurementProceed(
          review: review,
          operationId: operationId,
        );
        fail('A warning without explicit acknowledgement cannot proceed.');
      });
      expect(result.isError, true);
      expect(result.structuredContent, {
        'measurementReview': review.toJson(),
        'reviewDigest': review.digest.hex,
        'acknowledgementRequired': true,
      });
      final text = (result.content.single as TextContent).text;
      expect(jsonDecode(text), result.structuredContent);
      expect(text, contains('Welcome experiment'));
      expect(text, contains('Completed welcome'));
      expect(text, contains('metricSourceUnavailable'));
    },
  );

  test(
    'unrelated malformed content still cannot enter the error channel',
    () async {
      final result = await guardErrors('killing the surface', () async {
        throw const FormatException('corrupt credential SUPERSECRET');
      });
      expect(result.isError, true);
      expect(result.structuredContent, isNull);
      final text = (result.content.single as TextContent).text;
      expect(text, 'An unexpected error occurred while killing the surface.');
      expect(text, isNot(contains('SUPERSECRET')));
    },
  );
}
