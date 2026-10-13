import 'package:restage_shared/restage_shared.dart';

/// Where a push points the app's renderer.
///
/// Naming nothing takes the caller's default: a signed-in person pushes to
/// their own head, a key to the environment its own row names.
final class BundlePushTarget {
  /// The caller's default.
  const BundlePushTarget.caller() : environment = null, personal = false;

  /// One named environment of the app.
  const BundlePushTarget.environment(String slug)
    : environment = slug,
      personal = false;

  /// The caller's own head.
  const BundlePushTarget.personal() : environment = null, personal = true;

  /// The environment slug, when one was named.
  final String? environment;

  /// Whether the caller asked for their own head.
  final bool personal;

  /// Whether the caller named a target at all.
  bool get named => environment != null || personal;
}

/// A target the command can refuse before it does any work.
final class BundlePushTargetRefusal {
  const BundlePushTargetRefusal(this.message);

  /// The sentence the reader sees.
  final String message;
}

/// Reads the target from what the caller passed.
///
/// Returns a refusal for the pairs that can never be right, so a push fails
/// before it builds anything.
({BundlePushTarget? target, BundlePushTargetRefusal? refusal})
resolveBundlePushTarget({
  required String? environment,
  required bool personal,
  required bool withKey,
}) {
  if (environment != null && personal) {
    return (
      target: null,
      refusal: const BundlePushTargetRefusal(
        'Name one target: --env <slug> for an environment head, or '
        '--personal for your own.',
      ),
    );
  }
  if (personal && withKey) {
    return (
      target: null,
      refusal: const BundlePushTargetRefusal(
        'A key moves the head of the environment it is bound to, so it has no '
        'personal head to push to. Drop --personal, or sign in.',
      ),
    );
  }
  if (environment != null && !isValidRenderBundleEnvironmentSlug(environment)) {
    return (
      target: null,
      refusal: BundlePushTargetRefusal(
        'Refusing the environment `$environment`. An environment slug is 1 to '
        '$renderBundleEnvironmentSlugMaxLength lowercase letters, digits, `-` '
        'or `_`, starting and ending with a letter or digit.',
      ),
    );
  }
  if (environment != null) {
    return (target: BundlePushTarget.environment(environment), refusal: null);
  }
  if (personal) {
    return (target: const BundlePushTarget.personal(), refusal: null);
  }
  return (target: const BundlePushTarget.caller(), refusal: null);
}
