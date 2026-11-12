import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/commands/surface_routing_command.dart'
    show isCanonicalOperationId, newOperationId;
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Formats the original safe aggregate and its exact approval digest.
@experimental
String formatDeliveryMeasurementMutationReview(
  DeliveryMeasurementMutationReviewV1 review,
) =>
    '${deliveryMeasurementMutationReviewSummary(review)}\n'
    '${const JsonEncoder.withIndent('  ').convert(review.toJson())}';

/// [review] as the JSON document `--review-measurement` prints, the whole of
/// its output: the aggregate `digest` to pass as `--reviewed-digest`, and the
/// complete `review`.
@experimental
String measurementReviewDocument(DeliveryMeasurementMutationReviewV1 review) =>
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'digest': review.digest.hex,
      'review': review.toJson(),
    });

/// The one-line summary of [review]: its operation, digest and consequence.
@experimental
String deliveryMeasurementMutationReviewSummary(
  DeliveryMeasurementMutationReviewV1 review,
) {
  final consequence = deliveryMeasurementMutationConsequence(review);
  return 'Measurement impact ${review.operation}; review ${review.digest.hex}.'
      '${consequence == null ? '' : ' $consequence'}';
}

/// Describes the serving consequence without changing the canonical review.
@experimental
String? deliveryMeasurementMutationConsequence(
  DeliveryMeasurementMutationReviewV1 review,
) {
  if (review.operation != 'surfaceKill' ||
      !review.reviews.any((impact) => impact.affectedSources.isNotEmpty)) {
    return null;
  }
  return 'Killing this surface stops fresh experimental delivery from it and '
      'may interrupt measurement. Experiment lifecycle, immutable versions, '
      'and saved results are unchanged.';
}

/// The original server review that requires explicit acknowledgement.
@experimental
class DeliveryMeasurementReviewRequired extends FormatException {
  /// Retain the complete safe review so every transport can present it.
  DeliveryMeasurementReviewRequired(this.review)
    : super(
        '${formatDeliveryMeasurementMutationReview(review)}\n'
        'Explicitly review these warnings and supply their exact aggregate '
        'review digest.',
      );

  /// The complete review issued by the service.
  final DeliveryMeasurementMutationReviewV1 review;
}

/// Present the server review and ask separately about its measurement warnings.
///
/// Warnings and refusals print in full; a review with nothing to acknowledge
/// prints only a serving consequence, if any. Returns null on an interactive
/// decline.
/// Headless callers must supply the digest they reviewed; general
/// confirmation flags cannot acknowledge it.
@experimental
Future<DeliveryMeasurementMutationProceedV1?>
confirmDeliveryMeasurementProceed({
  required DeliveryMeasurementMutationReviewV1 review,
  required Interactive interactive,
  required StringSink stdout,
  String? reviewedDigest,
  String? operationId,
}) async {
  final warned = review.reviews.any((impact) => impact.warningCodes.isNotEmpty);
  if (warned || review.refusalCodes.isNotEmpty) {
    stdout.writeln(formatDeliveryMeasurementMutationReview(review));
  } else if (deliveryMeasurementMutationConsequence(review)
      case final consequence?) {
    stdout.writeln(consequence);
  }
  var approvedDigest = reviewedDigest;
  if (review.refusalCodes.isEmpty &&
      warned &&
      approvedDigest == null &&
      interactive.isInteractive) {
    if (!await interactive.confirm(
      'Acknowledge every measurement warning in review ${review.digest.hex}?',
    )) {
      return null;
    }
    approvedDigest = review.digest.hex;
  }
  return reviewedDeliveryMeasurementProceed(
    review: review,
    reviewedDigest: approvedDigest,
    operationId: operationId,
  );
}

/// Creates proceed evidence from a complete server review and explicit consent.
///
/// Warning-free reviews require no warning acknowledgement. Warned reviews
/// require the exact aggregate digest the operator approved; live consent does
/// not supply it. Every acknowledgement retains the original review and codes.
@experimental
DeliveryMeasurementMutationProceedV1 reviewedDeliveryMeasurementProceed({
  required DeliveryMeasurementMutationReviewV1 review,
  String? reviewedDigest,
  String? operationId,
}) {
  if (review.refusalCodes.isNotEmpty) {
    throw FormatException(
      'The service refused the measurement review: '
      '${review.refusalCodes.join(', ')}.',
    );
  }
  final warned = review.reviews.where((r) => r.warningCodes.isNotEmpty);
  if ((warned.isNotEmpty && reviewedDigest == null) ||
      (reviewedDigest != null && reviewedDigest != review.digest.hex)) {
    throw DeliveryMeasurementReviewRequired(review);
  }
  if (operationId != null && !isCanonicalOperationId(operationId)) {
    throw const FormatException(
      'The operation id must be a canonical lowercase UUIDv4.',
    );
  }
  final acknowledgements = [
    for (final impact in warned)
      DeliveryMeasurementImpactAcknowledgementV1(
        reviewDigest: impact.digest,
        warningCodes: impact.warningCodes,
      ),
  ]..sort((a, b) => a.reviewDigest.hex.compareTo(b.reviewDigest.hex));
  return requireDeliveryMeasurementProceed(
    review: review,
    proceed: DeliveryMeasurementMutationProceedV1(
      operationId: operationId ?? newOperationId(),
      reviewDigest: review.digest,
      acknowledgements: acknowledgements,
    ),
  );
}

/// Requires the public codec's exact complete-review acknowledgement contract.
@experimental
DeliveryMeasurementMutationProceedV1 requireDeliveryMeasurementProceed({
  required DeliveryMeasurementMutationReviewV1 review,
  required DeliveryMeasurementMutationProceedV1 proceed,
}) {
  if (!proceed.acknowledges(review)) {
    throw const FormatException(
      'The proceed evidence does not acknowledge this complete measurement '
      'review and its exact warning set.',
    );
  }
  return proceed;
}
