import 'package:restage_codegen/src/coverage_measurement/coverage_report.dart';
import 'package:restage_codegen/src/coverage_measurement/coverage_walker.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'coverage_harness.dart';

/// Real-Flutter proof that the emit-confirmation lie-catcher *discriminates*.
///
/// Two custom widgets the classifier BOTH recognise as `themeAsData`-inlinable
/// — the classifier is intentionally broad and does not check the theme
/// contract. The translator's strict emit then discriminates: an
/// **in-contract** `Theme.of(c).colorScheme.primary` read emit-confirms,
/// while an
/// **out-of-contract** `Theme.of(c).colorScheme.surfaceVariant` read is
/// rejected (`themeReadOutOfContract`), so the harness demotes it to
/// `classifier-only/emit-failed`.
///
/// This is the realistic counterpart to the two direct `attemptInlineEmit`
/// unit tests (in `custom_widget_inlining_test.dart`): it resolves against
/// real `package:flutter/material.dart` and opts into `probeEmit` against a
/// catalog that declares the composed `Box`'s `color` property — so the only
/// emit failure is the INTRINSIC out-of-contract read, not catalog thinness.
/// It deliberately does NOT snapshot (the real catalog is a moving target);
/// it asserts the discrimination directly.
void main() {
  const inContractKey = 'package:apps_examples/coverage_fixtures/'
      'lie_catcher_proof.dart#ProofThemeInContract';
  const outOfContractKey = 'package:apps_examples/coverage_fixtures/'
      'lie_catcher_proof.dart#ProofThemeOutOfContract';

  // Local `Box` stub (a non-Flutter name so it does not collide with
  // Flutter's own widgets); imports real material.dart so the classifier's
  // element-resolution gate for `Theme.of` fires. `surfaceVariant` is a
  // deprecated — and therefore out-of-contract — ColorScheme role.
  const source = '''
// ignore_for_file: annotate_overrides, depend_on_referenced_packages
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Box extends StatelessWidget {
  const Box({this.color, super.key});
  final Color? color;
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'ProofThemeInContract',
  library: WidgetLibrary.custom('coverage.proof'),
  category: WidgetCategory.decoration,
  description: 'in-contract theme read — emit-confirms',
)
class ProofThemeInContract extends StatelessWidget {
  const ProofThemeInContract({super.key});
  Widget build(BuildContext context) =>
      Box(color: Theme.of(context).colorScheme.primary);
}

@RestageWidget(
  name: 'ProofThemeOutOfContract',
  library: WidgetLibrary.custom('coverage.proof'),
  category: WidgetCategory.decoration,
  description: 'out-of-contract theme read — classifier accepts, emit rejects',
)
class ProofThemeOutOfContract extends StatelessWidget {
  const ProofThemeOutOfContract({super.key});
  Widget build(BuildContext context) =>
      Box(color: Theme.of(context).colorScheme.surfaceVariant);
}
''';

  test(
      'the lie-catcher demotes a classifier-inlinable but emit-failed '
      'themeAsData widget to classifierOnly on real Flutter, while keeping '
      'the emit-confirmed one inlinable', () async {
    final catalog = catalogWith([
      entry(
        name: 'Box',
        properties: [prop('color', PropertyType.color)],
        flutterType: 'package:apps_examples/coverage_fixtures/'
            'lie_catcher_proof.dart#Box',
      ),
    ]);

    final probe = await classifyAllInFixture(
      {'lib/coverage_fixtures/lie_catcher_proof.dart': source},
      inputPath: 'lib/coverage_fixtures/lie_catcher_proof.dart',
      catalog: catalog,
      probeEmit: true,
    );

    // Both widgets must be present and classified.
    final inContract = probe.classifications[inContractKey];
    final outOfContract = probe.classifications[outOfContractKey];
    expect(inContract, isNotNull, reason: 'in-contract widget not classified');
    expect(
      outOfContract,
      isNotNull,
      reason: 'out-of-contract widget not classified',
    );

    // The classifier is broad: BOTH read the theme, so both are
    // themeAsData-inlinable by classifier verdict alone.
    expect(bucketFor(inContract!), CoverageBucket.inlinableThemeAsData);
    expect(bucketFor(outOfContract!), CoverageBucket.inlinableThemeAsData);

    // The translator's strict emit discriminates on the theme contract.
    expect(probe.emitOutcomes[inContractKey], EmitOutcome.confirmed);
    expect(probe.emitOutcomes[outOfContractKey], EmitOutcome.failed);

    // The lie-catcher: the emit-failed widget is demoted to classifierOnly;
    // the emit-confirmed one keeps its inlinable bucket.
    expect(
      bucketForEmit(inContract, probe.emitOutcomes[inContractKey]!),
      CoverageBucket.inlinableThemeAsData,
    );
    expect(
      bucketForEmit(outOfContract, probe.emitOutcomes[outOfContractKey]!),
      CoverageBucket.classifierOnly,
    );
  });
}
