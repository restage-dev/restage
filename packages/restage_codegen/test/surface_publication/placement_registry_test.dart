import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/generated_dart_builder.dart';
import 'package:restage_codegen/src/restage_source_roster_builder.dart';
import 'package:restage_codegen/src/surface_publication/output_builder.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Every builder that resolves a placement plan registers it, so a package
/// that configures one Restage builder key and forgets another is told.
///
/// Build Runner has no cross-builder options channel: each key accepts the
/// same options with the same defaults, and "configure it once" is honest
/// only through root global options or repeated target options. Before this
/// record existed, only the builders that compile surfaces ever met, so a
/// divergent portable-output root on the outputs key wrote bundles and the
/// index under a root nothing else agreed with, silently.
const _divergenceMessage =
    'Placement options divergence between Restage builder targets';

/// One authored library with no Restage declaration at all. Placement is
/// resolved from options alone, so the record has to disagree on the options
/// even when the package has nothing to compile.
const _source = '// authored, no Restage declarations\n';

Future<({bool succeeded, String report})> _run(List<Builder> builders) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  readerWriter.testing.writeString(
    AssetId('apps_examples', 'lib/plain.dart'),
    _source,
  );
  final logs = <String>[];
  final result = await testBuilders(
    builders,
    const {'apps_examples|lib/plain.dart': _source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) => logs.add('${record.message}${record.error ?? ''}'),
  );
  return (succeeded: result.succeeded, report: logs.join('\n'));
}

void main() {
  group('placement record — every plan-resolving builder participates', () {
    test('a divergent output root on the outputs key is caught', () async {
      // The case that motivated closing this gap: the outputs builder reads a
      // plan but compiles no surfaces, so nothing else in the build would
      // have noticed it writing bundles and the index somewhere else.
      final result = await _run([
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        RestageOutputsBuilder(
          const BuilderOptions({'output_root': 'tool/restage'}),
        ),
      ]);
      expect(result.succeeded, isFalse);
      expect(result.report, contains(_divergenceMessage));
      expect(result.report, contains('output_root=-'));
      expect(result.report, contains('output_root=tool/restage'));
    });

    test('a divergent generated-Dart root on the Dart key is caught', () async {
      final result = await _run([
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        RestageGeneratedDartBuilder(
          const BuilderOptions({'dart_output_root': 'lib/generated/restage'}),
        ),
      ]);
      expect(result.succeeded, isFalse);
      expect(result.report, contains(_divergenceMessage));
    });

    test('a divergent source layout on the roster key is caught', () async {
      final result = await _run([
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        const RestageSourceRosterBuilder(
          BuilderOptions({'source_output_layout': 'adjacent'}),
        ),
      ]);
      expect(result.succeeded, isFalse);
      expect(result.report, contains(_divergenceMessage));
    });

    test('every key at its default agrees', () async {
      // The guard must not fire on an unconfigured package — by far the
      // common case, and the one a false positive would break outright.
      final result = await _run([
        const RestageSourceRosterBuilder(BuilderOptions.empty),
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        RestageOutputsBuilder(BuilderOptions.empty),
        RestageGeneratedDartBuilder(BuilderOptions.empty),
      ]);
      expect(result.succeeded, isTrue, reason: result.report);
    });

    test('every key carrying the same configuration agrees', () async {
      // What the diagnostic itself tells the developer to do: set the option
      // once under global options so every key resolves it identically.
      const options = BuilderOptions({'output_root': 'tool/restage'});
      final result = await _run([
        const RestageSourceRosterBuilder(options),
        const PackageSurfaceCompilerBuilder(options),
        RestageOutputsBuilder(options),
        RestageGeneratedDartBuilder(options),
      ]);
      expect(result.succeeded, isTrue, reason: result.report);
    });
  });
}
