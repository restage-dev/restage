import 'dart:convert';

import 'package:restage_cli/src/delivery/measurement_impact.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:test/test.dart';

import '../commands/delivery_command_test.dart'
    show placementScope, warningImpact;
import '../commands/delivery_sample_command_test.dart' show operationId;

DeliveryMeasurementMutationReviewV1 aggregate({
  bool refused = false,
  bool warned = true,
  bool changed = false,
}) {
  final scope = placementScope();
  final impact = warningImpact(scope);
  final json = impact.toJson()..['operation'] = 'surfaceKill';
  final reviews = [
    DeliveryMeasurementImpactReviewV1.fromJson(json),
    DeliveryMeasurementImpactReviewV1(
      scope: placementScope(live: true),
      operation: 'surfaceKill',
      dependencyDigest: CanonicalDigest('a' * 64),
      affectedSources: warned
          ? [
              DeliveryMeasurementSourceImpactV1.fromJson({
                ...impact.affectedSources.single.toJson(),
                'experimentReference': {
                  ...impact.affectedSources.single.experimentReference.toJson(),
                  'target': placementScope(live: true).target.toJson(),
                },
                'experimentName': 'Second target experiment',
                'metricName': 'Second target metric',
              }),
            ]
          : const [],
    ),
  ];
  final selected = warned ? reviews : <DeliveryMeasurementImpactReviewV1>[];
  selected.sort(
    (a, b) => base64Encode(
      a.scope.canonicalBytes,
    ).compareTo(base64Encode(b.scope.canonicalBytes)),
  );
  return DeliveryMeasurementMutationReviewV1(
    operation: 'surfaceKill',
    reviews: selected,
    dependencyDigest: CanonicalDigest((changed ? 'c' : 'b') * 64),
    refusalCodes: refused ? ['measurementAuthorityUnavailable'] : const [],
  );
}

void main() {
  test(
    'complete aggregate needs explicit approval before every warned scope can proceed',
    () {
      final review = aggregate();
      expect(
        () => reviewedDeliveryMeasurementProceed(
          review: review,
          operationId: operationId,
        ),
        throwsFormatException,
      );
      expect(
        () => reviewedDeliveryMeasurementProceed(
          review: review,
          operationId: operationId,
          reviewedDigest: 'a' * 64,
        ),
        throwsFormatException,
      );
      final proceed = reviewedDeliveryMeasurementProceed(
        review: review,
        reviewedDigest: review.digest.hex,
        operationId: operationId,
      );
      expect(proceed.operationId, operationId);
      expect(proceed.acknowledgements, hasLength(2));
      expect(proceed.acknowledges(review), true);
      expect(
        proceed.acknowledgements.map((a) => a.reviewDigest.hex),
        orderedEquals(
          proceed.acknowledgements.map((a) => a.reviewDigest.hex).toList()
            ..sort(),
        ),
      );
    },
  );

  test(
    'interactive acknowledgement follows the original review and can decline',
    () async {
      final review = aggregate();
      final output = StringBuffer();
      var replies = 0;
      final accepted = await confirmDeliveryMeasurementProceed(
        review: review,
        operationId: operationId,
        stdout: output,
        interactive: RealInteractive(
          stdout: output,
          isInteractiveOverride: true,
          readLine: () async {
            expect(output.toString(), contains('Welcome experiment'));
            expect(output.toString(), contains('Second target metric'));
            expect(output.toString(), contains(review.digest.hex));
            replies++;
            return 'yes';
          },
        ),
      );
      expect(replies, 1);
      expect(accepted!.acknowledges(review), true);

      final declined = await confirmDeliveryMeasurementProceed(
        review: review,
        operationId: operationId,
        stdout: StringBuffer(),
        interactive: RealInteractive(
          stdout: StringBuffer(),
          isInteractiveOverride: true,
          readLine: () async => 'no',
        ),
      );
      expect(declined, isNull);
    },
  );

  test(
    'headless confirmation retains the exact review and never supplies consent',
    () async {
      final review = aggregate();
      final output = StringBuffer();
      final interactive = RealInteractive(
        stdout: output,
        isInteractiveOverride: false,
        readLine: () async => fail('A headless call must not prompt.'),
      );
      await expectLater(
        confirmDeliveryMeasurementProceed(
          review: review,
          operationId: operationId,
          stdout: output,
          interactive: interactive,
        ),
        throwsA(
          isA<DeliveryMeasurementReviewRequired>()
              .having((error) => error.review, 'review', same(review))
              .having(
                (error) => error.message,
                'safe review',
                contains('Welcome experiment'),
              ),
        ),
      );
      final proceed = await confirmDeliveryMeasurementProceed(
        review: review,
        reviewedDigest: review.digest.hex,
        operationId: operationId,
        stdout: output,
        interactive: interactive,
      );
      expect(proceed!.acknowledges(review), true);
    },
  );

  test(
    'original safe names references warnings and complete review digest are readable',
    () {
      final review = aggregate();
      final output = formatDeliveryMeasurementMutationReview(review);
      expect(output, contains('Welcome experiment'));
      expect(output, contains('Completed welcome'));
      expect(output, contains('Second target experiment'));
      expect(output, contains('Second target metric'));
      expect(output, contains('metricSourceUnavailable'));
      expect(output, contains('stops fresh experimental delivery'));
      expect(output, contains('saved results are unchanged'));
      expect(output, contains(review.digest.hex));
      final document = jsonDecode(output.substring(output.indexOf('\n') + 1));
      expect(document, review.toJson());
    },
  );

  test(
    'incomplete acknowledgements and stale source cuts cannot be reused',
    () {
      final review = aggregate();
      final proceed = reviewedDeliveryMeasurementProceed(
        review: review,
        reviewedDigest: review.digest.hex,
        operationId: operationId,
      );
      final incomplete = DeliveryMeasurementMutationProceedV1(
        operationId: operationId,
        reviewDigest: review.digest,
        acknowledgements: [proceed.acknowledgements.first],
      );
      expect(
        () => requireDeliveryMeasurementProceed(
          review: review,
          proceed: incomplete,
        ),
        throwsFormatException,
      );
      expect(
        () => requireDeliveryMeasurementProceed(
          review: aggregate(changed: true),
          proceed: proceed,
        ),
        throwsFormatException,
      );
      expect(
        requireDeliveryMeasurementProceed(review: review, proceed: proceed),
        same(proceed),
      );
    },
  );

  test(
    'server refusals block proceeds even with explicit digest and a warning-free review stays warning-free',
    () {
      final refused = aggregate(refused: true);
      expect(
        () => reviewedDeliveryMeasurementProceed(
          review: refused,
          reviewedDigest: refused.digest.hex,
          operationId: operationId,
        ),
        throwsFormatException,
      );
      final clear = aggregate(warned: false);
      expect(deliveryMeasurementMutationConsequence(clear), isNull);
      expect(
        formatDeliveryMeasurementMutationReview(clear),
        isNot(contains('stops fresh experimental delivery')),
      );
      final proceed = reviewedDeliveryMeasurementProceed(
        review: clear,
        operationId: operationId,
      );
      expect(proceed.acknowledgements, isEmpty);
      expect(proceed.acknowledges(clear), true);
      expect(
        () => reviewedDeliveryMeasurementProceed(
          review: clear,
          operationId: 'not-an-operation',
        ),
        throwsFormatException,
      );
    },
  );

  test('other mutations do not acquire a surface-kill consequence', () {
    final impact = DeliveryMeasurementImpactReviewV1.fromJson(
      warningImpact(placementScope()).toJson()..['operation'] = 'surfaceFreeze',
    );
    final review = DeliveryMeasurementMutationReviewV1(
      operation: 'surfaceFreeze',
      reviews: [impact],
      dependencyDigest: CanonicalDigest('b' * 64),
    );
    expect(deliveryMeasurementMutationConsequence(review), isNull);
  });
}
