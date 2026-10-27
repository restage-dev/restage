import 'dart:io';
import 'dart:ui' show ColorSpace;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

// The companion codegen fixture test derives and validates this RFW source.
void main() {
  testWidgets(
      'authored native styles survive wire consumers and native adapters',
      (tester) async {
    final fixture = File('test/fixtures/authored_native_style.rfwtxt')
            .existsSync()
        ? File('test/fixtures/authored_native_style.rfwtxt')
        : File(
            'packages/restage_core/test/fixtures/authored_native_style.rfwtxt');
    final dsl = fixture.readAsStringSync();
    const color = Color.from(
        alpha: 0.812345,
        red: 0.234567,
        green: 0.345678,
        blue: 0.456789,
        colorSpace: ColorSpace.displayP3);
    final decoration = TextDecoration.combine(
        [TextDecoration.underline, TextDecoration.overline]);
    final style = TextStyle(
        color: color,
        fontWeight: const FontWeight(550),
        decoration: decoration);
    final runtime = Runtime();
    addTearDown(runtime.dispose);
    runtime.update(
        const LibraryName(['restage', 'core']), buildCoreWidgetLibrary());
    runtime.update(const LibraryName(['authored']), rfw.parseLibraryFile(dsl));
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.light().copyWith(
            colorScheme: ThemeData.light().colorScheme.copyWith(primary: color),
            textTheme: TextTheme(bodyMedium: style)),
        home: RemoteWidget(
            runtime: runtime,
            data: DynamicContent({}),
            widget: const FullyQualifiedWidgetName(
                LibraryName(['authored']), 'Root'))));
    expect(tester.takeException(), isNull);
    expect(
        tester.widget<ColoredBox>(find.byType(ColoredBox).last).color, color);
    final text = tester.widget<Text>(find.text('exact'));
    expect(text.style!.color, color);
    expect(text.style!.fontWeight, const FontWeight(550));
    expect(text.style!.decoration, decoration);
  });
}
