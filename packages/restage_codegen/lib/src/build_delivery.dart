import 'package:build/build.dart';
import 'package:restage_shared/restage_shared.dart' show canonicalServiceUrl;

/// The publishable key, service URL and delivery channel build.yaml sets for
/// an app.
typedef BuildDelivery = ({String apiKey, String baseUrl, String? channel});

/// The `api_key`, `base_url` and `channel` options as build.yaml spells them.
typedef BuildDeliverySettings = ({
  String? apiKey,
  String? baseUrl,
  String? channel,
});

/// The generated constant holding the build's publishable key.
const String kBuildApiKeyName = '_restageApiKey';

/// The generated constant holding the build's service URL.
const String kBuildBaseUrlName = '_restageBaseUrl';

/// The generated constant holding the build's delivery channel.
const String kBuildChannelName = '_restageChannel';

/// The `api_key`, `base_url` and `channel` options of the root package's
/// `restage_codegen:user_factories` builder; the service URL in canonical
/// form.
BuildDeliverySettings readBuildDeliveryOptions(BuilderOptions options) {
  if (!options.isRoot) return (apiKey: null, baseUrl: null, channel: null);
  final baseUrl = _option(options, 'base_url');
  final canonical = baseUrl == null ? null : canonicalServiceUrl(baseUrl);
  return (
    apiKey: _option(options, 'api_key'),
    baseUrl: canonical == null || canonical.isEmpty ? null : canonical,
    channel: _option(options, 'channel'),
  );
}

/// The settings as a delivery, or null when the key or URL is missing.
BuildDelivery? completeBuildDelivery(BuildDeliverySettings settings) =>
    switch (settings) {
      (apiKey: final apiKey?, baseUrl: final baseUrl?, :final channel) => (
        apiKey: apiKey,
        baseUrl: baseUrl,
        channel: channel,
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
