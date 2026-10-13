/// The kind of head a reference names.
enum RenderBundleHeadKind {
  /// A named environment of the app, such as `staging`.
  environment,

  /// One person's own branch preview, written `user/<handle>`.
  personal,
}

/// The prefix a personal head reference carries.
const renderBundleUserHeadPrefix = 'user/';

/// Maximum length of the handle portion of a personal head reference.
const renderBundleHandleMaxLength = 32;

/// Maximum length of an environment slug in a head reference.
const renderBundleEnvironmentSlugMaxLength = 32;

/// Handles and environment slugs share one grammar: 1-32 lowercase ASCII
/// alphanumerics, with `-` and `_` allowed only between alphanumerics.
final RegExp _labelPattern = RegExp(
  r'^[a-z0-9](?:[a-z0-9_-]{0,30}[a-z0-9])?$',
);

/// A parsed render-bundle head reference.
///
/// Its [text] is the canonical form used in links, the command line and the
/// wire: an environment slug on its own, or `user/<handle>`.
class RenderBundleHead {
  const RenderBundleHead._(this.kind, this.label);

  /// The head an environment slug names.
  factory RenderBundleHead.environment(String slug) {
    if (!isValidRenderBundleEnvironmentSlug(slug)) {
      throw const FormatException('Invalid render-bundle environment head.');
    }
    return RenderBundleHead._(RenderBundleHeadKind.environment, slug);
  }

  /// The head one person's [handle] names.
  factory RenderBundleHead.personal(String handle) {
    if (!isValidRenderBundleHandle(handle)) {
      throw const FormatException('Invalid render-bundle personal head.');
    }
    return RenderBundleHead._(RenderBundleHeadKind.personal, handle);
  }

  /// Which kind of head this is.
  final RenderBundleHeadKind kind;

  /// The environment slug, or the handle, without any prefix.
  final String label;

  /// The environment slug this head names, or null when it is personal.
  String? get environmentSlug =>
      kind == RenderBundleHeadKind.environment ? label : null;

  /// The handle this head names, or null when it names an environment.
  String? get handle => kind == RenderBundleHeadKind.personal ? label : null;

  /// The canonical text form.
  String get text => switch (kind) {
        RenderBundleHeadKind.environment => label,
        RenderBundleHeadKind.personal => '$renderBundleUserHeadPrefix$label',
      };

  @override
  String toString() => text;

  @override
  bool operator ==(Object other) =>
      other is RenderBundleHead && other.kind == kind && other.label == label;

  @override
  int get hashCode => Object.hash(kind, label);
}

/// Whether [handle] fits the personal-head handle grammar.
bool isValidRenderBundleHandle(String handle) =>
    handle.length <= renderBundleHandleMaxLength &&
    _labelPattern.hasMatch(handle);

/// Whether [slug] may name an environment head.
///
/// `user` is refused so an environment can never shadow the personal-head
/// prefix in a reference.
bool isValidRenderBundleEnvironmentSlug(String slug) =>
    slug != 'user' &&
    slug.length <= renderBundleEnvironmentSlugMaxLength &&
    _labelPattern.hasMatch(slug);

/// Whether [reference] is a canonical head reference of either kind.
bool isValidRenderBundleHead(String reference) {
  if (reference.startsWith(renderBundleUserHeadPrefix)) {
    return isValidRenderBundleHandle(
      reference.substring(renderBundleUserHeadPrefix.length),
    );
  }
  return isValidRenderBundleEnvironmentSlug(reference);
}

/// Parses [reference] into its head, throwing a [FormatException] before any
/// caller does external work when it is not canonical.
///
/// Whether the named environment exists on the app is resolved by the server;
/// this answers only whether the reference is well formed.
RenderBundleHead parseRenderBundleHead(String reference) {
  if (reference.startsWith(renderBundleUserHeadPrefix)) {
    return RenderBundleHead.personal(
      reference.substring(renderBundleUserHeadPrefix.length),
    );
  }
  return RenderBundleHead.environment(reference);
}

/// Reduces [email] to a personal handle, or returns null when nothing legal
/// remains. The local part is lowercased and anything outside the grammar
/// becomes a separator; callers resolve collisions within the app.
String? renderBundleHandleFromEmail(String email) {
  final at = email.indexOf('@');
  final local = (at < 0 ? email : email.substring(0, at)).toLowerCase();
  final reduced = local
      .replaceAll(RegExp('[^a-z0-9_-]'), '-')
      .replaceAll(RegExp('^[^a-z0-9]+'), '')
      .replaceAll(RegExp('[^a-z0-9]+\$'), '');
  if (reduced.isEmpty) return null;
  final clipped = reduced.length <= renderBundleHandleMaxLength
      ? reduced
      : reduced
          .substring(0, renderBundleHandleMaxLength)
          .replaceAll(RegExp('[^a-z0-9]+\$'), '');
  return isValidRenderBundleHandle(clipped) ? clipped : null;
}
