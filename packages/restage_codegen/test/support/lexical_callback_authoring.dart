import 'dart:io';
import 'dart:isolate';

import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_shared/restage_shared.dart';
import '../helpers.dart';

const lexicalCallbackSource = r'''
import 'package:flutter/widgets.dart';
Widget x() => LayoutBuilder(builder: (context, constraints) {
  var value = constraints.maxWidth.toInt();
  value += 1;
  return Column(children: [
    LayoutBuilder(builder: (context, constraints) { value++; return Text('$value'); }),
    LayoutBuilder(builder: (context, constraints) => Text('$value')),
  ]);
});
''';

Future<(String, Catalog)> compileLexicalCallback() async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
  );
  final catalog = decodeCatalog(File.fromUri(uri!).readAsStringSync());
  final source = await parseExpressionFromSourceForTest(
    lexicalCallbackSource,
    rootPackage: 'apps_examples',
  );
  final result = ExpressionTranslator(
    catalog: catalog,
    helpers: HelperRegistry(),
  ).translate(source);
  if (result.issues.isNotEmpty)
    throw StateError(result.issues.map((issue) => issue.message).join('\n'));
  return ('import restage.core; widget Root = ${result.dsl};\n', catalog);
}
