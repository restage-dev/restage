import 'dart:io';
import 'dart:isolate';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_shared/restage_shared.dart';
import '../helpers.dart';

const collectionAuthoringSource = r'''
import 'package:flutter/widgets.dart';
Widget x() => LayoutBuilder(builder: (context, constraints) {
  var calls = 0;
  final rows = [1, 2, 3].where((row) { calls++; return row > 1; });
  return Column(children: [
    for (final row in rows) Text('row$row'),
    ...[4, 5].map((row) { final label = row * 2; return Text('map$label'); }).toList(),
    Text('calls$calls'),
  ]);
});
''';

Future<(String, Catalog)> compileCollectionAuthoring({
  String authoredSource = collectionAuthoringSource,
}) async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
  );
  final catalog = decodeCatalog(File.fromUri(uri!).readAsStringSync());
  final source = await parseExpressionFromSourceForTest(
    authoredSource,
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
