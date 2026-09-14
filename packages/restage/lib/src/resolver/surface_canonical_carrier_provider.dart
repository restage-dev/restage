import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';
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
    final encoded = base64UrlEncode(utf8.encode(
      CanonicalSurfaceExperimentAssignmentV1Codec.encodeCanonicalJson(
          assignment),
    )).replaceAll('=', '');
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
