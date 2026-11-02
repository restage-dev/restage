import 'dart:convert';
import 'dart:io';

import 'package:a2ui_core/a2ui_core.dart' as core;
import 'package:build/build.dart';
import 'package:restage_codegen/src/a2ui/a2ui_protocol.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test(
    'production dollar names emit parser-valid distinct properties',
    () async {
      const fixture =
          '../restage_a2ui/test/generated/encoded_property_fixture.dart';
      final source = File(fixture).readAsStringSync();
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
        includeFlutter: true,
      );
      final sourceId = AssetId(
        'apps_examples',
        'lib/encoded_property_fixture.dart',
      );
      readerWriter.testing.writeString(sourceId, source);
      final builder = UserA2uiCatalogBuilder(BuilderOptions.empty);
      final logs = <String>[];
      final result = await testBuilder(
        builder,
        {
          'apps_examples|lib/encoded_property_fixture.dart': source,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
        onLog: (record) => logs.add(record.message),
      );
      expect(result.succeeded, isTrue, reason: logs.join('\n'));
      String read(String path) => utf8.decode(
        result.readerWriter.testing.readBytes(
          AssetId('apps_examples', path),
        ),
      );
      final documentText = read(builder.plan.a2uiCatalogPath);
      final envelope = jsonDecode(documentText) as Map<String, Object?>;
      final document = envelope['a2uiCatalog']! as Map<String, Object?>;
      // This is the actual published parser, not equality of two emitted maps.
      final parsed = core.Catalog.fromJson(document);
      expect(parsed.toJson(), document);
      final schema = parsed.components['EncodedPropertyProbe']!.schema.value;
      final properties = schema['properties']! as Map<String, Object?>;
      expect(
        properties.keys,
        containsAll([
          'props_encoded_002400760061006c00750065',
          a2uiPropertyName('encoded_002400760061006c00750065'),
          'props_value',
          'props_details',
        ]),
      );
      expect(properties.keys, hasLength(4));
      final details = properties['props_details']! as Map<String, Object?>;
      expect((details['properties']! as Map).keys, [r'$value']);
      expect(
        document['instructions'],
        contains(
          r'$value => props_encoded_002400760061006c00750065',
        ),
      );
      final dart = read('lib/generated/restage_a2ui_catalog.g.dart').replaceAll(
        'package:apps_examples/encoded_property_fixture.dart',
        'encoded_property_fixture.dart',
      );
      expect(dart, contains(r'$value:'));
      expect(dart, contains('encoded_002400760061006c00750065:'));
      final artifacts = {
        '../restage_a2ui/test/generated/encoded_property_catalog.g.dart':
            '${formatGeneratedDart(dart).trimRight()}\n',
        '../restage_a2ui/test/generated/encoded_property_catalog.a2ui.json':
            '${documentText.trimRight()}\n',
      };
      for (final entry in artifacts.entries) {
        final file = File(entry.key);
        if (Platform.environment['REGEN_A2UI_DART_GOLDEN'] == '1') {
          file.writeAsStringSync(entry.value);
        }
        expect(
          file.readAsStringSync(),
          entry.value,
          reason: 'Regenerate with REGEN_A2UI_DART_GOLDEN=1',
        );
      }
    },
  );
}
