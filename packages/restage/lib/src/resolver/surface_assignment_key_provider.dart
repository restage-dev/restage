import 'dart:async';

import 'package:meta/meta.dart';

import 'delivery_input_budget.dart';
import 'surface_assignment_credential_store.dart';

/// Internal provider for the SDK-owned identity key used with hosted surface
/// requests.
///
/// This is deliberately not exported from `restage.dart`: hosts do not supply
/// the key. `Restage.configure` installs the service-issued credential handle
/// scoped to the SDK-owned local identity. Hosted resolvers capture it
/// immediately before fetching active content; the accompanying lease rejects
/// work when that identity changes.
abstract final class SurfaceAssignmentKeyProvider {
  static FutureOr<String?> Function()? _current;
  static FutureOr<String?> Function()? _local;
  static Future<SurfaceRegistrationAttempt?> Function()? _registration;
  static String? Function()? _confirmedKey;
  static Future<bool> Function(
      SurfaceRegistrationAttempt, int, String, int, int)? _confirmRegistration;
  static Future<void> Function(SurfaceRegistrationAttempt)? _refuseRegistration;
  static int Function()? _identityGeneration;
  static int _configurationEpoch = 0;

  /// Current provider. Tests set this directly; production code uses [install]
  /// so a lease also observes anonymous-identity generation changes.
  static FutureOr<String?> Function()? get current => _current;

  /// Monotonic identity of the installed assignment-key provider.
  @internal
  static int get configurationGeneration => _configurationEpoch;

  /// Current identity and credential-retention epoch of the installed provider.
  @internal
  static int get analyticsIdentityGeneration {
    final provider = _identityGeneration;
    if (provider == null) return 0;
    try {
      return provider();
    } on Object {
      return -1;
    }
  }

  static set current(FutureOr<String?> Function()? provider) {
    _configurationEpoch += 1;
    _current = provider;
    _local = null;
    _identityGeneration = null;
    _registration = null;
    _confirmedKey = null;
    _confirmRegistration = null;
    _refuseRegistration = null;
  }

  /// The key source that reads only what this device already holds.
  @visibleForTesting
  static set local(FutureOr<String?> Function()? provider) => _local = provider;

  /// Installs the production key and identity-generation providers together.
  @internal
  static void install({
    required FutureOr<String?> Function() key,
    required int Function() identityGeneration,
    FutureOr<String?> Function()? localKey,
    Future<SurfaceRegistrationAttempt?> Function()? registration,
    String? Function()? confirmedKey,
    Future<bool> Function(SurfaceRegistrationAttempt, int, String, int, int)?
        confirmRegistration,
    Future<void> Function(SurfaceRegistrationAttempt)? refuseRegistration,
  }) {
    _configurationEpoch += 1;
    _current = key;
    _local = localKey;
    _identityGeneration = identityGeneration;
    _registration = registration;
    _confirmedKey = confirmedKey;
    _confirmRegistration = confirmRegistration;
    _refuseRegistration = refuseRegistration;
  }

  /// The key this device already holds, without registering; null when none
  /// is held or no local source is installed.
  @internal
  static Future<String?> resolveLocal() async {
    final provider = _local;
    if (provider == null) return null;
    try {
      final value = await provider();
      return _isValidAssignmentKey(value) ? value : null;
    } on Object {
      return null;
    }
  }

  /// Resolves the current key, returning null when disabled, degraded, or
  /// not answered within [DeliveryInputBudget.defaultTotal] or before
  /// [keyDeadline].
  static Future<String?> resolve({Future<void>? keyDeadline}) async {
    final provider = _current;
    if (provider == null) return null;
    try {
      final value = await DeliveryInputBudget.run(
        (budget) => budget.bound(
          _beforeDeadline(Future.sync(provider), keyDeadline),
        ),
        total: DeliveryInputBudget.defaultTotal,
      );
      return _isValidAssignmentKey(value) ? value : null;
    } on Object {
      return null;
    }
  }

  /// Captures an identity lease before resolving the assignment key.
  /// Provider changes and identity resets invalidate the lease even without a key.
  /// [resolveKey] skips key reads when false. Exceeding [budget] (default
  /// [DeliveryInputBudget.defaultTotal]) or [keyDeadline] yields no key.
  @internal
  static Future<SurfaceAssignmentResolutionLease> captureLease({
    DeliveryInputBudget? budget,
    bool resolveKey = true,
    Future<void>? keyDeadline,
  }) async {
    final configurationEpoch = _configurationEpoch;
    final generationProvider = _identityGeneration;
    final identityGeneration = generationProvider?.call() ?? 0;
    final provider = resolveKey ? _current : null;
    final registrationProvider = resolveKey ? _registration : null;
    var deadlinePassed = false;

    String? key;
    SurfaceRegistrationAttempt? registration;
    if (registrationProvider != null) {
      try {
        registration = await DeliveryInputBudget.run(
          (owned) => owned.bound(keyDeadline == null
              ? registrationProvider()
              : Future.any<SurfaceRegistrationAttempt?>([
                  registrationProvider(),
                  keyDeadline.then((_) {
                    deadlinePassed = true;
                    return null;
                  }),
                ])),
          shared: budget,
          total: DeliveryInputBudget.defaultTotal,
        );
        key = registration?.credentialHandle;
      } on Object {
        registration = null;
      }
    } else if (provider != null) {
      try {
        final value = await DeliveryInputBudget.run(
          (owned) => owned.bound(_beforeDeadline(
            Future.sync(provider),
            keyDeadline,
          )),
          shared: budget,
          total: DeliveryInputBudget.defaultTotal,
        );
        if (_isValidAssignmentKey(value)) key = value;
      } on Object {
        key = null;
      }
    }
    return SurfaceAssignmentResolutionLease._(
      configurationEpoch: configurationEpoch,
      identityGeneration: registration?.generation ?? identityGeneration,
      assignmentKey: key,
      registration: registration,
      registrationRequired: registrationProvider != null && !deadlinePassed,
      assignmentsAllowed: resolveKey && !deadlinePassed,
      confirmRegistration: _confirmRegistration,
      refuseRegistration: _refuseRegistration,
    );
  }

  /// A lease for the current identity that carries no key. Synchronous.
  @internal
  static SurfaceAssignmentResolutionLease captureKeylessLease() =>
      SurfaceAssignmentResolutionLease._(
        configurationEpoch: _configurationEpoch,
        identityGeneration: _identityGeneration?.call() ?? 0,
        assignmentKey: null,
        registration: null,
        registrationRequired: false,
        assignmentsAllowed: false,
        confirmRegistration: null,
        refuseRegistration: null,
      );

  static Future<String?> _beforeDeadline(
    Future<String?> value,
    Future<void>? deadline,
  ) =>
      deadline == null
          ? value
          : Future.any<String?>(<Future<String?>>[
              value,
              deadline.then<String?>((_) => null),
            ]);

  static bool _isLeaseCurrent(SurfaceAssignmentResolutionLease lease) {
    if (_configurationEpoch != lease._configurationEpoch) return false;
    final generationProvider = _identityGeneration;
    if (generationProvider == null) return lease._identityGeneration == 0;
    try {
      return generationProvider() == lease._identityGeneration &&
          (lease.registration == null ||
              _confirmedKey == null ||
              lease.assignmentKey == null ||
              _confirmedKey?.call() == lease.assignmentKey);
    } on Object {
      return false;
    }
  }

  /// Captures the tuple associated with a Measurement frame before its send.
  static Future<SurfaceRegistrationAttempt?>
      captureRegistrationAttempt() async {
    final provider = _registration;
    if (provider == null) return null;
    try {
      return await DeliveryInputBudget.run(
        (budget) => budget.bound(provider()),
        total: DeliveryInputBudget.defaultTotal,
      );
    } on Object {
      return null;
    }
  }

  static bool get registrationConfigured => _registration != null;

  /// The handle confirmed by a folded serve in the current identity epoch.
  static String? get confirmedKey => _confirmedKey?.call();

  /// Discards a credential refused for the frame's captured tuple.
  static Future<void> refuseRegistration(
      SurfaceRegistrationAttempt attempt) async {
    await _refuseRegistration?.call(attempt);
  }

  /// Clears any configured provider.
  static void clear() => current = null;
}

/// Internal identity epoch attached to hosted paywall resolution work.
@internal
final class SurfaceAssignmentResolutionLease {
  SurfaceAssignmentResolutionLease._({
    required int configurationEpoch,
    required int identityGeneration,
    required String? assignmentKey,
    required this.registration,
    required this.registrationRequired,
    required this.assignmentsAllowed,
    required this.confirmRegistration,
    required this.refuseRegistration,
  })  : assignmentKey = assignmentKey,
        sentAssignmentKey = assignmentKey,
        _configurationEpoch = configurationEpoch,
        _identityGeneration = identityGeneration;

  final int _configurationEpoch;
  final int _identityGeneration;

  /// The assignment key captured for the hosted request, when available.
  String? assignmentKey;

  /// The handle actually included when this request began.
  final String? sentAssignmentKey;

  /// Keeps content fetched with a new registration under its confirmed handle.
  void confirmHandle(String handle) {
    if (registration != null && sentAssignmentKey == null) {
      assignmentKey = handle;
    }
  }

  /// Retains the exact stored credential within this captured identity epoch.
  /// Checking currency observes its original persisted expiry; it never renews it.
  @internal
  SurfaceAssignmentResolutionLease forStoredAssignment(
    String key,
    SurfaceRegistrationAttempt? attempt,
  ) =>
      SurfaceAssignmentResolutionLease._(
        configurationEpoch: _configurationEpoch,
        identityGeneration: _identityGeneration,
        assignmentKey: key,
        registration: attempt,
        registrationRequired: false,
        assignmentsAllowed: true,
        confirmRegistration: null,
        refuseRegistration: null,
      );

  SurfaceAssignmentResolutionLease withoutAssignment() =>
      SurfaceAssignmentResolutionLease._(
        configurationEpoch: _configurationEpoch,
        identityGeneration: _identityGeneration,
        assignmentKey: null,
        registration: null,
        registrationRequired: false,
        assignmentsAllowed: false,
        confirmRegistration: null,
        refuseRegistration: null,
      );

  /// Persisted tuple captured before this request can leave the device.
  final SurfaceRegistrationAttempt? registration;

  /// A configured device sends no hosted request until its tuple is durable.
  final bool registrationRequired;

  /// Whether this request may carry experiment selection inputs.
  final bool assignmentsAllowed;

  bool get canSend => !registrationRequired || registration != null;

  final Future<bool> Function(
      SurfaceRegistrationAttempt, int, String, int, int)? confirmRegistration;
  final Future<void> Function(SurfaceRegistrationAttempt)? refuseRegistration;

  /// Whether provider configuration, identity, and credential retention are unchanged.
  bool get isCurrent => SurfaceAssignmentKeyProvider._isLeaseCurrent(this);
}

/// Internal signal that hosted resolution crossed an identity boundary.
@internal
final class StaleSurfaceAssignmentResolution implements Exception {
  const StaleSurfaceAssignmentResolution();
}

bool _isValidAssignmentKey(String? value) {
  if (value == null || value.isEmpty) return false;
  return value.trim() == value && !value.contains('\u0000');
}
