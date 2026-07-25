import 'package:restage/src/billing/anonymous_token.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists a pseudonymous, metering-only identifier used to count distinct
/// delivery/serve activity per app. It is sent ONLY to the surface-serve
/// delivery endpoint (never into the analytics event stream) and is minted
/// independently of the analytics opt-out. A UUIDv4 in shared_preferences;
/// best-effort; re-minted after an app uninstall.
final class MeteringTokenStore {
  MeteringTokenStore({
    Future<SharedPreferences> Function()? prefsProvider,
  }) : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  static const _prefsKey = 'restage.metering_token';

  final Future<SharedPreferences> Function() _prefsProvider;
  String? _cached;

  String? get cached => _cached;

  Future<String> getOrCreate() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }

    final prefs = await _prefsProvider();
    final persisted = prefs.getString(_prefsKey);
    if (persisted != null && isValidUuid(persisted)) {
      _cached = persisted;
      return persisted;
    }

    final token = generateUuidV4();
    await prefs.setString(_prefsKey, token);
    _cached = token;
    return token;
  }

  /// Delegates to the shared UUIDv4 helpers so the metering token and the
  /// billing anonymous token can never validate/mint by divergent rules.
  static bool isValidUuid(String value) =>
      AnonymousTokenStore.isValidUuid(value);

  static String generateUuidV4() => AnonymousTokenStore.generateUuidV4();
}
