import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';

/// One backend row, passed through as the server sent it.
typedef AdminRow = Map<String, Object?>;

/// App administration over the backend RPC: store products, product slots,
/// store connections, app platform configuration, and API keys.
///
/// Rows come back verbatim. None of these routes returns secret material.
@experimental
class AppAdminApi {
  /// Build a client backed by [_api].
  AppAdminApi(this._api);

  final RestageApi _api;

  /// Store products imported for an app, optionally for one [store]
  /// (`appStore` or `playStore`).
  Future<List<AdminRow>> listProducts({
    required String project,
    required String app,
    String? store,
    int? organizationId,
  }) => _rows('product', 'list', {
    'projectSlug': project,
    'appSlug': app,
    'store': ?store,
    'organizationId': ?organizationId,
  });

  /// Re-fetch [store]'s catalog and upsert each entry as a product.
  Future<List<AdminRow>> importProducts({
    required String project,
    required String app,
    required String store,
    int? organizationId,
  }) => _rows('product', 'importProducts', {
    'projectSlug': project,
    'appSlug': app,
    'store': store,
    'organizationId': ?organizationId,
  });

  /// The app's product slots.
  Future<List<AdminRow>> listProductSlots({
    required String project,
    required String app,
    int? organizationId,
  }) => _rows('productSlot', 'list', {
    'projectSlug': project,
    'appSlug': app,
    'organizationId': ?organizationId,
  });

  /// Create or replace one slot and its complete store mapping. A null
  /// product id unmaps that store.
  Future<AdminRow> upsertProductSlot({
    required String project,
    required String app,
    required String name,
    required String entitlement,
    required String? iosProductId,
    required String? androidProductId,
    int? organizationId,
  }) => _row('productSlot', 'upsert', {
    'projectSlug': project,
    'appSlug': app,
    'name': name,
    'entitlement': entitlement,
    'iosProductId': ?iosProductId,
    'androidProductId': ?androidProductId,
    'organizationId': ?organizationId,
  });

  /// The app's store connections, without their credentials.
  Future<List<AdminRow>> listStoreConnections({
    required String project,
    required String app,
    int? organizationId,
  }) => _rows('storeConnection', 'list', {
    'projectSlug': project,
    'appSlug': app,
    'organizationId': ?organizationId,
  });

  /// One app's platform configuration, or null when [app] is not in
  /// [project].
  Future<AdminRow?> readAppConfig({
    required String project,
    required String app,
    int? organizationId,
  }) async {
    final apps = await _rows('app', 'listApps', {
      'organizationId': ?organizationId,
      'projectSlug': project,
    });
    for (final row in apps) {
      if (row['slug'] == app) return row;
    }
    return null;
  }

  /// Update an app's platform configuration. A null field stays unchanged;
  /// an empty string clears it.
  Future<AdminRow> updateAppConfig({
    required String project,
    required String app,
    String? iosBundleId,
    String? androidPackage,
    String? webDomain,
    int? organizationId,
  }) => _row('app', 'updateAppConfiguration', {
    'projectSlug': project,
    'appSlug': app,
    'iosBundleId': ?iosBundleId,
    'androidPackage': ?androidPackage,
    'webDomain': ?webDomain,
    'organizationId': ?organizationId,
  });

  /// Active API keys at one environment target, redacted.
  Future<List<AdminRow>> listApiKeys({
    required String project,
    required String app,
    required String environment,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
  }) => _rows('apiKey', 'listKeys', {
    'projectSlug': project,
    'appSlug': app,
    'environmentSlug': environment,
    'environmentTargetId': ?environmentTargetId,
    'runtimePlane': ?runtimePlane?.wireName,
    'organizationId': ?organizationId,
  });

  /// Revoke one API key. Revoking a revoked key changes nothing.
  Future<void> revokeApiKey({
    required String project,
    required String app,
    required int apiKeyId,
    int? organizationId,
  }) async {
    await _api.call('apiKey', 'revokeKey', {
      'projectSlug': project,
      'appSlug': app,
      'apiKeyId': apiKeyId,
      'organizationId': ?organizationId,
    });
  }

  Future<List<AdminRow>> _rows(
    String endpoint,
    String method,
    Map<String, dynamic> args,
  ) async {
    final raw = await _api.call(endpoint, method, args);
    return [for (final row in raw as List<dynamic>) _asRow(row)];
  }

  Future<AdminRow> _row(
    String endpoint,
    String method,
    Map<String, dynamic> args,
  ) async => _asRow(await _api.call(endpoint, method, args));

  AdminRow _asRow(Object? raw) => (raw! as Map).cast<String, Object?>();
}
