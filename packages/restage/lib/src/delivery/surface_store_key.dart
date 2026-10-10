import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// Identifies one stored surface: the install's delivery scope, the surface,
/// and the contract version the app was built against.
@internal
@immutable
final class SurfaceStoreKey {
  /// Creates a key.
  const SurfaceStoreKey({
    required this.scope,
    required this.surfaceType,
    required this.slug,
    required this.contractVersion,
  });

  /// The scope for [apiKey] in [environment]: the first 16 hex characters of
  /// their SHA-256.
  static String scopeFor({
    required String apiKey,
    required String environment,
    String? baseUrl,
  }) =>
      configurationFingerprintFor(
              apiKey: apiKey, environment: environment, baseUrl: baseUrl)
          .substring(0, 16);

  /// Stable configured delivery authority, without retaining the credential.
  static String configurationFingerprintFor({
    required String apiKey,
    required String environment,
    String? baseUrl,
  }) =>
      sha256
          .convert(utf8.encode(baseUrl == null
              ? '$apiKey\u0000$environment'
              : '${normalizedOrigin(baseUrl)}\u0000$apiKey\u0000$environment'))
          .toString();

  /// Normalizes the configured service endpoint for local delivery isolation.
  static String normalizedOrigin(String value) {
    final uri = Uri.parse(value);
    final scheme = uri.scheme.toLowerCase();
    final port = uri.hasPort &&
            !((scheme == 'https' && uri.port == 443) ||
                (scheme == 'http' && uri.port == 80))
        ? ':${uri.port}'
        : '';
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return '$scheme://${uri.host.toLowerCase()}$port$path'
        '${uri.hasQuery ? '?${uri.query}' : ''}';
  }

  /// The delivery scope; see [scopeFor].
  final String scope;

  /// `paywall`, `screen`, `onboarding`, `message` or `survey`.
  final String surfaceType;

  /// The surface slug.
  final String slug;

  /// The bundled or compiled contract version; 0 when none applies.
  final int contractVersion;

  /// The JSON form stored beside each entry.
  Map<String, Object?> toJson() => <String, Object?>{
        'scope': scope,
        'surfaceType': surfaceType,
        'slug': slug,
        'contractVersion': contractVersion,
      };

  /// Parses [toJson] output; null when malformed.
  static SurfaceStoreKey? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final scope = json['scope'];
    final surfaceType = json['surfaceType'];
    final slug = json['slug'];
    final contractVersion = json['contractVersion'];
    if (scope is! String ||
        surfaceType is! String ||
        slug is! String ||
        contractVersion is! int) {
      return null;
    }
    return SurfaceStoreKey(
      scope: scope,
      surfaceType: surfaceType,
      slug: slug,
      contractVersion: contractVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SurfaceStoreKey &&
      other.scope == scope &&
      other.surfaceType == surfaceType &&
      other.slug == slug &&
      other.contractVersion == contractVersion;

  @override
  int get hashCode => Object.hash(scope, surfaceType, slug, contractVersion);

  @override
  String toString() =>
      'SurfaceStoreKey($scope, $surfaceType, $slug, $contractVersion)';
}
