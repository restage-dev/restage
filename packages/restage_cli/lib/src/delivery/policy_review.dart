import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/commands/surface_routing_command.dart'
    show isCanonicalOperationId, newOperationId;
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Formats the complete original policy review and its exact approval digest.
@experimental
String formatDeliveryPolicyReview(DeliveryPolicyReviewV1 review) =>
    'Delivery policy review ${review.digest.hex}.\n'
    '${const JsonEncoder.withIndent('  ').convert(review.toJson())}';

/// Retains the original server review that needs separate warning consent.
@experimental
class DeliveryPolicyReviewRequired extends FormatException {
  /// Exposes the complete safe review through the common transport error owner.
  DeliveryPolicyReviewRequired(this.review)
    : super(
        '${formatDeliveryPolicyReview(review)}\n'
        'Review every measurement warning and supply this exact review digest.',
      );

  /// Complete original review issued by the service.
  final DeliveryPolicyReviewV1 review;
}

/// Presents the original policy review and separately asks about its warnings.
@experimental
Future<DeliveryPolicyPublishRequestV1?> confirmDeliveryPolicyPublish({
  required DeliveryPolicyReviewV1 review,
  required Interactive interactive,
  required StringSink stdout,
  String? reviewedDigest,
  String? operationId,
}) async {
  stdout.writeln(formatDeliveryPolicyReview(review));
  var approvedDigest = reviewedDigest;
  if (review.refusalCodes.isEmpty &&
      review.measurementImpact.warningCodes.isNotEmpty &&
      approvedDigest == null &&
      interactive.isInteractive) {
    if (!await interactive.confirm(
      'Acknowledge every measurement warning in policy review ${review.digest.hex}?',
    )) {
      return null;
    }
    approvedDigest = review.digest.hex;
  }
  return reviewedDeliveryPolicyPublish(
    review: review,
    reviewedDigest: approvedDigest,
    operationId: operationId,
  );
}

/// Constructs an exact reviewed publish request without inferring source impact.
@experimental
DeliveryPolicyPublishRequestV1 reviewedDeliveryPolicyPublish({
  required DeliveryPolicyReviewV1 review,
  String? reviewedDigest,
  String? operationId,
}) {
  final refusals = {...review.refusalCodes};
  if (refusals.isNotEmpty) {
    throw FormatException(
      'The service refused the review: ${refusals.join(', ')}.',
    );
  }
  final impact = review.measurementImpact;
  if ((impact.warningCodes.isNotEmpty && reviewedDigest == null) ||
      (reviewedDigest != null && reviewedDigest != review.digest.hex)) {
    throw DeliveryPolicyReviewRequired(review);
  }
  if (operationId != null && !isCanonicalOperationId(operationId)) {
    throw const FormatException(
      'The operation id must be a canonical lowercase version 4 UUID.',
    );
  }
  final acknowledgement = impact.warningCodes.isEmpty
      ? null
      : DeliveryMeasurementImpactAcknowledgementV1(
          reviewDigest: impact.digest,
          warningCodes: impact.warningCodes,
        );
  if (acknowledgement != null && !acknowledgement.acknowledges(impact)) {
    throw const FormatException(
      'The warning acknowledgement differs from the review.',
    );
  }
  return DeliveryPolicyPublishRequestV1(
    reviewRef: review.reviewRef,
    operationId: operationId ?? newOperationId(),
    measurementAcknowledgement: acknowledgement,
  );
}
