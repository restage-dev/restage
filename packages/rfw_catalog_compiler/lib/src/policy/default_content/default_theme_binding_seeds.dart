// packages/rfw_catalog_compiler/lib/src/policy/default_content/default_theme_binding_seeds.dart
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
    show ThemeBindingPath;

/// Initial closed set of (widget, property) → ThemeBindingPath seeds.
/// Key shape: `'WidgetName.propertyName'`.
const Map<String, ThemeBindingPath> kBuiltInThemeBindingSeeds = {
  'Text.color': ThemeBindingPath.path('defaultTextStyle.color'),
  'Text.fontSize': ThemeBindingPath.path('defaultTextStyle.fontSize'),
  'Text.fontWeight': ThemeBindingPath.path('defaultTextStyle.fontWeight'),
  'Icon.color': ThemeBindingPath.path('iconTheme.color'),
  'Icon.size': ThemeBindingPath.path('iconTheme.size'),
  'FilledButton.backgroundColor': ThemeBindingPath.path('colorScheme.primary'),
  'FilledButton.foregroundColor':
      ThemeBindingPath.path('colorScheme.onPrimary'),
  'ElevatedButton.backgroundColor':
      ThemeBindingPath.path('colorScheme.primary'),
  'ElevatedButton.foregroundColor':
      ThemeBindingPath.path('colorScheme.onPrimary'),
  'OutlinedButton.foregroundColor':
      ThemeBindingPath.path('colorScheme.primary'),
  'TextButton.foregroundColor': ThemeBindingPath.path('colorScheme.primary'),
  'Card.color': ThemeBindingPath.path('colorScheme.surface'),
  'Container.color': ThemeBindingPath.path('colorScheme.surface'),
};
