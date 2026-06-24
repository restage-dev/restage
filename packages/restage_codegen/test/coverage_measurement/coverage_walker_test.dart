import 'package:restage_codegen/src/coverage_measurement/coverage_report.dart';
import 'package:restage_codegen/src/coverage_measurement/coverage_walker.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:test/test.dart';

void main() {
  group('bucketFor — single-widget classification → CoverageBucket', () {
    test(
        'a ComposableWidget with no required mechanisms is '
        'inlinable / composition-only', () {
      final classification = ComposableWidget(
        'pkg/lib.dart#Card',
        requiredMechanisms: const {},
        composedCustomWidgets: const [],
      );
      expect(bucketFor(classification), CoverageBucket.inlinableComposition);
    });

    test(
        'a ComposableWidget needing constantFolding only is '
        'inlinable / + const-fold', () {
      final classification = ComposableWidget(
        'pkg/lib.dart#Pad',
        requiredMechanisms: const {InliningMechanism.constantFolding},
        composedCustomWidgets: const [],
      );
      expect(bucketFor(classification), CoverageBucket.inlinableConstantFold);
    });

    test(
        'a ComposableWidget needing themeAsData (with or without '
        'constantFolding) is inlinable / + theme-as-data', () {
      final themeOnly = ComposableWidget(
        'pkg/lib.dart#Pill',
        requiredMechanisms: const {InliningMechanism.themeAsData},
        composedCustomWidgets: const [],
      );
      final themeAndFold = ComposableWidget(
        'pkg/lib.dart#Banner',
        requiredMechanisms: const {
          InliningMechanism.constantFolding,
          InliningMechanism.themeAsData,
        },
        composedCustomWidgets: const [],
      );
      expect(bucketFor(themeOnly), CoverageBucket.inlinableThemeAsData);
      expect(bucketFor(themeAndFold), CoverageBucket.inlinableThemeAsData);
    });

    test(
        'a ComposableWidget needing declarativeState (with or without '
        'other mechanisms) is inlinable / + declarative-state', () {
      final stateOnly = ComposableWidget(
        'pkg/lib.dart#Toggle',
        requiredMechanisms: const {InliningMechanism.declarativeState},
        composedCustomWidgets: const [],
      );
      final stateAndTheme = ComposableWidget(
        'pkg/lib.dart#Expander',
        requiredMechanisms: const {
          InliningMechanism.declarativeState,
          InliningMechanism.themeAsData,
        },
        composedCustomWidgets: const [],
      );
      expect(bucketFor(stateOnly), CoverageBucket.inlinableDeclarativeState);
      expect(
        bucketFor(stateAndTheme),
        CoverageBucket.inlinableDeclarativeState,
      );
    });

    test('an ImperativeWidget is structural', () {
      final classification = ImperativeWidget(
        'pkg/lib.dart#Chart',
        blockers: const [
          Blocker(
            kind: BlockerKind.customPainter,
            location: 'pkg/lib.dart#Chart@10:5',
            detail: 'CustomPaint(painter: ChartPainter())',
          ),
        ],
      );
      expect(bucketFor(classification), CoverageBucket.structural);
    });

    test('an UnclassifiableWidget is deferred', () {
      const classification = UnclassifiableWidget(
        'pkg/lib.dart#Strange',
        reason: 'build() uses an inline event-handler closure, which this '
            'transpiler increment does not yet analyse',
      );
      expect(bucketFor(classification), CoverageBucket.deferred);
    });
  });

  group(
      'bucketForEmit — emit-aware bucketing (B1: emit-confirmed, not '
      'merely classifier-recognised)', () {
    test(
        'a ComposableWidget the classifier recognises as inlinable but whose '
        'strict emit FAILED buckets to classifierOnly, not an inlinable '
        'bucket — this is the lie-catcher the classifier-only metric missed',
        () {
      final classification = ComposableWidget(
        'pkg/lib.dart#ThemePill',
        requiredMechanisms: const {InliningMechanism.themeAsData},
        composedCustomWidgets: const [],
      );
      // The classifier-only (upper-bound) view counts it inlinable.
      expect(bucketFor(classification), CoverageBucket.inlinableThemeAsData);
      // The emit-aware view demotes it: the translator's strict emit found
      // issues (e.g. an out-of-contract theme read), so it does NOT inline.
      expect(
        bucketForEmit(classification, EmitOutcome.failed),
        CoverageBucket.classifierOnly,
      );
    });

    test(
        'a ComposableWidget whose strict emit is CONFIRMED keeps its '
        'classifier bucket', () {
      final classification = ComposableWidget(
        'pkg/lib.dart#Card',
        requiredMechanisms: const {},
        composedCustomWidgets: const [],
      );
      expect(
        bucketForEmit(classification, EmitOutcome.confirmed),
        CoverageBucket.inlinableComposition,
      );
    });

    test(
        'a deferred/structural widget is unaffected by the emit outcome — '
        'there is nothing to emit-confirm', () {
      const deferred = UnclassifiableWidget(
        'pkg/lib.dart#Strange',
        reason: 'unrecognised construct',
      );
      final structural = ImperativeWidget(
        'pkg/lib.dart#Chart',
        blockers: const [
          Blocker(
            kind: BlockerKind.customPainter,
            location: 'pkg/lib.dart#Chart@1:1',
            detail: 'CustomPaint(...)',
          ),
        ],
      );
      expect(
        bucketForEmit(deferred, EmitOutcome.notAttempted),
        CoverageBucket.deferred,
      );
      expect(
        bucketForEmit(structural, EmitOutcome.notAttempted),
        CoverageBucket.structural,
      );
    });

    test(
        'an inlinable candidate with notAttempted emit stays at the '
        'classifier (upper-bound) bucket — classifier-only CLI mode', () {
      final classification = ComposableWidget(
        'pkg/lib.dart#Pad',
        requiredMechanisms: const {InliningMechanism.constantFolding},
        composedCustomWidgets: const [],
      );
      expect(
        bucketForEmit(classification, EmitOutcome.notAttempted),
        CoverageBucket.inlinableConstantFold,
      );
    });
  });

  group('CoverageReport.from — bucketing + counts + inlinable rollup', () {
    test('an empty input produces a report with all counts at zero', () {
      final report = CoverageReport.from(const {});
      for (final bucket in CoverageBucket.values) {
        expect(report.countOf(bucket), 0);
      }
      expect(report.inlinableTotal, 0);
      expect(report.total, 0);
    });

    test('counts are partitioned by bucket and the rollup sums inlinables', () {
      final report = CoverageReport.from({
        'pkg/lib.dart#Card': ComposableWidget(
          'pkg/lib.dart#Card',
          requiredMechanisms: const {},
          composedCustomWidgets: const [],
        ),
        'pkg/lib.dart#Pad': ComposableWidget(
          'pkg/lib.dart#Pad',
          requiredMechanisms: const {InliningMechanism.constantFolding},
          composedCustomWidgets: const [],
        ),
        'pkg/lib.dart#Pill': ComposableWidget(
          'pkg/lib.dart#Pill',
          requiredMechanisms: const {InliningMechanism.themeAsData},
          composedCustomWidgets: const [],
        ),
        'pkg/lib.dart#Toggle': ComposableWidget(
          'pkg/lib.dart#Toggle',
          requiredMechanisms: const {InliningMechanism.declarativeState},
          composedCustomWidgets: const [],
        ),
        'pkg/lib.dart#Chart': ImperativeWidget(
          'pkg/lib.dart#Chart',
          blockers: const [
            Blocker(
              kind: BlockerKind.customPainter,
              location: 'pkg/lib.dart#Chart@1:1',
              detail: 'CustomPaint(...)',
            ),
          ],
        ),
        'pkg/lib.dart#Strange': const UnclassifiableWidget(
          'pkg/lib.dart#Strange',
          reason: 'build() uses something this transpiler increment does '
              'not yet recognise',
        ),
      });

      expect(report.countOf(CoverageBucket.inlinableComposition), 1);
      expect(report.countOf(CoverageBucket.inlinableConstantFold), 1);
      expect(report.countOf(CoverageBucket.inlinableThemeAsData), 1);
      expect(report.countOf(CoverageBucket.inlinableDeclarativeState), 1);
      expect(report.countOf(CoverageBucket.deferred), 1);
      expect(report.countOf(CoverageBucket.structural), 1);
      expect(report.inlinableTotal, 4);
      expect(report.total, 6);
    });

    test(
        'with emitOutcomes, an emit-failed inlinable is demoted to '
        'classifierOnly and dropped from the inlinable rollup', () {
      final report = CoverageReport.from(
        {
          'pkg#A': ComposableWidget(
            'pkg#A',
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
          'pkg#B': ComposableWidget(
            'pkg#B',
            requiredMechanisms: const {InliningMechanism.themeAsData},
            composedCustomWidgets: const [],
          ),
        },
        emitOutcomes: const {
          'pkg#A': EmitOutcome.confirmed,
          'pkg#B': EmitOutcome.failed,
        },
      );
      expect(report.countOf(CoverageBucket.inlinableComposition), 1);
      expect(report.countOf(CoverageBucket.classifierOnly), 1);
      expect(report.countOf(CoverageBucket.inlinableThemeAsData), 0);
      // The headline rollup counts only emit-confirmed inlinables.
      expect(report.inlinableTotal, 1);
      expect(report.total, 2);
    });

    test('widgets in each bucket are accessible by their keys', () {
      final report = CoverageReport.from({
        'pkg/a.dart#A': ComposableWidget(
          'pkg/a.dart#A',
          requiredMechanisms: const {},
          composedCustomWidgets: const [],
        ),
        'pkg/b.dart#B': ComposableWidget(
          'pkg/b.dart#B',
          requiredMechanisms: const {},
          composedCustomWidgets: const [],
        ),
      });
      expect(
        report.widgetsIn(CoverageBucket.inlinableComposition),
        unorderedEquals(<String>['pkg/a.dart#A', 'pkg/b.dart#B']),
      );
      expect(report.widgetsIn(CoverageBucket.structural), isEmpty);
    });
  });

  group('CoverageReport snapshot serialisation', () {
    test(
        'toSnapshotJson maps each bucket to its sorted widget-key list — a '
        'balanced bucket swap (count unchanged) shows up in the keys so the '
        'snapshot rail catches it', () {
      final report = CoverageReport.from({
        'pkg/lib.dart#Card': ComposableWidget(
          'pkg/lib.dart#Card',
          requiredMechanisms: const {},
          composedCustomWidgets: const [],
        ),
        'pkg/lib.dart#Pad': ComposableWidget(
          'pkg/lib.dart#Pad',
          requiredMechanisms: const {InliningMechanism.constantFolding},
          composedCustomWidgets: const [],
        ),
      });
      expect(report.toSnapshotJson(), {
        'inlinable/composition-only': ['pkg/lib.dart#Card'],
        'inlinable/+const-fold': ['pkg/lib.dart#Pad'],
        'inlinable/+theme-as-data': <String>[],
        'inlinable/+declarative-state': <String>[],
        'classifier-only/emit-failed': <String>[],
        'deferred': <String>[],
        'structural': <String>[],
      });
    });
  });
}
