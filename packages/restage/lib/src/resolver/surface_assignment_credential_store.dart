import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'surface_assignment_persistence.dart';

/// One durable registration identity and the handle already confirmed for it.
final class SurfaceRegistrationAttempt {
  const SurfaceRegistrationAttempt({
    required this.registrationNonce,
    required this.registrationCreatedAtMicros,
    required this.generation,
    required this.fingerprint,
    this.credentialHandle,
  });

  final String registrationNonce;
  final int registrationCreatedAtMicros;
  final int generation;

  /// Namespace-bound digest of the durable tuple, safe for local worker metadata.
  final String fingerprint;
  final String? credentialHandle;

  Map<String, Object?> get tuple => {
        'registrationNonce': registrationNonce,
        'registrationCreatedAtMicros': registrationCreatedAtMicros,
      };
}

/// Persists a registration tuple before it can be sent on a surface request.
final class SurfaceAssignmentCredentialStore {
  SurfaceAssignmentCredentialStore({
    required this.namespace,
    required this.actor,
    required this.identityGeneration,
    required this.onRetentionRollover,
    int Function()? nowMicros,
  }) : _nowMicros = nowMicros ?? _utcNowMicros;

  final String namespace;
  final Future<String> Function() actor;
  final int Function() identityGeneration;
  final void Function() onRetentionRollover;
  final int Function() _nowMicros;
  int? _observedIdentityGeneration;
  int _leaseGeneration = 0;
  _RegistrationState? _state;
  Future<SurfaceRegistrationAttempt?>? _pending;
  Future<void> _transition = Future<void>.value();

  int get generation {
    _observeIdentity();
    return _leaseGeneration;
  }

  String? get currentHandle {
    _observeIdentity();
    final state = _state;
    return state != null &&
            state.localExpiresAtMicros != null &&
            _nowMicros() < state.localExpiresAtMicros!
        ? state.handle
        : null;
  }

  void _observeIdentity() {
    final current = identityGeneration();
    if (_observedIdentityGeneration == current) return;
    _observedIdentityGeneration = current;
    _state = null;
    _pending = null;
    _leaseGeneration++;
  }

  Future<String?> resolve() async => (await capture())?.credentialHandle;

  Future<SurfaceRegistrationAttempt?> capture() {
    _observeIdentity();
    final state = _state;
    if (state != null &&
        (state.localExpiresAtMicros == null ||
            _nowMicros() < state.localExpiresAtMicros!)) {
      return Future.value(_attempt(state));
    }
    final pending = _pending;
    if (pending != null) return pending;
    late final Future<SurfaceRegistrationAttempt?> next;
    next = _loadOrMint().whenComplete(() {
      if (identical(_pending, next)) _pending = null;
    });
    return _pending = next;
  }

  SurfaceRegistrationAttempt _attempt(_RegistrationState state) =>
      SurfaceRegistrationAttempt(
        registrationNonce: state.nonce,
        registrationCreatedAtMicros: state.createdAtMicros,
        generation: _leaseGeneration,
        fingerprint: _fingerprint(state),
        credentialHandle: state.handle,
      );

  String _fingerprint(_RegistrationState state) => sha256
      .convert(utf8.encode(jsonEncode([
        'restage.registration.v1',
        namespace,
        state.nonce,
        state.createdAtMicros,
      ])))
      .toString();

  Future<SurfaceRegistrationAttempt?> _loadOrMint() async {
    final identityGenerationAtStart = identityGeneration();
    final persistenceGeneration = SurfaceAssignmentPersistence.generation;
    try {
      await SurfaceAssignmentPersistence.ready;
      final identity = await actor();
      final prefs = await SharedPreferences.getInstance();
      if (identityGeneration() != identityGenerationAtStart ||
          persistenceGeneration != SurfaceAssignmentPersistence.generation) {
        return null;
      }
      final storageKey = _keyFor(identity);
      final stored = prefs.getString(storageKey);
      _RegistrationState? state;
      if (stored != null) {
        try {
          state = _RegistrationState.fromJson(jsonDecode(stored));
        } on Object {
          state = null;
        }
      }
      if (state != null &&
          state.localExpiresAtMicros != null &&
          _nowMicros() >= state.localExpiresAtMicros!) {
        state = null;
        _leaseGeneration++;
        onRetentionRollover();
      }
      state ??= _RegistrationState.mint(_nowMicros());
      if (!await SurfaceAssignmentPersistence.writeString(
        storageKey,
        jsonEncode(state.toJson()),
        generation: persistenceGeneration,
      )) {
        return null;
      }
      if (identityGeneration() != identityGenerationAtStart ||
          persistenceGeneration != SurfaceAssignmentPersistence.generation) {
        return null;
      }
      _state = state;
      return _attempt(state);
    } on Object {
      return null;
    }
  }

  /// The held handle under the persisted local deadline. Never sends a request.
  Future<String?> resolveLocal() async => (await capture())?.credentialHandle;

  /// Commits only a response for the tuple and generation that were sent.
  Future<bool> confirm({
    required SurfaceRegistrationAttempt attempt,
    required int localRequestStartMicros,
    required String credentialHandle,
    required int expiresAtMicros,
    required int serverNowMicros,
  }) =>
      _orderedTransition(() async {
        final state = _matching(attempt);
        if (state == null ||
            !RegExp(r'^ic1\.[0-9a-f]{64}$').hasMatch(credentialHandle) ||
            expiresAtMicros <= 0 ||
            serverNowMicros <= 0) {
          return false;
        }
        if (state.handle != null &&
            (state.handle != credentialHandle ||
                state.serverExpiresAtMicros != expiresAtMicros)) {
          return false;
        }
        final remaining = max(0, expiresAtMicros - serverNowMicros);
        final candidateDeadline = localRequestStartMicros + remaining;
        final previousDeadline = state.localExpiresAtMicros;
        final updated = state.withConfirmation(
          credentialHandle,
          expiresAtMicros,
          previousDeadline == null
              ? candidateDeadline
              : min(previousDeadline, candidateDeadline),
        );
        return _persistCurrent(attempt, updated);
      });

  /// Retires the current local attempt after a typed registration refusal.
  Future<void> refuse(SurfaceRegistrationAttempt attempt) =>
      _orderedTransition(() async {
        if (_matching(attempt) == null) return;
        final replacement = _RegistrationState.mint(_nowMicros());
        if (!await _persistCurrent(attempt, replacement)) return;
        _leaseGeneration++;
        onRetentionRollover();
      });

  /// Retires only the durable tuple captured by the refused outbox frame.
  /// Loading inside the ordered transition makes this work after restart too.
  Future<bool> refuseFingerprint(String fingerprint) =>
      _orderedTransition(() async {
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)) return false;
        final attempt = await capture();
        if (attempt == null ||
            attempt.credentialHandle == null ||
            attempt.fingerprint != fingerprint ||
            _matching(attempt) == null) {
          return false;
        }
        final replacement = _RegistrationState.mint(_nowMicros());
        if (!await _persistCurrent(attempt, replacement)) return false;
        _leaseGeneration++;
        onRetentionRollover();
        return true;
      });

  Future<T> _orderedTransition<T>(Future<T> Function() action) {
    final next = _transition.then((_) => action());
    _transition = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  _RegistrationState? _matching(SurfaceRegistrationAttempt attempt) {
    _observeIdentity();
    final state = _state;
    return attempt.generation == _leaseGeneration &&
            state?.nonce == attempt.registrationNonce &&
            state?.createdAtMicros == attempt.registrationCreatedAtMicros
        ? state
        : null;
  }

  Future<bool> _persistCurrent(
    SurfaceRegistrationAttempt attempt,
    _RegistrationState updated,
  ) async {
    final current = _matching(attempt);
    if (current == null) return false;
    final persistenceGeneration = SurfaceAssignmentPersistence.generation;
    try {
      final identity = await actor();
      if (!identical(_matching(attempt), current)) return false;
      final wrote = await SurfaceAssignmentPersistence.writeString(
        _keyFor(identity),
        jsonEncode(updated.toJson()),
        generation: persistenceGeneration,
      );
      if (!wrote || !identical(_matching(attempt), current)) return false;
      _state = updated;
      return true;
    } on Object {
      return false;
    }
  }

  String _keyFor(String identity) =>
      'restage.assignmentRegistration.${sha256.convert(utf8.encode(jsonEncode([
            namespace,
            identity
          ])))}';

  static int _utcNowMicros() => DateTime.now().toUtc().microsecondsSinceEpoch;
}

final class _RegistrationState {
  const _RegistrationState({
    required this.nonce,
    required this.createdAtMicros,
    this.handle,
    this.serverExpiresAtMicros,
    this.localExpiresAtMicros,
  });

  factory _RegistrationState.mint(int now) {
    final random = Random.secure();
    return _RegistrationState(
      nonce: base64UrlEncode(
        List<int>.generate(32, (_) => random.nextInt(256)),
      ).replaceAll('=', ''),
      createdAtMicros: max(1, now),
    );
  }

  factory _RegistrationState.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) throw const FormatException();
    final nonce = value['registrationNonce'];
    final created = value['registrationCreatedAtMicros'];
    if (nonce is! String ||
        nonce.length != 43 ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(nonce) ||
        !_isCanonicalNonce(nonce) ||
        created is! int ||
        created < 1 ||
        created > 9007199254740991) {
      throw const FormatException();
    }
    final handle = value['credentialHandle'];
    final expiry = value['expiresAtMicros'];
    final deadline = value['localExpiresAtMicros'];
    if ((handle == null && (expiry != null || deadline != null)) ||
        (handle != null &&
            (handle is! String ||
                !RegExp(r'^ic1\.[0-9a-f]{64}$').hasMatch(handle) ||
                expiry is! int ||
                expiry < 1 ||
                deadline is! int ||
                deadline < 1))) {
      throw const FormatException();
    }
    return _RegistrationState(
      nonce: nonce,
      createdAtMicros: created,
      handle: handle as String?,
      serverExpiresAtMicros: expiry as int?,
      localExpiresAtMicros: deadline as int?,
    );
  }

  final String nonce;
  final int createdAtMicros;
  final String? handle;
  final int? serverExpiresAtMicros;
  final int? localExpiresAtMicros;

  static bool _isCanonicalNonce(String nonce) {
    try {
      final bytes = base64Url.decode(base64Url.normalize(nonce));
      return bytes.length == 32 &&
          base64UrlEncode(bytes).replaceAll('=', '') == nonce;
    } on FormatException {
      return false;
    }
  }

  _RegistrationState withConfirmation(
          String handle, int expiry, int deadline) =>
      _RegistrationState(
        nonce: nonce,
        createdAtMicros: createdAtMicros,
        handle: handle,
        serverExpiresAtMicros: expiry,
        localExpiresAtMicros: deadline,
      );

  Map<String, Object?> toJson() => {
        'registrationNonce': nonce,
        'registrationCreatedAtMicros': createdAtMicros,
        if (handle != null) 'credentialHandle': handle,
        if (serverExpiresAtMicros != null)
          'expiresAtMicros': serverExpiresAtMicros,
        if (localExpiresAtMicros != null)
          'localExpiresAtMicros': localExpiresAtMicros,
      };
}
