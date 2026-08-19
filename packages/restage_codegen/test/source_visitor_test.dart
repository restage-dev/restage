import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/source_visitor.dart';
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

    test('recognizes resolved canonical @Paywall and derives the file id',
        () async {
      final result = await _runCanonicalVisitorOn({
        'lib/feature_notice.dart': '''
          import 'package:flutter/widgets.dart';
          import 'package:restage/restage.dart';

          @Paywall()
          class FeatureNotice extends StatelessWidget {
            const FeatureNotice({super.key});

            @override
            Widget build(BuildContext context) => const SizedBox();
          }
        ''',
      });

      expect(result.issues, isEmpty);
      final source = result.sources.single;
      expect(source.id, 'feature_notice');
      expect(source.isCanonical, isTrue);
      expect(source.hasExplicitId, isFalse);
      expect(source.slot, isNull);
    });

    test('canonical explicit id is authoritative when it differs from file',
        () async {
      final result = await _runCanonicalVisitorOn({
        'lib/moved_paywall.dart': '''
          import 'package:flutter/widgets.dart';
          import 'package:restage/restage.dart';

          @Paywall(id: 'stable_paywall')
          class MovedPaywall extends StatelessWidget {
            const MovedPaywall({super.key});

            @override
            Widget build(BuildContext context) => const SizedBox();
          }
        ''',
      });

      expect(result.issues, isEmpty);
      expect(result.sources.single.id, 'stable_paywall');
      expect(result.sources.single.isCanonical, isTrue);
      expect(result.sources.single.hasExplicitId, isTrue);
    });

    test('two canonical implicit ids fail as ambiguous declarations', () async {
      final result = await _runCanonicalVisitorOn({
        'lib/ambiguous.dart': '''
          import 'package:flutter/widgets.dart';
          import 'package:restage/restage.dart';

          @Paywall()
          class FirstPaywall extends StatelessWidget {
            const FirstPaywall({super.key});

            @override
            Widget build(BuildContext context) => const SizedBox();
          }

          @Paywall()
          class SecondPaywall extends StatelessWidget {
            const SecondPaywall({super.key});

            @override
            Widget build(BuildContext context) => const SizedBox();
          }
        ''',
      });

      expect(
        result.issues.map((issue) => issue.code),
        contains(IssueCode.duplicateId),
      );
    });

    test('resolved lookalike @Paywall annotations are ignored', () async {
      final result = await runVisitorOn({
        'lib/lookalike.dart': '''
          class Paywall {
            const Paywall();
          }

          class StatelessWidget {
            const StatelessWidget();
          }

          class Widget {}
          class BuildContext {}

          @Paywall()
          class Lookalike extends StatelessWidget {
            const Lookalike();
            Widget build(BuildContext context) => 1;
          }
        ''',
      });

      expect(result.issues, isEmpty);
      expect(result.sources, isEmpty);
    });
  });
}

/// The workspace package config used by build_test points at the checked-out
/// package sources, while this phase may be testing a worktree whose SDK
/// annotation files have not been merged into that checkout yet. Replace only
/// the imported annotation source so the test still exercises analyzer
/// provenance rather than a local lookalike.
Future<VisitorResult> _runCanonicalVisitorOn(
  Map<String, String> sources,
) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
    includeFlutter: true,
  );
  readerWriter.testing.writeString(
    AssetId('restage', 'lib/src/authoring/paywall_source.dart'),
    '''
import 'package:meta/meta.dart';

@immutable
final class Paywall {
  const Paywall({this.id});
  final String? id;
}
''',
  );
  final assetMap = <String, String>{
    for (final entry in sources.entries)
      'apps_examples|${entry.key}': entry.value,
  };
  for (final entry in assetMap.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }

  VisitorResult? result;
  await testBuilder(
    _VisitorProbeBuilder((library, assetId) async {
      result = await visitPaywallSources(library, assetId);
    }),
    assetMap,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
  );
  return result!;
}

final class _VisitorProbeBuilder implements Builder {
  _VisitorProbeBuilder(this.onLibrary);

  final Future<void> Function(LibraryElement library, AssetId assetId)
      onLibrary;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.paywall_probe'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    await onLibrary(await buildStep.inputLibrary, buildStep.inputId);
  }
}
