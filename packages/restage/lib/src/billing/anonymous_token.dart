import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists an opaque anonymous app-user token used to thread the same
/// purchaser identity through store-side fields. The token is passed via
/// `PurchaseParam.applicationUserName`, which platforms route to Apple
/// `appAccountToken` and Google `obfuscatedAccountId`.
///
/// The token is a UUIDv4 string. Apple's StoreKit 2 silently drops a
/// non-UUID value passed to `appAccountToken`, so the validation guard
/// keeps the SDK honest against accidental corruption of the persisted
/// value.
///
/// Persistence is best-effort and does not survive an app uninstall.
/// Re-installs produce a fresh token; transactions reported under the prior
/// token are reconciled by the server via store transaction identifiers.
class AnonymousTokenStore {
  /// Creates a store. [prefsProvider] is the seam tests use to inject a
  /// fixture; production callers omit it and pick up
  /// [SharedPreferences.getInstance].
  AnonymousTokenStore({Future<SharedPreferences> Function()? prefsProvider})
      : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  /// Key under which the token is persisted in `shared_preferences`.
  static const _prefsKey = 'restage.anonymous_app_user_token';

  final Future<SharedPreferences> Function() _prefsProvider;

  String? _cached;

  /// Returns the persisted token, generating + persisting a new UUIDv4 on
  /// first run. Subsequent calls return the cached value without touching
  /// shared preferences.
  Future<String> getOrCreate() async {
    final cached = _cached;
    if (cached != null) return cached;
    final prefs = await _prefsProvider();
    final persisted = prefs.getString(_prefsKey);
    if (persisted != null && isValidUuid(persisted)) {
      _cached = persisted;
      return persisted;
    }
    final fresh = generateUuidV4();
    await prefs.setString(_prefsKey, fresh);
    _cached = fresh;
    return fresh;
  }

  /// The cached token if [getOrCreate] has resolved at least once,
  /// otherwise null. Synchronous; safe to call from hot paths (e.g.
  /// purchase initiation) where awaiting is undesirable.
  String? get cached => _cached;

  /// Returns true if [value] is a canonical-form UUIDv4 string.
  ///
  /// Checks length, dash placement, hex digits, version nibble (4), and
  /// variant nibble (8, 9, a, or b — case-insensitive).
  static bool isValidUuid(String value) {
    if (value.length != 36) return false;
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (i == 8 || i == 13 || i == 18 || i == 23) {
        if (c != 0x2D) return false;
        continue;
      }
      final isHex = (c >= 0x30 && c <= 0x39) ||
          (c >= 0x61 && c <= 0x66) ||
          (c >= 0x41 && c <= 0x46);
      if (!isHex) return false;
    }
    if (value.codeUnitAt(14) != 0x34) return false;
    final variant = value.codeUnitAt(19);
    final isVariant = variant == 0x38 ||
        variant == 0x39 ||
        variant == 0x61 ||
        variant == 0x62 ||
        variant == 0x41 ||
        variant == 0x42;
    return isVariant;
  }

  /// Generates a UUIDv4 from a CSPRNG (or the supplied [random] for
  /// tests). The output is the canonical 36-character string with the
  /// version nibble forced to 4 and the variant nibble forced to 8-b per
  /// RFC 4122 §4.4.
  static String generateUuidV4({Random? random}) {
    final r = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
