import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:restage_shared/restage_shared.dart';

import 'canonical_colors.dart';

/// Reads an admitted projection at the actual native callback context.
Object? readBuilderContext(BuildContext context, String name) {
  final location = builderContextLocation(name);
  if (location == null ||
      location.ancestorDepth != 0 ||
      builderContextValueType(name) == null) {
    throw FormatException('Unknown native context projection $name');
  }
  if (name.startsWith('context:device:')) {
    final path = name.substring('context:device:'.length);
    if (path == 'defaultTargetPlatform') return defaultTargetPlatform.name;
    if (path == 'locale') return Localizations.localeOf(context).toString();
    if (path == 'languageCode') {
      return Localizations.localeOf(context).languageCode;
    }
    if (path == 'countryCode') {
      return Localizations.localeOf(context).countryCode;
    }
    if (path == 'platform') return Theme.of(context).platform.name;
    final media = MediaQuery.of(context);
    return switch (path) {
      'screenWidth' => media.size.width,
      'screenHeight' => media.size.height,
      'shortestSide' => media.size.shortestSide,
      'longestSide' => media.size.longestSide,
      'orientation' => media.orientation.name,
      'pixelRatio' => media.devicePixelRatio,
      'safeAreaTop' => media.padding.top,
      'safeAreaBottom' => media.padding.bottom,
      'safeAreaLeft' => media.padding.left,
      'safeAreaRight' => media.padding.right,
      'viewPaddingTop' => media.viewPadding.top,
      'viewPaddingBottom' => media.viewPadding.bottom,
      'viewPaddingLeft' => media.viewPadding.left,
      'viewPaddingRight' => media.viewPadding.right,
      'viewInsetsTop' => media.viewInsets.top,
      'viewInsetsBottom' => media.viewInsets.bottom,
      'viewInsetsLeft' => media.viewInsets.left,
      'viewInsetsRight' => media.viewInsets.right,
      'boldText' => media.boldText,
      'disableAnimations' => media.disableAnimations,
      'accessibleNavigation' => media.accessibleNavigation,
      'highContrast' => media.highContrast,
      _ => throw FormatException('Unknown device projection $path'),
    };
  }
  final path = name.substring('context:theme:'.length).split('.');
  final theme = Theme.of(context);
  Object? value = switch (path.first) {
    'brightness' => theme.brightness.name,
    'colorScheme' => _colorSchemeData(theme.colorScheme),
    'textTheme' => _textThemeData(theme.textTheme),
    'defaultTextStyle' => _textStyleData(DefaultTextStyle.of(context).style),
    'iconTheme' => {
        'color': _colorData(theme.iconTheme.color),
        'size': theme.iconTheme.size
      },
    _ => throw FormatException('Unknown theme projection $name'),
  };
  for (final part in path.skip(1)) {
    value = (value as Map<String, Object?>?)?[part];
  }
  return value;
}

Map<String, Object?> _textThemeData(TextTheme textTheme) => <String, Object?>{
      'displayLarge': _textStyleData(textTheme.displayLarge),
      'displayMedium': _textStyleData(textTheme.displayMedium),
      'displaySmall': _textStyleData(textTheme.displaySmall),
      'headlineLarge': _textStyleData(textTheme.headlineLarge),
      'headlineMedium': _textStyleData(textTheme.headlineMedium),
      'headlineSmall': _textStyleData(textTheme.headlineSmall),
      'titleLarge': _textStyleData(textTheme.titleLarge),
      'titleMedium': _textStyleData(textTheme.titleMedium),
      'titleSmall': _textStyleData(textTheme.titleSmall),
      'bodyLarge': _textStyleData(textTheme.bodyLarge),
      'bodyMedium': _textStyleData(textTheme.bodyMedium),
      'bodySmall': _textStyleData(textTheme.bodySmall),
      'labelLarge': _textStyleData(textTheme.labelLarge),
      'labelMedium': _textStyleData(textTheme.labelMedium),
      'labelSmall': _textStyleData(textTheme.labelSmall),
    };

/// The admitted fields of one native text style.
Map<String, Object?> _textStyleData(TextStyle? style) {
  if (style == null) {
    return const <String, Object?>{builderStylePresenceField: false};
  }
  final color = style.color;
  final backgroundColor = style.backgroundColor;
  final fontFamily = style.fontFamily;
  final fontFamilyFallback = style.fontFamilyFallback;
  final fontSize = style.fontSize;
  final fontWeight = style.fontWeight;
  final fontStyle = style.fontStyle;
  final letterSpacing = style.letterSpacing;
  final wordSpacing = style.wordSpacing;
  final height = style.height;
  final leadingDistribution = style.leadingDistribution;
  final textBaseline = style.textBaseline;
  final overflow = style.overflow;
  final decoration = style.decoration;
  final decorationColor = style.decorationColor;
  final decorationStyle = style.decorationStyle;
  final decorationThickness = style.decorationThickness;
  return <String, Object?>{
    builderStylePresenceField: true,
    if (color != null) 'color': _colorData(color),
    if (backgroundColor != null) 'backgroundColor': _colorData(backgroundColor),
    if (fontFamily != null) 'fontFamily': fontFamily,
    if (fontFamilyFallback != null)
      'fontFamilyFallback': List<Object?>.of(fontFamilyFallback),
    if (fontSize != null) 'fontSize': fontSize,
    if (fontWeight != null) 'fontWeight': fontWeight.value,
    if (fontStyle != null) 'fontStyle': fontStyle.name,
    if (letterSpacing != null) 'letterSpacing': letterSpacing,
    if (wordSpacing != null) 'wordSpacing': wordSpacing,
    if (height != null) 'height': height,
    if (leadingDistribution != null)
      'leadingDistribution': leadingDistribution.name,
    if (textBaseline != null) 'textBaseline': textBaseline.name,
    if (overflow != null) 'overflow': overflow.name,
    if (decoration != null) 'decoration': decoration.maskValue,
    if (decorationColor != null) 'decorationColor': _colorData(decorationColor),
    if (decorationStyle != null) 'decorationStyle': decorationStyle.name,
    if (decorationThickness != null) 'decorationThickness': decorationThickness,
  };
}

/// [color] as the value language's color record.
Map<String, Object?> builderColorData(Color color) => _colorData(color)!;

Map<String, Object?>? _colorData(Color? color) => color == null
    ? null
    : {
        'a': color.a,
        'r': color.r,
        'g': color.g,
        'b': color.b,
        'colorSpace': color.colorSpace.name,
        'material': canonicalMaterialColorName(color),
      };

/// The non-deprecated color roles with their original components and spaces.
Map<String, Object?> _colorSchemeData(ColorScheme cs) => <String, Object?>{
      'primary': _colorData(cs.primary),
      'onPrimary': _colorData(cs.onPrimary),
      'primaryContainer': _colorData(cs.primaryContainer),
      'onPrimaryContainer': _colorData(cs.onPrimaryContainer),
      'primaryFixed': _colorData(cs.primaryFixed),
      'primaryFixedDim': _colorData(cs.primaryFixedDim),
      'onPrimaryFixed': _colorData(cs.onPrimaryFixed),
      'onPrimaryFixedVariant': _colorData(cs.onPrimaryFixedVariant),
      'secondary': _colorData(cs.secondary),
      'onSecondary': _colorData(cs.onSecondary),
      'secondaryContainer': _colorData(cs.secondaryContainer),
      'onSecondaryContainer': _colorData(cs.onSecondaryContainer),
      'secondaryFixed': _colorData(cs.secondaryFixed),
      'secondaryFixedDim': _colorData(cs.secondaryFixedDim),
      'onSecondaryFixed': _colorData(cs.onSecondaryFixed),
      'onSecondaryFixedVariant': _colorData(cs.onSecondaryFixedVariant),
      'tertiary': _colorData(cs.tertiary),
      'onTertiary': _colorData(cs.onTertiary),
      'tertiaryContainer': _colorData(cs.tertiaryContainer),
      'onTertiaryContainer': _colorData(cs.onTertiaryContainer),
      'tertiaryFixed': _colorData(cs.tertiaryFixed),
      'tertiaryFixedDim': _colorData(cs.tertiaryFixedDim),
      'onTertiaryFixed': _colorData(cs.onTertiaryFixed),
      'onTertiaryFixedVariant': _colorData(cs.onTertiaryFixedVariant),
      'error': _colorData(cs.error),
      'onError': _colorData(cs.onError),
      'errorContainer': _colorData(cs.errorContainer),
      'onErrorContainer': _colorData(cs.onErrorContainer),
      'surface': _colorData(cs.surface),
      'onSurface': _colorData(cs.onSurface),
      'surfaceDim': _colorData(cs.surfaceDim),
      'surfaceBright': _colorData(cs.surfaceBright),
      'surfaceContainerLowest': _colorData(cs.surfaceContainerLowest),
      'surfaceContainerLow': _colorData(cs.surfaceContainerLow),
      'surfaceContainer': _colorData(cs.surfaceContainer),
      'surfaceContainerHigh': _colorData(cs.surfaceContainerHigh),
      'surfaceContainerHighest': _colorData(cs.surfaceContainerHighest),
      'onSurfaceVariant': _colorData(cs.onSurfaceVariant),
      'outline': _colorData(cs.outline),
      'outlineVariant': _colorData(cs.outlineVariant),
      'shadow': _colorData(cs.shadow),
      'scrim': _colorData(cs.scrim),
      'inverseSurface': _colorData(cs.inverseSurface),
      'onInverseSurface': _colorData(cs.onInverseSurface),
      'inversePrimary': _colorData(cs.inversePrimary),
      'surfaceTint': _colorData(cs.surfaceTint),
    };
