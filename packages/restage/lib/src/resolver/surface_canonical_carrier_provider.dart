import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'surface_assignment_key_provider.dart';
import 'surface_assignment_persistence.dart';

/// Internal audience observations and exact per-surface held assignments.
/// Providers are optional; configured assignment retention is scoped to the
/// current target and issued credential.
abstract final class SurfaceCanonicalCarrierProvider {
  static FutureOr<String?> Function()? _builtIns;
  static FutureOr<String?> Function()? _heldAssignment;
  static String? _storageScope;
  static final Map<(String, String, int?, String), String> _assignments = {};

  /// Enables retention within the current configured identity authority.
  static void enableAssignmentRetention(String storageScope) {
    _storageScope = storageScope;
    _heldAssignment = null;
    _assignments.clear();
  }

  /// Retains only an assignment admitted under the still-current identity.
  static Future<void> retain({
    required String surface,
    required String slug,
    int? contractVersion,
    required SurfaceAssignmentResolutionLease lease,
    required CanonicalSurfaceExperimentAssignmentV1? assignment,
  }) async {
    final persistenceGeneration = SurfaceAssignmentPersistence.generation;
    final storageScope = _storageScope;
    final key = lease.assignmentKey;
    if (storageScope == null ||
        !lease.isCurrent ||
        key == null ||
        assignment == null) {
      return;
    }
    final scope = (surface, slug, contractVersion, key);
    final encoded = _encode(assignment);
    _assignments[scope] = encoded;
    try {
      await SurfaceAssignmentPersistence.ready;
      if (lease.isCurrent && _storageScope == storageScope) {
        await SurfaceAssignmentPersistence.writeString(
          _storageKey(storageScope, scope),
          encoded,
          generation: persistenceGeneration,
        );
      }
    } on Object {
      // The current session still retains the issued assignment.
    }
  }

  /// Installs the audience-observation carrier source.
  @internal
  static void installBuiltIns(FutureOr<String?> Function()? provider) =>
      _builtIns = provider;

  /// Installs the source of the assignment this build already holds.
  @internal
  static void installHeldAssignment(FutureOr<String?> Function()? provider) =>
      _heldAssignment = provider;

  /// Whether an audience-observation source is installed.
  @internal
  static bool get hasBuiltIns => _builtIns != null;

  /// Resolves the audience observations, or null when unavailable.
  static Future<String?> builtIns() => _resolve(_builtIns);

  /// Resolves the held assignment, or null when this build holds none.
  static Future<String?> heldAssignment({
    String? surface,
    String? slug,
    int? contractVersion,
    String? assignmentKey,
  }) async {
    final persistenceGeneration = SurfaceAssignmentPersistence.generation;
    final storageScope = _storageScope;
    if (storageScope == null ||
        surface == null ||
        slug == null ||
        assignmentKey == null) {
      return _resolve(_heldAssignment);
    }
    final scope = (surface, slug, contractVersion, assignmentKey);
    final held = _assignments[scope];
    if (held != null) return held;
    try {
      await SurfaceAssignmentPersistence.ready;
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(_storageKey(storageScope, scope));
      if (_storageScope != storageScope ||
          persistenceGeneration != SurfaceAssignmentPersistence.generation ||
          encoded == null) {
        return null;
      }
      CanonicalSurfaceExperimentAssignmentV1Codec.decodeJson(
        utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
      );
      _assignments[scope] = encoded;
      return encoded;
    } on Object {
      return null;
    }
  }

  /// Whether [assignment] is the one this build holds for the surface under
  /// [assignmentKey].
  @internal
  static Future<bool> holds({
    required String surface,
    required String slug,
    int? contractVersion,
    required String assignmentKey,
    required CanonicalSurfaceExperimentAssignmentV1 assignment,
  }) async {
    if (_storageScope == null) return false;
    final held = await heldAssignment(
      surface: surface,
      slug: slug,
      contractVersion: contractVersion,
      assignmentKey: assignmentKey,
    );
    return held != null && held == _encode(assignment);
  }

  /// Retains the exact opaque carrier under its mount and current credential.
  @internal
  static Future<void> retainPlacement({
    required PlacementMountRequestV1 mount,
    required SurfaceAssignmentResolutionLease lease,
    required PresentationAssignmentCarrierV2 assignment,
  }) async {
    final generation = SurfaceAssignmentPersistence.generation;
    final namespace = _storageScope;
    final key = lease.assignmentKey;
    if (namespace == null || key == null || !lease.isCurrent) return;
    final scope = _placementScope(mount, key);
    final encoded =
        base64UrlEncode(assignment.canonicalBytes).replaceAll('=', '');
    _assignments[scope] = encoded;
    try {
      await SurfaceAssignmentPersistence.ready;
      if (lease.isCurrent && _storageScope == namespace) {
        await SurfaceAssignmentPersistence.writeString(
            _storageKey(namespace, scope), encoded,
            generation: generation);
      }
    } on Object {
      // The current presentation still retains its issued assignment.
    }
  }

  /// Forgets a placement carrier the server no longer proves.
  @internal
  static Future<void> forgetPlacement({
    required PlacementMountRequestV1 mount,
    required String assignmentKey,
  }) async {
    final generation = SurfaceAssignmentPersistence.generation;
    final namespace = _storageScope;
    if (namespace == null) return;
    final scope = _placementScope(mount, assignmentKey);
    _assignments.remove(scope);
    try {
      await SurfaceAssignmentPersistence.remove(_storageKey(namespace, scope),
          generation: generation);
    } on Object {
      // The in-memory carrier is already gone for this session.
    }
  }

  /// Reads only an original retained carrier; it establishes no new authority.
  @internal
  static Future<String?> heldPlacement({
    required PlacementMountRequestV1 mount,
    required String assignmentKey,
  }) async {
    final namespace = _storageScope;
    if (namespace == null) return null;
    final generation = SurfaceAssignmentPersistence.generation;
    final scope = _placementScope(mount, assignmentKey);
    final held = _assignments[scope];
    if (held != null) return held;
    try {
      await SurfaceAssignmentPersistence.ready;
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(_storageKey(namespace, scope));
      if (_storageScope != namespace ||
          generation != SurfaceAssignmentPersistence.generation ||
          encoded == null) {
        return null;
      }
      PresentationAssignmentCarrierV2.fromCanonicalBytes(
          base64Url.decode(base64Url.normalize(encoded)));
      _assignments[scope] = encoded;
      return encoded;
    } on Object {
      return null;
    }
  }

  static (String, String, int?, String) _placementScope(
          PlacementMountRequestV1 mount, String key) =>
      ('placement', sha256.convert(mount.canonicalBytes).toString(), null, key);

  static String _encode(CanonicalSurfaceExperimentAssignmentV1 assignment) =>
      base64UrlEncode(utf8.encode(
        CanonicalSurfaceExperimentAssignmentV1Codec.encodeCanonicalJson(
            assignment),
      )).replaceAll('=', '');

  /// Releases held in-memory assignments after an authenticated credential rollover.
  static void clearHeldAssignments() => _assignments.clear();

  /// Clears both providers.
  static void clear() {
    _builtIns = null;
    _heldAssignment = null;
    _storageScope = null;
    _assignments.clear();
  }

  static String _storageKey(
      String namespace, (String, String, int?, String) scope) {
    final encodedScope = jsonEncode([
      namespace,
      scope.$1,
      scope.$2,
      scope.$3,
      scope.$4,
    ]);
    return 'restage.assignment.${sha256.convert(utf8.encode(encodedScope))}';
  }

  static Future<String?> _resolve(
      FutureOr<String?> Function()? provider) async {
    if (provider == null) return null;
    try {
      final value = await provider();
      return (value == null || value.isEmpty) ? null : value;
    } on Object {
      return null;
    }
  }
}
