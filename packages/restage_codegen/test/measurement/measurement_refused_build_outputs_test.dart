// A build refused on ledger review keeps what the last build generated.

import 'package:build/build.dart';
import 'package:restage_codegen/src/generated_dart_builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/output_builder.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _package = 'apps_examples';
const _sourcePath = 'lib/features/ledger.dart';
const _priorOutputPaths = <String>[
  'lib/features/restage.generated/ledger.restage.g.dart',
  'lib/features/restage.generated/ledger.rsbundle',
  'lib/generated/restage.publication.json',
  'lib/generated/restage.outputs.json',
];
const _policyOptions = BuilderOptions({
  kMeasurementMinimumClientOption: 1,
  kMeasurementPrivacyPolicyRevisionOption: 'privacy.automatic-v1',
  kMeasurementCollectionBudgetRevisionOption: 'budget.automatic-v1',
});

void main() {
  test('a build refused on ledger review keeps the prior generated outputs',
      () async {
    final settled = await _build(_ledgerSource());
    expect(
      settled.result.succeeded,
      isTrue,
      reason: settled.result.errors.join('\n'),
    );
    final prior = <String, List<int>>{
      for (final path in _priorOutputPaths)
        path: settled.readerWriter.testing.readBytes(
          AssetId(_package, path),
        ),
    };
    final ledger = settled.readerWriter.testing.readString(
      AssetId(_package, kRestageMeasurementCompilerOutputPath),
    );

    // The build system removes an output before re-running the step that owns
    // it, so the refused build starts without any of them.
    final refused = await _build(
      _ledgerSource(reshaped: true),
      ledger: ledger,
      priorOutputs: prior,
    );
    expect(refused.result.succeeded, isFalse);
    expect(
      refused.result.errors.join('\n'),
      contains('Measurement identity reconciliation requires review'),
    );
    final proposals = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
      refused.readerWriter.testing.readBytes(
        AssetId(_package, kRestageMeasurementCompilerOutputPath),
      ),
    );
    expect(proposals.valid, isFalse);
    expect(proposals.proposals, isNotEmpty);
    for (final entry in prior.entries) {
      expect(
        refused.readerWriter.testing.readBytes(AssetId(_package, entry.key)),
        orderedEquals(entry.value),
        reason: entry.key,
      );
    }
  });
}

Future<({TestBuilderResult result, TestReaderWriter readerWriter})> _build(
  String source, {
  String? ledger,
  Map<String, List<int>> priorOutputs = const {},
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
  );
  final result = await testBuilders(
    [
      PackageSurfaceCompilerBuilder(
        _policyOptions,
        ledgerWriter: _discardLedgerSource,
        priorOutputReader: (_, __) async => priorOutputs,
      ),
      RestageGeneratedDartBuilder(BuilderOptions.empty),
      RestageOutputsBuilder(BuilderOptions.empty),
    ],
    <String, Object>{
      '$_package|$_sourcePath': source,
      if (ledger != null)
        '$_package|$kRestageMeasurementCompilerLedgerSourcePath': ledger,
    },
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  return (result: result, readerWriter: readerWriter);
}

Future<void> _discardLedgerSource({
  required String package,
  required RestageMeasurementCompilerOutputV1 output,
}) async {}

String _ledgerSource({bool reshaped = false}) {
  const button = '''
FilledButton(
  onPressed: surfaceEvent(activate),
  child: const Text('Activate'),
)
''';
  // Two identical siblings: reshaping their container leaves no way to tell
  // which prior element is which, so the build is refused for review.
  final body = reshaped
      ? 'Row(children: [$button, $button])'
      : 'Column(children: [$button, $button])';
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/ledger.restage.g.dart';

@Screen(id: 'ledger', surface: Surface.general)
final class LedgerScreen extends StatelessWidget {
  const LedgerScreen({super.key});

  static const activate = SurfaceEvent<void>('activate');

  @override
  Widget build(BuildContext context) => $body;
}
''';
}
