import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../restage_rpc_client/restage_rpc_client.dart';
import 'surface_assignment_persistence.dart';

/// Persists the registration attempt and its opaque expiring credential together.
final class SurfaceAssignmentCredentialStore {
  SurfaceAssignmentCredentialStore({
    required this.namespace,
    required this.actor,
    required this.identityGeneration,
    required this.client,
    required this.onRetentionRollover,
    int Function()? nowMicros,
  }) : _nowMicros = nowMicros ?? _utcNowMicros;

  final String namespace;
  final Future<String> Function() actor;
  final int Function() identityGeneration;
  final RestageRpcClient? Function() client;
  final void Function() onRetentionRollover;
  final int Function() _nowMicros;
  int? _generation;
  int? _observedActorGeneration;
  int _leaseGeneration = 0;
  int? _expiresAtMicros;
  Future<String?>? _pending;

  /// Changes at local identity reset or an authenticated retention rollover.
  int get generation {
    final current = identityGeneration();
    if (_observedActorGeneration != current) {
      _observedActorGeneration = current;
      _leaseGeneration += 1;
    }
    return _leaseGeneration;
  }

  Future<String?> resolve() {
    final current = identityGeneration();
    final expiry = _expiresAtMicros;
    if (_generation == current &&
        _pending != null &&
        (expiry == null || _nowMicros() < expiry)) {
      return _pending!;
    }
    _generation = current;
    _expiresAtMicros = null;
    return _pending = _resolve(current);
  }

  Future<String?> _resolve(int generation) async {
    final persistenceGeneration = SurfaceAssignmentPersistence.generation;
    final rpc = client();
    if (rpc == null) return null;
    bool isCurrent() =>
        identityGeneration() == generation &&
        identical(client(), rpc) &&
        persistenceGeneration == SurfaceAssignmentPersistence.generation;
    try {
      await SurfaceAssignmentPersistence.ready;
      if (!isCurrent()) return null;
      final identity = await actor();
      if (!isCurrent()) return null;
      final prefs = await SharedPreferences.getInstance();
      if (!isCurrent()) return null;
      final scope =
          sha256.convert(utf8.encode(jsonEncode([namespace, identity])));
      final storageKey = 'restage.assignmentRegistration.$scope';
      final stored = prefs.getString(storageKey);
      Map<String, dynamic>? registration =
          stored == null ? null : jsonDecode(stored) as Map<String, dynamic>;
      final heldExpiry = registration?['expiresAtMicros'] as int?;
      if (heldExpiry != null && _nowMicros() >= heldExpiry) {
        registration = null;
        _leaseGeneration += 1;
        onRetentionRollover();
      }
      if (registration == null) {
        final random = Random.secure();
        registration = {
          'registrationNonce': base64UrlEncode(
            List<int>.generate(32, (_) => random.nextInt(256)),
          ).replaceAll('=', ''),
          'registrationCreatedAtMicros': _nowMicros(),
        };
      }
      // SharedPreferences updates its memory cache even when a platform write
      // fails. Confirm durability on every retry before sending this attempt.
      if (!await SurfaceAssignmentPersistence.writeString(
        storageKey,
        jsonEncode(registration),
        generation: persistenceGeneration,
      )) {
        if (isCurrent()) _pending = null;
        return null;
      }
      if (!isCurrent()) return null;
      final previousHandle = registration['credentialHandle'] as String?;
      final issued = await rpc.registerAssignmentCredential(
        registrationNonce: registration['registrationNonce'] as String,
        registrationCreatedAtMicros:
            registration['registrationCreatedAtMicros'] as int,
        credentialHandle: previousHandle,
      );
      if (!isCurrent() ||
          issued == null ||
          (previousHandle != null &&
              (issued.credentialHandle != previousHandle ||
                  issued.expiresAtMicros != heldExpiry))) {
        if (isCurrent()) _pending = null;
        return null;
      }
      final persistedRegistration = {
        ...registration,
        'credentialHandle': issued.credentialHandle,
        'expiresAtMicros': issued.expiresAtMicros,
      };
      if (!await SurfaceAssignmentPersistence.writeString(
          storageKey, jsonEncode(persistedRegistration),
          generation: persistenceGeneration)) {
        if (isCurrent()) _pending = null;
        return null;
      }
      if (!isCurrent()) return null;
      _expiresAtMicros = issued.expiresAtMicros;
      return issued.credentialHandle;
    } on Object {
      if (isCurrent()) _pending = null;
      return null;
    }
  }

  static int _utcNowMicros() => DateTime.now().toUtc().microsecondsSinceEpoch;
}
