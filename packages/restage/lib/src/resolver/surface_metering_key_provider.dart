import '../metering/metering_token_store.dart';

/// Process-global source of the metering-only identity attached to hosted
/// surface-serve requests.
abstract final class SurfaceMeteringKeyProvider {
  static MeteringTokenStore? _store;

  static void install({required MeteringTokenStore store}) => _store = store;

  static void clear() => _store = null;

  /// Resolves the current metering key (minting+persisting on first use), or
  /// null when no provider is installed. Never throws — a prefs fault yields
  /// null so a serve is metered as tokenless rather than failing.
  static Future<String?> currentKey() async {
    final store = _store;
    if (store == null) {
      return null;
    }
    try {
      return await store.getOrCreate();
    } on Object {
      return null;
    }
  }
}
