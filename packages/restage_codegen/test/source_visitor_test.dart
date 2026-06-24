import 'package:restage_codegen/src/issue.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('visitPaywallSources', () {
    test('finds @PaywallSource classes and extracts build() expression',
        () async {
      final result = await runVisitorOn({
        'lib/foo.dart': '''
          $kStubAnnotationsAndBases

          @PaywallSource(id: 'foo')
          class FooPaywall extends StatelessWidget {
            const FooPaywall();
            Widget build(BuildContext context) => 42;
          }
        ''',
      });
      expect(result.issues, isEmpty);
      expect(result.sources, hasLength(1));
      expect(result.sources.first.id, 'foo');
      expect(result.sources.first.className, 'FooPaywall');
      expect(result.sources.first.rootExpression, isNotNull);
    });

    test('extracts root expression from single-return block body', () async {
      final result = await runVisitorOn({
        'lib/foo.dart': '''
          $kStubAnnotationsAndBases

          @PaywallSource(id: 'foo')
          class FooPaywall extends StatelessWidget {
            const FooPaywall();
            Widget build(BuildContext context) {
              return 1;
            }
          }
        ''',
      });
      expect(result.issues, isEmpty);
      expect(result.sources, hasLength(1));
      expect(result.sources.first.id, 'foo');
      expect(result.sources.first.rootExpression, isNotNull);
    });

    test('captures slot annotation field', () async {
      final result = await runVisitorOn({
        'lib/foo.dart': '''
          $kStubAnnotationsAndBases

          @PaywallSource(id: 'foo', slot: 'primary')
          class FooPaywall extends StatelessWidget {
            const FooPaywall();
            Widget build(BuildContext context) => 1;
          }
        ''',
      });
      expect(result.sources.single.slot, 'primary');
    });

    test('accepts supported StatefulWidget roots', () async {
      final result = await runVisitorOn({
        'lib/foo.dart': '''
          $kStubAnnotationsAndBases

          abstract class StatefulWidget extends Widget {
            const StatefulWidget();
          }

          abstract class State<T extends StatefulWidget> {
            late T widget;
            Widget build(BuildContext context);
            void setState(void Function() fn) {}
          }

          class Text extends Widget {
            const Text(this.text);
            final String text;
          }

          @PaywallSource(id: 'foo')
          class FooPaywall extends StatefulWidget {
            const FooPaywall();
            _FooPaywallState createState() => _FooPaywallState();
          }

          class _FooPaywallState extends State<FooPaywall> {
            bool annual = false;
            Widget build(BuildContext context) =>
                Text(annual ? 'Annual' : 'Monthly');
          }
        ''',
      });

      expect(result.issues, isEmpty);
      expect(result.sources, hasLength(1));
      final source = result.sources.single;
      expect(source.build.state!.single.name, 'annual');
    });

    test('emits unsupportedBaseClass for non-StatelessWidget base', () async {
      final result = await runVisitorOn({
        'lib/foo.dart': '''
          $kStubAnnotationsAndBases

          class OtherBase {}

          @PaywallSource(id: 'foo')
          class FooPaywall extends OtherBase {
            const FooPaywall();
            dynamic build(dynamic context) => null;
          }
        ''',
      });
      expect(result.sources, isEmpty);
      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.unsupportedBaseClass),
      );
    });

    test('emits buildMethodMissing when no build()', () async {
      final result = await runVisitorOn({
        'lib/foo.dart': '''
          $kStubAnnotationsAndBases

          @PaywallSource(id: 'foo')
          class FooPaywall extends StatelessWidget {
            const FooPaywall();
          }
        ''',
      });
      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.buildMethodMissing),
      );
    });

    test('emits buildMethodTooComplex on multi-statement body', () async {
      final result = await runVisitorOn({
        'lib/foo.dart': '''
          $kStubAnnotationsAndBases

          @PaywallSource(id: 'foo')
          class FooPaywall extends StatelessWidget {
            const FooPaywall();
            Widget build(BuildContext context) {
              final x = 1;
              return x;
            }
          }
        ''',
      });
      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.buildMethodTooComplex),
      );
    });

    test('extracts the root expression past leading const locals', () async {
      // A `const` local before the single return is inert compile-time data;
      // the body still reduces to one returned widget (its reference folds at
      // translation). `final` / `var` locals stay rejected (the test above).
      final result = await runVisitorOn({
        'lib/foo.dart': '''
          $kStubAnnotationsAndBases

          @PaywallSource(id: 'foo')
          class FooPaywall extends StatelessWidget {
            const FooPaywall();
            Widget build(BuildContext context) {
              const accent = 0xFF3366FF;
              return accent;
            }
          }
        ''',
      });
      expect(result.issues, isEmpty);
      expect(result.sources, hasLength(1));
      expect(result.sources.first.rootExpression, isNotNull);
    });

    test('emits duplicateId when two classes share the same id', () async {
      final result = await runVisitorOn({
        'lib/foo.dart': '''
          $kStubAnnotationsAndBases

          @PaywallSource(id: 'shared')
          class A extends StatelessWidget {
            const A();
            Widget build(BuildContext context) => 1;
          }

          @PaywallSource(id: 'shared')
          class B extends StatelessWidget {
            const B();
            Widget build(BuildContext context) => 2;
          }
        ''',
      });
      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.duplicateId),
      );
      // All occurrences of the duplicate id are removed from sources.
      expect(result.sources, isEmpty);
    });

    test('classes without @PaywallSource are ignored', () async {
      final result = await runVisitorOn({
        'lib/foo.dart': '''
          $kStubAnnotationsAndBases

          class NotAPaywall extends StatelessWidget {
            const NotAPaywall();
            Widget build(BuildContext context) => 1;
          }
        ''',
      });
      expect(result.sources, isEmpty);
      expect(result.issues, isEmpty);
    });

    test(
        'emits annotationEvaluationFailed when @PaywallSource has '
        'non-const argument', () async {
      // PaywallSource(id: MyIds.pro) — the getter is non-const so
      // computeConstantValue() returns null. The slow-path source-text check
      // still recognises the annotation as PaywallSource and the visitor
      // must emit annotationEvaluationFailed rather than silently skipping.
      final result = await runVisitorOn({
        'lib/foo.dart': '''
          $kStubAnnotationsAndBases

          class MyIds {
            static String get pro => 'pro_upgrade'; // non-const
          }

          @PaywallSource(id: MyIds.pro)
          class FooPaywall extends StatelessWidget {
            const FooPaywall();
            Widget build(BuildContext context) => 1;
          }
        ''',
      });
      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.annotationEvaluationFailed),
      );
      // The class must not appear as a successfully parsed source.
      expect(result.sources, isEmpty);
    });

    test('two distinct @PaywallSource classes in one file both extract',
        () async {
      // The resolved-library lookup is awaited inside the per-class
      // loop; this confirms the await-in-for chain extracts both
      // root expressions in source order rather than dropping or
      // re-ordering one if a future change parallelises the loop.
      final result = await runVisitorOn({
        'lib/foo.dart': '''
          $kStubAnnotationsAndBases

          @PaywallSource(id: 'first')
          class FirstPaywall extends StatelessWidget {
            const FirstPaywall();
            Widget build(BuildContext context) => 1;
          }

          @PaywallSource(id: 'second')
          class SecondPaywall extends StatelessWidget {
            const SecondPaywall();
            Widget build(BuildContext context) => 2;
          }
        ''',
      });
      expect(result.issues, isEmpty);
      expect(result.sources, hasLength(2));
      expect(result.sources[0].id, 'first');
      expect(result.sources[0].className, 'FirstPaywall');
      expect(result.sources[0].rootExpression, isNotNull);
      expect(result.sources[1].id, 'second');
      expect(result.sources[1].className, 'SecondPaywall');
      expect(result.sources[1].rootExpression, isNotNull);
    });
  });
}
