import 'dart:async';

import 'package:meta/meta.dart';

/// Internal provider for hosted surface experiment assignment keys.
///
/// This is deliberately not exported from `restage.dart`: hosts do not choose
/// experiment assignments. `Restage.configure` installs it from the SDK-owned
/// analytics identity when hosted analytics is active; hosted resolvers read it
/// just before fetching an active experiment arm.
abstract final class SurfaceAssignmentKeyProvider {
  static FutureOr<String?> Function()? _current;
  static int Function()? _identityGeneration;
  static int _configurationEpoch = 0;

  /// Current provider. Tests set this directly; production code uses [install]
  /// so a lease also observes anonymous-identity generation changes.
  static FutureOr<String?> Function()? get current => _current;

  /// Monotonic identity of the installed assignment-key provider.
  @internal
  static int get configurationGeneration => _configurationEpoch;

  /// Current anonymous actor generation observed by the installed provider.
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
  }

  /// Installs the production key and identity-generation providers together.
  @internal
  static void install({
    required FutureOr<String?> Function() key,
    required int Function() identityGeneration,
  }) {
    _configurationEpoch += 1;
    _current = key;
    _identityGeneration = identityGeneration;
  }

  /// Resolves the current key, returning null when disabled or degraded.
  static Future<String?> resolve() async {
    final provider = _current;
    if (provider == null) return null;
    try {
      final value = await provider();
      return _isValidAssignmentKey(value) ? value : null;
    } on Object {
      return null;
    }
  }

  /// Captures the identity lease before awaiting the assignment key.
  ///
  /// The lease remains meaningful when the key is null or degraded: provider
  /// replacement and anonymous-identity reset still invalidate hosted work
  /// selected during the earlier generation.
  @internal
  static Future<SurfaceAssignmentResolutionLease> captureLease() async {
    final configurationEpoch = _configurationEpoch;
    final generationProvider = _identityGeneration;
    final identityGeneration = generationProvider?.call() ?? 0;
    final provider = _current;

    String? key;
    if (provider != null) {
      try {
        final value = await provider();
        if (_isValidAssignmentKey(value)) key = value;
      } on Object {
        key = null;
      }
    }
    return SurfaceAssignmentResolutionLease._(
      configurationEpoch: configurationEpoch,
      identityGeneration: identityGeneration,
      assignmentKey: key,
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

  /// Clears any configured provider.
  static void clear() => current = null;
}

/// Internal identity epoch attached to hosted paywall resolution work.
@internal
@immutable
final class SurfaceAssignmentResolutionLease {
  const SurfaceAssignmentResolutionLease._({
    required int configurationEpoch,
    required int identityGeneration,
    required this.assignmentKey,
  })  : _configurationEpoch = configurationEpoch,
        _identityGeneration = identityGeneration;

  final int _configurationEpoch;
  final int _identityGeneration;

  /// The assignment key captured for the hosted request, when available.
  final String? assignmentKey;

  /// Whether both provider configuration and anonymous identity are unchanged.
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
