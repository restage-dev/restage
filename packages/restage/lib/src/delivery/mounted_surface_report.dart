import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show DeliverySurfaceTypeId, PlacementKeyV1;
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../early/early_request.dart';

/// The surfaces this install mounted since the last request the service
/// answered. Kept on disk, so a killed app still reports them. Entries belong
/// to the API key that delivered them: a request with another key never sends
/// them.
@internal
final class MountedSurfaceReport {
  /// Creates a report over [preferences]; tests pass their own.
  MountedSurfaceReport({
    Future<SharedPreferences> Function()? preferences,
    DateTime Function()? now,
    Future<void> Function(String scope, String fragment)? mirror,
    String? apiKey,
  })  : _preferences = preferences ?? SharedPreferences.getInstance,
        _now = now ?? DateTime.now,
        _mirror = mirror ?? EarlyRequest.setMountedSince,
        _initialScope = apiKey == null ? '' : scopeOf(apiKey);

  /// Names the API key a report belongs to: the start of the key's SHA-256.
  static String scopeOf(String apiKey) =>
      sha256.convert(utf8.encode(apiKey)).toString().substring(0, 16);

  /// The report this process keeps.
  static MountedSurfaceReport instance = MountedSurfaceReport();

  static const _key = 'restage.mounted_since';

  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _now;
  final Future<void> Function(String scope, String fragment) _mirror;
  late _Slot _slot = _open(_initialScope);
  final String _initialScope;
  Future<void> _writes = Future<void>.value();

  // One key's entries. A call keeps the slot it started in, so a key bound
  // meanwhile never receives its writes.
  _Slot _open(String scope) => _Slot(scope, () => _read(scope));

  Future<List<PlacementMountedSurfaceV1>> _read(String scope) async {
    final entries = <PlacementMountedSurfaceV1>[];
    try {
      final stored = (await _preferences()).getString(_storageKey(scope));
      if (stored != null) {
        for (final value in jsonDecode(stored) as List<Object?>) {
          try {
            entries.add(PlacementMountedSurfaceV1.fromJson(value));
          } on Object {
            // An entry that no longer decodes is dropped.
          }
        }
      }
    } on Object {
      // Unreadable storage reports nothing.
    }
    return entries;
  }

  static String _storageKey(String scope) =>
      scope.isEmpty ? _key : '$_key.$scope';

  /// The entries a request reports now, at most the most recent 64.
  Future<List<PlacementMountedSurfaceV1>> pending() async {
    final entries = await _slot.entries;
    return List.unmodifiable(entries.length > kMaximumMountedSinceSurfaces
        ? entries.sublist(entries.length - kMaximumMountedSinceSurfaces)
        : entries);
  }

  /// Notes that [slug] of [surfaceType] mounted through [placement] now.
  /// A surface already noted for the month is not noted again.
  Future<void> record({
    required PlacementKeyV1 placement,
    required DeliverySurfaceTypeId surfaceType,
    required String slug,
  }) async {
    final utc = _now().toUtc();
    final month = '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}';
    final slot = _slot;
    final entries = await slot.entries;
    if (entries.any((entry) =>
        entry.surfaceType == surfaceType &&
        entry.slug == slug &&
        entry.month == month)) {
      return;
    }
    entries.add(PlacementMountedSurfaceV1(
      placement: placement,
      surfaceType: surfaceType,
      slug: slug,
      month: month,
    ));
    if (entries.length > kMaximumMountedSinceSurfaces) {
      entries.removeRange(0, entries.length - kMaximumMountedSinceSurfaces);
    }
    await _persist(slot, entries);
  }

  /// Drops [sent] once the service answered the request that carried them.
  /// Surfaces mounted since that request was built stay.
  Future<void> acknowledge(List<PlacementMountedSurfaceV1> sent) async {
    if (sent.isEmpty) return;
    final slot = _slot;
    final entries = await slot.entries;
    final before = entries.length;
    entries.removeWhere(sent.contains);
    if (entries.length != before) await _persist(slot, entries);
  }

  /// Reports for [apiKey] from now on; those of another key stay stored.
  void bindKey(String apiKey) {
    final scope = scopeOf(apiKey);
    if (scope == _slot.scope) return;
    final slot = _slot = _open(scope);
    unawaited(_mirrorHeld(slot));
  }

  // The platform reads the report of the key its own request carries.
  Future<void> _mirrorHeld(_Slot slot) async {
    final entries = await slot.entries;
    try {
      await _mirror(slot.scope, _fragmentOf(entries));
    } on Object {
      // The platform's request then carries none; Dart's carries it.
    }
  }

  static String _fragmentOf(List<PlacementMountedSurfaceV1> entries) =>
      mountedSinceTemplateFragment(
        entries.length > kMaximumMountedSinceSurfaces
            ? entries.sublist(entries.length - kMaximumMountedSinceSurfaces)
            : entries,
      );

  Future<void> _persist(_Slot slot, List<PlacementMountedSurfaceV1> entries) {
    final scope = slot.scope;
    final text = jsonEncode([for (final entry in entries) entry.toJson()]);
    final fragment = _fragmentOf(entries);
    final write = _writes.then((_) async {
      try {
        await (await _preferences()).setString(_storageKey(scope), text);
        await _mirror(scope, fragment);
      } on Object {
        // The report stays in memory and is written with the next change.
      }
    });
    _writes = write;
    return write;
  }
}

final class _Slot {
  _Slot(this.scope, this._read);

  final String scope;
  final Future<List<PlacementMountedSurfaceV1>> Function() _read;
  List<PlacementMountedSurfaceV1>? _loaded;

  // Each call reads until one read lands, so a read cut short is retried.
  Future<List<PlacementMountedSurfaceV1>> get entries async {
    final loaded = _loaded;
    if (loaded != null) return loaded;
    final read = await _read();
    return _loaded ??= read;
  }
}
