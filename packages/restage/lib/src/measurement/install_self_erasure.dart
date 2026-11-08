import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../restage_rpc_client/uuid_v4.dart';
import 'governed_measurement_transport.dart';

/// Captured SDK configuration and identity fences for one erasure attempt.
final class InstallSelfErasureContext {
  const InstallSelfErasureContext({
    required this.namespace,
    required this.actor,
    required this.readHandle,
    required this.isCurrent,
    required this.finalize,
  });

  final String namespace;
  final Future<String> Function() actor;
  final Future<String?> Function() readHandle;
  final bool Function() isCurrent;
  final Future<void> Function(
    String actor,
    String? resetActor,
    Future<void> Function(String actor) markReset,
    Future<void> Function() markFinalized,
  ) finalize;
}

/// Retains retry authority until matching completion and durable local cleanup.
final class InstallSelfErasure {
  final Map<String, Future<RestagePrivacyReceiptV1>> _active = {};
  final Map<String, String> _records = {};

  /// Unfinished installation resets block enrollment across app namespaces.
  static bool enrollmentAllowed(SharedPreferences prefs, String actor) {
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('restage.installErasure.')) continue;
      try {
        final record = jsonDecode(prefs.getString(key)!) as Map;
        if (record['resetActor'] is String &&
            record['finalized'] != true &&
            (record['actor'] == actor || record['resetActor'] == actor)) {
          return false;
        }
      } on Object {
        return false;
      }
    }
    return true;
  }

  void discardMemory() {
    _active.clear();
    _records.clear();
  }

  Future<RestagePrivacyReceiptV1> request(InstallSelfErasureContext? context) {
    if (context == null) return Future.value(_unavailable());
    final active = _active[context.namespace];
    if (active != null) return active;
    final transport = GovernedMeasurementPortRegistry.measurement;
    late final Future<RestagePrivacyReceiptV1> pending;
    pending = _request(context, transport).whenComplete(() {
      if (identical(_active[context.namespace], pending)) {
        _active.remove(context.namespace);
      }
    });
    return _active[context.namespace] = pending;
  }

  Future<RestagePrivacyReceiptV1> _request(
    InstallSelfErasureContext context,
    RestageGovernedMeasurementTransport transport,
  ) async {
    RestagePrivacyRequestV1? envelope;
    try {
      final key =
          'restage.installErasure.${sha256.convert(utf8.encode(context.namespace))}';
      final prefs = await SharedPreferences.getInstance();
      final actor = await context.actor();
      if (!context.isCurrent()) return _unavailable();
      final stored = _records[key] ?? prefs.getString(key);
      late MeasurementInstallErasureRequestV1 operation;
      late String originalActor;
      String? resetActor;
      var finalized = false;
      if (stored != null) {
        final record = jsonDecode(stored) as Map<String, dynamic>;
        originalActor = record['actor'] as String;
        resetActor = record['resetActor'] as String?;
        finalized = record['finalized'] == true;
        operation = MeasurementInstallErasureRequestV1.fromJson(
          (record['request'] as Map).cast<String, Object?>(),
        );
      } else {
        final handle = await context.readHandle();
        if (handle == null || !context.isCurrent()) return _unavailable();
        originalActor = actor;
        operation = MeasurementInstallErasureRequestV1(
          operationId: generateUuidV4(),
          assignmentKey: handle,
        );
      }
      final record = <String, Object?>{
        'actor': originalActor,
        'request': operation.toJson(),
        if (resetActor != null) 'resetActor': resetActor,
        if (finalized) 'finalized': true,
      };
      Future<void> save() async {
        final encoded = jsonEncode(record);
        _records[key] = encoded;
        if (!await prefs.setString(key, encoded)) {
          throw StateError('Erasure retry state could not be persisted');
        }
      }

      await save();
      envelope = RestagePrivacyRequestV1(
        targets: RestagePrivacyTargets.measurement,
        action: RestagePrivacyAction.delete,
        correlationId: operation.operationId,
        authorities: [
          RestagePrivacyDomainAuthority(
            domain: RestagePrivacyDomain.measurement,
            requestCanonicalBytes: operation.canonicalBytes,
          ),
        ],
      );
      if (!context.isCurrent()) return unavailablePrivacyReceipt(envelope);
      final result = await transport.requestPrivacy(envelope);
      if (!_matches(result, operation)) {
        return unavailablePrivacyReceipt(envelope);
      }
      if (result.status != RestagePrivacyCoordinatorStatus.completed) {
        return result;
      }
      if (!context.isCurrent()) return unavailablePrivacyReceipt(envelope);
      if (!finalized) {
        await context.finalize(originalActor, resetActor, (actor) async {
          record['resetActor'] = actor;
          await save();
        }, () async {
          record['finalized'] = true;
          try {
            await save();
          } on Object {
            record.remove('finalized');
            _records[key] = jsonEncode(record);
            rethrow;
          }
        });
      }
      if (!await prefs.remove(key)) return unavailablePrivacyReceipt(envelope);
      _records.remove(key);
      return result;
    } on Object {
      return envelope == null
          ? _unavailable()
          : unavailablePrivacyReceipt(envelope);
    }
  }

  bool _matches(
    RestagePrivacyReceiptV1 result,
    MeasurementInstallErasureRequestV1 operation,
  ) {
    if (result.targets != RestagePrivacyTargets.measurement ||
        result.action != RestagePrivacyAction.delete ||
        result.correlationId != operation.operationId ||
        result.domainResults.length != 1) {
      return false;
    }
    final domain = result.domainResults.single;
    if (domain is RestagePrivacyDomainFailedV1) return true;
    if (domain is! RestagePrivacyDomainReceiptResultV1 ||
        domain.receipt.operationId != operation.operationId) {
      return false;
    }
    if (domain.status != RestagePrivacyDomainStatus.completed) return true;
    final receipt = MeasurementInstallErasureReceiptV1.fromCanonicalBytes(
      domain.receipt.receiptCanonicalBytes,
    );
    return receipt.operationId == operation.operationId;
  }
}

RestagePrivacyReceiptV1 _unavailable() => RestagePrivacyReceiptV1(
      targets: RestagePrivacyTargets.measurement,
      action: RestagePrivacyAction.delete,
      status: RestagePrivacyCoordinatorStatus.failed,
      domainResults: [
        RestagePrivacyDomainResult.failed(
          domain: RestagePrivacyDomain.measurement,
          action: RestagePrivacyAction.delete,
          failure: const RestagePrivacyDomainFailureV1(
            code: RestagePrivacyFailureCode.temporarilyUnavailable,
          ),
        ),
      ],
    );
