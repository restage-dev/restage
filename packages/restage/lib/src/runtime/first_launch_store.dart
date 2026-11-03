import 'dart:math' show max, min;

import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show kMaximumPortableJsonInteger;
import 'package:shared_preferences/shared_preferences.dart';

import 'native_facts.dart';

/// Persists the first SDK-observed launch, independently of user identity.
/// Root-isolate stores sharing a preferences instance share initialization.
final class FirstLaunchStore {
  FirstLaunchStore({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  static const _key = 'restage.first_launch_utc';
  static final _initializations = Expando<Future<DateTime?>>();
  // Cached origins whose platform write has not succeeded, per preferences.
  static final _unconfirmed = Expando<bool>();
  static final _writes = Expando<Future<void>>();

  final Future<SharedPreferences> Function() _preferences;
  Future<DateTime?>? _initialization;
  SharedPreferences? _resolved;

  /// Whether the last origin read is not yet stored; reading again retries it.
  bool get unconfirmed {
    final preferences = _resolved;
    return preferences != null && _unconfirmed[preferences] == true;
  }

  /// Returns the UTC origin, or unknown if storage cannot be read. A new
  /// origin is returned at once; its write runs alone and a failed one is
  /// retried on the next read. An existing corrupt value is left intact.
  Future<DateTime?> readOrCreate(DateTime nowUtc) =>
      _initialization ??= _resolve(nowUtc.toUtc()).whenComplete(() {
        _initialization = null;
      });

  Future<DateTime?> _resolve(DateTime nowUtc) async {
    try {
      final preferences = await _preferences();
      _resolved = preferences;
      final existing = _initializations[preferences];
      if (existing != null) return await existing;

      final native = (NativeFacts.available
          ? await NativeFacts.fact('firstLaunchMicros')
          : null);
      final origin = native is int && native > 0
          ? DateTime.fromMicrosecondsSinceEpoch(native, isUtc: true)
          : nowUtc;
      final initialization =
          _readOrCreate(preferences, origin).whenComplete(() {
        _initializations[preferences] = null;
      });
      _initializations[preferences] = initialization;
      return await initialization;
    } on Object {
      return null;
    }
  }

  static Future<DateTime?> _readOrCreate(
    SharedPreferences preferences,
    DateTime nowUtc,
  ) async {
    // The cache is shared with the app, so it is never reloaded: a reload
    // would drop writes made while it runs.
    if (preferences.containsKey(_key)) {
      final stored = preferences.get(_key);
      if (stored is! String) return null;
      final firstLaunch = DateTime.tryParse(stored);
      if (firstLaunch == null ||
          !firstLaunch.isUtc ||
          firstLaunch.toIso8601String() != stored) {
        return null;
      }
      if (_unconfirmed[preferences] == true) _persist(preferences, stored);
      return firstLaunch;
    }
    _persist(preferences, nowUtc.toIso8601String());
    return nowUtc;
  }

  // setString updates the cache at once; one platform write runs at a time.
  static void _persist(SharedPreferences preferences, String stored) {
    if (_writes[preferences] != null) return;
    _unconfirmed[preferences] = true;
    _writes[preferences] = () async {
      try {
        if (await preferences.setString(_key, stored)) {
          _unconfirmed[preferences] = null;
        }
      } on Object {
        // Left unconfirmed; the next read retries.
      } finally {
        _writes[preferences] = null;
      }
    }();
  }
}

/// Whole elapsed UTC days since the first observed launch, unknown if absent.
int? daysSinceInstall({
  required DateTime nowUtc,
  required DateTime? firstLaunchUtc,
}) =>
    firstLaunchUtc == null
        ? null
        : min(
            kMaximumPortableJsonInteger,
            max(0, nowUtc.toUtc().difference(firstLaunchUtc.toUtc()).inDays),
          );
