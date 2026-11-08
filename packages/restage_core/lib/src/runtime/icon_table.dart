import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart'
    show BuildContext, Color, Icon, IconData, Key, TextDirection, Widget;

import '../widgets/delivered_icon_fonts.dart';
import '../widgets/restage_delivered_icon.dart';

/// The icons a Restage surface can render, as one code-point table per icon
/// font family.
///
/// A delivered surface document carries an icon as its integer code point and
/// font family, and this value decides which glyph that pair means for this
/// app. Generated registration and surface references add their icons;
/// `Restage.configure()` preserves that selection. Literal icons absent from
/// this table can render through a surface's delivered subset font.
///
/// A few code points name two glyphs within one family — one that mirrors in a
/// right-to-left locale and one that does not — so the mirroring ones live in
/// their own [mirrored] map and a surface selects between them.
///
/// A host can also add an explicit table during app startup:
///
/// ```dart
/// void main() {
///   InstalledIconTable.add(
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
///  * [restageIcon], which builds a surface's icon from this table.
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
/// starts empty; ordinary `Restage.configure()` does not add icon families.
abstract final class InstalledIconTable {
  InstalledIconTable._();

  static RestageIconTable _installed = RestageIconTable.none;
  static bool _snapshotted = false;

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
    _installed = table;
    _snapshotted = false;
  }

  /// Adds [table] to what is already installed, one union per font family in
  /// each of the mirroring and non-mirroring maps.
  ///
  /// Where both carry the same code point in the same family and the same map,
  /// the already-installed icon wins, so adding never changes the glyph a code
  /// point already means. Adding [RestageIconTable.none] preserves the current
  /// object.
  static void add(RestageIconTable table) {
    if (table.isEmpty) return;
    // A mount adds its icons on every build; once the table holds its own
    // copies, nothing new keeps it.
    if (_snapshotted &&
        _covers(_installed.families, table.families) &&
        _covers(_installed.mirrored, table.mirrored)) {
      return;
    }
    _installed = RestageIconTable.fromFamilies(
      families: _union(_installed.families, table.families),
      mirrored: _union(_installed.mirrored, table.mirrored),
    );
    _snapshotted = true;
  }

  /// Drops the installation and restores the [RestageIconTable.none] default,
  /// so a test cannot leak its installation into the next one.
  static void reset() {
    _installed = RestageIconTable.none;
    _snapshotted = false;
  }
}

/// Whether [installed] already carries every code point of [added].
bool _covers(
  Map<String, Map<int, IconData>> installed,
  Map<String, Map<int, IconData>> added,
) =>
    added.entries.every((entry) {
      final family = installed[entry.key];
      return family != null && entry.value.keys.every(family.containsKey);
    });

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

/// Builds the icon a surface names by [codePoint] within [fontFamily].
///
/// The installed table wins; otherwise a font delivered with the surface that
/// covers the code point draws it. Throws [RestageIconUnavailableError] when
/// neither carries it.
Widget restageIcon(
  BuildContext context, {
  Key? key,
  required int codePoint,
  String? fontFamily,
  bool matchTextDirection = false,
  double? size,
  Color? color,
  String? semanticLabel,
  TextDirection? textDirection,
}) {
  final family = fontFamily ?? RestageIconTable.materialIconsFamily;
  final installed = InstalledIconTable.current.lookUp(
    family,
    codePoint,
    matchTextDirection: matchTextDirection,
  );
  if (installed != null) {
    return Icon(
      installed,
      key: key,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
      textDirection: textDirection,
    );
  }
  if (key != null) {
    // Delivered fonts use a different widget type and cannot retain Icon's
    // native key owner. Use the existing unavailable-icon fallback boundary.
    throw RestageIconUnavailableError(
        fontFamily: family,
        codePoint: codePoint,
        matchTextDirection: matchTextDirection,
        requiresNativeIcon: true);
  }
  final delivered = DeliveredIconFonts.lookUp(context, family);
  if (delivered != null && delivered.codePoints.contains(codePoint)) {
    return RestageDeliveredIcon(
      codePoint: codePoint,
      fontFamily: delivered.loadedFamily,
      matchTextDirection: matchTextDirection,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
      textDirection: textDirection,
    );
  }
  throw RestageIconUnavailableError(
    fontFamily: family,
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
    this.requiresNativeIcon = false,
  });

  /// Whether a native key requires an actual Icon owner.
  final bool requiresNativeIcon;

  /// The icon font family the surface named.
  final String fontFamily;

  /// The code point the surface named.
  final int codePoint;

  /// Whether the surface named the mirroring glyph of that code point.
  final bool matchTextDirection;

  /// Names the missing code point, its font family and variant, and the fix.
  String get message {
    final icon = 'The icon 0x${codePoint.toRadixString(16)} in font family '
        '$fontFamily${matchTextDirection ? ' with matchTextDirection: true' : ''}';
    const all = '`InstalledIconTable.add(builtInIconTable())` keeps every '
        'built-in icon.';
    return requiresNativeIcon
        ? '$icon has a key, so it must be in the installed icon table, and '
            "it isn't. Try removing the key, or add the icon at startup with "
            '`InstalledIconTable.add()` and release a build. $all'
        : "$icon isn't in the installed icon table, and the surface carries "
            'no font that draws it. Try including the icon in the app: draw '
            "it in the app's own code, or add it at startup with "
            '`InstalledIconTable.add()`, then release a build. $all';
  }

  @override
  String toString() => message;
}
