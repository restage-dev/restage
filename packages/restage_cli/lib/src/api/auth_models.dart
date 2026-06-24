import 'package:meta/meta.dart';

/// Reply from a single `exchangeDeviceCode` poll.
@experimental
enum DeviceAuthorizationStatus {
  /// Approval is still in flight — the caller waits and re-polls.
  pending,

  /// The grant has been approved and the credentials are attached.
  success,

  /// The grant has timed out and must be restarted.
  expired,

  /// The grant is unknown, already used, or otherwise unusable. The
  /// caller cannot distinguish these — the same status is returned to
  /// avoid leaking distinguishing failure modes.
  notFound;

  /// Parse the wire-format status string emitted by the backend.
  static DeviceAuthorizationStatus parse(String raw) {
    for (final value in DeviceAuthorizationStatus.values) {
      if (value.name == raw) return value;
    }
    throw FormatException(
      'Unknown device-authorization status "$raw" — the server may '
      'be running a newer release than this client.',
    );
  }
}

/// Response from `auth.startDeviceAuthorization`.
@experimental
@immutable
class DeviceAuthorizationStart {
  /// Construct a start response.
  const DeviceAuthorizationStart({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresInSeconds,
    required this.pollIntervalSeconds,
  });

  /// Opaque secret the caller presents on subsequent polls.
  final String deviceCode;

  /// Short, human-readable code the user types into the dashboard.
  final String userCode;

  /// URL the user visits to enter the [userCode].
  final String verificationUri;

  /// Grant lifetime in seconds — beyond which `exchangeDeviceCode`
  /// returns `expired`.
  final int expiresInSeconds;

  /// Advisory delay between polls, in seconds.
  final int pollIntervalSeconds;

  /// Decode from the backend's JSON-shaped wire payload. Tolerates the
  /// trailing `__className__` discriminator the server emits.
  factory DeviceAuthorizationStart.fromJson(Map<String, dynamic> json) =>
      DeviceAuthorizationStart(
        deviceCode: json['deviceCode']! as String,
        userCode: json['userCode']! as String,
        verificationUri: json['verificationUri']! as String,
        expiresInSeconds: json['expiresInSeconds']! as int,
        pollIntervalSeconds: json['pollIntervalSeconds']! as int,
      );
}

/// Reply from a single `exchangeDeviceCode` poll.
@experimental
@immutable
class DeviceAuthorizationResult {
  /// Construct a result.
  const DeviceAuthorizationResult({
    required this.status,
    this.keyId,
    this.key,
    this.userInfo,
    this.pollIntervalSeconds,
  });

  /// Current state of the grant.
  final DeviceAuthorizationStatus status;

  /// AuthKey row id — populated on [DeviceAuthorizationStatus.success].
  final int? keyId;

  /// AuthKey secret half — populated on [DeviceAuthorizationStatus.success].
  final String? key;

  /// Authenticated user — populated on [DeviceAuthorizationStatus.success].
  final CliUserInfo? userInfo;

  /// Advisory poll interval — populated on
  /// [DeviceAuthorizationStatus.pending].
  final int? pollIntervalSeconds;

  /// Decode from the backend's JSON-shaped wire payload.
  factory DeviceAuthorizationResult.fromJson(Map<String, dynamic> json) =>
      DeviceAuthorizationResult(
        status: DeviceAuthorizationStatus.parse(json['status']! as String),
        keyId: json['keyId'] as int?,
        key: json['key'] as String?,
        userInfo: json['userInfo'] == null
            ? null
            : CliUserInfo.fromJson(json['userInfo']! as Map<String, dynamic>),
        pollIntervalSeconds: json['pollIntervalSeconds'] as int?,
      );
}

/// Slim view of the backend's `UserInfo` — only the fields the
/// command-line surface displays. The wire payload may carry additional
/// fields; unknown fields are ignored.
@experimental
@immutable
class CliUserInfo {
  /// Construct a user-info snapshot.
  const CliUserInfo({this.id, this.email});

  /// Numeric user id, if present in the payload.
  final int? id;

  /// Primary email, if present in the payload.
  final String? email;

  /// Decode from the backend's JSON-shaped wire payload.
  factory CliUserInfo.fromJson(Map<String, dynamic> json) =>
      CliUserInfo(id: json['id'] as int?, email: json['email'] as String?);
}
