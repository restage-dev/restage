import 'package:args/args.dart';
import 'package:restage_cli/src/api/delivery_management_api.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/commands/measurement_page_command.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_cli/src/delivery/measurement_impact.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Adds review and exact acknowledgement controls to an existing mutation.
void addSurfaceMeasurementReviewOptions(ArgParser parser) {
  parser
    ..addFlag(
      'review-measurement',
      negatable: false,
      help:
          'Return the complete measurement impact review without changing the surface.',
    )
    ..addOption(
      'reviewed-digest',
      help:
          'The exact aggregate digest whose measurement warnings you reviewed.',
    )
    ..addOption(
      'operation-id',
      help:
          'Canonical lowercase UUIDv4 for this retry. Generated when omitted.',
    );
}

/// Reviews the same complete surface operation that the caller will submit.
Future<({DeliveryMeasurementMutationProceedV1? proceed, int? exitCode})>
reviewSurfaceMeasurement({
  required CommandIo io,
  required ArgResults arguments,
  required SurfaceApi api,
  required LifecycleContext target,
  required SurfaceLifecycleIdentity identity,
  required String operation,
  required String reason,
  int? publishedRevision,
  int? contractVersion,
  bool? frozen,
}) async {
  final DeliveryMeasurementMutationReviewV1 review;
  final familyOperation = const {
    'surfaceActivate',
    'surfaceRollback',
  }.contains(operation);
  try {
    review = await api.reviewDeliveryImpact(
      project: target.project,
      app: target.app,
      surfaceType: identity.surface,
      surfaceSlug: identity.slug,
      environment: target.environment,
      operation: operation,
      reason: reason,
      publishedRevision: publishedRevision,
      contractVersion: familyOperation
          ? contractVersion ?? identity.contractVersion
          : null,
      sourceKind: familyOperation ? identity.sourceKind : null,
      frozen: frozen,
      environmentTargetId: target.environmentTargetId,
      runtimePlane: target.runtimePlane,
      organizationId: target.organizationId,
      expectedTarget: targetCoordinateOf(target),
    );
  } on DeliveryManagementResponseException catch (error) {
    io.stderr.writeln(error);
    return (proceed: null, exitCode: 2);
  }
  if (arguments['review-measurement'] as bool) {
    io.stdout.writeln(formatDeliveryMeasurementMutationReview(review));
    return (proceed: null, exitCode: review.refusalCodes.isEmpty ? 0 : 1);
  }
  try {
    final proceed = await confirmDeliveryMeasurementProceed(
      review: review,
      interactive: io.interactive,
      stdout: io.stdout,
      reviewedDigest: arguments['reviewed-digest'] as String?,
      operationId: arguments['operation-id'] as String?,
    );
    if (proceed == null) {
      io.stdout.writeln('Aborted.');
      return (proceed: null, exitCode: 1);
    }
    return (proceed: proceed, exitCode: null);
  } on DeliveryMeasurementReviewRequired {
    io.stderr.writeln(
      'Review the complete warnings, then pass --reviewed-digest ${review.digest.hex}.',
    );
    return (proceed: null, exitCode: 1);
  } on FormatException catch (error) {
    io.stderr.writeln(error.message);
    return (proceed: null, exitCode: 1);
  }
}
