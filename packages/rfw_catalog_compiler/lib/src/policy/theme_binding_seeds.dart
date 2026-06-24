// packages/rfw_catalog_compiler/lib/src/policy/theme_binding_seeds.dart
import 'package:meta/meta.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
    show ThemeBindingPath;

/// (widget-name, property-name) → [ThemeBindingPath] seeds for
/// theme-binding inference.
@immutable
final class ThemeBindingSeeds {
  /// Creates a theme-binding seeds instance with the supplied patterns.
  const ThemeBindingSeeds({required this.namePatterns});

  /// Key shape: `'WidgetName.propertyName'`
  /// (e.g. `'Text.color'` →
  /// `ThemeBindingPath.path('defaultTextStyle.color')`).
  final Map<String, ThemeBindingPath> namePatterns;

  /// Returns a new instance that merges this instance's patterns with
  /// [namePatterns].
  ThemeBindingSeeds extend({
    Map<String, ThemeBindingPath> namePatterns = const {},
  }) =>
      ThemeBindingSeeds(
        namePatterns: {...this.namePatterns, ...namePatterns},
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ThemeBindingSeeds &&
          namePatterns.length == other.namePatterns.length &&
          namePatterns.entries
              .every((e) => other.namePatterns[e.key] == e.value));

  @override
  int get hashCode => Object.hashAllUnordered(
        namePatterns.entries.map((e) => Object.hash(e.key, e.value)),
      );
}
