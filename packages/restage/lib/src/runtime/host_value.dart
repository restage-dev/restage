import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Encodes each app value a generated mount computes, keyed as the surface
/// reads it, from its source expression and its computation. A value whose
/// computation throws is left out, so the surface reads it as missing.
Map<String, Object?> restageHostValues(
  Map<String, (String, Object? Function())> values,
) {
  final encoded = <String, Object?>{};
  for (final MapEntry(key: key, value: (expression, compute))
      in values.entries) {
    final Object? computed;
    try {
      computed = compute();
    } on Object catch (error) {
      assert(() {
        if (_reportedThrows.add(expression)) {
          debugPrint(
            "[restage] '$expression' threw while computing in the app, so "
            'the surface reads it as missing: $error',
          );
        }
        return true;
      }());
      continue;
    }
    encoded[key] = restageHostValue(computed);
  }
  return encoded;
}

/// Expressions already reported as throwing, so each is logged once.
final Set<String> _reportedThrows = {};

/// Encodes an app value a generated mount passes to its surface.
///
/// Colors become ARGB integers, edge insets `[start, top, end, bottom]`
/// (left and right are read as start and end, as for a written inset), text
/// styles the map a surface's text style reads, and enums their names.
/// Lists and string-keyed maps are encoded element by element.
Object? restageHostValue(Object? value) => switch (value) {
      null || bool() || num() || String() => value,
      Color() => value.toARGB32(),
      EdgeInsets() => <Object?>[
          value.left,
          value.top,
          value.right,
          value.bottom,
        ],
      EdgeInsetsDirectional() => <Object?>[
          value.start,
          value.top,
          value.end,
          value.bottom,
        ],
      TextStyle() => _textStyle(value),
      Enum() => value.name,
      List<Object?>() => <Object?>[
          for (final item in value) restageHostValue(item),
        ],
      Map<String, Object?>() => <String, Object?>{
          for (final entry in value.entries)
            entry.key: restageHostValue(entry.value),
        },
      _ => throw ArgumentError.value(
          value,
          'value',
          'is not a value a surface can receive',
        ),
    };

Map<String, Object?> _textStyle(TextStyle style) {
  final decoration = style.decoration;
  return <String, Object?>{
    if (!style.inherit) 'inherit': false,
    if (style.color case final color?) 'color': color.toARGB32(),
    if (style.backgroundColor case final color?)
      'backgroundColor': color.toARGB32(),
    if (style.fontSize case final size?) 'fontSize': size,
    if (style.fontWeight case final weight?) 'fontWeight': _fontWeight(weight),
    if (style.fontStyle case final fontStyle?) 'fontStyle': fontStyle.name,
    if (style.letterSpacing case final spacing?) 'letterSpacing': spacing,
    if (style.wordSpacing case final spacing?) 'wordSpacing': spacing,
    if (style.textBaseline case final baseline?) 'textBaseline': baseline.name,
    if (style.height case final height?) 'height': height,
    if (style.leadingDistribution case final distribution?)
      'leadingDistribution': distribution.name,
    if (style.locale case final locale?) 'locale': _locale(locale),
    if (style.foreground case final paint?)
      'foreground': _paint(paint, 'foreground'),
    if (style.background case final paint?)
      'background': _paint(paint, 'background'),
    if (style.shadows case final shadows?)
      'shadows': <Object?>[
        for (final shadow in shadows)
          <String, Object?>{
            'color': shadow.color.toARGB32(),
            'offset': <String, Object?>{
              'x': shadow.offset.dx,
              'y': shadow.offset.dy,
            },
            'blurRadius': shadow.blurRadius,
          },
      ],
    if (style.fontFeatures case final features?)
      'fontFeatures': <Object?>[
        for (final feature in features)
          <String, Object?>{'feature': feature.feature, 'value': feature.value},
      ],
    if (style.fontVariations case final variations?)
      'fontVariations': <Object?>[
        for (final variation in variations)
          <String, Object?>{'axis': variation.axis, 'value': variation.value},
      ],
    if (decoration != null) 'decoration': _decoration(decoration),
    if (style.decorationColor case final color?)
      'decorationColor': color.toARGB32(),
    if (style.decorationStyle case final decorationStyle?)
      'decorationStyle': decorationStyle.name,
    if (style.decorationThickness case final thickness?)
      'decorationThickness': thickness,
    if (style.debugLabel case final label?) 'debugLabel': label,
    if (style.fontFamily case final family?) 'fontFamily': family,
    if (style.fontFamilyFallback case final fallback?)
      'fontFamilyFallback': List<Object?>.of(fallback),
    if (style.overflow case final overflow?) 'overflow': overflow.name,
  };
}

/// The nearest of the nine standard weights a surface decodes.
String _fontWeight(FontWeight weight) =>
    'w${((weight.value / 100).round() * 100).clamp(100, 900)}';

String _locale(Locale locale) => [
      locale.languageCode,
      if (locale.scriptCode case final script?) script,
      if (locale.countryCode case final country?) country,
    ].join('-');

/// The decoration's lines, as one token or a list of them.
Object _decoration(TextDecoration decoration) {
  const lines = {
    'underline': TextDecoration.underline,
    'overline': TextDecoration.overline,
    'lineThrough': TextDecoration.lineThrough,
  };
  final present = [
    for (final MapEntry(:key, :value) in lines.entries)
      if (decoration.contains(value)) key,
  ];
  return switch (present) {
    [] => 'none',
    [final single] => single,
    _ => present,
  };
}

Map<String, Object?> _paint(Paint paint, String field) {
  assert(() {
    final dropped = [
      if (paint.shader != null) 'shader',
      if (paint.colorFilter != null) 'color filter',
      if (paint.maskFilter != null) 'mask filter',
      if (paint.imageFilter != null) 'image filter',
      if (paint.style == PaintingStyle.stroke) 'stroke',
    ];
    if (dropped.isNotEmpty) {
      debugPrint(
        'Restage: $field on this surface is drawn without its '
        '${dropped.join(', ')}.',
      );
    }
    return true;
  }());
  return <String, Object?>{
    'color': paint.color.toARGB32(),
    'blendMode': paint.blendMode.name,
    'filterQuality': paint.filterQuality.name,
    'isAntiAlias': paint.isAntiAlias,
  };
}
