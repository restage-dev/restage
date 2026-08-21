import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Transport seam for the explicit governed Measurement and privacy domains.
///
/// This is a port rather than an authority implementation. Until an accepted
/// host-side authority is installed, every operation fails closed.
abstract interface class RestageGovernedMeasurementTransport {
  /// Requests one exact direct host/IDP link challenge.
  Future<MeasurementLinkChallengeOperationResultV1> issueLinkChallenge(
    MeasurementLinkChallengeRequestV1 request,
  );

  /// Forwards a direct host assertion without decoding it in the SDK.
  Future<MeasurementLinkOperationResultV1> linkSubject(
    MeasurementLinkRequestV1 request,
  );

  /// Forwards one explicit subject reset operation.
  Future<MeasurementSubjectOperationResultV1> resetSubject(
    MeasurementSubjectOperationRequestV1 request,
  );

  /// Forwards one explicit consent-withdrawal operation.
  Future<MeasurementSubjectOperationResultV1> withdrawConsent(
    MeasurementSubjectOperationRequestV1 request,
  );

  /// Forwards one domain-independent privacy coordinator request.
  Future<RestagePrivacyReceiptV1> requestPrivacy(
    RestagePrivacyRequestV1 request,
  );
}

/// Internal compatibility name for focused SDK transport tests.
@internal
abstract interface class RestageMeasurementOperationsPort
    implements RestageGovernedMeasurementTransport {}

/// Installation registry for a transport, never an identity authority.
@internal
abstract final class GovernedMeasurementPortRegistry {
  static RestageGovernedMeasurementTransport _measurement =
      const _UnavailableMeasurementPort();

  /// Current governed Measurement transport.
  static RestageGovernedMeasurementTransport get measurement => _measurement;

  /// Installs the configured explicit transport or restores fail-closed mode.
  static void install(RestageGovernedMeasurementTransport? measurement) {
    _measurement = measurement ?? const _UnavailableMeasurementPort();
  }

  /// Installs an explicit port for focused SDK contract tests.
  static void debugInstall(RestageGovernedMeasurementTransport? measurement) =>
      install(measurement);

  /// Clears the installed port and restores fail-closed behavior.
  static void debugReset() => install(null);
}

final class _UnavailableMeasurementPort
    implements RestageGovernedMeasurementTransport {
  const _UnavailableMeasurementPort();

  @override
  Future<MeasurementLinkChallengeOperationResultV1> issueLinkChallenge(
    MeasurementLinkChallengeRequestV1 request,
  ) async =>
      unavailableLinkChallengeResult();

  @override
  Future<MeasurementLinkOperationResultV1> linkSubject(
    MeasurementLinkRequestV1 request,
  ) async =>
      _unavailableLinkResult();

  @override
  Future<MeasurementSubjectOperationResultV1> resetSubject(
    MeasurementSubjectOperationRequestV1 request,
  ) async =>
      _unavailableSubjectOperationResult();

  @override
  Future<MeasurementSubjectOperationResultV1> withdrawConsent(
    MeasurementSubjectOperationRequestV1 request,
  ) async =>
      _unavailableSubjectOperationResult();

  @override
  Future<RestagePrivacyReceiptV1> requestPrivacy(
    RestagePrivacyRequestV1 request,
  ) async =>
      unavailablePrivacyReceipt(request);
}

@internal
MeasurementLinkChallengeOperationResultV1 unavailableLinkChallengeResult() =>
    const MeasurementLinkChallengeOperationResultV1.failed(
      MeasurementLinkFailureV1(
        code: MeasurementLinkFailureCode.temporarilyUnavailable,
      ),
    );

@internal
MeasurementLinkOperationResultV1 unavailableLinkResult() =>
    _unavailableLinkResult();

MeasurementLinkOperationResultV1 _unavailableLinkResult() =>
    const MeasurementLinkOperationResultV1.failed(
      MeasurementLinkFailureV1(
        code: MeasurementLinkFailureCode.temporarilyUnavailable,
      ),
    );

@internal
MeasurementSubjectOperationResultV1 unavailableSubjectOperationResult() =>
    _unavailableSubjectOperationResult();

MeasurementSubjectOperationResultV1 _unavailableSubjectOperationResult() =>
    const MeasurementSubjectOperationResultV1.failed(
      MeasurementLinkFailureV1(
        code: MeasurementLinkFailureCode.temporarilyUnavailable,
      ),
    );

@internal
RestagePrivacyReceiptV1 unavailablePrivacyReceipt(
  RestagePrivacyRequestV1 request, {
  RestagePrivacyFailureCode code =
      RestagePrivacyFailureCode.temporarilyUnavailable,
}) =>
    RestagePrivacyReceiptV1(
      targets: request.targets,
      action: request.action,
      correlationId: request.correlationId,
      status: RestagePrivacyCoordinatorStatus.failed,
      domainResults: request.targets.domains
          .map(
            (domain) => RestagePrivacyDomainResult.failed(
              domain: domain,
              action: request.action,
              failure: RestagePrivacyDomainFailureV1(code: code),
            ),
          )
          .toList(growable: false),
    );
