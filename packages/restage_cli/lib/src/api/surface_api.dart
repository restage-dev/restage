import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/byte_data_wire.dart';
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
  /// belongs to several; when omitted the backend resolves it. Archived
  /// surfaces are left out unless [includeArchived] is set.
  Future<List<SurfaceSummary>> list({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    int? organizationId,
    int? appId,
    bool includeArchived = false,
  }) async {
    final raw = await _api.call('surface', 'list', <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'surfaceType': surfaceType.wireName,
      'organizationId': ?organizationId,
      'appId': ?appId,
      if (includeArchived) 'includeArchived': true,
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
    return _surfaceBytes(raw);
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
      'bytes': encodeByteDataWire(bytes),
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
    SurfaceSourceKind? sourceKind,
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
      if (sourceKind != null) 'sourceKind': sourceKind.wireName,
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

  /// Read one family's revision history. The server resolves the family from
  /// the optional [sourceKind] and [contractVersion] the way activation does,
  /// and the result names it.
  Future<SurfaceContractFamilyHistoryResult> surfaceContractHistory({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    required String environment,
    SurfaceSourceKind? sourceKind,
    int? contractVersion,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
  }) async {
    final raw = await _api
        .call('surface', 'surfaceContractHistory', <String, dynamic>{
          'projectSlug': project,
          'appSlug': app,
          'surfaceType': surfaceType.wireName,
          'surfaceSlug': surfaceSlug,
          'environmentSlug': environment,
          'sourceKind': ?sourceKind?.wireName,
          'contractVersion': ?contractVersion,
          'environmentTargetId': ?environmentTargetId,
          'runtimePlane': ?runtimePlane?.wireName,
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
    SurfaceSourceKind? sourceKind,
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
      if (sourceKind != null) 'sourceKind': sourceKind.wireName,
    });
    return SurfaceFamilyMutationResult.fromJsonOrNull(
      raw,
      environmentSlug: environment,
    );
  }

  /// Activate one family revision without changing any other family pointer.
  /// The server resolves the family from the optional [sourceKind] and
  /// [contractVersion]; a null [publishedRevision] activates its newest
  /// revision. The result names the family and revision.
  Future<SurfaceFamilyMutationResult> activate({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    required String environment,
    required int? publishedRevision,
    required String reason,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
    int? contractVersion,
    SurfaceSourceKind? sourceKind,
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
      'contractVersion': ?contractVersion,
      'sourceKind': ?sourceKind?.wireName,
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
    SurfaceSourceKind? sourceKind,
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
          if (sourceKind != null) 'sourceKind': sourceKind.wireName,
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
    String? label,
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
      'label': ?label,
    });
    return raw as int;
  }

  /// Names [version] of the surface in [environment], or clears the name
  /// when [label] is null or empty.
  Future<void> renameVersion({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    required String environment,
    required int version,
    required String? label,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
    int? contractVersion,
  }) async {
    await _api.call('surface', 'renameVersion', <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'surfaceType': surfaceType.wireName,
      'surfaceSlug': surfaceSlug,
      'environmentSlug': environment,
      'version': version,
      'label': label,
      'environmentTargetId': ?environmentTargetId,
      'runtimePlane': ?runtimePlane?.wireName,
      'organizationId': ?organizationId,
      'contractVersion': ?contractVersion,
    });
  }

  /// Archives the surface: it stops serving in every environment.
  Future<void> archive({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    int? organizationId,
  }) => _lifecycle(
    'archive',
    project: project,
    app: app,
    surfaceType: surfaceType,
    surfaceSlug: surfaceSlug,
    organizationId: organizationId,
  );

  /// Restores an archived surface.
  Future<void> restore({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    int? organizationId,
  }) => _lifecycle(
    'restore',
    project: project,
    app: app,
    surfaceType: surfaceType,
    surfaceSlug: surfaceSlug,
    organizationId: organizationId,
  );

  /// Deletes an archived surface for good.
  Future<void> deleteForGood({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    int? organizationId,
  }) => _lifecycle(
    'deleteForGood',
    project: project,
    app: app,
    surfaceType: surfaceType,
    surfaceSlug: surfaceSlug,
    organizationId: organizationId,
  );

  Future<void> _lifecycle(
    String method, {
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    int? organizationId,
  }) async {
    await _api.call('surfaceArchive', method, <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'surfaceType': surfaceType.wireName,
      'surfaceSlug': surfaceSlug,
      'organizationId': ?organizationId,
    });
  }
}

Uint8List _surfaceBytes(Object? raw) => decodeByteDataWire(
  raw,
  malformed: (detail) => FormatException('The surface reply $detail'),
);
