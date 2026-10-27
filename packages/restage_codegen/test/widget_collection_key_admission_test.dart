import 'dart:io';

import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _catalog = decodeCatalog(File(
  File('packages/restage_core/lib/src/widget_catalog/catalog.json').existsSync()
      ? 'packages/restage_core/lib/src/widget_catalog/catalog.json'
      : '../restage_core/lib/src/widget_catalog/catalog.json',
).readAsStringSync());

Future<TranslationResult> _translate(String body) async {
  final expression = await parseExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';
Widget x() => $body;
''', rootPackage: 'apps_examples');
  return ExpressionTranslator(
    catalog: _catalog,
    helpers: HelperRegistry(),
  ).translate(expression);
}

Future<String> _lower(String body) async {
  final result = await _translate(body);
  expect(result.issues, isEmpty,
      reason: result.issues.map((issue) => issue.message).join('\n'));
  return result.dsl;
}

void main() {
  test('ordinary child lists retain legacy scalar key exclusion', () async {
    final baseline = await _lower("Column(children:[Text('item')])");
    for (final key in [
      'const ValueKey<int>(1)',
      "const ValueKey<String>('item')"
    ]) {
      final actual = await _lower("Column(children:[Text('item',key:$key)])");
      expect(actual, baseline);
      expect(actual, isNot(contains('__RestageBuilderContinuation')));
    }
  });

  test('nested scalar keys and static item keys do not promote ordinary lists',
      () async {
    final nested = await _lower(
        "Column(children:[Padding(padding:EdgeInsets.zero,child:Text('item',key:const ValueKey<String>('nested')))])");
    expect(nested, isNot(contains('__RestageBuilderContinuation')));
    final baseline = await _lower(
        "Column(children:[for(final label in ['a','b']) Text(label),Text('sibling')])");
    final keyed = await _lower(
        "Column(children:[for(final label in ['a','b']) Text(label,key:ValueKey<String>(label)),Text('sibling')])");
    expect(keyed, baseline);
    expect(keyed, isNot(contains('__RestageBuilderContinuation')));
  });

  test('ordinary and nested child lists refuse fresh native keys', () async {
    for (final child in [
      "Text('item',key:UniqueKey())",
      "Padding(padding:EdgeInsets.zero,child:Text('item',key:UniqueKey()))",
    ]) {
      final result = await _translate('Column(children:[$child])');
      expect(result.issues, hasLength(1));
      expect(result.issues.single.code, IssueCode.propertyValueTypeMismatch);
      expect(result.issues.single.message,
          contains('requires an installed native Key binding'));
    }
  });

  test('native delegate and callback collections retain key programs',
      () async {
    final delegate = await _lower(
        "GridView.custom(gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2),childrenDelegate:SliverChildListDelegate([Text('item',key:ValueKey<String>('item'))]))");
    expect(delegate, contains('__RestageBuilderContinuation'));
    final callback = await _lower(
        "LayoutBuilder(builder:(_,constraints)=>Column(children:[Text('item',key:ValueKey<String>('item'))]))");
    expect(RegExp('__RestageBuilderContinuation').allMatches(callback),
        hasLength(2));
  });
}
