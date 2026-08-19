import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_shared/restage_shared.dart';

/// Typed wrapper over the backend's `surface` RPC endpoint.
///
/// Mirrors the paywall API client with two differences: every call threads
/// the surface type (`'paywall'` / `'onboarding'` / `'message'` / `'survey'` /
/// `'general'`)
/// into the arg map, and the methods target the `'surface'` endpoint. HTTP
/// failures throw [RestageApiException], which the caller decodes with
/// [decodeSurfaceTypedException] to recover the typed [SurfaceException]
/// variants.
@experimental
class SurfaceApi {
  /// Build a surface API client backed by [_api].
  SurfaceApi(this._api);

  final RestageApi _api;

  /// List surfaces of [surfaceType] under (project, app).
  ///
  /// [organizationId] disambiguates the owning organization when the caller
  /// belongs to several; when omitted the backend resolves it.
  Future<List<SurfaceSummary>> list({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    int? organizationId,
    int? appId,
  }) async {
    final raw = await _api.call('surface', 'list', <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'surfaceType': surfaceType.wireName,
      'organizationId': ?organizationId,
      'appId': ?appId,
    });
    return [
      for (final item in raw as List<dynamic>)
        SurfaceSummary.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// Download the persisted draft frame for
  /// (project, app, surfaceType, surfaceSlug) — the raw canonical
  /// `SurfacePayload` bytes (a never-saved surface returns a 1-byte skeleton).
  Future<Uint8List> load({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    int? organizationId,
    int? appId,
  }) async {
    final raw = await _api.call('surface', 'load', <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'surfaceType': surfaceType.wireName,
      'surfaceSlug': surfaceSlug,
      'organizationId': ?organizationId,
      'appId': ?appId,
    });
    return _decodeByteDataWire(raw as String);
  }

  /// Return the active published version of (project, app, surfaceType,
  /// surfaceSlug) in [environment], or null when nothing has been published
  /// there yet.
  Future<int?> getPublishedVersion({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    required String environment,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
  }) async {
    final raw = await _api
        .call('surface', 'getPublishedVersion', <String, dynamic>{
          'projectSlug': project,
          'appSlug': app,
          'surfaceType': surfaceType.wireName,
          'surfaceSlug': surfaceSlug,
          'environmentSlug': environment,
          if (environmentTargetId != null)
            'environmentTargetId': environmentTargetId,
          if (runtimePlane != null) 'runtimePlane': runtimePlane.wireName,
          'organizationId': ?organizationId,
        });
    return raw as int?;
  }

  /// Upload [bytes] as the draft for
  /// (project, app, surfaceType, surfaceSlug).
  ///
  /// The backend's `surface.save` endpoint creates the surface row on
  /// first write; subsequent calls replace the draft with last-write-wins
  /// semantics. Requires the member role.
  ///
  /// [organizationId] disambiguates the owning organization when the caller
  /// belongs to several; when omitted the backend resolves it.
  Future<void> save({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    required Uint8List bytes,
    int? organizationId,
    int? appId,
  }) async {
    await _api.call('surface', 'save', <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'surfaceType': surfaceType.wireName,
      'surfaceSlug': surfaceSlug,
      // Wire format for `ByteData` arguments: a literal string of the
      // form `decode('<base64>', 'base64')`. The server strips the
      // prefix/suffix and base64-decodes back into a `ByteData`. Must
      // match exactly — the server does not accept a bare base64 value.
      'bytes': "decode('${base64Encode(bytes)}', 'base64')",
      'organizationId': ?organizationId,
      'appId': ?appId,
    });
  }

  /// Live lifecycle snapshot of (project, app, surfaceType, surfaceSlug) in
  /// [environment]. Returns the active version, lock state, delivery shape, and
  /// version history. Requires the member role.
  ///
  /// [organizationId] disambiguates the owning organization when the caller
  /// belongs to several; when omitted the backend resolves it.
  Future<SurfaceStatusResult> surfaceStatus({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    required String environment,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
    int? contractVersion,
  }) async {
    final raw = await _api.call('surface', 'surfaceStatus', <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'surfaceType': surfaceType.wireName,
      'surfaceSlug': surfaceSlug,
      'environmentSlug': environment,
      if (environmentTargetId != null)
        'environmentTargetId': environmentTargetId,
      if (runtimePlane != null) 'runtimePlane': runtimePlane.wireName,
      'organizationId': ?organizationId,
      'contractVersion': contractVersion,
    });
    return SurfaceStatusResult.fromJson(
      raw as Map<String, dynamic>,
      environmentSlug: environment,
    );
  }

  /// Audit timeline for one surface in [environment]. Includes chained and
  /// pending-chain events. Requires the member role.
  Future<List<SurfaceAuditLogEntry>> listSurfaceHistory({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    required String environment,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
    int? contractVersion,
  }) async {
    final raw = await _api
        .call('surface', 'listSurfaceHistory', <String, dynamic>{
          'projectSlug': project,
          'appSlug': app,
          'surfaceType': surfaceType.wireName,
          'surfaceSlug': surfaceSlug,
          'environmentSlug': environment,
          if (environmentTargetId != null)
            'environmentTargetId': environmentTargetId,
          if (runtimePlane != null) 'runtimePlane': runtimePlane.wireName,
          'organizationId': ?organizationId,
          'contractVersion': contractVersion,
        });
    return [
      for (final item in raw as List<dynamic>)
        SurfaceAuditLogEntry.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// Read the immutable revision history for one exact generated family.
  ///
  /// The nested family reference is the generated backend model. Its
  /// non-versioned flow/paywall form intentionally omits `contractVersion`;
  /// standalone screens carry their positive contract version.
  Future<SurfaceContractFamilyHistoryResult> surfaceContractHistory({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    required String environment,
    required SurfaceSourceKind sourceKind,
    int? contractVersion,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
  }) async {
    final family = <String, dynamic>{
      '__className__': 'SurfaceContractFamilyReference',
      'surfaceType': surfaceType.wireName,
      'surfaceSlug': surfaceSlug,
      'sourceKind': sourceKind.wireName,
      if (contractVersion != null) 'contractVersion': contractVersion,
    };
    final raw = await _api
        .call('surface', 'surfaceContractHistory', <String, dynamic>{
          'projectSlug': project,
          'appSlug': app,
          'environmentSlug': environment,
          'family': family,
          if (environmentTargetId != null)
            'environmentTargetId': environmentTargetId,
          if (runtimePlane != null) 'runtimePlane': runtimePlane.wireName,
          'organizationId': ?organizationId,
        });
    return SurfaceContractFamilyHistoryResult.fromJson(raw);
  }

  /// Full organization audit stream. Requires the admin role.
  Future<List<SurfaceAuditLogEntry>> listAuditLog({
    required int organizationId,
  }) async {
    final raw = await _api.call('surface', 'listAuditLog', <String, dynamic>{
      'organizationId': organizationId,
    });
    return [
      for (final item in raw as List<dynamic>)
        SurfaceAuditLogEntry.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// Compliance / DHF export rows. Requires admin role and a paid plan.
  Future<List<SurfaceComplianceExportRow>> exportComplianceAudit({
    required int organizationId,
  }) async {
    final raw = await _api.call(
      'surface',
      'exportComplianceAudit',
      <String, dynamic>{'organizationId': organizationId},
    );
    return [
      for (final item in raw as List<dynamic>)
        SurfaceComplianceExportRow.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// Organization-level chain verification verdict. Requires the admin role.
  Future<SurfaceChainVerdictResult> surfaceChainVerdict({
    required int organizationId,
  }) async {
    final raw = await _api.call(
      'surface',
      'surfaceChainVerdict',
      <String, dynamic>{'organizationId': organizationId},
    );
    return SurfaceChainVerdictResult.fromJson(raw as Map<String, dynamic>);
  }

  /// Kill the surface — null its active-version pointer so the SDK falls back
  /// to its bundled asset. [frozen] also locks the surface against new
  /// publishes. [reason] is recorded in the audit trail. Requires the admin
  /// role.
  ///
  /// The [frozen] flag maps to the backend's kill `mode`: `'frozen'` when true,
  /// `'transient'` when false.
  ///
  /// [organizationId] disambiguates the owning organization when the caller
  /// belongs to several; when omitted the backend resolves it.
  Future<SurfaceIdentityMutationResult?> kill({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    required String environment,
    required bool frozen,
    required String reason,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
  }) async {
    final raw = await _api.call('surface', 'killSurface', <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'surfaceType': surfaceType.wireName,
      'surfaceSlug': surfaceSlug,
      'environmentSlug': environment,
      'mode': frozen ? 'frozen' : 'transient',
      'reason': reason,
      if (environmentTargetId != null)
        'environmentTargetId': environmentTargetId,
      if (runtimePlane != null) 'runtimePlane': runtimePlane.wireName,
      'organizationId': ?organizationId,
    });
    return SurfaceIdentityMutationResult.fromJsonOrNull(
      raw,
      environmentSlug: environment,
    );
  }

  /// Set or clear the surface's publish-lock. When [locked] is true no further
  /// publishes are accepted until the lock is cleared. [reason] is recorded in
  /// the audit trail. Requires the admin role.
  ///
  /// [organizationId] disambiguates the owning organization when the caller
  /// belongs to several; when omitted the backend resolves it.
  Future<SurfaceIdentityMutationResult?> setLock({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    required String environment,
    required bool locked,
    required String reason,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
  }) async {
    final raw = await _api.call('surface', 'setSurfaceLock', <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'surfaceType': surfaceType.wireName,
      'surfaceSlug': surfaceSlug,
      'environmentSlug': environment,
      'locked': locked,
      'reason': reason,
      if (environmentTargetId != null)
        'environmentTargetId': environmentTargetId,
      if (runtimePlane != null) 'runtimePlane': runtimePlane.wireName,
      'organizationId': ?organizationId,
    });
    return SurfaceIdentityMutationResult.fromJsonOrNull(
      raw,
      environmentSlug: environment,
    );
  }

  /// Roll one exact family back to [toVersion] by re-pointing its active
  /// revision pointer. [lockAfter] freezes the identity after the re-point to
  /// prevent accidental overwrite. [reason] is recorded in the audit trail.
  /// Requires the admin role.
  ///
  /// [organizationId] disambiguates the owning organization when the caller
  /// belongs to several; when omitted the backend resolves it.
  Future<SurfaceFamilyMutationResult?> rollback({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    required String environment,
    required int toVersion,
    required bool lockAfter,
    required String reason,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
    int? contractVersion,
  }) async {
    final raw = await _api.call('surface', 'rollbackSurface', <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'surfaceType': surfaceType.wireName,
      'surfaceSlug': surfaceSlug,
      'environmentSlug': environment,
      'toVersion': toVersion,
      'lockAfter': lockAfter,
      'reason': reason,
      if (environmentTargetId != null)
        'environmentTargetId': environmentTargetId,
      if (runtimePlane != null) 'runtimePlane': runtimePlane.wireName,
      'organizationId': ?organizationId,
      'contractVersion': contractVersion,
    });
    return SurfaceFamilyMutationResult.fromJsonOrNull(
      raw,
      environmentSlug: environment,
    );
  }

  /// Activate one exact family revision without changing any other family
  /// pointer. A null [contractVersion] explicitly selects the existing
  /// non-versioned flow/paywall lineage.
  Future<SurfaceFamilyMutationResult> activate({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    required String environment,
    required int publishedRevision,
    required String reason,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
    int? contractVersion,
  }) async {
    final raw = await _api.call('surface', 'activateSurface', <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'surfaceType': surfaceType.wireName,
      'surfaceSlug': surfaceSlug,
      'environmentSlug': environment,
      'publishedRevision': publishedRevision,
      'reason': reason,
      if (environmentTargetId != null)
        'environmentTargetId': environmentTargetId,
      if (runtimePlane != null) 'runtimePlane': runtimePlane.wireName,
      'organizationId': ?organizationId,
      'contractVersion': contractVersion,
    });
    return SurfaceFamilyMutationResult.fromJson(
      raw,
      environmentSlug: environment,
    );
  }

  /// Informational preview of a rollback to [toVersion]: how it is expected to
  /// affect the currently-live cohort. Does NOT mutate state and does NOT block
  /// rollback. Requires the admin role (it previews an admin operation).
  ///
  /// [organizationId] disambiguates the owning organization when the caller
  /// belongs to several; when omitted the backend resolves it.
  Future<RollbackPreflightResult> rollbackPreflight({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    required String environment,
    required int toVersion,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
    int? contractVersion,
  }) async {
    final raw = await _api
        .call('surface', 'rollbackPreflight', <String, dynamic>{
          'projectSlug': project,
          'appSlug': app,
          'surfaceType': surfaceType.wireName,
          'surfaceSlug': surfaceSlug,
          'environmentSlug': environment,
          'toVersion': toVersion,
          if (environmentTargetId != null)
            'environmentTargetId': environmentTargetId,
          if (runtimePlane != null) 'runtimePlane': runtimePlane.wireName,
          'organizationId': ?organizationId,
          'contractVersion': contractVersion,
        });
    return RollbackPreflightResult.fromJson(raw as Map<String, dynamic>);
  }

  /// Snapshot the latest draft for (project, app, surfaceType, surfaceSlug)
  /// into the named [environment]. Returns the newly assigned version
  /// number, monotonic per (surface, environment). Requires the admin role.
  ///
  /// [organizationId] disambiguates the owning organization when the caller
  /// belongs to several; when omitted the backend resolves it.
  Future<int> publish({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    required String environment,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
  }) async {
    final raw = await _api.call('surface', 'publish', <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'surfaceType': surfaceType.wireName,
      'surfaceSlug': surfaceSlug,
      'environmentSlug': environment,
      if (environmentTargetId != null)
        'environmentTargetId': environmentTargetId,
      if (runtimePlane != null) 'runtimePlane': runtimePlane.wireName,
      'organizationId': ?organizationId,
    });
    return raw as int;
  }
}

/// Decode the wire form of a returned `ByteData`
/// (`decode('<base64>', 'base64')`) back into bytes.
///
/// Tolerates a bare base64 string if the wire form ever changes; an
/// unparseable value throws from [base64Decode] and surfaces to the caller.
Uint8List _decodeByteDataWire(String wire) {
  const prefix = "decode('";
  const suffix = "', 'base64')";
  if (wire.startsWith(prefix) && wire.endsWith(suffix)) {
    return base64Decode(
      wire.substring(prefix.length, wire.length - suffix.length),
    );
  }
  return base64Decode(wire);
}
