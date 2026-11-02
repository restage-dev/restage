import 'dart:io';

import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:restage_codegen/src/runtime_realization.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'native_key_integration_test.dart' show keyCatalog, translateKey;

void main() {
  final core = keyCatalog('restage_core');
  test(
    'all guarded realizations share exact constructor and key authority',
    () {
      final catalog = decodeCatalog(
        File(
          '../restage_core/lib/src/widget_catalog/catalog.json',
        ).readAsStringSync(),
      );
      final guarded = catalog.widgets
          .where((entry) => runtimeRealizationFor(entry) != null)
          .toList();
      expect(guarded, hasLength(18));
      final key = core.widgets
          .singleWhere((entry) => entry.name == 'Text')
          .properties
          .singleWhere((property) => property.name == 'key');
      WidgetEntry keyEntry(
        WidgetEntry entry, {
        String? name,
        String? type,
        WidgetLibrary? library,
      }) => WidgetEntry(
        wireId: entry.wireId,
        name: name ?? entry.name,
        library: library ?? entry.library,
        category: entry.category,
        description: entry.description,
        flutterType: type ?? entry.flutterType,
        childrenSlot: ChildrenSlot.none,
        properties: [key],
      );
      for (final original in guarded) {
        final entry = keyEntry(original);
        final factory = emitFactoryFunction(
          entry,
          nativeIndex: NativeCatalogIndex(core),
        )!;
        expect(
          factory,
          contains('return ${runtimeRealizationFor(entry)}('),
          reason: entry.name,
        );
        expect(
          factory,
          contains('key: RestageDecoders.guardReplacementKey('),
          reason: entry.name,
        );
        expect(factory, contains("type: 'flutter.Key'"), reason: entry.name);
        for (final mismatch in [
          keyEntry(original, name: 'Other${original.name}'),
          keyEntry(original, type: 'package:other/other.dart#${original.name}'),
          keyEntry(
            original,
            library: const WidgetLibrary.custom('other.widgets'),
          ),
        ]) {
          expect(runtimeRealizationFor(mismatch), isNull);
          expect(
            emitFactoryFunction(
              mismatch,
              nativeIndex: NativeCatalogIndex(core),
            ),
            isNot(contains('guardReplacementKey')),
          );
        }
      }
    },
  );
  for (final (name, body) in [
    ('Row', 'Row(children:[],KEY)'),
    (
      'AnimatedAlign',
      'AnimatedAlign(duration:Duration.zero,alignment:Alignment.center,KEY)',
    ),
  ]) {
    for (final (argument, native) in [
      ('key:itemKey', true),
      ('key:const ObjectKey(1)', true),
      ('key:(null)', false),
      ("key:const ValueKey<String>('legacy')", false),
    ]) {
      test('guarded $name source owner boundary $argument', () async {
        final result = await translateKey(
          body.replaceFirst('KEY', argument),
          core,
        );
        if (native) {
          expect(
            result.issues.map((issue) => issue.message),
            contains(contains('original $name owner')),
          );
        } else {
          expect(
            result.issues,
            isEmpty,
            reason: result.issues.map((issue) => issue.message).join('\n'),
          );
          expect(result.dsl, isNot(contains('key:')));
        }
      });
    }
  }
}
