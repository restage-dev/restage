import 'dart:convert';
import 'dart:io';

import 'package:restage_codegen/src/a2ui/a2ui_catalog_adapter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_catalog_model.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// A small but representative sample that EXERCISES both capability axes:
///  * built-in widgets at mixed content versions — a leaf (`Text`@1), a
///    container (`Column`@1), and a button at a non-baseline version
///    (`FilledButton`@2) → the built-in floor lands at 2;
///  * a custom library (`acme.widgets`@3) contributing one component
///    (`AcmeBanner`@5) → the custom-library axis is populated, and the custom
///    widget's own `sinceVersion` (5) must NOT raise the built-in floor.
///
/// So the golden proves the two-axis stamp, the built-in/custom split, the
/// custom-library `$id` vector, and the discriminator-only component schema.
RestageStampedA2uiCatalog _sampleCatalog() {
  const acme = WidgetLibrary.custom('acme.widgets');
  final catalog = Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
      acme: const LibraryInfo(version: '1.0.0', capabilityVersion: 3),
    },
    widgets: [
      entry(
        name: 'Text',
        properties: [prop('text', PropertyType.string, required: true)],
      ),
      entry(name: 'Column', properties: [prop('spacing', PropertyType.real)]),
      entry(name: 'FilledButton', properties: [], sinceVersion: 2),
      entry(
        name: 'AcmeBanner',
        properties: [],
        library: acme,
        sinceVersion: 5,
      ),
    ],
  );
  return emitA2uiCatalog(catalog);
}

const _goldenPath = 'test/a2ui/golden/sample_catalog.a2ui.json';

void main() {
  test('golden — versioned A2UI catalog for a sample widget set', () {
    const encoder = JsonEncoder.withIndent('  ');
    final actual = encoder.convert(_sampleCatalog().toJson());

    final file = File(_goldenPath);
    if (Platform.environment['REGEN_A2UI_GOLDEN'] == '1') {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$actual\n');
    }

    expect(
      file.existsSync(),
      isTrue,
      reason: 'run with REGEN_A2UI_GOLDEN=1 to generate $_goldenPath',
    );
    expect(actual, file.readAsStringSync().trimRight());
  });
}
