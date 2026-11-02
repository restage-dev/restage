import 'dart:io';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_compiler_core/src/rfw_program_envelope.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';
import 'support/collection_authoring.dart';

void main() {
  for (final children in [
    "for (final row in ['one', 'two'].where((v) => v != '')) Text(row)",
    "...['one', 'two'].map((row) => Text(row)).toList()",
    "for (final row in [true, false].where((v) => v)) Text('\$row')",
    "for (final row in [DateTime.utc(2024)].where((v) => v.year == 2024)) Text('\${row.year}')",
    "for (final flag in [true].where((v) => v)) for (final row in ['one'].where((v) => v != '')) Text('\$row\$flag')",
  ]) {
    test('typed item iteration reaches catalog capability: $children', () async {
      final (source, catalog) = await compileCollectionAuthoring(
        authoredSource:
            "import 'package:flutter/widgets.dart'; Widget x() => LayoutBuilder(builder: (context, constraints) => Column(children: [$children]));",
      );
      expect(source, contains('forEachItem'));
      expect(
        validateModelAgainstCatalog(rfw.parseLibraryFile(source), catalog),
        isEmpty,
      );
      expect(
        deriveSurfaceCapability(
          rfw.parseLibraryFile(source),
          catalog,
        ).builtInFloor,
        24,
      );
    });
  }
  test(
    'iteration envelopes reject mismatched and unbound parameter shapes',
    () {
      const strings = ValueType('list', item: ValueType.string);
      Object envelope(
        ValueType source,
        ValueType parameter, {
        bool index = false,
        bool unused = false,
        bool collection = true,
      }) {
        final program = BuilderProgram(
          values: ValueProgram(
            nodes: [
              ValueNode('capture', source, name: 'source'),
            ],
            captures: {'source': source},
            parameters: {'item': parameter},
            root: 0,
          ),
          result: unused
              ? const BuilderResult.body(0)
              : index
              ? const BuilderResult.forEach(0, 'item', BuilderResult.body(0))
              : const BuilderResult.forEachItem(
                  0,
                  'item',
                  BuilderResult.body(0),
                ),
          collection: collection,
          bodyCount: 1,
        );
        return {
          'version': 1,
          'program': program.encode(),
          'captures': <String, Object?>{'source': <String>[]},
          'bodies': [
            const rfw.WidgetBuilderDeclaration(
              'frame',
              rfw.ConstructorCall('Text', {}),
            ),
          ],
        };
      }

      expect(
        decodeRfwProgramEnvelope(envelope(strings, ValueType.string)),
        isNotNull,
      );
      expect(
        decodeRfwProgramEnvelope(
          envelope(ValueType.integer, ValueType.integer, index: true),
        ),
        isNotNull,
      );
      for (final value in [
        envelope(strings, ValueType.boolean),
        envelope(strings, const ValueType('String', nullable: true)),
        envelope(strings, ValueType.string, unused: true),
        envelope(strings, ValueType.string, collection: false),
        envelope(ValueType.string, ValueType.string),
        envelope(ValueType.integer, ValueType.string, index: true),
        envelope(
          ValueType.integer,
          const ValueType('int', nullable: true),
          index: true,
        ),
        envelope(
          const ValueType.native('List<Model>'),
          const ValueType.native('Model'),
        ),
        envelope(
          const ValueType('list', item: ValueType.native('Model')),
          const ValueType.native('Model'),
        ),
      ])
        expect(() => decodeRfwProgramEnvelope(value), throwsFormatException);
    },
  );

  test(
    'authored native collections reach builder bodies with capability 24',
    () async {
      final (source, catalog) = await compileCollectionAuthoring();
      final fixture = File('../restage_core/test/fixtures/collections.rfwtxt');
      if (Platform.environment['WRITE_COLLECTION_FIXTURE'] == '1')
        fixture.writeAsStringSync(source);
      expect(fixture.readAsStringSync(), source);
      expect(source, contains('forEachItem'));
      expect(
        deriveSurfaceCapability(
          rfw.parseLibraryFile(source),
          catalog,
        ).builtInFloor,
        24,
      );
    },
  );
}
