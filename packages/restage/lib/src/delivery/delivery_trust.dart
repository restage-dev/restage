import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

/// Why a signed delivery was not accepted.
@internal
enum DeliveryTrustRefusal {
  /// The signature names a key the app was not configured with.
  unknownKey,

  /// The signature does not verify.
  invalidSignature,

  /// Authorized before the newest content the surface has shown.
  rollback,
}

/// The delivery keys and the last accepted version of each surface.
@internal
abstract final class DeliveryTrust {
  static List<DeliveryPublicKey> _configured = const [];
  static List<DeliveryPublicKey> _debugKeys = const [];
  static DeliveryKeyring _keyring = DeliveryKeyring(const []);
  static final Map<(Surface, String), int> _authorizedAt = {};

  /// The configured keyring.
  static DeliveryKeyring get keyring => _keyring;

  /// Installs [keys] and forgets every accepted version.
  static void configure(Iterable<DeliveryPublicKey> keys) {
    _configured = List.unmodifiable(keys);
    _keyring = DeliveryKeyring([..._configured, ..._debugKeys]);
    _authorizedAt.clear();
  }

  /// Keys accepted in addition to every configuration, for tests.
  @visibleForTesting
  static set debugAdditionalKeys(List<DeliveryPublicKey> keys) {
    _debugKeys = List.unmodifiable(keys);
    configure(_configured);
  }

  /// Raises the bar to the saved root [descriptor] without verifying it,
  /// before saved content is read back; reading it back verifies it.
  static void seed(SurfaceArtifactDescriptor descriptor) => _raise(descriptor);

  /// Checks [descriptor]'s signature and, for a [fresh] [root] delivery,
  /// refuses one the server authorized before the newest content this
  /// surface has shown; null when it is accepted.
  ///
  /// Every version served at once carries that set's authorization time, so
  /// any of them is accepted, and a rollback, rule or experiment that changes
  /// the set authorizes its versions again. A saved copy, or a version the
  /// app asked for by number, is never refused this way.
  static DeliveryTrustRefusal? admit(
    SurfaceArtifactDescriptor descriptor, {
    required bool root,
    required bool fresh,
  }) {
    switch (_keyring.check(descriptor)) {
      case DeliveryRefusal.unknownKey:
        return DeliveryTrustRefusal.unknownKey;
      case DeliveryRefusal.invalidSignature:
        return DeliveryTrustRefusal.invalidSignature;
      case null:
        break;
    }
    if (!root) return null;
    final last =
        _authorizedAt[(descriptor.surfaceType, descriptor.surfaceSlug)];
    if (fresh && last != null && descriptor.authorizedAtMicros < last) {
      return DeliveryTrustRefusal.rollback;
    }
    _raise(descriptor);
    return null;
  }

  static void _raise(SurfaceArtifactDescriptor descriptor) {
    final key = (descriptor.surfaceType, descriptor.surfaceSlug);
    final last = _authorizedAt[key];
    if (last == null || descriptor.authorizedAtMicros > last) {
      _authorizedAt[key] = descriptor.authorizedAtMicros;
    }
  }
}
