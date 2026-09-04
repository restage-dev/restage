import 'package:build/build.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _policyOptions = BuilderOptions({
  kMeasurementMinimumClientOption: 1,
  kMeasurementPrivacyPolicyRevisionOption: 'privacy.automatic-v1',
  kMeasurementCollectionBudgetRevisionOption: 'budget.automatic-v1',
});

const _firstAsset = 'apps_examples|lib/features/first.dart';
const _secondAsset = 'apps_examples|lib/features/second.dart';

const _text = 'package:flutter/src/widgets/text.dart#Text';
const _firstScreen = 'package:apps_examples/features/first.dart#FirstScreen';
const _secondScreen = 'package:apps_examples/features/second.dart#SecondScreen';

const _button = '''
FilledButton(
  onPressed: surfaceEvent(activate),
  child: const Text('Go'),
)''';

/// Repeated identical option rows: every card shares one reconciliation
/// fingerprint, so nothing here is separable by fingerprint alone.
const _option = '''
FilledButton(
  onPressed: surfaceEvent(activate),
  child: const Row(
    children: [
      Expanded(child: Text('option')),
      Icon(Icons.chevron_right),
    ],
  ),
)''';

const _panel = '''
SafeArea(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        const Text('one'),
        const SizedBox(height: 8),
        const Text('two'),
        const SizedBox(height: 8),
        $_option,
        const SizedBox(height: 8),
        $_option,
        const SizedBox(height: 8),
        $_option,
      ],
    ),
  ),
)''';

void main() {
  test('inserting an ancestor above a screen body keeps every identity',
      () async {
    final first = await _compile({
      _firstAsset: _screen(body: 'Scaffold(body: $_panel)'),
    });
    expect(first.result.succeeded, isTrue);

    final wrapped = await _compile(
      {
        _firstAsset: _screen(
          body: '''
Scaffold(
  body: Column(
    children: [
      AppBar(title: const Text('heading')),
      Expanded(child: $_panel),
    ],
  ),
)''',
        ),
      },
      priorOutput: first.output,
    );
    expect(
      wrapped.result.succeeded,
      isTrue,
      reason: wrapped.result.errors.join('\n'),
    );
    expect(wrapped.output.valid, isTrue);
    expect(wrapped.output.proposals, isEmpty);
    expect(wrapped.output.errors, isEmpty);

    // Every element the screen already had keeps its identity and references.
    final before = _screenNodes(first.output, _firstScreen);
    final after = _screenNodes(wrapped.output, _firstScreen);
    expect(before, hasLength(greaterThan(8)));
    expect(
      after.map((node) => node.codeIdentityId.value).toSet(),
      containsAll(before.map((node) => node.codeIdentityId.value)),
    );
    expect(
      _referenceIds(after),
      containsAll(_referenceIds(before)),
    );
    // Only the four inserted elements are new.
    expect(after, hasLength(before.length + 4));
    final introduced = after.where(
      (node) => !before
          .map((prior) => prior.codeIdentityId.value)
          .contains(node.codeIdentityId.value),
    );
    expect(
      introduced
          .map(
            (node) => node.structuralOccurrenceKey.split('|').last,
          )
          .toSet(),
      {
        'widget:package:flutter/src/widgets/basic.dart#Column',
        'widget:package:flutter/src/material/app_bar.dart#AppBar',
        'widget:$_text',
        'widget:package:flutter/src/widgets/basic.dart#Expanded',
      },
    );
  });

  test('two identical siblings changing container still propose candidates',
      () async {
    final first = await _compile({
      _firstAsset: _screen(body: 'Column(children: [$_button, $_button])'),
    });
    expect(first.result.succeeded, isTrue);

    final swapped = await _compile(
      {_firstAsset: _screen(body: 'Row(children: [$_button, $_button])')},
      priorOutput: first.output,
    );
    expect(swapped.result.succeeded, isFalse);
    expect(swapped.output.valid, isFalse);
    expect(
      swapped.output.proposals.any(
        (proposal) =>
            proposal.candidatePriorStructuralOccurrenceKeys.length > 1,
      ),
      isTrue,
    );
  });

  test('a retired element in another screen is never a candidate', () async {
    final first = await _compile({
      _firstAsset: _screen(body: "Column(children: [Text('a'), Text('b')])"),
      _secondAsset:
          _screen(name: 'Second', body: "Column(children: [Text('c')])"),
    });
    expect(first.result.succeeded, isTrue);

    final relocated = await _compile(
      {
        _firstAsset: _screen(body: "Column(children: [Text('a')])"),
        _secondAsset: _screen(
          name: 'Second',
          body: "Column(children: [Text('c'), Text('d')])",
        ),
      },
      priorOutput: first.output,
    );
    expect(
      relocated.result.succeeded,
      isTrue,
      reason: relocated.result.errors.join('\n'),
    );
    expect(relocated.output.valid, isTrue);
    expect(relocated.output.proposals, isEmpty);
    expect(relocated.output.errors, isEmpty);

    final retired = first.output.ledgerNodes.singleWhere(
      (node) =>
          node.structuralOccurrenceKey.startsWith('$_firstScreen|') &&
          node.structuralOccurrenceKey.endsWith('children[1]|widget:$_text'),
    );
    final introduced = relocated.output.ledgerNodes.singleWhere(
      (node) =>
          node.structuralOccurrenceKey.startsWith('$_secondScreen|') &&
          node.structuralOccurrenceKey.endsWith('children[1]|widget:$_text'),
    );
    expect(
      introduced.reconciliationFingerprint,
      retired.reconciliationFingerprint,
      reason: 'the cross-screen candidate must be reachable by fingerprint',
    );
    expect(introduced.codeIdentityId, isNot(retired.codeIdentityId));
    expect(
      relocated.output.ledgerNodes
          .singleWhere((node) => node.codeIdentityId == retired.codeIdentityId)
          .active,
      isFalse,
    );
  });
}

List<MeasurementCompilerLedgerNode> _screenNodes(
  RestageMeasurementCompilerOutputV1 output,
  String screen,
) =>
    [
      for (final node in output.ledgerNodes)
        if (node.active && node.structuralOccurrenceKey.startsWith('$screen|'))
          node,
    ];

Set<String> _referenceIds(List<MeasurementCompilerLedgerNode> nodes) => {
      for (final node in nodes)
        for (final event in node.events)
          if (event.active) event.generatedReferenceId.value,
    };

String _screen({required String body, String name = 'First'}) {
  final file = name.toLowerCase();
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/$file.restage.g.dart';

@Screen(id: '$file', surface: Surface.general)
final class ${name}Screen extends StatelessWidget {
  const ${name}Screen({super.key});

  static const activate = SurfaceEvent<void>('activate');

  @override
  Widget build(BuildContext context) => $body;
}
''';
}

Future<
    ({
      TestBuilderResult result,
      RestageMeasurementCompilerOutputV1 output,
    })> _compile(
  Map<String, String> sources, {
  RestageMeasurementCompilerOutputV1? priorOutput,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final result = await testBuilder(
    const PackageSurfaceCompilerBuilder(_policyOptions),
    {
      ...sources,
      if (priorOutput != null)
        'apps_examples|$kRestageMeasurementCompilerLedgerSourcePath':
            priorOutput.encodeCanonicalJson(),
    },
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  final output = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
    readerWriter.testing.readBytes(
      AssetId('apps_examples', kRestageMeasurementCompilerOutputPath),
    ),
  );
  return (result: result, output: output);
}
