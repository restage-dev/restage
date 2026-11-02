import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final catalog = decodeCatalog(
    File(
      '../restage_core/lib/src/widget_catalog/catalog.json',
    ).readAsStringSync(),
  );
  for (final name in ['casts', 'helpers', 'nullable', 'context']) {
    test(
      '$name native source matches the runtime differential fixture',
      () async {
        final source = File(
          'test/fixtures/grid_scalar/$name.dart.txt',
        ).readAsStringSync();
        final params = <RootContextParam>[];
        final expression = name == 'casts' || name == 'helpers'
            ? await parseExpressionFromSourceForTest(
                source,
                rootPackage: 'apps_examples',
              )
            : await (() async {
                final probe = await parseMethodExpressionFromSourceForTest(
                  source,
                  className: 'P',
                  rootPackage: 'apps_examples',
                );
                final parameter = probe
                    .classes['P']!
                    .unnamedConstructor!
                    .formalParameters
                    .single;
                params.add(
                  RootContextParam(
                    name: 'items',
                    type: parameter.type,
                    typeCode: parameter.type.getDisplayString(),
                    kind: RootContextParamKind.named,
                    hostDataShape: deriveHostDataShape(
                      parameter.type,
                      root: 'items',
                    ).shape,
                    field: (parameter as FieldFormalParameterElement).field,
                    isRequired: true,
                    defaultValueCode: null,
                    hasNullDefault: false,
                  ),
                );
                return probe.expression;
              })();
        final result = ExpressionTranslator(
          catalog: catalog,
          helpers: HelperRegistry(),
        ).translate(expression, rootParams: params);
        expect(
          result.issues,
          isEmpty,
          reason: result.issues.map((issue) => issue.message).join('\n'),
        );
        final dsl = 'import restage.core; widget Root = ${result.dsl};\n';
        final fixture = File(
          '../restage_core/test/fixtures/grid_scalar/$name.rfw',
        );
        if (Platform.environment['UPDATE_GRID_SCALAR_FIXTURES'] == '1') {
          fixture.writeAsStringSync(dsl);
        }
        expect(dsl, fixture.readAsStringSync());
      },
    );
  }
  test('recursive key helpers refuse at the authored helper call', () async {
    final expression = await parseExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';
int readKey(Key key)=>readKey(key);
Widget x()=>GridView.builder(
 gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2),
 itemBuilder:(_,index)=>null,findChildIndexCallback:(key)=>readKey(key));
''', rootPackage: 'apps_examples');
    final result = ExpressionTranslator(
      catalog: catalog,
      helpers: HelperRegistry(),
    ).translate(expression);
    expect(
      result.issues.any(
        (issue) =>
            issue.message.contains('Recursive pure helper is unsupported'),
      ),
      isTrue,
    );
  });
}
