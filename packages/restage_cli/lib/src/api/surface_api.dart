import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_shared/restage_shared.dart';

/// Typed wrapper over the backend's `surface` RPC endpoint.
///
/// Mirrors the paywall API client with two differences: every call threads
/// the surface type (`'paywall'` / `'onboarding'` / `'message'` / `'survey'`)
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
  }) async {
    final raw = await _api.call('surface', 'list', <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'surfaceType': surfaceType.wireName,
      'organizationId': ?organizationId,
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
  }) async {
    final raw = await _api.call('surface', 'load', <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'surfaceType': surfaceType.wireName,
      'surfaceSlug': surfaceSlug,
      'organizationId': ?organizationId,
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
    int? organizationId,
  }) async {
    final raw = await _api
        .call('surface', 'getPublishedVersion', <String, dynamic>{
          'projectSlug': project,
          'appSlug': app,
          'surfaceType': surfaceType.wireName,
          'surfaceSlug': surfaceSlug,
          'environmentSlug': environment,
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
    });
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
    int? organizationId,
  }) async {
    final raw = await _api.call('surface', 'publish', <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'surfaceType': surfaceType.wireName,
      'surfaceSlug': surfaceSlug,
      'environmentSlug': environment,
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
