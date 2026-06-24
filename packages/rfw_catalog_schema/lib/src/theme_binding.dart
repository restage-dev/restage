import 'package:meta/meta.dart';

/// Where a value comes from when resolved at render time against the
/// active Flutter theme.
///
/// Used wherever a catalog field declares "the runtime should resolve
/// this from the theme rather than carry a frozen literal" — design
/// tokens' `resolver` field and property defaults via
/// `ThemeBindingDefault`.
///
/// Construct one of the three meaningful shapes via the named
/// constructors — [ThemeBindingPath.path] (a theme dot-path only),
/// [ThemeBindingPath.resolver] (a registered resolver only), or
/// [ThemeBindingPath.both]. There is deliberately no constructor that
/// leaves both fields null: a binding with neither is a no-op, so the
/// empty state is made structurally unconstructable rather than guarded
/// by a runtime check.
@immutable
final class ThemeBindingPath {
  /// A binding that resolves a [path] into the active theme tree, with no
  /// computed resolver.
  const ThemeBindingPath.path(String this.path) : resolverName = null;

  /// A binding that resolves through a registered [resolverName], with no
  /// static theme path.
  const ThemeBindingPath.resolver(String this.resolverName) : path = null;

  /// A binding that carries both a static [path] and a computed
  /// [resolverName].
  const ThemeBindingPath.both({
    required String this.path,
    required String this.resolverName,
  });

  /// Dot-path into Flutter's theme tree, e.g. `'colorScheme.primary'`
  /// resolved against `Theme.of(context)`. Null when the binding is
  /// purely computed via [resolverName] and has no useful path form.
  final String? path;

  /// When the binding is a computed default rather than a static path,
  /// names a registered resolver in the SDK runtime. Null when [path]
  /// alone suffices.
  final String? resolverName;

  @override
  bool operator ==(Object other) =>
      other is ThemeBindingPath &&
      other.path == path &&
      other.resolverName == resolverName;

  @override
  int get hashCode => Object.hash(path, resolverName);

  @override
  String toString() {
    if (path != null && resolverName != null) {
      return 'ThemeBindingPath.both(path: $path, resolverName: $resolverName)';
    }
    if (path != null) return 'ThemeBindingPath.path($path)';
    return 'ThemeBindingPath.resolver($resolverName)';
  }
}
