import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart' show WidgetVocabulary;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Where Flutter declares `IconData`.
const String _kFlutterPackagePrefix = 'package:flutter/';

/// Every field `IconData`'s const constructor takes, which is every field a
/// reconstruction has to copy.
const Set<String> _kIconDataFields = <String>{
  'codePoint',
  'fontFamily',
  'fontPackage',
  'matchTextDirection',
  'fontFamilyFallback',
};

/// The `RestageWidgetLibraries.fromVocabulary` argument each built-in
/// namespace fills.
final Map<String, String> _kBuiltInNamespaceArguments = Map.unmodifiable({
  WidgetLibrary.core.namespace: 'core',
  WidgetLibrary.material.namespace: 'material',
  WidgetLibrary.cupertino.namespace: 'cupertino',
});

/// An icon a delivered surface cannot carry exactly as its source names it.
///
/// A surface that renders one fails the build rather than delivering an icon
/// that would render differently from the constant the author wrote.
abstract interface class IconCarriageFailure implements Exception {
  /// Why the icon cannot be carried, phrased as a clause that reads after the
  /// icon's name.
  String get reason;
}

/// A const `IconData` that cannot be rebuilt field for field.
///
/// Raised rather than dropping a field: a Flutter release that adds one to
/// `IconData` has to fail the build, not silently change how an icon renders.
@immutable
final class IconDataReconstructionFailure implements IconCarriageFailure {
  /// Creates a failure explaining [reason], which reads after the icon name.
  const IconDataReconstructionFailure(this.reason);

  /// Why the constant cannot be rebuilt, phrased as a clause.
  @override
  final String reason;

  @override
  String toString() => 'IconDataReconstructionFailure: $reason';
}

/// An `IconData` that names no font family.
///
/// The icon table is keyed by family, so such an icon cannot be carried at
/// all. A surface that renders one fails the build rather than delivering a
/// bare code point the runtime would look up under the Material family and
/// throw on. A walk that only censuses what an app could deliver passes it
/// over instead.
@immutable
final class IconFontFamilyMissing implements IconCarriageFailure {
  /// Creates the refusal.
  const IconFontFamilyMissing();

  @override
  String get reason =>
      'it names no font family, and an icon a delivered surface renders must '
      'name the family its glyph is looked up in';

  @override
  String toString() => 'IconFontFamilyMissing: $reason';
}

/// Two icons that share a font family, a code point and their mirroring but
/// rebuild to different values.
///
/// The delivered surface carries the family, the code point and whether the
/// icon mirrors. Two icons agreeing on all three and differing anywhere else —
/// the font package, the fallback families — are what the runtime genuinely
/// cannot tell apart, and installing whichever one sorted first would change
/// how the other renders with no diagnostic.
@immutable
final class IconCodePointCollision implements IconCarriageFailure {
  /// Creates the collision between the already-carried [carried] and the newly
  /// met [met], which share a font family, a code point and their mirroring.
  factory IconCodePointCollision(
    IconDataReference carried,
    IconDataReference met,
  ) {
    final spellings = <String>[carried.spelling(), met.spelling()]..sort();
    return IconCodePointCollision._(
      fontFamily: met.fontFamily,
      codePoint: met.codePoint,
      matchTextDirection: met.matchTextDirection,
      firstSpelling: spellings.first,
      secondSpelling: spellings.last,
    );
  }

  const IconCodePointCollision._({
    required this.fontFamily,
    required this.codePoint,
    required this.matchTextDirection,
    required this.firstSpelling,
    required this.secondSpelling,
  });

  /// The font family both icons name.
  final String fontFamily;

  /// The glyph both icons select within [fontFamily].
  final int codePoint;

  /// The mirroring both icons declare, which the wire carries as well.
  final bool matchTextDirection;

  /// The lower of the two rebuilt spellings. The pair is ordered so the
  /// message does not depend on which icon was met first.
  final String firstSpelling;

  /// The higher of the two rebuilt spellings.
  final String secondSpelling;

  @override
  String get reason =>
      'it shares code point 0x${codePoint.toRadixString(16)} in font family '
      "'$fontFamily', and its mirroring, with another icon that rebuilds "
      'differently — $firstSpelling and $secondSpelling. A delivered surface '
      'carries nothing that tells those two apart, so render one of the two';

  @override
  String toString() => 'IconCodePointCollision: two icons share code point '
      "0x${codePoint.toRadixString(16)} in font family '$fontFamily' and "
      'mirror alike, but rebuild differently — $firstSpelling and '
      '$secondSpelling.';
}

/// One compile-time `IconData` a surface renders, carrying every field the
/// const constructor takes.
///
/// Generated code rebuilds the value rather than naming the constant that
/// holds it: a generated surface reference is a part of its authored file,
/// which imports the SDK but not necessarily the library declaring the icon.
@immutable
final class IconDataReference {
  /// Creates a reference to the glyph [codePoint] in [fontFamily].
  const IconDataReference({
    required this.codePoint,
    required this.fontFamily,
    this.fontPackage,
    this.matchTextDirection = false,
    this.fontFamilyFallback,
  });

  /// The glyph the icon selects within [fontFamily].
  final int codePoint;

  /// The icon font family. The vocabulary keys icons by it, so an icon naming
  /// no family cannot be carried and fails the build instead.
  final String fontFamily;

  /// The package shipping [fontFamily], or `null` when the app ships it.
  final String? fontPackage;

  /// Whether the icon mirrors under a right-to-left directionality.
  final bool matchTextDirection;

  /// The families to fall back on, or `null` when the icon declares none.
  final List<String>? fontFamilyFallback;

  /// The `IconData(…)` expression rebuilding this icon, for a const context.
  ///
  /// [sdkPrefix] qualifies `IconData`, which generated code reaches through
  /// the Restage SDK. Every argument equal to the constructor default is left
  /// out, so the emission stays minimal and byte-stable.
  String spelling([String sdkPrefix = '']) {
    final buffer = StringBuffer(
      '${sdkPrefix}IconData(0x${codePoint.toRadixString(16)}',
    )..write(', fontFamily: ${_dartStringLiteral(fontFamily)}');
    final package = fontPackage;
    if (package != null) {
      buffer.write(', fontPackage: ${_dartStringLiteral(package)}');
    }
    if (matchTextDirection) buffer.write(', matchTextDirection: true');
    final fallback = fontFamilyFallback;
    if (fallback != null) {
      final families = fallback.map(_dartStringLiteral).join(', ');
      buffer.write(', fontFamilyFallback: <String>[$families]');
    }
    buffer.write(')');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is IconDataReference &&
      other.codePoint == codePoint &&
      other.fontFamily == fontFamily &&
      other.fontPackage == fontPackage &&
      other.matchTextDirection == matchTextDirection &&
      _sameFallback(other.fontFamilyFallback, fontFamilyFallback);

  @override
  int get hashCode => Object.hash(
        codePoint,
        fontFamily,
        fontPackage,
        matchTextDirection,
        Object.hashAll(fontFamilyFallback ?? const <String>[]),
      );
}

bool _sameFallback(List<String>? left, List<String>? right) {
  if (left == null || right == null) return left == right;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// Whether [value] is an instance of Flutter's `IconData`.
bool isIconDataValue(DartObject value) {
  final type = value.type;
  if (type is! InterfaceType) return false;
  for (final candidate in <InterfaceType>[type, ...type.allSupertypes]) {
    final element = candidate.element;
    if (element.name == 'IconData' &&
        element.library.identifier.startsWith(_kFlutterPackagePrefix)) {
      return true;
    }
  }
  return false;
}

/// A faithful, field-for-field reconstruction of the const `IconData` [value].
///
/// Throws [IconDataReconstructionFailure] when a field cannot be copied
/// exactly, including a field this generator does not know about, and
/// [IconFontFamilyMissing] when the constant names no font family.
IconDataReference iconDataReference(DartObject value) {
  _requireKnownIconDataFields(value);
  final codePoint = value.getField('codePoint')?.toIntValue();
  if (codePoint == null) {
    throw const IconDataReconstructionFailure(
      "its 'codePoint' is not a constant integer",
    );
  }
  final fontFamily = value.getField('fontFamily')?.toStringValue();
  if (fontFamily == null || fontFamily.isEmpty) {
    throw const IconFontFamilyMissing();
  }
  return IconDataReference(
    codePoint: codePoint,
    fontFamily: fontFamily,
    fontPackage: _optionalString(value, 'fontPackage'),
    matchTextDirection: _requiredBool(value, 'matchTextDirection'),
    fontFamilyFallback: _optionalStringList(value, 'fontFamilyFallback'),
  );
}

/// Refuses an `IconData` whose fields are not exactly the set rebuilt here.
void _requireKnownIconDataFields(DartObject value) {
  final type = value.type;
  if (type is! InterfaceType) {
    throw const IconDataReconstructionFailure('its type did not resolve');
  }
  final declared = <String>{};
  for (final candidate in <InterfaceType>[type, ...type.allSupertypes]) {
    for (final field in candidate.element.fields) {
      // A getter-induced field declares no state, so it is not one to rebuild.
      // Named exactly: a field from a declaring formal parameter DOES declare
      // state, and reads as `!isOriginDeclaration` too.
      if (field.isStatic || field.isOriginGetterSetter) continue;
      final name = field.name;
      if (name != null) declared.add(name);
    }
  }
  if (declared.length == _kIconDataFields.length &&
      declared.containsAll(_kIconDataFields)) {
    return;
  }
  final unexpected = declared.difference(_kIconDataFields).toList()..sort();
  final missing = _kIconDataFields.difference(declared).toList()..sort();
  throw IconDataReconstructionFailure(
    'its fields are not the ones this build rebuilds'
    '${unexpected.isEmpty ? '' : ' (unexpected: ${unexpected.join(', ')})'}'
    '${missing.isEmpty ? '' : ' (missing: ${missing.join(', ')})'}. '
    'Every IconData field must be copied, so extend the reconstruction '
    'rather than shipping an icon with a dropped field',
  );
}

String? _optionalString(DartObject value, String field) {
  final read = value.getField(field);
  if (read == null) {
    throw IconDataReconstructionFailure("its '$field' could not be read");
  }
  if (read.isNull) return null;
  final text = read.toStringValue();
  if (text == null) {
    throw IconDataReconstructionFailure(
      "its '$field' is not a constant string",
    );
  }
  return text;
}

bool _requiredBool(DartObject value, String field) {
  final read = value.getField(field)?.toBoolValue();
  if (read == null) {
    throw IconDataReconstructionFailure(
      "its '$field' is not a constant boolean",
    );
  }
  return read;
}

List<String>? _optionalStringList(DartObject value, String field) {
  final read = value.getField(field);
  if (read == null) {
    throw IconDataReconstructionFailure("its '$field' could not be read");
  }
  if (read.isNull) return null;
  final elements = read.toListValue();
  if (elements == null) {
    throw IconDataReconstructionFailure(
      "its '$field' is not a constant list",
    );
  }
  final families = <String>[];
  for (final element in elements) {
    final family = element.toStringValue();
    if (family == null) {
      throw IconDataReconstructionFailure(
        "its '$field' holds a value that is not a constant string",
      );
    }
    families.add(family);
  }
  return families;
}

String _dartStringLiteral(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  return "'$escaped'";
}

/// [family] re-keyed in ascending code-point order, which is what makes a
/// regenerated table byte-stable.
Map<int, IconDataReference> _byAscendingCodePoint(
  Map<int, IconDataReference> family,
) {
  final entries = family.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return Map<int, IconDataReference>.unmodifiable(
    <int, IconDataReference>{
      for (final entry in entries) entry.key: entry.value,
    },
  );
}

/// [byFamily] re-keyed in ascending family and, within each, code-point order.
Map<String, Map<int, IconDataReference>> _canonicalFamilies(
  Map<String, Map<int, IconDataReference>> byFamily,
) {
  final families = byFamily.keys.toList()..sort();
  return Map<String, Map<int, IconDataReference>>.unmodifiable(
    <String, Map<int, IconDataReference>>{
      for (final family in families)
        family: _byAscendingCodePoint(byFamily[family]!),
    },
  );
}

/// The icons one translation — or one library walk — meets, refusing a second
/// icon that shares a font family, code point and mirroring with a different
/// rebuilt value.
///
/// Mirroring travels on the wire, so the two members of a mirroring pair are
/// separately addressable entries rather than a collision, and are collected
/// apart. Folding two references onto one (family, code point, mirroring) is
/// silent only when they rebuild to the identical value, field for field.
final class IconReferenceCollector {
  final Map<String, Map<int, IconDataReference>> _byFamily =
      <String, Map<int, IconDataReference>>{};
  final Map<String, Map<int, IconDataReference>> _mirroredByFamily =
      <String, Map<int, IconDataReference>>{};

  /// Records [icon].
  ///
  /// Throws [IconCodePointCollision] when an icon already recorded shares its
  /// family, code point and mirroring but rebuilds to a different value.
  void add(IconDataReference icon) {
    final table = icon.matchTextDirection ? _mirroredByFamily : _byFamily;
    final family = table[icon.fontFamily] ??= <int, IconDataReference>{};
    final carried = family[icon.codePoint];
    if (carried == null) {
      family[icon.codePoint] = icon;
      return;
    }
    if (carried != icon) throw IconCodePointCollision(carried, icon);
  }

  /// Records every icon in [icons], in order.
  void addAll(Iterable<IconDataReference> icons) => icons.forEach(add);

  /// Every recorded icon that does not mirror, keyed by font family and then
  /// by code point, both ascending — the order that makes a regenerated table
  /// byte-stable.
  Map<String, Map<int, IconDataReference>> get byFamily =>
      _canonicalFamilies(_byFamily);

  /// Every recorded icon that mirrors under a right-to-left directionality,
  /// keyed the same way.
  Map<String, Map<int, IconDataReference>> get mirroredByFamily =>
      _canonicalFamilies(_mirroredByFamily);

  /// Every icon recorded, the non-mirroring ones first, each half ordered by
  /// family and then by code point.
  List<IconDataReference> get references =>
      List<IconDataReference>.unmodifiable(<IconDataReference>[
        for (final family in byFamily.values) ...family.values,
        for (final family in mirroredByFamily.values) ...family.values,
      ]);
}

/// The catalog widgets and icons one surface — or one whole app — needs
/// installed to render.
///
/// Both halves are canonical: widget names sort ascending, families and code
/// points sort ascending. Two builds of one input emit the same bytes.
@immutable
final class SurfaceVocabularyReferences {
  /// Creates a canonical set from [widgetNames] and [icons].
  ///
  /// [icons] takes mirroring and non-mirroring icons together; each is routed
  /// to the half it belongs in. Throws [IconCodePointCollision] when two of
  /// them share a font family, code point and mirroring but rebuild
  /// differently.
  factory SurfaceVocabularyReferences({
    Iterable<String> widgetNames = const <String>[],
    Iterable<IconDataReference> icons = const <IconDataReference>[],
  }) {
    final names = widgetNames.toSet().toList()..sort();
    final collected = IconReferenceCollector()..addAll(icons);
    return SurfaceVocabularyReferences._(
      widgetNames: Set<String>.unmodifiable(names),
      icons: collected.byFamily,
      mirroredIcons: collected.mirroredByFamily,
    );
  }

  const SurfaceVocabularyReferences._({
    required this.widgetNames,
    required this.icons,
    required this.mirroredIcons,
  });

  /// A set naming no widget and no icon.
  static const SurfaceVocabularyReferences empty =
      SurfaceVocabularyReferences._(
    widgetNames: <String>{},
    icons: <String, Map<int, IconDataReference>>{},
    mirroredIcons: <String, Map<int, IconDataReference>>{},
  );

  /// Namespaced catalog widget names, sorted ascending.
  final Set<String> widgetNames;

  /// Icons that do not mirror, keyed by font family and then by code point.
  final Map<String, Map<int, IconDataReference>> icons;

  /// Icons that mirror under a right-to-left directionality, keyed the same
  /// way. One code point can appear in both halves, naming two glyphs.
  final Map<String, Map<int, IconDataReference>> mirroredIcons;

  /// Whether nothing at all is named.
  bool get isEmpty =>
      widgetNames.isEmpty && icons.isEmpty && mirroredIcons.isEmpty;

  /// Whether anything here is installable at render time — a built-in widget
  /// or an icon. A custom-library widget is not: it reaches the runtime
  /// through the app's generated factories instead.
  bool get namesInstallable =>
      icons.isNotEmpty ||
      mirroredIcons.isNotEmpty ||
      widgetNames.any((qualified) {
        final separator = qualified.indexOf(':');
        return separator > 0 &&
            _kBuiltInNamespaceArguments.containsKey(
              qualified.substring(0, separator),
            );
      });

  /// Every icon, the non-mirroring ones first, each half ordered by family and
  /// then by code point.
  Iterable<IconDataReference> get orderedIcons sync* {
    for (final family in icons.values) {
      yield* family.values;
    }
    for (final family in mirroredIcons.values) {
      yield* family.values;
    }
  }

  /// The wire-shaped vocabulary these references describe.
  WidgetVocabulary get vocabulary {
    final codePoints = <String, Set<int>>{};
    for (final icon in orderedIcons) {
      (codePoints[icon.fontFamily] ??= <int>{}).add(icon.codePoint);
    }
    return WidgetVocabulary(
      widgetNames: widgetNames,
      iconCodePoints: codePoints,
    );
  }

  /// A canonical set naming everything here and everything in [other].
  ///
  /// Throws [IconCodePointCollision] when the two sides disagree on what one
  /// font family, code point and mirroring renders.
  SurfaceVocabularyReferences union(SurfaceVocabularyReferences other) =>
      SurfaceVocabularyReferences(
        widgetNames: <String>{...widgetNames, ...other.widgetNames},
        icons: [...orderedIcons, ...other.orderedIcons],
      );
}

/// A running union of several surfaces' vocabularies that remembers which
/// surface first contributed each icon.
///
/// Two surfaces can each be carriable and still disagree on what one font
/// family, code point and mirroring renders. The attribution is what lets that
/// refusal name both sides instead of only the one being folded in.
final class VocabularyUnionBuilder {
  final Map<String, String> _owners = <String, String>{};
  SurfaceVocabularyReferences _union = SurfaceVocabularyReferences.empty;

  /// Everything folded in so far.
  SurfaceVocabularyReferences get union => _union;

  /// Folds [vocabulary] in, attributed to [owner].
  ///
  /// Throws the union's [IconCarriageFailure] unchanged, leaving this builder
  /// as it was before the call.
  void add(SurfaceVocabularyReferences vocabulary, String owner) {
    _union = _union.union(vocabulary);
    for (final icon in vocabulary.orderedIcons) {
      _owners.putIfAbsent(
        _ownerKey(icon.fontFamily, icon.codePoint, icon.matchTextDirection),
        () => owner,
      );
    }
  }

  /// The owner that first contributed the icon [failure] collided with, or
  /// `null` when [failure] is not a collision or nothing carried it yet.
  String? ownerOf(IconCarriageFailure failure) {
    if (failure is! IconCodePointCollision) return null;
    return _owners[_ownerKey(
      failure.fontFamily,
      failure.codePoint,
      failure.matchTextDirection,
    )];
  }
}

String _ownerKey(String fontFamily, int codePoint, bool matchTextDirection) =>
    '$fontFamily\u0000$codePoint\u0000$matchTextDirection';

/// The catalog widgets [entries] name, as a reference set.
SurfaceVocabularyReferences referencesOfCatalogEntries(
  Iterable<WidgetEntry> entries,
) =>
    SurfaceVocabularyReferences(
      widgetNames: [
        for (final entry in entries)
          WidgetVocabulary.qualifiedName(entry.library.namespace, entry.name),
      ],
    );

/// The `SurfaceVocabulary(…)` expression naming [references], for a `const`
/// context.
///
/// [sdkPrefix] qualifies the SDK types, the re-exported per-widget builder
/// functions, and `IconData`. Custom-library widgets are left out — an app
/// registers those through its generated factories.
String emitSurfaceVocabulary(
  SurfaceVocabularyReferences references, {
  String sdkPrefix = '',
}) {
  final buildersByArgument = <String, List<String>>{};
  for (final qualified in references.widgetNames) {
    final separator = qualified.indexOf(':');
    if (separator <= 0) continue;
    final argument =
        _kBuiltInNamespaceArguments[qualified.substring(0, separator)];
    if (argument == null) continue;
    (buildersByArgument[argument] ??= <String>[])
        .add(qualified.substring(separator + 1));
  }
  final hasWidgets = buildersByArgument.isNotEmpty;
  final hasMirroredIcons = references.mirroredIcons.isNotEmpty;
  final hasIcons = references.icons.isNotEmpty || hasMirroredIcons;
  if (!hasWidgets && !hasIcons) return '${sdkPrefix}SurfaceVocabulary.none';

  final buffer = StringBuffer('${sdkPrefix}SurfaceVocabulary(');
  if (hasWidgets) {
    buffer.write('widgets: ${sdkPrefix}RestageWidgetLibraries.fromVocabulary(');
    for (final argument in const ['core', 'material', 'cupertino']) {
      final names = buildersByArgument[argument];
      if (names == null) continue;
      buffer.write('$argument: {');
      for (final name in names) {
        buffer.write("'$name': ${sdkPrefix}build$name,");
      }
      buffer.write('},');
    }
    buffer.write('),');
  }
  if (hasIcons) {
    buffer.write('icons: ${sdkPrefix}RestageIconTable.fromFamilies(families: ');
    _writeIconFamilies(buffer, references.icons, sdkPrefix);
    // The mirroring map is written only when a surface names such an icon.
    if (hasMirroredIcons) {
      buffer.write(', mirrored: ');
      _writeIconFamilies(buffer, references.mirroredIcons, sdkPrefix);
    }
    buffer.write('),');
  }
  buffer.write(')');
  return buffer.toString();
}

/// Writes [byFamily] as one `RestageIconTable.fromFamilies` map argument.
void _writeIconFamilies(
  StringBuffer buffer,
  Map<String, Map<int, IconDataReference>> byFamily,
  String sdkPrefix,
) {
  buffer.write('{');
  for (final family in byFamily.entries) {
    buffer.write("'${family.key}': {");
    for (final icon in family.value.entries) {
      buffer.write(
        '0x${icon.key.toRadixString(16)}: ${icon.value.spelling(sdkPrefix)},',
      );
    }
    buffer.write('},');
  }
  buffer.write('}');
}
