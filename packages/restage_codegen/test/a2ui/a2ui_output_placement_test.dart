import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Placement of the two A2UI outputs.
///
/// The importable catalog Dart is package-wide generated Dart: only a
/// configured generated-Dart root moves it. The producer-facing capability
/// document is portable tooling data: only a configured portable-output root
/// moves it, into that root's `a2ui/` purpose directory. Neither is ever a
/// bundle entry, a publication artifact, a delivery capability sidecar, or an
/// application asset, so the bundled-runtime switch and the source layout
/// leave both exactly where they were.
///
/// Placement decides WHERE each file goes and never WHAT is in it: every
/// configured case asserts the emitted bytes against the default-placement
/// bytes.
const _defaultDartPath = 'lib/generated/restage_a2ui_catalog.g.dart';
const _defaultJsonPath = 'lib/generated/restage_a2ui_catalog.a2ui.json';

const _customerSource = '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageLibrary(
    library: WidgetLibrary.custom('acme.widgets'),
    capabilityVersion: 1,
  )
  const restageLibrary = 0;

  @RestageWidget(
    name: 'Gauge',
    library: WidgetLibrary.custom('acme.widgets'),
    category: WidgetCategory.decoration,
    description: 'a customer gauge',
  )
  class Gauge {
    const Gauge({required this.value});
    @RestageProperty(description: 'the reading')
    final double value;
  }
''';

/// Every package-relative path the builder wrote, mapped to its exact bytes.
Future<Map<String, List<int>>> _emit(Map<String, dynamic> options) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'restage_codegen',
  );
  readerWriter.testing.writeString(
    AssetId('apps_examples', 'lib/gauge.dart'),
    _customerSource,
  );
  final logs = <String>[];
  final result = await testBuilder(
    UserA2uiCatalogBuilder(BuilderOptions(options)),
    const {'apps_examples|lib/gauge.dart': _customerSource},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) => logs.add(record.message),
  );
  expect(result.succeeded, isTrue, reason: logs.join('\n'));
  return {
    for (final asset in result.outputs)
      if (asset.package == 'apps_examples')
        asset.path: result.readerWriter.testing.readBytes(asset),
  };
}

void main() {
  group('UserA2uiCatalogBuilder — output placement', () {
    test('default placement declares and writes the two colocated files',
        () async {
      expect(
        UserA2uiCatalogBuilder(BuilderOptions.empty).buildExtensions,
        {
          r'$package$': [_defaultDartPath, _defaultJsonPath],
        },
      );
      final emitted = await _emit(const {});
      expect(
        emitted.keys,
        unorderedEquals(<String>[_defaultDartPath, _defaultJsonPath]),
      );

      // Prove the probe is not vacuous: every other case in this group
      // compares paths and bytes against this emit, so an empty or
      // widget-less emit would make all of them pass for the wrong reason.
      final stamp = jsonDecode(utf8.decode(emitted[_defaultJsonPath]!))
          as Map<String, Object?>;
      final catalog = stamp['a2uiCatalog']! as Map<String, Object?>;
      expect((catalog['components']! as Map).keys, contains('Gauge'));
      expect(
        utf8.decode(emitted[_defaultDartPath]!),
        contains('buildRestageCatalogItems'),
      );
    });

    test('a configured output root moves only the producer document', () async {
      const options = {'output_root': 'tool/restage'};
      const movedJsonPath = 'tool/restage/a2ui/restage_a2ui_catalog.a2ui.json';

      expect(
        UserA2uiCatalogBuilder(const BuilderOptions(options)).buildExtensions,
        {
          r'$package$': [_defaultDartPath, movedJsonPath],
        },
      );

      final baseline = await _emit(const {});
      final configured = await _emit(options);
      expect(
        configured.keys,
        unorderedEquals(<String>[_defaultDartPath, movedJsonPath]),
      );
      expect(configured[movedJsonPath], baseline[_defaultJsonPath]);
      expect(configured[_defaultDartPath], baseline[_defaultDartPath]);
    });

    test('a configured generated-Dart root moves only the catalog Dart',
        () async {
      const options = {'dart_output_root': 'lib/generated/restage'};
      const movedDartPath = 'lib/generated/restage/restage_a2ui_catalog.g.dart';

      expect(
        UserA2uiCatalogBuilder(const BuilderOptions(options)).buildExtensions,
        {
          r'$package$': [movedDartPath, _defaultJsonPath],
        },
      );

      final baseline = await _emit(const {});
      final configured = await _emit(options);
      expect(
        configured.keys,
        unorderedEquals(<String>[movedDartPath, _defaultJsonPath]),
      );
      expect(configured[movedDartPath], baseline[_defaultDartPath]);
      expect(configured[_defaultJsonPath], baseline[_defaultJsonPath]);
    });

    test('both roots configured move each file independently', () async {
      const options = {
        'dart_output_root': 'lib/generated/restage',
        'output_root': 'tool/restage',
      };
      expect(
        UserA2uiCatalogBuilder(const BuilderOptions(options)).buildExtensions,
        {
          r'$package$': [
            'lib/generated/restage/restage_a2ui_catalog.g.dart',
            'tool/restage/a2ui/restage_a2ui_catalog.a2ui.json',
          ],
        },
      );
      expect(
        (await _emit(options)).keys,
        unorderedEquals(<String>[
          'lib/generated/restage/restage_a2ui_catalog.g.dart',
          'tool/restage/a2ui/restage_a2ui_catalog.a2ui.json',
        ]),
      );
    });

    test('bundled runtime never routes A2UI output into application assets',
        () async {
      // The producer document is not a bundle entry and not an application
      // asset; the switch that relocates bundles must not touch it.
      const options = {'bundled_runtime': true};
      final emitted = await _emit(options);
      expect(
        UserA2uiCatalogBuilder(const BuilderOptions(options)).buildExtensions,
        {
          r'$package$': [_defaultDartPath, _defaultJsonPath],
        },
      );
      expect(
        emitted.keys,
        unorderedEquals(<String>[_defaultDartPath, _defaultJsonPath]),
      );
      expect(
        emitted.keys.where((path) => path.startsWith('assets/')),
        isEmpty,
      );
    });

    test('the source layout and the inspection report leave both files put',
        () async {
      // Neither file belongs to any single authored library, so the per-source
      // layout has nothing to say about them, and neither is ever reported on.
      for (final options in const <Map<String, dynamic>>[
        {'source_output_layout': 'adjacent'},
        {'source_output_layout': 'generated_directory'},
        {'inspection_report': true},
      ]) {
        expect(
          UserA2uiCatalogBuilder(BuilderOptions(options)).buildExtensions,
          {
            r'$package$': [_defaultDartPath, _defaultJsonPath],
          },
          reason: 'options $options must not move A2UI output',
        );
      }
    });

    test('no emitted path is a bundle, a publication record, or a sidecar',
        () async {
      final emitted = await _emit(const {'output_root': 'tool/restage'});
      for (final path in emitted.keys) {
        expect(path, isNot(endsWith('.rsbundle')));
        expect(path, isNot(endsWith('.capability.json')));
        expect(path, isNot(endsWith('.restage.md')));
        expect(path, isNot(contains('/bundles/')));
        expect(path, isNot(contains('/metadata/')));
        expect(path, isNot(contains('/reports/')));
      }
    });

    test('an unrecognized option is rejected instead of silently ignored', () {
      expect(
        () => UserA2uiCatalogBuilder(
          const BuilderOptions({'a2ui_output_root': 'tool/restage'}),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('a2ui_output_root'),
          ),
        ),
      );
    });

    test('a malformed placement option fails before any output is declared',
        () {
      expect(
        () => UserA2uiCatalogBuilder(
          const BuilderOptions({'output_root': '../escape'}),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => UserA2uiCatalogBuilder(
          const BuilderOptions({'dart_output_root': 'tool/restage'}),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
