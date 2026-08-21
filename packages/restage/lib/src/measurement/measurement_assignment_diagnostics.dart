import 'package:meta/meta.dart';

/// Internal result of one assignment-delivery attempt.
///
/// The result deliberately carries no subject, Flutter identity, selection, or
/// ITT authority. The service-owned adapter supplies only a closed delivery
/// diagnostic after its durable pre-render decision.
@internal
sealed class MeasurementAssignmentDeliveryDiagnostic {
  /// Creates one assignment-delivery diagnostic.
  const MeasurementAssignmentDeliveryDiagnostic();
}

/// Candidate-delivery state observed after a durable assignment.
///
/// This is diagnostic-only: none of these states can select treatment or
/// create, remove, or reinterpret an ITT unit.
@internal
enum MeasurementAssignmentCandidateDeliveryDiagnostic {
  /// Candidate delivery completed after the durable assignment.
  rendered,

  /// Candidate delivery failed, while the durable unit remains enrolled.
  renderFailedButEnrolled,

  /// A prior request already completed candidate delivery.
  alreadyRendered,

  /// Another request owns the candidate-delivery attempt.
  renderInFlight,
}

/// The service durably admitted an assignment.
@internal
final class MeasurementAssignmentDeliveryAssigned
    extends MeasurementAssignmentDeliveryDiagnostic {
  /// Creates a diagnostic from the post-commit candidate-delivery state.
  const MeasurementAssignmentDeliveryAssigned({
    required this.candidateDelivery,
  });

  /// Candidate-delivery state. It is not assignment or ITT authority.
  final MeasurementAssignmentCandidateDeliveryDiagnostic candidateDelivery;
}

/// The request was outside the admitted audience.
@internal
final class MeasurementAssignmentDeliveryOutsideAudience
    extends MeasurementAssignmentDeliveryDiagnostic {
  /// Creates an outside-audience diagnostic.
  const MeasurementAssignmentDeliveryOutsideAudience();
}

/// The request was in the audience but failed the additional eligibility
/// authority.
@internal
final class MeasurementAssignmentDeliveryIneligible
    extends MeasurementAssignmentDeliveryDiagnostic {
  /// Creates an ineligible diagnostic.
  const MeasurementAssignmentDeliveryIneligible();
}

/// A non-inference assignment failure that must not become an assignment.
@internal
final class MeasurementAssignmentDeliveryUnavailable
    extends MeasurementAssignmentDeliveryDiagnostic {
  /// Creates an unavailable assignment diagnostic.
  const MeasurementAssignmentDeliveryUnavailable(this.reason);

  /// Closed local, transport, or policy reason.
  final MeasurementAssignmentUnavailableReason reason;
}

/// The eligible randomized-unit population could not be resolved without
/// making a false assignment or inventing a denominator.
@internal
final class MeasurementAssignmentDeliveryInferenceUnavailable
    extends MeasurementAssignmentDeliveryDiagnostic {
  /// Creates an inference-unavailable assignment diagnostic.
  const MeasurementAssignmentDeliveryInferenceUnavailable(this.reason);

  /// Closed reason for the unavailable eligible population.
  final MeasurementInferenceUnavailableReason reason;
}

/// Why an assignment delivery attempt did not produce an assignment or an
/// inference-population diagnosis.
@internal
enum MeasurementAssignmentUnavailableReason {
  /// The host disabled the replacement measurement path.
  disabled,

  /// No authenticated adapter is installed in this SDK composition.
  noAdapter,

  /// The authenticated session was absent or invalid.
  unauthenticated,

  /// The service denied access to the configured target.
  forbidden,

  /// The service reported a retryable unavailable condition.
  serviceUnavailable,

  /// The response status was outside the closed transport mapping.
  unexpectedStatus,

  /// A response did not satisfy the closed typed transport boundary.
  malformedResponse,

  /// The assignment policy authority was unavailable.
  policyUnavailable,

  /// The assignment policy denied the requested operation.
  policyDenied,

  /// Required provenance could not be established.
  provenanceFailed,

  /// The installed client cannot satisfy the admitted capability.
  unsupported,

  /// The bounded evaluation budget was exceeded.
  overBudget,

  /// The adapter did not complete with a typed outcome.
  transportFailure,
}

/// Why a randomized-unit population or its pre-treatment source is unavailable
/// for inference.
@internal
enum MeasurementInferenceUnavailableReason {
  /// The eligible population could not be resolved exactly.
  eligiblePopulationUnresolved,

  /// The source relation is unavailable.
  sourceUnavailable,

  /// Transport truncation prevents a complete population claim.
  transportTruncated,

  /// A source value failed the closed domain contract.
  domainRejected,

  /// The population is still pending a required terminal state.
  pending,

  /// Retention expiry removed a required relation.
  retentionExpired,

  /// Privacy erasure removed a required relation.
  privacyErasure,

  /// Privacy revocation invalidated the population.
  privacyRevocation,

  /// Integrity of the complete population cannot be proved.
  integrityUnprovable,
}

/// Internal local presentation state used by a future exposure consumer.
///
/// Assignment and exposure are separate states. In particular, assignment,
/// child paint, prefetch, render failure, and fallback do not imply exposure.
@internal
enum MeasurementExposureDiagnosticState {
  /// No exposure attempt was made.
  notAttempted,

  /// A root candidate did not paint successfully.
  notExposed,

  /// The assigned root candidate painted successfully.
  exposed,

  /// Rendering failed before a successful root paint.
  renderFailed,

  /// The host rendered a fallback instead of the assigned candidate.
  fallback,

  /// Exposure could not be classified without an authoritative result.
  unavailable,
}

/// One local exposure diagnostic with no subject or widget identity.
@internal
final class MeasurementExposureDiagnostic {
  const MeasurementExposureDiagnostic._({
    required this.state,
    this.unavailableReason,
  });

  /// Creates a diagnostic for a delivery that was never attempted.
  const MeasurementExposureDiagnostic.notAttempted()
      : this._(state: MeasurementExposureDiagnosticState.notAttempted);

  /// Creates a diagnostic for a root candidate that did not expose.
  const MeasurementExposureDiagnostic.notExposed()
      : this._(state: MeasurementExposureDiagnosticState.notExposed);

  /// Creates a diagnostic for a successfully painted root candidate.
  const MeasurementExposureDiagnostic.exposed()
      : this._(state: MeasurementExposureDiagnosticState.exposed);

  /// Creates a diagnostic for a failed render.
  const MeasurementExposureDiagnostic.renderFailed()
      : this._(state: MeasurementExposureDiagnosticState.renderFailed);

  /// Creates a diagnostic for a rendered fallback.
  const MeasurementExposureDiagnostic.fallback()
      : this._(state: MeasurementExposureDiagnosticState.fallback);

  /// Creates a typed unavailable exposure diagnostic.
  const MeasurementExposureDiagnostic.unavailable({
    required MeasurementInferenceUnavailableReason reason,
  }) : this._(
          state: MeasurementExposureDiagnosticState.unavailable,
          unavailableReason: reason,
        );

  /// Local exposure state.
  final MeasurementExposureDiagnosticState state;

  /// Why an unavailable exposure could not be classified, when applicable.
  final MeasurementInferenceUnavailableReason? unavailableReason;

  /// Whether the diagnostic is the successful exposure state.
  bool get isExposed => state == MeasurementExposureDiagnosticState.exposed;
}
