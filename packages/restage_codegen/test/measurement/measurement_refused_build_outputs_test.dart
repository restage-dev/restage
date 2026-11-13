// A build refused on ledger review keeps what the last build generated.

import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../support/surface_build_chain.dart';

const _package = 'apps_examples';
const _sourcePath = 'lib/features/ledger.dart';
const _priorOutputPaths = <String>[
  'lib/features/restage.generated/ledger.restage.g.dart',
  '.restage/build/bundles/lib/features/ledger.rsbundle',
  '.restage/build/metadata/restage.publication.json',
  '.restage/build/metadata/restage.outputs.json',
  '.restage/build/metadata/restage.analytics-id.metadata.json',
  '.restage/build/metadata/restage.capture.json',
  '.restage/build/widget_catalog/catalog.json',
];
const _policyOptions = BuilderOptions({
  kMeasurementMinimumClientOption: 1,
  kMeasurementPrivacyPolicyRevisionOption: 'privacy.automatic-v1',
  kMeasurementCollectionBudgetRevisionOption: 'budget.automatic-v1',
});

void main() {
  test(
    'a build refused on ledger review keeps the prior generated outputs',
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

      // The refused build starts without them and reads them as prior outputs.
      final refused = await _build(
        _ledgerSource(reshaped: true),
        ledger: ledger,
        priorOutputs: prior,
      );
      expect(refused.result.succeeded, isFalse);
      expect(
        refused.result.errors.join('\n'),
        allOf(
          contains("This build can't tell which earlier widget"),
          isNot(contains('InvalidOutputException')),
        ),
      );
      final stamp =
          jsonDecode(
                refused.readerWriter.testing.readString(
                  AssetId(
                    _package,
                    '.restage/build/metadata/restage.build.json',
                  ),
                ),
              )
              as Map<String, Object?>;
      expect(stamp['result'], 'failed');
      expect(
        (stamp['errors']! as List).join('\n'),
        contains("This build can't tell which earlier widget"),
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
    },
  );

  test(
    'the refusal says how to resolve it, and resolving it rebuilds',
    () async {
      final settled = await _build(_ledgerSource());
      expect(settled.result.succeeded, isTrue);
      final ledger = settled.readerWriter.testing.readString(
        AssetId(_package, kRestageMeasurementCompilerOutputPath),
      );
      final refused = await _build(
        _ledgerSource(reshaped: true),
        ledger: ledger,
      );
      expect(refused.result.succeeded, isFalse);
      final message = refused.result.errors.join('\n');
      expect(
        message,
        allOf([
          contains("This build can't tell which earlier widget the one at "),
          contains('.restage/measurement-state.json'),
          contains('"acceptedRelocations"'),
          contains('"codeIdentityId": "code.auto.'),
          contains('"acceptedIntroductions"'),
          contains('Then rebuild.'),
        ]),
      );

      final proposals = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        refused.readerWriter.testing.readBytes(
          AssetId(_package, kRestageMeasurementCompilerOutputPath),
        ),
      ).proposals;
      final edited = jsonDecode(ledger) as Map<String, Object?>;
      edited['acceptedIntroductions'] = [
        for (final proposal in proposals)
          {'structuralOccurrenceKey': proposal.toStructuralOccurrenceKey},
      ];
      final resolved = await _build(
        _ledgerSource(reshaped: true),
        ledger: const JsonEncoder.withIndent('  ').convert(edited),
      );
      expect(
        resolved.result.succeeded,
        isTrue,
        reason: resolved.result.errors.join('\n'),
      );
    },
  );

  test('a hand-formatted state file is accepted', () async {
    final settled = await _build(_ledgerSource());
    final ledger = settled.readerWriter.testing.readString(
      AssetId(_package, kRestageMeasurementCompilerOutputPath),
    );
    final indented = const JsonEncoder.withIndent(
      '  ',
    ).convert(jsonDecode(ledger));
    final rebuilt = await _build(_ledgerSource(), ledger: indented);
    expect(
      rebuilt.result.succeeded,
      isTrue,
      reason: rebuilt.result.errors.join('\n'),
    );
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
      ...surfaceBuildChain(
        compiler: PackageSurfaceCompilerBuilder(
          _policyOptions,
          ledgerWriter: _discardLedgerSource,
        ),
        priorOutputs: priorOutputs,
      ),
    ],
    <String, Object>{
      '$_package|$_sourcePath': source,
      // A custom widget. The build writes a custom catalog too.
      '$_package|lib/features/chip.dart': _chip,
      // The surface has been pushed, so ambiguous matches need review.
      '$_package|.restage/receipts/acme/main/app/surface/general/ledger/'
              'production/push-r1.json':
          '{}',
      if (ledger != null)
        '$_package|$kRestageMeasurementCompilerLedgerSourcePath': ledger,
    },
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  return (result: result, readerWriter: readerWriter);
}

const _chip = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget(
  name: 'LedgerChip',
  library: WidgetLibrary.custom('app.widgets'),
  category: WidgetCategory.decoration,
  description: 'A chip.',
)
class LedgerChip extends StatelessWidget {
  const LedgerChip({super.key, required this.label});

  @RestageProperty(description: 'The label.', required: true)
  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}
''';

Future<void> _discardLedgerSource({
  required String package,
  required RestageMeasurementCompilerOutputV1 output,
}) async {}

String _ledgerSource({bool reshaped = false}) {
  const button = '''
FilledButton(
  onPressed: context.surfaceEvent(activate),
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
