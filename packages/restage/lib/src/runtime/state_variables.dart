import 'dart:ui';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart'
    show ColorScheme, IconThemeData, MediaQueryData, TextStyle, TextTheme;
import 'package:rfw/rfw.dart';

import 'context_data.dart';

/// Populates the `data.device.*` namespace on [target].
///
/// Includes the locale and its subtags, the platform identifier, screen size
/// and orientation, device pixel ratio, and safe-area insets. Authors reference
/// these via `data.device.screenWidth`, `data.device.orientation`, and so on.
///
/// ```dart
/// populateDeviceData(
///   content,
///   locale: Localizations.localeOf(context),
///   mediaQuery: MediaQuery.of(context),
///   platform: currentDevicePlatform(),
/// );
/// ```
void populateDeviceData(
  DynamicContent target, {
  required Locale locale,
  required MediaQueryData mediaQuery,
  String platform = 'unknown',
}) {
  final countryCode = locale.countryCode;
  target.update('device', <String, Object?>{
    'locale': locale.toString(),
    'languageCode': locale.languageCode,
    // Nullable at the source; a missing key reads back as null.
    if (countryCode != null && countryCode.isNotEmpty)
      'countryCode': countryCode,
    'platform': platform,
    'screenWidth': mediaQuery.size.width,
    'screenHeight': mediaQuery.size.height,
    'shortestSide': mediaQuery.size.shortestSide,
    'longestSide': mediaQuery.size.longestSide,
    'orientation': mediaQuery.orientation.name,
    'pixelRatio': mediaQuery.devicePixelRatio,
    'safeAreaTop': mediaQuery.padding.top,
    'safeAreaBottom': mediaQuery.padding.bottom,
    'safeAreaLeft': mediaQuery.padding.left,
    'safeAreaRight': mediaQuery.padding.right,
    'viewPaddingTop': mediaQuery.viewPadding.top,
    'viewPaddingBottom': mediaQuery.viewPadding.bottom,
    'viewPaddingLeft': mediaQuery.viewPadding.left,
    'viewPaddingRight': mediaQuery.viewPadding.right,
  });
}

/// The current runtime platform identifier for `data.device.platform`.
///
/// Returns `'web'` on Flutter Web (where `defaultTargetPlatform` reports the
/// underlying host OS rather than the web target), and otherwise the
/// [TargetPlatform] name (`'iOS'`, `'android'`, `'macOS'`, `'windows'`,
/// `'linux'`, `'fuchsia'`). This is the value paywall authors read via
/// `data.device.platform`.
String currentDevicePlatform() => kIsWeb ? 'web' : defaultTargetPlatform.name;

/// Populates the `data.theme.*` namespace on [target] from the host app's
/// ambient theme.
///
/// Writes the theme as primitive-valued data so a paywall can reference it
/// via `data.theme.colorScheme.primary`, `data.theme.iconTheme.size`, etc.
///
/// Colors are written as 32-bit ARGB integers ([Color.toARGB32]); sizes as
/// doubles; `fontWeight` as a `w100`–`w900` string; every other enum-valued
/// text-style field as its own member name; `brightness` as the ambient
/// theme's `light` / `dark` token. All 46 [ColorScheme] color roles are always
/// written. [IconThemeData] and [TextStyle] fields are nullable — a null field
/// has its key omitted (`DynamicContent` cannot hold null; a missing key reads
/// back as null, so the consumer falls through to its own default). A
/// `decoration` combining more than one line has no token and is omitted the
/// same way.
///
/// [colorScheme], [iconTheme], and [textTheme] are taken from the ambient
/// `ThemeData`; [defaultTextStyle] is the ambient `DefaultTextStyle`'s style.
void populateThemeData(
  DynamicContent target, {
  required ColorScheme colorScheme,
  required IconThemeData iconTheme,
  required TextStyle defaultTextStyle,
  required TextTheme textTheme,
}) {
  final iconColor = iconTheme.color;
  final iconSize = iconTheme.size;
  target.update('theme', <String, Object?>{
    // `ThemeData.brightness` is defined as its colour scheme's brightness.
    'brightness': colorScheme.brightness.name,
    'colorScheme': _colorSchemeData(colorScheme),
    'iconTheme': <String, Object?>{
      if (iconColor != null) 'color': iconColor.toARGB32(),
      if (iconSize != null) 'size': iconSize,
    },
    'defaultTextStyle': _textStyleData(defaultTextStyle),
    'textTheme': _textThemeData(textTheme),
  });
}

/// Each published [TextTheme] style as its own sub-map of the fields the
/// `data.theme.textTheme.<style>.<field>` contract carries.
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

/// One published style's fields, null fields omitted. Shared by every
/// `textTheme.<style>` and by `defaultTextStyle`, so the two carry the same
/// keys.
Map<String, Object?> _textStyleData(TextStyle? style) {
  if (style == null) return const <String, Object?>{};
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
  final decorationToken =
      decoration == null ? null : _textDecorationToken(decoration);
  final decorationColor = style.decorationColor;
  final decorationStyle = style.decorationStyle;
  final decorationThickness = style.decorationThickness;
  return <String, Object?>{
    if (color != null) 'color': color.toARGB32(),
    if (backgroundColor != null) 'backgroundColor': backgroundColor.toARGB32(),
    if (fontFamily != null) 'fontFamily': fontFamily,
    if (fontFamilyFallback != null)
      'fontFamilyFallback': List<Object?>.of(fontFamilyFallback),
    if (fontSize != null) 'fontSize': fontSize,
    if (fontWeight != null) 'fontWeight': _fontWeightToken(fontWeight),
    if (fontStyle != null) 'fontStyle': fontStyle.name,
    if (letterSpacing != null) 'letterSpacing': letterSpacing,
    if (wordSpacing != null) 'wordSpacing': wordSpacing,
    if (height != null) 'height': height,
    if (leadingDistribution != null)
      'leadingDistribution': leadingDistribution.name,
    if (textBaseline != null) 'textBaseline': textBaseline.name,
    if (overflow != null) 'overflow': overflow.name,
    if (decorationToken != null) 'decoration': decorationToken,
    if (decorationColor != null) 'decorationColor': decorationColor.toARGB32(),
    if (decorationStyle != null) 'decorationStyle': decorationStyle.name,
    if (decorationThickness != null) 'decorationThickness': decorationThickness,
  };
}

/// The token naming [decoration], or null when it combines more than one
/// line — the contract carries the four named decorations only, so a combined
/// value has its key omitted and the consumer keeps its own default.
String? _textDecorationToken(TextDecoration decoration) {
  if (decoration == TextDecoration.none) return 'none';
  if (decoration == TextDecoration.underline) return 'underline';
  if (decoration == TextDecoration.overline) return 'overline';
  if (decoration == TextDecoration.lineThrough) return 'lineThrough';
  return null;
}

/// The nearest standard `w100`–`w900` token for [weight].
///
/// `FontWeight`'s constructor accepts any value 1–1000 (variable fonts), but
/// the `data.theme.*` contract and RFW's `enumValue<FontWeight>` decoder know
/// only the nine standard weights — so a non-standard value is snapped to the
/// closest standard weight.
String _fontWeightToken(FontWeight weight) {
  final snapped = ((weight.value / 100).round() * 100).clamp(100, 900);
  return 'w$snapped';
}

/// The full non-deprecated [ColorScheme] color-role set, each as an ARGB int.
Map<String, Object?> _colorSchemeData(ColorScheme cs) => <String, Object?>{
      'primary': cs.primary.toARGB32(),
      'onPrimary': cs.onPrimary.toARGB32(),
      'primaryContainer': cs.primaryContainer.toARGB32(),
      'onPrimaryContainer': cs.onPrimaryContainer.toARGB32(),
      'primaryFixed': cs.primaryFixed.toARGB32(),
      'primaryFixedDim': cs.primaryFixedDim.toARGB32(),
      'onPrimaryFixed': cs.onPrimaryFixed.toARGB32(),
      'onPrimaryFixedVariant': cs.onPrimaryFixedVariant.toARGB32(),
      'secondary': cs.secondary.toARGB32(),
      'onSecondary': cs.onSecondary.toARGB32(),
      'secondaryContainer': cs.secondaryContainer.toARGB32(),
      'onSecondaryContainer': cs.onSecondaryContainer.toARGB32(),
      'secondaryFixed': cs.secondaryFixed.toARGB32(),
      'secondaryFixedDim': cs.secondaryFixedDim.toARGB32(),
      'onSecondaryFixed': cs.onSecondaryFixed.toARGB32(),
      'onSecondaryFixedVariant': cs.onSecondaryFixedVariant.toARGB32(),
      'tertiary': cs.tertiary.toARGB32(),
      'onTertiary': cs.onTertiary.toARGB32(),
      'tertiaryContainer': cs.tertiaryContainer.toARGB32(),
      'onTertiaryContainer': cs.onTertiaryContainer.toARGB32(),
      'tertiaryFixed': cs.tertiaryFixed.toARGB32(),
      'tertiaryFixedDim': cs.tertiaryFixedDim.toARGB32(),
      'onTertiaryFixed': cs.onTertiaryFixed.toARGB32(),
      'onTertiaryFixedVariant': cs.onTertiaryFixedVariant.toARGB32(),
      'error': cs.error.toARGB32(),
      'onError': cs.onError.toARGB32(),
      'errorContainer': cs.errorContainer.toARGB32(),
      'onErrorContainer': cs.onErrorContainer.toARGB32(),
      'surface': cs.surface.toARGB32(),
      'onSurface': cs.onSurface.toARGB32(),
      'surfaceDim': cs.surfaceDim.toARGB32(),
      'surfaceBright': cs.surfaceBright.toARGB32(),
      'surfaceContainerLowest': cs.surfaceContainerLowest.toARGB32(),
      'surfaceContainerLow': cs.surfaceContainerLow.toARGB32(),
      'surfaceContainer': cs.surfaceContainer.toARGB32(),
      'surfaceContainerHigh': cs.surfaceContainerHigh.toARGB32(),
      'surfaceContainerHighest': cs.surfaceContainerHighest.toARGB32(),
      'onSurfaceVariant': cs.onSurfaceVariant.toARGB32(),
      'outline': cs.outline.toARGB32(),
      'outlineVariant': cs.outlineVariant.toARGB32(),
      'shadow': cs.shadow.toARGB32(),
      'scrim': cs.scrim.toARGB32(),
      'inverseSurface': cs.inverseSurface.toARGB32(),
      'onInverseSurface': cs.onInverseSurface.toARGB32(),
      'inversePrimary': cs.inversePrimary.toARGB32(),
      'surfaceTint': cs.surfaceTint.toARGB32(),
    };

/// Publishes host-supplied render data under `data.context.*`
/// unconditionally on every call, writing only the `context` root key.
/// Mount widgets' `context:` parameter skips unchanged republishes.
/// Signed zero is canonicalized to `0.0`; keep each path's numeric runtime type
/// stable because renderer scalar `==` can miss `int`/`double` transitions.
///
/// ```dart
/// populateContextData(
///   content,
///   <String, Object?>{
///     'profile': <String, Object?>{
///       'plan': 'pro',
///     },
///   },
/// );
/// ```
void populateContextData(
  DynamicContent target,
  Map<String, Object?> context,
) {
  target.update(kContextDataKey, ContextSnapshot.of(context).value);
}
