import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/theme_binding.dart';
import 'package:rfw_catalog_schema/src/wire_id.dart';

/// Discriminator for the [DefaultValueSource] sealed hierarchy. Used by
/// the JSON codec to tag each subtype on the wire and by consumers that
/// need a stable identifier without pattern-matching the runtime type.
///
/// **Compatibility.** Additions to this enum are breaking changes for
/// downstream consumers that switch exhaustively on a
/// [DefaultValueSourceKind] value, and they require a matching new
/// subtype on the [DefaultValueSource] sealed class.
enum DefaultValueSourceKind {
  /// Tags [LiteralDefault].
  literal,

  /// Tags [TokenRefDefault].
  tokenRef,

  /// Tags [ThemeBindingDefault].
  themeBinding,

  /// Tags [FlutterCtorDefault].
  flutterCtorDefault,
}

/// How a property's default value is supplied when the blob does not
/// carry an explicit value. Sealed hierarchy: a property has at most
/// one default source.
///
/// **Null vs FlutterCtorDefault.** These are distinct:
///
///   * `defaultSource: null` — the catalog makes no claim about the
///     default. The Flutter ctor's own default applies at construction
///     time, and the catalog has not been asked to think about it. This
///     is the common case for properties that don't need editor /
///     catalog awareness of the default.
///   * `defaultSource: FlutterCtorDefault()` — the catalog *explicitly*
///     delegates to Flutter's ctor default. The editor surfaces this as
///     "(Flutter default)"; the diff tool treats a switch between null
///     and FlutterCtorDefault as a semantic change (the curator's intent
///     shifted), not a no-op.
sealed class DefaultValueSource {
  const DefaultValueSource();

  /// Discriminator for this source's concrete subtype.
  DefaultValueSourceKind get kind;
}

/// Literal value baked into the catalog (e.g. `5`, `'start'`, `true`,
/// `[0, 0, 0, 0]`). Type must match the property's `PropertyType`.
@immutable
final class LiteralDefault extends DefaultValueSource {
  /// Const constructor.
  const LiteralDefault(this.value);

  /// The literal default value. Type matches the property's
  /// `PropertyType`.
  final Object value;

  @override
  DefaultValueSourceKind get kind => DefaultValueSourceKind.literal;

  @override
  bool operator ==(Object other) =>
      other is LiteralDefault && _deepEquals(other.value, value);

  @override
  int get hashCode => _deepHash(value);

  /// Recursive structural equality used to compare two literal default
  /// values across nested collections. `==` on Dart's built-in
  /// collections doesn't recurse; consumers expect literal defaults to
  /// compare by structure (e.g. two `LiteralDefault([0, 0, 0, 0])`
  /// values are equal regardless of underlying list identity).
  static bool _deepEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key)) return false;
        if (!_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    return a == b;
  }

  static int _deepHash(Object? value) {
    if (value is List) {
      // Use the list's elements rather than identity so two structurally
      // equal lists hash equal.
      return Object.hashAll(value.map(_deepHash));
    }
    if (value is Map) {
      return Object.hashAllUnordered(
        value.entries
            .map((e) => Object.hash(_deepHash(e.key), _deepHash(e.value))),
      );
    }
    return value.hashCode;
  }
}

/// Reference to a design token. The runtime resolves the wire-ID
/// reference at render time via the token's resolver / fallback.
@immutable
final class TokenRefDefault extends DefaultValueSource {
  /// Const constructor.
  const TokenRefDefault(this.token);

  /// Cross-library reference; the token may live in `restage.core`,
  /// `restage.material`, or a customer library.
  final WireIdRef token;

  @override
  DefaultValueSourceKind get kind => DefaultValueSourceKind.tokenRef;

  @override
  bool operator ==(Object other) =>
      other is TokenRefDefault && other.token == token;

  @override
  int get hashCode => token.hashCode;
}

/// Direct theme binding without intermediate token. Used when a property
/// has a property-specific default that doesn't warrant surfacing as a
/// reusable design token (e.g. `Text.style.color` binding to
/// `defaultTextStyle.color` is a Flutter convention, not a
/// customer-facing design-system value).
@immutable
final class ThemeBindingDefault extends DefaultValueSource {
  /// Const constructor.
  const ThemeBindingDefault(this.path);

  /// The theme path / resolver the runtime walks to fetch the default.
  final ThemeBindingPath path;

  @override
  DefaultValueSourceKind get kind => DefaultValueSourceKind.themeBinding;

  @override
  bool operator ==(Object other) =>
      other is ThemeBindingDefault && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// Marker: the catalog intentionally delegates to Flutter's own ctor
/// default. Distinct from `defaultSource: null` (which means "the
/// catalog made no claim either way"). Use when the curator's intent is
/// "let Flutter decide" — the editor surfaces this as "(Flutter
/// default)" rather than leaving the UI ambiguous; the diff tool treats
/// a transition between null and FlutterCtorDefault as a semantic
/// change.
@immutable
final class FlutterCtorDefault extends DefaultValueSource {
  /// Const constructor.
  const FlutterCtorDefault();

  @override
  DefaultValueSourceKind get kind => DefaultValueSourceKind.flutterCtorDefault;

  @override
  bool operator ==(Object other) => other is FlutterCtorDefault;

  @override
  int get hashCode => (FlutterCtorDefault).hashCode;
}
