import 'package:flutter/foundation.dart' show immutable, mapEquals, setEquals;
import 'package:flutter/widgets.dart';

/// One icon font delivered with a surface and loaded for this process.
@immutable
final class LoadedIconFont {
  /// Creates the entry for a font loaded as [loadedFamily] that covers
  /// [codePoints].
  const LoadedIconFont({
    required this.loadedFamily,
    required this.codePoints,
  });

  /// The family name the font was loaded under.
  final String loadedFamily;

  /// The code points the loaded font carries a glyph for.
  final Set<int> codePoints;

  @override
  bool operator ==(Object other) =>
      other is LoadedIconFont &&
      other.loadedFamily == loadedFamily &&
      setEquals(other.codePoints, codePoints);

  @override
  int get hashCode => Object.hash(loadedFamily, codePoints.length);
}

/// The icon fonts delivered with the surface below, keyed by the source font
/// family a surface names.
class DeliveredIconFonts extends InheritedWidget {
  /// Provides [fonts] to the surface in [child].
  const DeliveredIconFonts({
    required this.fonts,
    required super.child,
    super.key,
  });

  /// The delivered fonts, keyed by source font family.
  final Map<String, LoadedIconFont> fonts;

  /// The delivered font for [sourceFamily] in scope, or `null` when none is.
  static LoadedIconFont? lookUp(BuildContext context, String sourceFamily) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<DeliveredIconFonts>();
    return scope?.fonts[sourceFamily];
  }

  @override
  bool updateShouldNotify(DeliveredIconFonts oldWidget) =>
      !mapEquals(oldWidget.fonts, fonts);
}
