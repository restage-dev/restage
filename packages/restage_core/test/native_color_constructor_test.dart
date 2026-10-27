import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

import 'fixtures/native_color_constructors.dart' as source;

void main() {
  testWidgets(
      'resolved nullable Color constants remain null in root and callback factories',
      (tester) async {
    for (final (dsl, bind) in [
      (source.nativeColorDslnullable, source.nativeColorBindingsnullable),
      (
        source.nativeColorDslnullableLayout,
        source.nativeColorBindingsnullableLayout
      ),
    ]) {
      const root = LibraryName(['test']);
      final installed = bind({});
      final runtime = Runtime()
        ..update(
            const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
        ..update(root,
            rfw.parseLibraryFile('import restage.core; widget Root = $dsl;'));
      await tester.pumpWidget(RestageNativeValues(
          bindings: installed,
          child: RemoteWidget(
              runtime: runtime,
              data: DynamicContent({
                'context': {
                  for (final entry in installed.entries)
                    entry.key: entry.value.contract.reference(entry.key),
                }
              }),
              widget: const FullyQualifiedWidgetName(root, 'Root'))));
      expect(tester.takeException(), isNull);
      expect(tester.widget<Container>(find.byType(Container)).color, isNull);
      await tester.pumpWidget(const SizedBox());
      runtime.dispose();
    }
  });

  testWidgets(
      'authored constructors retain maps aliases and canonical constants',
      (tester) async {
    final swatch = <int, Color>{500: Colors.red, 100: Colors.green};
    final native = source.ColorConstructorSource(swatch: swatch);
    for (final (name, dsl, bindings, build, canonical) in [
      (
        'fresh',
        source.nativeColorDslfresh,
        source.nativeColorBindingsfresh,
        native.fresh,
        false
      ),
      (
        'accent',
        source.nativeColorDslaccent,
        source.nativeColorBindingsaccent,
        native.accent,
        false
      ),
      (
        'constant',
        source.nativeColorDslconstant,
        source.nativeColorBindingsconstant,
        native.constant,
        true
      ),
      (
        'baseConstant',
        source.nativeColorDslbaseConstant,
        source.nativeColorBindingsbaseConstant,
        native.baseConstant,
        true
      ),
      (
        'alias',
        source.nativeColorDslalias,
        source.nativeColorBindingsalias,
        native.alias,
        true
      ),
      (
        'imported',
        source.nativeColorDslimported,
        source.nativeColorBindingsimported,
        native.imported,
        true
      ),
      (
        'importedStatic',
        source.nativeColorDslimportedStatic,
        source.nativeColorBindingsimportedStatic,
        native.importedStatic,
        true
      ),
      (
        'wrappedConst',
        source.nativeColorDslwrappedConst,
        source.nativeColorBindingswrappedConst,
        native.wrappedConst,
        true
      ),
      (
        'staticAlias',
        source.nativeColorDslstaticAlias,
        source.nativeColorBindingsstaticAlias,
        native.staticAlias,
        true
      ),
      (
        'localAlias',
        source.nativeColorDsllocalAlias,
        source.nativeColorBindingslocalAlias,
        native.localAlias,
        true
      ),
      (
        'layout',
        source.nativeColorDsllayout,
        source.nativeColorBindingslayout,
        native.layout,
        false
      ),
    ]) {
      const root = LibraryName(['test']);
      final runtime = Runtime()
        ..update(
            const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
        ..update(root,
            rfw.parseLibraryFile('import restage.core; widget Root = $dsl;'));
      final installed = bindings(swatch);
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: RestageNativeValues(
              bindings: installed,
              child: RemoteWidget(
                  runtime: runtime,
                  data: DynamicContent({
                    'context': {
                      for (final entry in installed.entries)
                        entry.key: entry.value.contract.reference(entry.key),
                    }
                  }),
                  widget: const FullyQualifiedWidgetName(root, 'Root')))));
      expect(tester.takeException(), isNull, reason: name);
      final context = tester.element(find.byType(RemoteWidget));
      final nativeWidget = build(context);
      final List<Color> expected;
      if (nativeWidget is LayoutBuilder) {
        final built = nativeWidget.builder(context, const BoxConstraints());
        expected = built is Row
            ? built.children.cast<ColoredBox>().map((box) => box.color).toList()
            : [(built as ColoredBox).color];
      } else {
        expected = [(nativeWidget as ColoredBox).color];
      }
      final actual = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .map((box) => box.color)
          .toList();
      expect(actual.length, expected.length, reason: name);
      for (var index = 0; index < actual.length; index++) {
        final color = actual[index];
        final oracle = expected[index];
        expect(color.runtimeType, oracle.runtimeType, reason: name);
        expect(color == oracle && oracle == color, isTrue, reason: name);
        expect(color.hashCode, oracle.hashCode, reason: name);
        expect([color.a, color.r, color.g, color.b, color.colorSpace],
            [oracle.a, oracle.r, oracle.g, oracle.b, oracle.colorSpace]);
        expect(identical(color, oracle), canonical, reason: name);
        if (!canonical) {
          swatch[500] = Colors.blue;
          expect((color as ColorSwatch<int>)[500], same(swatch[500]));
          expect((oracle as ColorSwatch<int>)[500], same(swatch[500]));
        }
      }
      if (name == 'layout') {
        expect(actual[0], same(actual[1]));
        expect(expected[0], same(expected[1]));
      }
      await tester.pumpWidget(const SizedBox());
      runtime.dispose();
    }
  });
}
