import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/auth_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';

/// Typed wrapper over the backend's `auth` RPC endpoint.
@experimental
class AuthApi {
  /// Build an [AuthApi] backed by [_api].
  AuthApi(this._api);

  final RestageApi _api;

  /// Start a device-authorization grant.
  Future<DeviceAuthorizationStart> startDeviceAuthorization() async {
    final response = await _api.call(
      'auth',
      'startDeviceAuthorization',
      const <String, dynamic>{},
    );
    return DeviceAuthorizationStart.fromJson(response! as Map<String, dynamic>);
  }

  /// Poll for a device-authorization grant identified by [deviceCode].
  Future<DeviceAuthorizationResult> exchangeDeviceCode(
    String deviceCode,
  ) async {
    final response = await _api.call(
      'auth',
      'exchangeDeviceCode',
      <String, dynamic>{'deviceCode': deviceCode},
    );
    return DeviceAuthorizationResult.fromJson(
      response! as Map<String, dynamic>,
    );
  }

  /// Revoke the current session's AuthKey.
  Future<void> logout() async {
    await _api.call('auth', 'logout', const <String, dynamic>{});
  }

  /// Return the authenticated user's profile, or `null` when the
  /// session is unauthenticated or environment-bound.
  Future<CliUserInfo?> whoami() async {
    final response = await _api.call(
      'auth',
      'whoami',
      const <String, dynamic>{},
    );
    if (response == null) return null;
    return CliUserInfo.fromJson(response as Map<String, dynamic>);
  }
}
