import 'dart:ui';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart'
    show ColorScheme, IconThemeData, MediaQueryData, TextStyle;
import 'package:restage_shared/restage_shared.dart';
import 'package:meta/meta.dart';
import 'package:rfw/rfw.dart';

/// Live price data for one product, resolved at runtime from StoreKit / Play.
///
/// Host apps supply these via `RestagePaywall.priceQueries`; billing gateways
/// can also provide resolved prices before rendering.
///
/// ```dart
/// // Map prices resolved from your billing layer to product ids, then hand
/// // the map to the paywall.
/// final priceQueries = <String, PriceInfo>{
///   'pro_monthly': PriceInfo(
///     localizedPrice: r'$9.99',
///     priceMicros: 9990000,
///     currency: 'USD',
///     title: 'Pro Monthly',
///     description: 'Unlock everything',
///   ),
/// };
/// RestagePaywall(id: 'pro_upgrade', priceQueries: priceQueries);
/// ```
@immutable
final class PriceInfo {
  /// Const constructor.
  ///
  /// Asserts: [priceMicros] is non-negative, [currency] is a 3-character
  /// ISO 4217 code, and [trialDurationDays] is only set when [isTrial]
  /// is true.
  const PriceInfo({
    required this.localizedPrice,
    required this.priceMicros,
    required this.currency,
    required this.title,
    required this.description,
    this.isTrial = false,
    this.trialDurationDays,
  })  : assert(priceMicros >= 0, 'priceMicros must be non-negative'),
        assert(currency.length == 3,
            'currency must be a 3-character ISO 4217 code'),
        assert(isTrial || trialDurationDays == null,
            'trialDurationDays only meaningful when isTrial is true');

  /// Pre-formatted, currency-appropriate price string (e.g. `$9.99`, `€8,99`).
  final String localizedPrice;

  /// Price in micros (1 USD = 1_000_000 micros).
  final int priceMicros;

  /// ISO 4217 currency code (e.g. `USD`, `EUR`).
  final String currency;

  /// Product title shown in UI.
  final String title;

  /// Product description shown in UI.
  final String description;

  /// Whether this purchase is currently in a free-trial period.
  final bool isTrial;

  /// Trial length in days, if [isTrial] is true. Null otherwise.
  final int? trialDurationDays;

  /// Value equality over all scalar fields.
  ///
  /// [PriceInfo] is a value record host apps supply through
  /// `RestagePaywall.priceQueries` (a `Map<String, PriceInfo>`). Hosts
  /// commonly cache resolved store prices and diff "did the price change"
  /// before rebuilding; with identity equality two instances carrying the
  /// same data compare unequal, so a host re-mapping fresh query results each
  /// frame would see a spurious change every rebuild. Value equality keeps
  /// host-side caches and dedup honest.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PriceInfo &&
          other.localizedPrice == localizedPrice &&
          other.priceMicros == priceMicros &&
          other.currency == currency &&
          other.title == title &&
          other.description == description &&
          other.isTrial == isTrial &&
          other.trialDurationDays == trialDurationDays;

  @override
  int get hashCode => Object.hash(
        localizedPrice,
        priceMicros,
        currency,
        title,
        description,
        isTrial,
        trialDurationDays,
      );
}

/// Populates the `data.products.*` namespace on [target].
///
/// Each product entry is addressable by both `productId` and `slot`, so paywall
/// authors can reference `data.products.primary.localizedPrice` (slot) or
/// `data.products.pro_monthly.localizedPrice` (productId) interchangeably.
///
/// Products without a corresponding entry in [priceQueries] are skipped — only
/// products whose live price has been resolved appear in the populated map.
///
/// ```dart
/// // `prices` is your billing layer's resolved price map (productId ->
/// // PriceInfo); `products` is the set you registered with Restage.configure.
/// populateProductData(
///   content,
///   products: Restage.configuredProducts,
///   priceQueries: prices,
/// );
/// ```
void populateProductData(
  DynamicContent target, {
  required List<RestageProduct> products,
  required Map<String, PriceInfo> priceQueries,
}) {
  final byProduct = <String, Map<String, Object?>>{};
  for (final p in products) {
    final price = priceQueries[p.id];
    if (price == null) continue;
    final entry = <String, Object?>{
      'localizedPrice': price.localizedPrice,
      'priceMicros': price.priceMicros,
      'currency': price.currency,
      'title': price.title,
      'description': price.description,
      'isTrial': price.isTrial,
      if (price.trialDurationDays != null)
        'trialDurationDays': price.trialDurationDays,
    };
    byProduct[p.id] = entry;
    byProduct[p.slot] = entry;
  }
  target.update('products', byProduct);
}

/// Populates the `data.device.*` namespace on [target].
///
/// Includes locale, platform identifier, screen size, device pixel ratio, and
/// safe-area insets. Paywall authors reference these via
/// `data.device.screenWidth`, `data.device.safeAreaTop`, etc.
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
  target.update('device', <String, Object?>{
    'locale': locale.toString(),
    'platform': platform,
    'screenWidth': mediaQuery.size.width,
    'screenHeight': mediaQuery.size.height,
    'pixelRatio': mediaQuery.devicePixelRatio,
    'safeAreaTop': mediaQuery.padding.top,
    'safeAreaBottom': mediaQuery.padding.bottom,
    'safeAreaLeft': mediaQuery.padding.left,
    'safeAreaRight': mediaQuery.padding.right,
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
/// Sibling of [populateProductData] / [populateDeviceData].
///
/// Colors are written as 32-bit ARGB integers ([Color.toARGB32]); sizes as
/// doubles; `fontWeight` as a `w100`–`w900` string. All 46 [ColorScheme] color
/// roles are always written. [IconThemeData] and [TextStyle] fields are
/// nullable — a null field has its key omitted (`DynamicContent` cannot hold
/// null; a missing key reads back as null, so the consumer falls through to
/// its own default).
///
/// [colorScheme] and [iconTheme] are taken from the ambient `ThemeData`;
/// [defaultTextStyle] is the ambient `DefaultTextStyle`'s style.
void populateThemeData(
  DynamicContent target, {
  required ColorScheme colorScheme,
  required IconThemeData iconTheme,
  required TextStyle defaultTextStyle,
}) {
  final iconColor = iconTheme.color;
  final iconSize = iconTheme.size;
  final textColor = defaultTextStyle.color;
  final fontSize = defaultTextStyle.fontSize;
  final fontWeight = defaultTextStyle.fontWeight;
  target.update('theme', <String, Object?>{
    'colorScheme': _colorSchemeData(colorScheme),
    'iconTheme': <String, Object?>{
      if (iconColor != null) 'color': iconColor.toARGB32(),
      if (iconSize != null) 'size': iconSize,
    },
    'defaultTextStyle': <String, Object?>{
      if (textColor != null) 'color': textColor.toARGB32(),
      if (fontSize != null) 'fontSize': fontSize,
      if (fontWeight != null) 'fontWeight': _fontWeightToken(fontWeight),
    },
  });
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
