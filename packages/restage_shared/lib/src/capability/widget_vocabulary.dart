import 'package:meta/meta.dart';

/// The exact widget names and icon code points a renderer can draw.
///
/// A capability floor answers "how new is this renderer"; a vocabulary answers
/// "can this renderer draw this widget and this icon". Names are namespaced
/// strings such as `restage.material:Icon` or `restage.core:Column`, spelled by
/// [qualifiedName] and treated as opaque identifiers here — the namespace
/// prefix is never parsed.
///
/// Every instance is canonical: names and code points are sorted ascending,
/// font families are sorted ascending, and all collections are unmodifiable.
/// Two vocabularies with the same members are equal and encode to the same
/// JSON regardless of the order they were built in.
@immutable
final class WidgetVocabulary {
  /// Creates a canonical vocabulary from [widgetNames] and [iconCodePoints].
  ///
  /// [widgetNames] holds namespaced widget names. [iconCodePoints] maps a font
  /// family to the icon code points available in it. Both default to empty.
  factory WidgetVocabulary({
    Set<String> widgetNames = const <String>{},
    Map<String, Set<int>> iconCodePoints = const <String, Set<int>>{},
  }) {
    final names = widgetNames.toList()..sort();

    final families = iconCodePoints.keys.toList()..sort();
    final canonicalIcons = <String, Set<int>>{};
    for (final family in families) {
      final codePoints = iconCodePoints[family]!.toList()..sort();
      canonicalIcons[family] = Set<int>.unmodifiable(codePoints);
    }

    return WidgetVocabulary._(
      widgetNames: Set<String>.unmodifiable(names),
      iconCodePoints: Map<String, Set<int>>.unmodifiable(canonicalIcons),
    );
  }

  const WidgetVocabulary._({
    required this.widgetNames,
    required this.iconCodePoints,
  });

  /// Decodes a vocabulary from its JSON wire form.
  ///
  /// Missing or `null` fields decode as empty. A field of the wrong type
  /// throws a [FormatException].
  factory WidgetVocabulary.fromJson(Map<String, dynamic> json) {
    final rawNames = json['widgetNames'];
    final widgetNames = <String>{};
    if (rawNames != null) {
      if (rawNames is! List) {
        throw FormatException('malformed WidgetVocabulary: $json');
      }
      for (final name in rawNames) {
        if (name is! String) {
          throw FormatException('malformed WidgetVocabulary: $json');
        }
        widgetNames.add(name);
      }
    }

    final rawIcons = json['iconCodePoints'];
    final iconCodePoints = <String, Set<int>>{};
    if (rawIcons != null) {
      if (rawIcons is! Map) {
        throw FormatException('malformed WidgetVocabulary: $json');
      }
      for (final entry in rawIcons.entries) {
        final family = entry.key;
        final rawCodePoints = entry.value;
        if (family is! String || rawCodePoints is! List) {
          throw FormatException('malformed WidgetVocabulary: $json');
        }
        final codePoints = <int>{};
        for (final codePoint in rawCodePoints) {
          if (codePoint is! int) {
            throw FormatException('malformed WidgetVocabulary: $json');
          }
          codePoints.add(codePoint);
        }
        iconCodePoints[family] = codePoints;
      }
    }

    return WidgetVocabulary(
      widgetNames: widgetNames,
      iconCodePoints: iconCodePoints,
    );
  }

  /// A vocabulary naming no widgets and no icons.
  static final WidgetVocabulary empty = WidgetVocabulary();

  /// The canonical spelling of [widgetName] in [libraryNamespace], such as
  /// `restage.material:Icon` — the one form every producer and consumer of
  /// [widgetNames] uses.
  ///
  /// The full library namespace is used, never an abbreviation of it, so two
  /// custom libraries sharing a last segment cannot collide. Throws an
  /// [ArgumentError] naming the offending input when either part is empty or
  /// contains the `:` separator.
  static String qualifiedName(String libraryNamespace, String widgetName) {
    if (libraryNamespace.isEmpty || libraryNamespace.contains(':')) {
      throw ArgumentError.value(
        libraryNamespace,
        'libraryNamespace',
        'must be non-empty and must not contain ":"',
      );
    }
    if (widgetName.isEmpty || widgetName.contains(':')) {
      throw ArgumentError.value(
        widgetName,
        'widgetName',
        'must be non-empty and must not contain ":"',
      );
    }
    return '$libraryNamespace:$widgetName';
  }

  /// Namespaced widget names, sorted ascending. Unmodifiable.
  final Set<String> widgetNames;

  /// Icon code points per font family, each sorted ascending and the families
  /// themselves sorted ascending. Unmodifiable.
  final Map<String, Set<int>> iconCodePoints;

  /// JSON wire form.
  Map<String, dynamic> toJson() => {
        'widgetNames': widgetNames.toList(),
        'iconCodePoints': <String, dynamic>{
          for (final entry in iconCodePoints.entries)
            entry.key: entry.value.toList(),
        },
      };

  /// Returns a canonical vocabulary naming everything in this one and in
  /// [other]: the union of widget names, and a per-family union of code
  /// points.
  WidgetVocabulary union(WidgetVocabulary other) {
    final mergedIcons = <String, Set<int>>{};
    for (final entry in iconCodePoints.entries) {
      mergedIcons[entry.key] = <int>{...entry.value};
    }
    for (final entry in other.iconCodePoints.entries) {
      (mergedIcons[entry.key] ??= <int>{}).addAll(entry.value);
    }

    return WidgetVocabulary(
      widgetNames: <String>{...widgetNames, ...other.widgetNames},
      iconCodePoints: mergedIcons,
    );
  }

  /// Whether this vocabulary names everything [other] names.
  ///
  /// True when every widget name in [other] is present here and, for every
  /// font family in [other], every one of its code points is present here. An
  /// empty [other] is always contained.
  bool containsAll(WidgetVocabulary other) {
    if (!widgetNames.containsAll(other.widgetNames)) return false;
    for (final entry in other.iconCodePoints.entries) {
      final installed = iconCodePoints[entry.key];
      if (installed == null) {
        if (entry.value.isEmpty) continue;
        return false;
      }
      if (!installed.containsAll(entry.value)) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! WidgetVocabulary) return false;
    if (other.widgetNames.length != widgetNames.length) return false;
    if (!widgetNames.containsAll(other.widgetNames)) return false;
    if (other.iconCodePoints.length != iconCodePoints.length) return false;
    for (final entry in iconCodePoints.entries) {
      final theirs = other.iconCodePoints[entry.key];
      if (theirs == null || theirs.length != entry.value.length) return false;
      if (!theirs.containsAll(entry.value)) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    // Collection hashes are identity-based, so fold the canonical order.
    var iconHash = 0;
    for (final entry in iconCodePoints.entries) {
      iconHash = Object.hash(iconHash, entry.key, Object.hashAll(entry.value));
    }
    return Object.hash(Object.hashAll(widgetNames), iconHash);
  }
}
