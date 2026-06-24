import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/paywall_models.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_shared/restage_shared.dart';

/// Typed wrapper presenting paywalls as a view over the generic `surface` RPC
/// endpoint (`surfaceType: paywall`).
///
/// A paywall is a single-blob surface: [save] wraps the raw blob in a
/// [BlobSurfacePayload] (the canonical frame the surface store expects) and
/// [load] unwraps that frame back to the inner blob; [list] adapts each
/// `SurfaceSummary` to a [PaywallSummary]. Every method delegates to
/// [SurfaceApi] with [SurfaceType.paywall], so paywalls share the one delivery
/// substrate with every other surface. HTTP failures throw
/// [RestageApiException], which the caller decodes (the surface endpoint's
/// typed exceptions) to surface a more specific error.
@experimental
class PaywallApi {
  /// Build a paywall API client backed by [api].
  PaywallApi(RestageApi api) : _surface = SurfaceApi(api);

  final SurfaceApi _surface;

  /// List paywalls under (project, app).
  ///
  /// [organizationId] disambiguates the owning organization when the caller
  /// belongs to several; when omitted the backend resolves it.
  Future<List<PaywallSummary>> list({
    required String project,
    required String app,
    int? organizationId,
  }) async {
    final surfaces = await _surface.list(
      project: project,
      app: app,
      surfaceType: SurfaceType.paywall,
      organizationId: organizationId,
    );
    return [
      for (final surface in surfaces)
        PaywallSummary(
          slug: surface.slug,
          name: surface.name,
          draftUpdatedAt: surface.draftUpdatedAt,
          publishedVersionByEnvironment: surface.publishedVersionByEnvironment,
        ),
    ];
  }

  /// Upload [bytes] as the draft for (project, app, paywall), wrapped in the
  /// canonical [BlobSurfacePayload] frame the surface store expects, stamping
  /// the **derived** capability floor [minClient] and [requiredLibraries] the
  /// codegen recorded for the surface. The backend creates the surface row on
  /// first write; subsequent calls replace the draft with last-write-wins
  /// semantics.
  Future<void> save({
    required String project,
    required String app,
    required String paywall,
    required Uint8List bytes,
    required int minClient,
    List<LibraryRequirement> requiredLibraries = const [],
    int? organizationId,
  }) async {
    final canonical = BlobSurfacePayload(
      minClient: minClient,
      blob: bytes,
      requiredLibraries: requiredLibraries,
    ).canonicalBytes;
    await _surface.save(
      project: project,
      app: app,
      surfaceType: SurfaceType.paywall,
      surfaceSlug: paywall,
      bytes: canonical,
      organizationId: organizationId,
    );
  }

  /// Snapshot the latest draft for (project, app, paywall) into the named
  /// [environment]. Returns the newly assigned version number, monotonic per
  /// (paywall, environment).
  Future<int> publish({
    required String project,
    required String app,
    required String paywall,
    required String environment,
    int? organizationId,
  }) {
    return _surface.publish(
      project: project,
      app: app,
      surfaceType: SurfaceType.paywall,
      surfaceSlug: paywall,
      environment: environment,
      organizationId: organizationId,
    );
  }

  /// Return the active published version of (project, app, paywall) in
  /// [environment], or null when nothing has been published there yet.
  Future<int?> getPublishedVersion({
    required String project,
    required String app,
    required String paywall,
    required String environment,
    int? organizationId,
  }) {
    return _surface.getPublishedVersion(
      project: project,
      app: app,
      surfaceType: SurfaceType.paywall,
      surfaceSlug: paywall,
      environment: environment,
      organizationId: organizationId,
    );
  }

  /// Download the compiled draft blob for (project, app, paywall) — the inner
  /// blob, unwrapped from its [BlobSurfacePayload] frame. A never-saved paywall
  /// returns the backend's 1-byte skeleton unchanged.
  Future<Uint8List> load({
    required String project,
    required String app,
    required String paywall,
    int? organizationId,
  }) async {
    final frame = await _surface.load(
      project: project,
      app: app,
      surfaceType: SurfaceType.paywall,
      surfaceSlug: paywall,
      organizationId: organizationId,
    );
    // A never-saved surface returns the 1-byte skeleton — not a decodable
    // payload frame. Pass it through unchanged.
    if (frame.length <= 1) {
      return frame;
    }
    return (SurfacePayload.decode(frame) as BlobSurfacePayload).blob;
  }
}
