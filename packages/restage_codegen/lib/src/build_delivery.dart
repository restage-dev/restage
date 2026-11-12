import 'package:build/build.dart';
import 'package:restage_shared/restage_shared.dart' show canonicalServiceUrl;

/// The publishable key, service URL, delivery channel and analytics default
/// build.yaml sets for an app.
typedef BuildDelivery = ({
  String apiKey,
  String baseUrl,
  String? channel,
  bool analytics,
});

/// The `api_key`, `base_url`, `channel` and `analytics` options as build.yaml
/// spells them; `analytics` is true unless set to false.
typedef BuildDeliverySettings = ({
  String? apiKey,
  String? baseUrl,
  String? channel,
  bool analytics,
});

/// The generated constant holding the build's publishable key.
const String kBuildApiKeyName = '_restageApiKey';

/// The generated constant holding the build's service URL.
const String kBuildBaseUrlName = '_restageBaseUrl';

/// The generated constant holding the build's delivery channel.
const String kBuildChannelName = '_restageChannel';

/// The generated constant holding the build's analytics default.
const String kBuildAnalyticsName = '_restageAnalytics';

/// The generated constant holding the build's delivery keys.
const String kBuildDeliveryKeysName = '_restageDeliveryKeys';

/// The `delivery_keys` option of the root package's
/// `restage_codegen:user_factories` builder, each
/// `<organizationId>:<base64url key>` as `restage keys delivery` prints it.
List<String> readBuildDeliveryKeys(BuilderOptions options) {
  if (!options.isRoot) return const [];
  final value = options.config['delivery_keys'];
  if (value == null) return const [];
  if (value is! List ||
      value.any((key) => key is! String || key.trim().isEmpty)) {
    throw ArgumentError.value(
      value,
      'delivery_keys',
      'The delivery_keys option of restage_codegen:user_factories takes a '
          'list of keys as `restage keys delivery` prints them. Try running '
          '`restage init`, which writes it.',
    );
  }
  return [for (final key in value) (key as String).trim()];
}

/// The `api_key`, `base_url` and `channel` options of the root package's
/// `restage_codegen:user_factories` builder; the service URL in canonical
/// form.
BuildDeliverySettings readBuildDeliveryOptions(BuilderOptions options) {
  if (!options.isRoot) {
    return (apiKey: null, baseUrl: null, channel: null, analytics: true);
  }
  final analytics = options.config['analytics'] ?? true;
  if (analytics is! bool) {
    throw ArgumentError.value(
      analytics,
      'analytics',
      'The analytics option of restage_codegen:user_factories takes true or '
          'false. Try `analytics: true` or `analytics: false`.',
    );
  }
  final baseUrl = _option(options, 'base_url');
  final canonical = baseUrl == null ? null : canonicalServiceUrl(baseUrl);
  return (
    apiKey: _option(options, 'api_key'),
    baseUrl: canonical == null || canonical.isEmpty ? null : canonical,
    channel: _option(options, 'channel'),
    analytics: analytics,
  );
}

/// The settings as a delivery, or null when the key or URL is missing.
BuildDelivery? completeBuildDelivery(BuildDeliverySettings settings) =>
    switch (settings) {
      (
        apiKey: final apiKey?,
        baseUrl: final baseUrl?,
        :final channel,
        :final analytics,
      ) =>
        (
          apiKey: apiKey,
          baseUrl: baseUrl,
          channel: channel,
          analytics: analytics,
        ),
      _ => null,
    };

String? _option(BuilderOptions options, String key) {
  final value = options.config[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

/// The one build line for an app whose build carries no publishable key and
/// service URL, or null when both are set.
String? missingBuildDeliveryLine(BuildDeliverySettings settings) {
  if (settings.apiKey == null) {
    return "The first-launch request isn't built in: no publishable key. "
        'Try `restage init --sdk-key rs_pk_...`.';
  }
  if (settings.baseUrl == null) {
    return "The first-launch request isn't built in, and the app runs "
        'offline: no service URL. Try setting `base_url` next to `api_key` '
        'under restage_codegen:user_factories in build.yaml, for example '
        '`base_url: https://api.restage.dev`.';
  }
  return null;
}
