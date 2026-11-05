import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/single_select_recognition.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'native_key_integration_test.dart'
    show resolveKeySource, translateKey, translateKeyProbe, keyCatalog;

void main() {
  final catalogs = [
    for (final package in ['restage_core', 'restage_material'])
      decodeCatalog(
        File(
          '../$package/lib/src/widget_catalog/catalog.json',
        ).readAsStringSync(),
      ),
  ];
  final catalog = Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {for (final c in catalogs) ...c.libraries},
    widgets: [for (final c in catalogs) ...c.widgets],
    structuredTypes: [for (final c in catalogs) ...c.structuredTypes],
    unions: [for (final c in catalogs) ...c.unions],
  );
  for (final key in ['itemKey', "const ObjectKey('native')"]) {
    test('PageView substitution refuses original native key $key', () async {
      final result = await translateKey(
        "PageView(key:$key,children:[const SizedBox()])",
        catalog,
      );
      // The original PageView keeps its native key by rendering from the app.
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((issue) => issue.message).join('\n'),
      );
      expect(
        [for (final island in result.islands) island.reason?.message],
        [contains('original PageView owner')],
      );
    });
  }
  // The pager lowering can't carry a key, so the PageView keeps it from the app.
  test('PageView with a scalar ValueKey renders from the app', () async {
    final result = await translateKey(
      "PageView(key:const ValueKey<String>('legacy'),children:[const SizedBox()])",
      catalog,
    );
    expect(
      result.issues,
      isEmpty,
      reason: result.issues.map((i) => i.message).join('\n'),
    );
    expect(result.dsl, isNot(startsWith('RestagePager(')));
    expect(
      [for (final island in result.islands) island.reason?.message],
      [contains("Restage keeps a widget's key only through")],
    );
  });
  for (final site in ['group', 'container', 'option', 'label', 'dropdown']) {
    for (final native in [true, false]) {
      test('single-select owner boundary site=$site native=$native', () async {
        final key = native ? 'itemKey' : "const ValueKey<String>('legacy')";
        String named(String target) => site == target ? 'key:$key,' : '';
        final body = site == 'dropdown'
            ? "DropdownButton<String>(${named('dropdown')}onChanged:(_) {},items:[DropdownMenuItem<String>(value:'a',child:Text('A'))])"
            : "RadioGroup<String>(${named('group')}groupValue:'a',onChanged:(_) {},child:Column(${named('container')}children:[RadioListTile<String>(${named('option')}value:'a',title:Text('A',${named('label')}))]))";
        final probe = await resolveKeySource(
          "import 'package:flutter/material.dart'; class P extends StatelessWidget {const P({required this.itemKey});final Key itemKey; Widget build(BuildContext context)=>$body;}",
        );
        final creation = probe.expression as InstanceCreationExpression;
        final outcome = site == 'dropdown'
            ? recogniseDropdown(creation)
            : recogniseRadioGroup(creation);
        expect(
          outcome,
          native ? isA<SingleSelectDeferred>() : isA<SingleSelectRecognised>(),
        );
      });
    }
  }
  for (final native in [true, false]) {
    test('inline custom owner boundary native=$native', () async {
      final key = native ? 'itemKey' : "const ValueKey<String>('legacy')";
      final probe = await resolveKeySource(
        "import 'package:flutter/material.dart'; class Inline extends StatelessWidget {const Inline({super.key});Widget build(BuildContext context)=>const Text('inside');} class P extends StatelessWidget {const P({required this.itemKey});final Key itemKey;Widget build(BuildContext context)=>Inline(key:$key);}",
      );
      final declaration = (probe.expression.root as CompilationUnit)
          .declarations
          .whereType<ClassDeclaration>()
          .singleWhere((c) => c.namePart.typeName.lexeme == 'Inline');
      final body = extractInlinableBuildBody(
        declaration.body.members.whereType<MethodDeclaration>().single.body,
      )!.expression;
      final classKey = '${probe.classes['Inline']!.library.identifier}#Inline';
      final result = translateKeyProbe(
        probe,
        keyCatalog('restage_core'),
        classifications: {
          classKey: ComposableWidget(
            classKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        blueprints: {
          classKey: CustomWidgetBlueprint(
            classKey: classKey,
            rfwName: 'Inline',
            buildExpression: body,
            params: const [],
          ),
        },
      );
      // Without a mount to carry it, the widget keeps its key from the app.
      {
        expect(
          result.issues,
          isEmpty,
          reason: result.issues.map((issue) => issue.message).join('\n'),
        );
        expect(
          [for (final island in result.islands) island.reason?.message],
          [
            contains(
              native
                  ? 'original custom widget owner'
                  : "Restage keeps a widget's key only through",
            ),
          ],
        );
        expect(result.dsl, isNot(contains('Inline()')));
      }
    });
  }
}
