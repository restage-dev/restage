import 'package:meta/meta.dart';

import '../restage_rpc_client/uuid_v4.dart';

/// Internal provider for the existing analytics identifier sent with hosted
/// active requests. Absent unless analytics is enabled.
abstract final class SurfaceAnalyticsIdentityProvider {
  static Future<String?> Function()? _current;

  static int _generation = 0;

  /// Monotonic generation of the analytics provider.
  static int get generation => _generation;

  @internal
  static void install(Future<String?> Function() anonymousId) {
    if (_current != anonymousId) _generation += 1;
    _current = anonymousId;
  }

  @internal
  static void clear() {
    _generation += 1;
    _current = null;
  }

  /// Resolves the identifier, or null when analytics is disabled or degraded.
  static Future<String?> anonymousId() async {
    final provider = _current;
    if (provider == null) return null;
    try {
      final value = await provider();
      return value != null && isValidUuidV4(value) ? value : null;
    } on Object {
      return null;
    }
  }
}
