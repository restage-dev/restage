import 'package:meta/meta.dart';
import 'package:restage_shared/src/analytics/analytics_wire_enums.dart';

/// Client app context attached to a client-sourced `AnalyticsEvent`.
///
/// Required for `source=client` events; absent for server / app-wide events.
/// `platform` is an unknown-preserving wire string (see [AnalyticsPlatform]).
@immutable
final class AnalyticsAppContext {
  /// Creates an app context.
  const AnalyticsAppContext({
    required this.platform,
    required this.locale,
    required this.sdkVersion,
    this.appVersion,
    this.appBuild,
  });

  /// Decodes from a JSON map. Fails loud ([FormatException]) on a missing or
  /// non-string required field.
  factory AnalyticsAppContext.fromJson(Map<String, Object?> json) {
    return AnalyticsAppContext(
      platform: _requireString(json, 'platform'),
      locale: _requireString(json, 'locale'),
      sdkVersion: _requireString(json, 'sdkVersion'),
      appVersion: _optionalString(json, 'appVersion'),
      appBuild: _optionalString(json, 'appBuild'),
    );
  }

  /// Reporting platform (`ios`/`android`/…). Unknown-preserving wire string.
  final String platform;

  /// BCP-47-ish locale (e.g. `en_US`).
  final String locale;

  /// The Restage SDK version.
  final String sdkVersion;

  /// Host app version (e.g. `2.3.1`), if known.
  final String? appVersion;

  /// Host app build (e.g. `42`), if known.
  final String? appBuild;

  /// Encodes to a JSON map. Optional fields are omitted when null.
  Map<String, Object?> toJson() => <String, Object?>{
        'platform': platform,
        'locale': locale,
        'sdkVersion': sdkVersion,
        if (appVersion != null) 'appVersion': appVersion,
        if (appBuild != null) 'appBuild': appBuild,
      };

  @override
  bool operator ==(Object other) =>
      other is AnalyticsAppContext &&
      other.platform == platform &&
      other.locale == locale &&
      other.sdkVersion == sdkVersion &&
      other.appVersion == appVersion &&
      other.appBuild == appBuild;

  @override
  int get hashCode =>
      Object.hash(platform, locale, sdkVersion, appVersion, appBuild);
}

String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException(
    'AnalyticsAppContext.$key must be a non-null string, got: $value',
  );
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException(
    'AnalyticsAppContext.$key must be a string when present, got: $value',
  );
}
