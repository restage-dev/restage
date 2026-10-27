import 'dart:io';

import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

import 'helpers.dart';

final class _NoCaptures implements ValueReader {
  @override
  Object? read(List<Object> path, ValueType type) =>
      throw StateError('Unexpected captured value');

  @override
  int length(List<Object> path) => throw StateError('Unexpected captured list');
}

void main() {
  test('nullable native device values retain a parseable missing branch',
      () async {
    final catalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    final expression = await parseExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';
Widget x()=>LayoutBuilder(builder:(local,constraints)=>Text('Hi',
  semanticsLabel:Localizations.localeOf(local).countryCode));
''', rootPackage: 'apps_examples');
    final result =
        ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
            .translate(expression);
    expect(result.issues, isEmpty,
        reason: result.issues.map((issue) => issue.message).join('\n'));
    expect(result.dsl, isNot(contains('data.device')));
    final root = rfw
        .parseLibraryFile('import restage.core;widget Root=${result.dsl};')
        .widgets
        .single
        .root as rfw.ConstructorCall;
    final slot = root.arguments['builder']! as rfw.ConstructorCall;
    final program = BuilderProgram.decode(slot.arguments['program']! as String);
    final body = (slot.arguments['bodies']! as List).single
        as rfw.WidgetBuilderDeclaration;
    final label = (body.widget as rfw.ConstructorCall)
        .arguments['semanticsLabel']! as rfw.Switch;
    expect(label.outputs.keys, [false]);
    for (final country in <String?>[null, 'US']) {
      final frame = program.invoke(
        captures: _NoCaptures(),
        parameters: {'context:device:countryCode': country},
      );
      expect(frame.values.values, contains(country));
    }
  });

  test('builder device reads use native callback parameters without snapshots',
      () async {
    final catalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    final expression = await parseExpressionFromSourceForTest(r'''
import 'package:flutter/widgets.dart';
Widget x()=>LayoutBuilder(builder:(local,constraints)=>Text(
  '${MediaQuery.viewInsetsOf(local).top}|' +
  '${MediaQuery.viewInsetsOf(local).bottom}|' +
  '${MediaQuery.viewInsetsOf(local).left}|' +
  '${MediaQuery.viewInsetsOf(local).right}|' +
  '${MediaQuery.boldTextOf(local)}|' +
  '${MediaQuery.disableAnimationsOf(local)}|' +
  '${MediaQuery.accessibleNavigationOf(local)}|' +
  '${MediaQuery.highContrastOf(local)}'));
''', rootPackage: 'apps_examples');
    final result =
        ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
            .translate(expression);
    expect(result.issues, isEmpty,
        reason: result.issues.map((issue) => issue.message).join('\n'));
    expect(result.hoisted, isEmpty);
    expect(result.dsl, isNot(contains('data.device')));
    final root = rfw
        .parseLibraryFile('import restage.core;widget Root=${result.dsl};')
        .widgets
        .single
        .root as rfw.ConstructorCall;
    final slot = root.arguments['builder']! as rfw.ConstructorCall;
    final program = BuilderProgram.decode(slot.arguments['program']! as String);
    final expected = <String, ValueType>{
      'viewInsetsTop': ValueType.real,
      'viewInsetsBottom': ValueType.real,
      'viewInsetsLeft': ValueType.real,
      'viewInsetsRight': ValueType.real,
      'boldText': ValueType.boolean,
      'disableAnimations': ValueType.boolean,
      'accessibleNavigation': ValueType.boolean,
      'highContrast': ValueType.boolean,
    };
    expect(
        program.values.parameters.keys,
        unorderedEquals([
          'arg1',
          ...expected.keys.map((path) => 'context:device:$path'),
        ]));
    expect(program.values.captures, isEmpty);
    for (final entry in expected.entries) {
      expect(program.values.parameters['context:device:${entry.key}']!.kind,
          entry.value.kind);
    }
  });
}
