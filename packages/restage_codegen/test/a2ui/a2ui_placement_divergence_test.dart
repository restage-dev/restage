import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Placement divergence reaches the A2UI catalog builder.
///
/// Build Runner has no cross-builder options channel, so a package can
/// configure one Restage builder key and forget another. The A2UI builder is
/// the awkward case: it reads a placement plan but compiles no surfaces and
/// reads no compiler handoff, so it shares no artifact with the rest of the
/// pipeline and would otherwise be the one key that never meets the others —
/// a package configuring a different root here than on the outputs key would
/// get a quietly split layout, which is exactly what the divergence
/// diagnostic exists to prevent.
///
/// The package below declares one `@RestageWidget` and no surface at all, so
/// nothing but the shared placement record connects the two builders.
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

Future<({bool succeeded, List<String> logs})> _run({
  required Map<String, dynamic> compilerOptions,
  required Map<String, dynamic> a2uiOptions,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'restage_codegen',
  );
  readerWriter.testing.writeString(
    AssetId('apps_examples', 'lib/gauge.dart'),
    _customerSource,
  );
  final logs = <String>[];
  final result = await testBuilders(
    [
      PackageSurfaceCompilerBuilder(BuilderOptions(compilerOptions)),
      UserA2uiCatalogBuilder(BuilderOptions(a2uiOptions)),
    ],
    const {'apps_examples|lib/gauge.dart': _customerSource},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) => logs.add('${record.message}${record.error ?? ''}'),
  );
  return (succeeded: result.succeeded, logs: logs);
}

void main() {
  group('A2UI catalog builder — placement options divergence', () {
    test('a surface-free package still diverges loudly on a conflicting key',
        () async {
      final result = await _run(
        compilerOptions: const {},
        a2uiOptions: const {'output_root': 'tool/restage'},
      );

      expect(
        result.succeeded,
        isFalse,
        reason: 'A2UI resolving a different placement than another Restage '
            'builder key must fail the build, never emit at its own root and '
            'leave the package with a split layout.',
      );
      final report = result.logs.join('\n');
      expect(
        report,
        contains('Placement options divergence between Restage builder '
            'targets'),
      );
      // The report must name BOTH resolutions — a diagnostic that says only
      // "they disagree" leaves the developer to guess which key to change.
      expect(report, contains('output_root=-'));
      expect(report, contains('output_root=tool/restage'));
      // The remedy must name the disagreeing builder keys and steer away
      // from global_options, never toward it: root global_options overrides
      // the options every package in the build sets for itself.
      expect(
        report,
        contains('restage_codegen:restage_package_surface_compiler'),
      );
      expect(report, contains('restage_codegen:user_a2ui_catalog'));
      expect(report, contains('Do not set them under global_options'));
    });

    test('identical options on both keys build cleanly', () async {
      // The guard must not fire on the configuration the divergence message
      // itself tells the developer to adopt.
      final result = await _run(
        compilerOptions: const {'output_root': 'tool/restage'},
        a2uiOptions: const {'output_root': 'tool/restage'},
      );
      expect(result.succeeded, isTrue, reason: result.logs.join('\n'));
    });

    test('the default configuration on both keys builds cleanly', () async {
      final result = await _run(
        compilerOptions: const {},
        a2uiOptions: const {},
      );
      expect(result.succeeded, isTrue, reason: result.logs.join('\n'));
    });

    test('a divergent generated-Dart root is caught too', () async {
      // Both roots are part of one signature, so the check is not specific to
      // the axis the A2UI producer document happens to follow.
      final result = await _run(
        compilerOptions: const {},
        a2uiOptions: const {'dart_output_root': 'lib/generated/restage'},
      );
      expect(result.succeeded, isFalse);
      expect(
        result.logs.join('\n'),
        contains('Placement options divergence between Restage builder '
            'targets'),
      );
    });
  });
}
