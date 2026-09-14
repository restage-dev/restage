import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart' show IconData;

/// The icons a Restage surface can render, as one code-point table per icon
/// font family.
///
/// A delivered surface document carries an icon as its integer code point and
/// font family, and this value decides which glyph that pair means for this
/// app. Ordinary `Restage.configure()` supplies both full icon families unless
/// an explicit selection exists. For a derived build, generated registration
/// and surface references add their icons, and
/// `Restage.configureWithInstalledCatalog()` preserves that narrower root.
///
/// A few code points name two glyphs within one family — one that mirrors in a
/// right-to-left locale and one that does not — so the mirroring ones live in
/// their own [mirrored] map and a surface selects between them.
///
/// A host can also install an explicit table during app startup:
///
/// ```dart
/// void main() {
///   InstalledIconTable.install(
///     const RestageIconTable.fromFamilies(families: <String, Map<int, IconData>>{
///       RestageIconTable.materialIconsFamily: <int, IconData>{
///         0xe156: Icons.check,
///       },
///     }),
///   );
///   runApp(const MyApp());
/// }
/// ```
///
/// Write each entry as an integer literal key against a `const` icon value.
/// `Icons.check.codePoint` is field access on a const object, which Dart does
/// not accept as a constant expression, so it cannot be the key.
///
/// See also:
///
///  * [InstalledIconTable], the process-wide store surfaces read.
///  * [resolveInstalledIcon], the lookup a rendered surface performs.
@immutable
final class RestageIconTable {
  /// Creates the table from an explicit per-family set of icons.
  ///
  /// Each outer map is keyed by icon font family — [materialIconsFamily] and
  /// [cupertinoIconsFamily] today — and each inner map by code point. An
  /// omitted family contributes nothing. [mirrored] carries the icons whose
  /// glyph mirrors in a right-to-left locale, which share their code point
  /// with an entry in [families]. Both are named, so two maps of the same type
  /// cannot be swapped by mistake.
  ///
  /// The maps are stored exactly as given — nothing is copied, sorted or
  /// canonicalized — so this is usable as a `const` expression, including from
  /// generated code in another package.
  const RestageIconTable.fromFamilies({
    this.families = const <String, Map<int, IconData>>{},
    this.mirrored = const <String, Map<int, IconData>>{},
  });

  /// A table that contributes no icon at all.
  static const RestageIconTable none = RestageIconTable.fromFamilies();

  /// The font family of Flutter's Material icons, as it appears on the wire.
  static const String materialIconsFamily = 'MaterialIcons';

  /// The font family of Flutter's Cupertino icons, as it appears on the wire.
  static const String cupertinoIconsFamily = 'CupertinoIcons';

  /// The installed icons that do not mirror, keyed by font family and then by
  /// code point.
  final Map<String, Map<int, IconData>> families;

  /// The installed icons whose glyph mirrors in a right-to-left locale, keyed
  /// the same way.
  final Map<String, Map<int, IconData>> mirrored;

  /// Whether no family contributes an icon, mirroring or not.
  bool get isEmpty =>
      families.values.every((family) => family.isEmpty) &&
      mirrored.values.every((family) => family.isEmpty);

  /// The icon [fontFamily] gives to [codePoint], or `null` when the table
  /// carries no such entry.
  ///
  /// [matchTextDirection] selects the mirroring glyph for a code point that
  /// names two.
  IconData? lookUp(
    String fontFamily,
    int codePoint, {
    bool matchTextDirection = false,
  }) {
    final table = matchTextDirection ? mirrored : families;
    return table[fontFamily]?[codePoint];
  }
}

/// Process-wide store of the [RestageIconTable] every rendered Restage surface
/// resolves its icons through.
///
/// Each generated surface [add]s the icons it draws as it mounts, and the
/// generated catalog reads the store each time it builds an icon. The store
/// starts empty; ordinary `Restage.configure()` supplies both full families
/// only when no selection has been made.
abstract final class InstalledIconTable {
  InstalledIconTable._();

  static RestageIconTable _installed = RestageIconTable.none;
  static bool _hasSelection = false;

  /// Whether an installation or an explicit app vocabulary chose this store.
  ///
  /// An explicitly empty selection is distinct from an unconfigured store.
  static bool get hasSelection => _hasSelection;

  /// The installed table — [RestageIconTable.none] until [install].
  static RestageIconTable get current => _installed;

  /// Installs [table] for the rest of the process, replacing any prior
  /// installation.
  ///
  /// Replacing discards whatever a mounted surface already contributed through
  /// [add], so an app that installs explicitly does it before mounting any
  /// surface.
  ///
  /// For a preview or authoring tool that renders content it cannot know ahead
  /// of time: call once from app startup, before mounting a surface. An
  /// application's surfaces install what they draw through [add] instead.
  static void install(RestageIconTable table) {
    _hasSelection = true;
    _installed = table;
  }

  /// Adds [table] to what is already installed, one union per font family in
  /// each of the mirroring and non-mirroring maps.
  ///
  /// Where both carry the same code point in the same family and the same map,
  /// the already-installed icon wins, so adding never changes the glyph a code
  /// point already means. Adding [RestageIconTable.none] preserves the current
  /// object.
  ///
  /// Omitting [explicitSelection] treats a nonempty direct addition as an app
  /// selection. Pass false for an implicit surface contribution, or true to
  /// record an explicit selection even when empty. Only an explicit selection
  /// prevents ordinary configuration from widening to the full default.
  static void add(RestageIconTable table, {bool? explicitSelection}) {
    _hasSelection = _hasSelection || (explicitSelection ?? !table.isEmpty);
    if (table.isEmpty) return;
    _installed = RestageIconTable.fromFamilies(
      families: _union(_installed.families, table.families),
      mirrored: _union(_installed.mirrored, table.mirrored),
    );
  }

  /// Drops the installation and restores the [RestageIconTable.none] default,
  /// so a test cannot leak its installation into the next one.
  static void reset() {
    _hasSelection = false;
    _installed = RestageIconTable.none;
  }
}

/// Unions [added] into [installed] per font family, with the already-installed
/// entry winning wherever both carry the same code point.
Map<String, Map<int, IconData>> _union(
  Map<String, Map<int, IconData>> installed,
  Map<String, Map<int, IconData>> added,
) {
  final families = <String, Map<int, IconData>>{};
  for (final family in <String>{...installed.keys, ...added.keys}) {
    final current = installed[family];
    final incoming = added[family];
    if (current == null) {
      families[family] = incoming!;
    } else if (incoming == null) {
      families[family] = current;
    } else {
      families[family] = <int, IconData>{...incoming, ...current};
    }
  }
  return families;
}

/// Resolves the icon a delivered surface named by [codePoint] within
/// [fontFamily], through the app's [InstalledIconTable].
///
/// [matchTextDirection] picks the mirroring glyph where a code point names
/// both, so the two stay distinguishable.
///
/// The generated catalog calls this in place of building an [IconData] from
/// the code point directly, which is what forces an app to retain the whole
/// icon font.
///
/// Throws [RestageIconUnavailableError] when the installed table carries no
/// such entry. Rendering a substitute glyph instead would look like it worked,
/// so the miss fails the surface and reaches the host through the mount's
/// existing unavailable path.
IconData resolveInstalledIcon(
  int codePoint, {
  required String fontFamily,
  bool matchTextDirection = false,
}) {
  final icon = InstalledIconTable.current.lookUp(
    fontFamily,
    codePoint,
    matchTextDirection: matchTextDirection,
  );
  if (icon != null) return icon;
  throw RestageIconUnavailableError(
    fontFamily: fontFamily,
    codePoint: codePoint,
    matchTextDirection: matchTextDirection,
  );
}

/// Thrown when a delivered surface names an icon the installed
/// [RestageIconTable] does not carry.
///
/// An incomplete table is a wiring mistake rather than bad content, so this is
/// a plain [Error] and not an [AssertionError]: it is thrown in release as
/// well as debug, and failing the surface is what stops a substitute glyph
/// from painting.
final class RestageIconUnavailableError extends Error {
  /// Creates the miss for [codePoint] within [fontFamily].
  RestageIconUnavailableError({
    required this.fontFamily,
    required this.codePoint,
    this.matchTextDirection = false,
  });

  /// The icon font family the surface named.
  final String fontFamily;

  /// The code point the surface named.
  final int codePoint;

  /// Whether the surface named the mirroring glyph of that code point.
  final bool matchTextDirection;

  /// Names the missing code point, its font family and variant, and the fix.
  String get message =>
      'Icon code point 0x${codePoint.toRadixString(16)} in font family '
      '$fontFamily with matchTextDirection: $matchTextDirection is not in the '
      'installed icon table. One code point can name both a glyph that mirrors '
      'in a right-to-left locale and one that does not, and the two are looked '
      'up separately. Generated surface code installs the icons its own '
      'surface draws, so check that the surface is mounted through its '
      'generated reference. A preview or authoring tool that renders content '
      'it cannot know ahead of time passes a wider RestageIconTable to '
      'InstalledIconTable.install().';

  @override
  String toString() => message;
}
