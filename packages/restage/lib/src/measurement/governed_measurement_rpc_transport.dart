import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import '../restage_rpc_client/restage_rpc_client.dart';
import 'governed_measurement_transport.dart';

/// SDK-installed authenticated HTTP transport for governed direct operations.
///
/// The transport sends only canonical carriers. It does not decode host/IDP
/// assertions, consent, region, requester binding, or any domain authority.
@internal
final class RestageGovernedMeasurementRpcTransport
    implements RestageGovernedMeasurementTransport {
  const RestageGovernedMeasurementRpcTransport(this._client);

  final RestageRpcClient _client;

  @override
  Future<MeasurementLinkChallengeOperationResultV1> issueLinkChallenge(
    MeasurementLinkChallengeRequestV1 request,
  ) =>
      _call(
        operation: _GovernedMeasurementRpcOperation.issueLinkChallenge,
        requestCanonicalBytes: request.canonicalBytes,
        decode: MeasurementLinkChallengeOperationResultV1.fromCanonicalBytes,
        unavailable: (failure) =>
            MeasurementLinkChallengeOperationResultV1.failed(
          MeasurementLinkFailureV1(code: _measurementFailureCode(failure)),
        ),
      );

  @override
  Future<MeasurementLinkOperationResultV1> linkSubject(
    MeasurementLinkRequestV1 request,
  ) =>
      _call(
        operation: _GovernedMeasurementRpcOperation.linkSubject,
        requestCanonicalBytes: request.canonicalBytes,
        decode: MeasurementLinkOperationResultV1.fromCanonicalBytes,
        unavailable: (failure) => MeasurementLinkOperationResultV1.failed(
          MeasurementLinkFailureV1(code: _measurementFailureCode(failure)),
        ),
      );

  @override
  Future<MeasurementSubjectOperationResultV1> resetSubject(
    MeasurementSubjectOperationRequestV1 request,
  ) =>
      _call(
        operation: _GovernedMeasurementRpcOperation.resetSubject,
        requestCanonicalBytes: request.canonicalBytes,
        decode: MeasurementSubjectOperationResultV1.fromCanonicalBytes,
        unavailable: (failure) => MeasurementSubjectOperationResultV1.failed(
          MeasurementLinkFailureV1(code: _measurementFailureCode(failure)),
        ),
      );

  @override
  Future<MeasurementSubjectOperationResultV1> withdrawConsent(
    MeasurementSubjectOperationRequestV1 request,
  ) =>
      _call(
        operation: _GovernedMeasurementRpcOperation.withdrawConsent,
        requestCanonicalBytes: request.canonicalBytes,
        decode: MeasurementSubjectOperationResultV1.fromCanonicalBytes,
        unavailable: (failure) => MeasurementSubjectOperationResultV1.failed(
          MeasurementLinkFailureV1(code: _measurementFailureCode(failure)),
        ),
      );

  @override
  Future<RestagePrivacyReceiptV1> requestPrivacy(
    RestagePrivacyRequestV1 request,
  ) =>
      _call(
        operation: _GovernedMeasurementRpcOperation.requestPrivacy,
        requestCanonicalBytes: request.canonicalBytes,
        decode: RestagePrivacyReceiptV1.fromCanonicalBytes,
        unavailable: (failure) => unavailablePrivacyReceipt(request,
            code: _privacyFailureCode(failure)),
      );

  Future<T> _call<T>({
    required _GovernedMeasurementRpcOperation operation,
    required List<int> requestCanonicalBytes,
    required T Function(List<int> bytes) decode,
    required T Function(GovernedMeasurementRpcFailure failure) unavailable,
  }) async {
    final carrier = base64Url.encode(requestCanonicalBytes).replaceAll('=', '');
    final outcome = await _client.invokeGovernedMeasurement(
      operation: operation.wireName,
      canonicalRequestBase64: carrier,
    );
    switch (outcome) {
      case GovernedMeasurementRpcAccepted(:final resultCanonicalBase64):
        try {
          return decode(
            base64Url.decode(base64Url.normalize(resultCanonicalBase64)),
          );
        } on Object {
          return unavailable(GovernedMeasurementRpcFailure.unavailable);
        }
      case GovernedMeasurementRpcFailed(:final failure):
        return unavailable(failure);
    }
  }
}

enum _GovernedMeasurementRpcOperation {
  issueLinkChallenge('issueLinkChallenge'),
  linkSubject('linkSubject'),
  resetSubject('resetSubject'),
  withdrawConsent('withdrawConsent'),
  requestPrivacy('requestPrivacy');

  const _GovernedMeasurementRpcOperation(this.wireName);

  final String wireName;
}

MeasurementLinkFailureCode _measurementFailureCode(
  GovernedMeasurementRpcFailure failure,
) =>
    switch (failure) {
      GovernedMeasurementRpcFailure.rejected =>
        MeasurementLinkFailureCode.invalidProof,
      GovernedMeasurementRpcFailure.unauthenticated =>
        MeasurementLinkFailureCode.notAllowed,
      GovernedMeasurementRpcFailure.conflict =>
        MeasurementLinkFailureCode.conflict,
      GovernedMeasurementRpcFailure.unavailable =>
        MeasurementLinkFailureCode.temporarilyUnavailable,
    };

RestagePrivacyFailureCode _privacyFailureCode(
  GovernedMeasurementRpcFailure failure,
) =>
    switch (failure) {
      GovernedMeasurementRpcFailure.rejected =>
        RestagePrivacyFailureCode.invalidProof,
      GovernedMeasurementRpcFailure.unauthenticated =>
        RestagePrivacyFailureCode.notAllowed,
      GovernedMeasurementRpcFailure.conflict =>
        RestagePrivacyFailureCode.conflict,
      GovernedMeasurementRpcFailure.unavailable =>
        RestagePrivacyFailureCode.temporarilyUnavailable,
    };
