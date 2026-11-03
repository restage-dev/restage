import 'package:restage_cli/src/api/restage_api.dart';

/// Reads the public keys an app's delivered content is signed with.
final class DeliveryKeysApi {
  /// Wrap [api].
  const DeliveryKeysApi(this._api);

  final RestageApi _api;

  /// Each key as `<organizationId>:<base64url key>`, the signing key first.
  Future<List<String>> list({
    required String project,
    required String app,
    int? organizationId,
  }) async {
    final raw = await _api.call('deliveryKeys', 'list', <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'organizationId': ?organizationId,
    });
    return [for (final key in raw as List<dynamic>) key as String];
  }
}
