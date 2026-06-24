import 'package:restage_codegen/src/widget_classification.dart';
import 'package:test/test.dart';

void main() {
  group('ImperativeWidget', () {
    test('requires a non-empty blocker list', () {
      expect(
        () => ImperativeWidget('pkg#A', blockers: const []),
        throwsA(isA<AssertionError>()),
      );
    });

    test('exposes its blockers as an unmodifiable list', () {
      final w = ImperativeWidget(
        'pkg#A',
        blockers: [
          const Blocker(
            kind: BlockerKind.customPainter,
            location: 'pkg#A@1:1',
            detail: 'CustomPaint',
          ),
        ],
      );
      expect(w.blockers, hasLength(1));
      expect(() => w.blockers.add(w.blockers.first), throwsUnsupportedError);
    });
  });

  group('ComposableWidget', () {
    test('exposes its mechanism set and composed list as unmodifiable', () {
      final w = ComposableWidget(
        'pkg#A',
        requiredMechanisms: {InliningMechanism.themeAsData},
        composedCustomWidgets: ['pkg#B'],
      );
      expect(w.requiredMechanisms, {InliningMechanism.themeAsData});
      expect(w.composedCustomWidgets, ['pkg#B']);
      expect(
        () => w.requiredMechanisms.add(InliningMechanism.constantFolding),
        throwsUnsupportedError,
      );
      expect(
        () => w.composedCustomWidgets.add('pkg#C'),
        throwsUnsupportedError,
      );
    });
  });

  group('WidgetClassification', () {
    test('every variant carries the classKey through the base', () {
      const unclassifiable =
          UnclassifiableWidget('pkg#A', reason: 'build() body');
      final composable = ComposableWidget(
        'pkg#B',
        requiredMechanisms: const {},
        composedCustomWidgets: const [],
      );
      // A sealed hierarchy — exhaustive over the three variants.
      for (final c in <WidgetClassification>[unclassifiable, composable]) {
        expect(c.classKey, isNotEmpty);
      }
      expect(unclassifiable.reason, 'build() body');
    });
  });
}
