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
    _identityGeneration = null;
    _registration = null;
    _confirmedKey = null;
    _confirmRegistration = null;
    _refuseRegistration = null;
  }

  /// Installs the production key and identity-generation providers together.
  @internal
  static void install({
    required FutureOr<String?> Function() key,
    required int Function() identityGeneration,
    Future<SurfaceRegistrationAttempt?> Function()? registration,
    String? Function()? confirmedKey,
    Future<bool> Function(SurfaceRegistrationAttempt, int, String, int, int)?
        confirmRegistration,
    Future<void> Function(SurfaceRegistrationAttempt)? refuseRegistration,
  }) {
    _configurationEpoch += 1;
    _current = key;
    _identityGeneration = identityGeneration;
    _registration = registration;
    _confirmedKey = confirmedKey;
    _confirmRegistration = confirmRegistration;
    _refuseRegistration = refuseRegistration;
  }

  /// Resolves the current key, returning null when disabled, degraded, or
  /// not answered within [DeliveryInputBudget.defaultTotal].
  static Future<String?> resolve() async {
    final provider = _current;
    if (provider == null) return null;
    try {
      final value = await DeliveryInputBudget.run(
        (budget) => budget.bound(Future.sync(provider)),
        total: DeliveryInputBudget.defaultTotal,
      );
      return _isValidAssignmentKey(value) ? value : null;
    } on Object {
      return null;
    }
  }

  /// Captures the identity lease before awaiting the assignment key.
  ///
  /// The lease remains meaningful when the key is null or degraded: provider
  /// replacement and anonymous-identity reset still invalidate hosted work
  /// selected during the earlier generation. A key not answered within
  /// [budget], or [DeliveryInputBudget.defaultTotal] when none is given,
  /// is captured as absent.
  @internal
  static Future<SurfaceAssignmentResolutionLease> captureLease({
    DeliveryInputBudget? budget,
  }) async {
    final configurationEpoch = _configurationEpoch;
    final generationProvider = _identityGeneration;
    final identityGeneration = generationProvider?.call() ?? 0;
    final provider = _current;
    final registrationProvider = _registration;

    String? key;
    SurfaceRegistrationAttempt? registration;
    if (registrationProvider != null) {
      try {
        registration = await DeliveryInputBudget.run(
          (owned) => owned.bound(registrationProvider()),
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
          (owned) => owned.bound(Future.sync(provider)),
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
      registrationRequired: registrationProvider != null,
      confirmRegistration: _confirmRegistration,
      refuseRegistration: _refuseRegistration,
    );
  }

  static bool _isLeaseCurrent(SurfaceAssignmentResolutionLease lease) {
    if (_configurationEpoch != lease._configurationEpoch) return false;
    final generationProvider = _identityGeneration;
    if (generationProvider == null) return lease._identityGeneration == 0;
    try {
      return generationProvider() == lease._identityGeneration;
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

  /// Persisted tuple captured before this request can leave the device.
  final SurfaceRegistrationAttempt? registration;

  /// A configured device sends no hosted request until its tuple is durable.
  final bool registrationRequired;

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
