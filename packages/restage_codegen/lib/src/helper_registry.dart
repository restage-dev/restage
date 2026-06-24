import 'package:meta/meta.dart';

/// Returns true when [libraryUri] is exactly [origin] or is under [origin]/.
bool libraryUriMatchesOrigin(String libraryUri, String origin) =>
    libraryUri == origin || libraryUri.startsWith('$origin/');

/// Whether a helper returns a value usable as a String state-ref or is a
/// VoidCallback (event-firing).
enum HelperReturnCategory {
  /// Returns a `String` — usable inside string interpolation as a state ref.
  string,

  /// Returns a `VoidCallback` — usable as an event handler property.
  voidCallback,
}

/// Translation rule for one recognized helper call.
@immutable
final class HelperDefinition {
  /// Const constructor.
  const HelperDefinition({
    required this.name,
    required this.libraryOrigin,
    required this.returnCategory,
    required this.translate,
  })  : assert(name.length > 0, 'HelperDefinition.name must not be empty'),
        assert(
          libraryOrigin.length > 0,
          'HelperDefinition.libraryOrigin must not be empty',
        );

  /// The function identifier as it appears in source (e.g. `paywallEvent`).
  final String name;

  /// Required Dart import URI prefix the call must originate from
  /// (typically `'package:restage'`).
  final String libraryOrigin;

  /// What kind of value this helper returns.
  final HelperReturnCategory returnCategory;

  /// Pure translation function: given the parsed argument map, returns an
  /// RFW DSL fragment string. Throws on invalid arg shapes.
  final String Function(HelperCallArgs args) translate;
}

/// Parsed arguments to a recognized helper call. Values are pre-translated
/// RFW DSL fragments (so `'foo'` is `'"foo"'`, `42` is `'42'`, etc.).
@immutable
final class HelperCallArgs {
  /// Const constructor.
  const HelperCallArgs({
    required this.positional,
    required this.named,
  });

  /// Positional arguments, in source order.
  final List<String> positional;

  /// Named arguments by name.
  final Map<String, String> named;
}

/// Pluggable table of recognized helper calls. Feature-specific helper
/// modules (e.g. `paywall_helpers.dart`) register entries here.
final class HelperRegistry {
  final List<HelperDefinition> _defs = [];

  /// Registers all entries in [definitions].
  ///
  /// Asserts (in debug mode) that no (name, libraryOrigin) pair is registered
  /// more than once.
  void registerAll(Iterable<HelperDefinition> definitions) {
    for (final def in definitions) {
      assert(
        !_defs.any(
          (existing) =>
              existing.name == def.name &&
              existing.libraryOrigin == def.libraryOrigin,
        ),
        'Duplicate helper registration: ${def.name} (${def.libraryOrigin})',
      );
      _defs.add(def);
    }
  }

  /// Returns the definition matching the given [name] and [libraryOrigin],
  /// or `null` if not registered.
  ///
  /// [libraryOrigin] is matched as a URI prefix: a registered origin of
  /// `'package:restage'` matches any sub-path under that
  /// package (e.g. `'package:restage/src/foo.dart'`) but not
  /// lookalike package names.
  HelperDefinition? find(String name, String libraryOrigin) {
    for (final def in _defs) {
      if (def.name == name &&
          libraryUriMatchesOrigin(libraryOrigin, def.libraryOrigin)) {
        return def;
      }
    }
    return null;
  }

  /// Returns the definition matching [name] alone, ignoring library origin.
  ///
  /// Used as a fallback when the analyzer cannot resolve a call to its
  /// declaring library — for example, when the Flutter SDK is not available
  /// to the build_runner resolver. Should only be used when the full
  /// [find] returns null and the call site has no element.
  HelperDefinition? findByNameOnly(String name) {
    for (final def in _defs) {
      if (def.name == name) return def;
    }
    return null;
  }

  /// The registered definitions, in registration order. Read-only — exposed so
  /// tooling can compare two registries' registered sets (e.g. the coverage
  /// scanner's default vs. the build's). Not exported from the package barrel.
  Iterable<HelperDefinition> get definitions => List.unmodifiable(_defs);
}
