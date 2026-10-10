import 'dart:math' show max, min;

import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show kMaximumPortableJsonInteger;
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the first SDK-observed launch, independently of user identity.
/// Root-isolate stores sharing a preferences instance share initialization.
final class FirstLaunchStore {
  FirstLaunchStore({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  static const _key = 'restage.first_launch_utc';
  static final _initializations = Expando<Future<DateTime?>>();

  final Future<SharedPreferences> Function() _preferences;
  Future<DateTime?>? _initialization;

  /// Returns a persisted UTC origin, or unknown if storage cannot confirm it.
  /// An existing corrupt value is left intact; only an absent key is created.
  Future<DateTime?> readOrCreate(DateTime nowUtc) =>
      _initialization ??= _resolve(nowUtc.toUtc()).whenComplete(() {
        _initialization = null;
      });

  Future<DateTime?> _resolve(DateTime nowUtc) async {
    try {
      final preferences = await _preferences();
      final existing = _initializations[preferences];
      if (existing != null) return await existing;

      final initialization =
          _readOrCreate(preferences, nowUtc).whenComplete(() {
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
    // A failed platform write can still change the preferences cache.
    await preferences.reload();
    if (preferences.containsKey(_key)) {
      final stored = preferences.get(_key);
      if (stored is! String) return null;
      final firstLaunch = DateTime.tryParse(stored);
      if (firstLaunch == null ||
          !firstLaunch.isUtc ||
          firstLaunch.toIso8601String() != stored) {
        return null;
      }
      return firstLaunch;
    }

    final written = await preferences.setString(_key, nowUtc.toIso8601String());
    return written ? nowUtc : null;
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
