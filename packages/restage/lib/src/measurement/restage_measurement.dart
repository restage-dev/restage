import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'governed_measurement_transport.dart';
import '../events/restage_event.dart';
import '../restage_rpc_client/restage_rpc_client.dart';
import '../restage_rpc_client/uuid_v4.dart';
import '../runtime/restage.dart';

/// Purchase conversion reporting and governed Measurement operations.
///
/// Purchase reports retain the originating paywall exposure. Governed identity
/// operations require explicit authenticated evidence and generation preconditions.
final class RestageMeasurement {
  /// Internal construction used by the SDK facade.
  @internal
  RestageMeasurement.internal();

  /// Reports a successful purchase for the paywall that emitted [event].
  ///
  /// Call after the store confirms success. The event retains its original
  /// exposure through paywall changes or dismissal, including events received
  /// through the app-wide stream. Each event is reported at most once.
  /// Returns false when the exposure or delivery is unavailable or refused.
  /// Package and product identifiers are retained; no paid amount is inferred.
  Future<bool> reportPurchase(
    RestageEvent event, {
    required String packageIdentifier,
    required String productIdentifier,
  }) {
    final exposure = _purchaseExposures[event];
    if (exposure == null ||
        !exposure._isCurrent() ||
        !Restage.isMeasurementEnabled ||
        !_validIdentifier(packageIdentifier) ||
        !_validIdentifier(productIdentifier)) {
      return Future.value(false);
    }
    return exposure._report ??= exposure._send({
      'eventId': generateUuidV4(),
      'packageIdentifier': packageIdentifier,
      'productIdentifier': productIdentifier,
      'reportedOccurredAtMicros': DateTime.now().toUtc().microsecondsSinceEpoch,
    });
  }

  /// Issues one exact direct host/IDP link challenge.
  Future<MeasurementLinkChallengeOperationResultV1> issueLinkChallenge(
    MeasurementLinkChallengeRequestV1 request,
  ) async {
    try {
      return await GovernedMeasurementPortRegistry.measurement
          .issueLinkChallenge(request);
    } on Object {
      return unavailableLinkChallengeResult();
    }
  }

  /// Links a subject through the complete direct host/IDP path.
  Future<MeasurementLinkOperationResultV1> linkSubject(
    MeasurementLinkRequestV1 request,
  ) async {
    try {
      return await GovernedMeasurementPortRegistry.measurement.linkSubject(
        request,
      );
    } on Object {
      return unavailableLinkResult();
    }
  }

  /// Resets the Measurement-owned subject link state explicitly.
  Future<MeasurementSubjectOperationResultV1> resetSubject(
    MeasurementSubjectOperationRequestV1 request,
  ) async {
    if (request.action != MeasurementSubjectOperationAction.resetSubject) {
      return _invalidSubjectOperationResult();
    }
    try {
      return await GovernedMeasurementPortRegistry.measurement.resetSubject(
        request,
      );
    } on Object {
      return unavailableSubjectOperationResult();
    }
  }

  /// Withdraws consent for future governed Measurement operations explicitly.
  Future<MeasurementSubjectOperationResultV1> withdrawConsent(
    MeasurementSubjectOperationRequestV1 request,
  ) async {
    if (request.action != MeasurementSubjectOperationAction.withdrawConsent) {
      return _invalidSubjectOperationResult();
    }
    try {
      return await GovernedMeasurementPortRegistry.measurement.withdrawConsent(
        request,
      );
    } on Object {
      return unavailableSubjectOperationResult();
    }
  }
}

final class _PurchaseExposure {
  _PurchaseExposure(this._prepare, this._client, this._isCurrent);

  final Future<_ExposureCoordinates?> Function() _prepare;
  final RestageRpcClient _client;
  final bool Function() _isCurrent;
  Future<bool>? _report;

  Future<bool> _send(Map<String, Object> report) async {
    try {
      final exposure = await _prepare();
      if (exposure == null) return false;
      return await _client.reportPurchase({
        ...report,
        'exposure': {
          'captureSessionNonce': exposure.captureSessionNonce,
          'publicationBindingReference':
              exposure.publicationBindingReference.toJson(),
        },
      }, publicationGuard: () => _isCurrent() && Restage.isMeasurementEnabled);
    } on Object {
      return false;
    }
  }
}

typedef _ExposureCoordinates = ({
  String captureSessionNonce,
  MeasurementPublicationBindingReferenceV1 publicationBindingReference,
});

final _purchaseExposures = Expando<_PurchaseExposure>();

/// Attaches the exact painted session before the event reaches host callbacks.
@internal
void attachPurchaseExposure(RestageEvent event,
    {required Future<
                ({
                  String captureSessionNonce,
                  MeasurementPublicationBindingReferenceV1 publicationBindingReference
                })?>
            Function()
        prepare}) {
  final client = Restage.activeRpcClient;
  if (!Restage.isMeasurementEnabled ||
      client == null ||
      _purchaseExposures[event] != null) {
    return;
  }
  _purchaseExposures[event] =
      _PurchaseExposure(prepare, client, Restage.captureEventAuthority());
}

/// Retains the same private exposure and report state on an emitted snapshot.
@internal
void retainPurchaseExposure(RestageEvent original, RestageEvent emitted) {
  final exposure = _purchaseExposures[original];
  if (exposure != null) _purchaseExposures[emitted] = exposure;
}

bool _validIdentifier(String identifier) =>
    identifier.isNotEmpty &&
    utf8.encode(identifier).length <= 256 &&
    !identifier.codeUnits.any((unit) => unit < 32 || unit == 127);

MeasurementSubjectOperationResultV1 _invalidSubjectOperationResult() =>
    const MeasurementSubjectOperationResultV1.failed(
      MeasurementLinkFailureV1(code: MeasurementLinkFailureCode.notAllowed),
    );
