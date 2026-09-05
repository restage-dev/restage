// The published text-style fields survive the round trip: what the host theme
// holds is what a bound surface renders.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_core/library_registration.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart' hide WidgetLibrary;

const _coreLibrary = LibraryName(<String>['restage', 'core']);
const _surfaceLibrary = LibraryName(<String>['acme', 'surface']);
const _root = FullyQualifiedWidgetName(_surfaceLibrary, 'Root');

/// Every published field of one text-theme style bound into the catalog's
/// flat `Text` slots — the shape a whole-style read compiles to.
const _source = '''
import restage.core;
widget Root = Text(
  text: 'Go Pro',
  color: data.theme.textTheme.titleLarge.color,
  backgroundColor: data.theme.textTheme.titleLarge.backgroundColor,
  fontFamily: data.theme.textTheme.titleLarge.fontFamily,
  fontFamilyFallback: data.theme.textTheme.titleLarge.fontFamilyFallback,
  fontSize: data.theme.textTheme.titleLarge.fontSize,
  fontWeight: data.theme.textTheme.titleLarge.fontWeight,
  fontStyle: data.theme.textTheme.titleLarge.fontStyle,
  letterSpacing: data.theme.textTheme.titleLarge.letterSpacing,
  wordSpacing: data.theme.textTheme.titleLarge.wordSpacing,
  height: data.theme.textTheme.titleLarge.height,
  leadingDistribution: data.theme.textTheme.titleLarge.leadingDistribution,
  textBaseline: data.theme.textTheme.titleLarge.textBaseline,
  overflow: data.theme.textTheme.titleLarge.overflow,
  decoration: data.theme.textTheme.titleLarge.decoration,
  decorationColor: data.theme.textTheme.titleLarge.decorationColor,
  decorationStyle: data.theme.textTheme.titleLarge.decorationStyle,
  decorationThickness: data.theme.textTheme.titleLarge.decorationThickness,
);
''';

const _titleLarge = TextStyle(
  color: Color(0xFF223344),
  backgroundColor: Color(0xFF445566),
  fontFamily: 'Charter',
  fontFamilyFallback: ['Georgia', 'serif'],
  fontSize: 22,
  fontWeight: FontWeight.w500,
  fontStyle: FontStyle.italic,
  letterSpacing: 0.15,
  wordSpacing: 1.25,
  height: 1.4,
  leadingDistribution: TextLeadingDistribution.even,
  textBaseline: TextBaseline.ideographic,
  overflow: TextOverflow.ellipsis,
  decoration: TextDecoration.lineThrough,
  decorationColor: Color(0xFF667788),
  decorationStyle: TextDecorationStyle.dashed,
  decorationThickness: 2.5,
);

Future<TextStyle> _renderedStyle(WidgetTester tester, TextStyle style) async {
  final runtime = Runtime()
    ..update(_coreLibrary, buildCoreWidgetLibrary())
    ..update(_surfaceLibrary, parseLibraryFile(_source));
  addTearDown(runtime.dispose);
  final data = DynamicContent();
  populateThemeData(
    data,
    colorScheme: const ColorScheme.light(),
    iconTheme: const IconThemeData(),
    defaultTextStyle: const TextStyle(),
    textTheme: TextTheme(titleLarge: style),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: RemoteWidget(
        runtime: runtime,
        data: data,
        widget: _root,
        onEvent: (_, __) {},
      ),
    ),
  );
  await tester.pump();
  return tester.widget<Text>(find.text('Go Pro')).style!;
}

void main() {
  testWidgets('a bound text-theme style renders every published field',
      (tester) async {
    final rendered = await _renderedStyle(tester, _titleLarge);

    expect(rendered.color, _titleLarge.color);
    expect(rendered.backgroundColor, _titleLarge.backgroundColor);
    expect(rendered.fontFamily, _titleLarge.fontFamily);
    expect(rendered.fontFamilyFallback, _titleLarge.fontFamilyFallback);
    expect(rendered.fontSize, _titleLarge.fontSize);
    expect(rendered.fontWeight, _titleLarge.fontWeight);
    expect(rendered.fontStyle, _titleLarge.fontStyle);
    expect(rendered.letterSpacing, _titleLarge.letterSpacing);
    expect(rendered.wordSpacing, _titleLarge.wordSpacing);
    expect(rendered.height, _titleLarge.height);
    expect(rendered.leadingDistribution, _titleLarge.leadingDistribution);
    expect(rendered.textBaseline, _titleLarge.textBaseline);
    expect(rendered.overflow, _titleLarge.overflow);
    expect(rendered.decoration, _titleLarge.decoration);
    expect(rendered.decorationColor, _titleLarge.decorationColor);
    expect(rendered.decorationStyle, _titleLarge.decorationStyle);
    expect(rendered.decorationThickness, _titleLarge.decorationThickness);
  });

  testWidgets('each named decoration renders as itself', (tester) async {
    for (final decoration in [
      TextDecoration.none,
      TextDecoration.underline,
      TextDecoration.overline,
      TextDecoration.lineThrough,
    ]) {
      final rendered = await _renderedStyle(
        tester,
        TextStyle(decoration: decoration),
      );
      expect(rendered.decoration, decoration, reason: '$decoration');
    }
  });

  testWidgets('a combined decoration is not published, so the slot stays unset',
      (tester) async {
    final rendered = await _renderedStyle(
      tester,
      TextStyle(
        decoration: TextDecoration.combine([
          TextDecoration.underline,
          TextDecoration.overline,
        ]),
      ),
    );

    expect(rendered.decoration, isNull);
  });
}
