import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_shared/restage_shared.dart';

/// A build push that moves the caller's own head.
const pushPersonalBuildFollowUp = FollowUp('build push', 'restage_push_build', [
  FollowUpArg('personal', null, flag: 'personal'),
]);

/// Why a key cannot push to a personal head, and what to do instead.
String keyHasNoPersonalHeadSentence() {
  final syntax = currentSelectorSyntax;
  return 'A key moves the head of the environment it is bound to, so it has '
      'no personal head to push to. To push to your own head, sign in, then '
      '${syntax.run.toLowerCase()} '
      '${syntax.command(pushPersonalBuildFollowUp)}.';
}

/// A build push that moves [environment]'s head.
FollowUp pushBuildFollowUp(String environment) => FollowUp(
  'build push',
  'restage_push_build',
  [FollowUpArg('environmentSlug', environment, flag: 'env')],
);

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
      refusal: BundlePushTargetRefusal(
        'Name one target: '
        '${currentSelectorSyntax.command(pushBuildFollowUp('<slug>'))} for an '
        'environment head, or '
        '${currentSelectorSyntax.command(pushPersonalBuildFollowUp)} for your '
        'own.',
      ),
    );
  }
  if (personal && withKey) {
    return (
      target: null,
      refusal: BundlePushTargetRefusal(keyHasNoPersonalHeadSentence()),
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
