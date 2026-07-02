import 'dart:async';

/// Internal provider for hosted paywall experiment assignment keys.
///
/// This is deliberately not exported from `restage.dart`: hosts do not choose
/// experiment assignments. `Restage.configure` installs it from the SDK-owned
/// analytics identity when hosted analytics is active; hosted resolvers read it
/// just before fetching the active paywall arm.
abstract final class SurfaceAssignmentKeyProvider {
  /// Current provider. Tests set this directly; production code configures it
  /// through `Restage.configure`.
  static FutureOr<String?> Function()? current;

  /// Resolves the current key, returning null when disabled or degraded.
  static Future<String?> resolve() async {
    final provider = current;
    if (provider == null) return null;
    try {
      final value = await provider();
      return _isValidAssignmentKey(value) ? value : null;
    } on Object {
      return null;
    }
  }

  /// Clears any configured provider.
  static void clear() => current = null;
}

bool _isValidAssignmentKey(String? value) {
  if (value == null || value.isEmpty) return false;
  return value.trim() == value && !value.contains('\u0000');
}
