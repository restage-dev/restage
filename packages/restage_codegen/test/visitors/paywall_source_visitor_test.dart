import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/codegen_builder.dart';
import 'package:restage_codegen/src/library_visitor.dart';
import 'package:restage_codegen/src/source_visitor.dart';
import 'package:restage_codegen/src/visitors/paywall_source_visitor.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('PaywallSourceVisitor (LibraryVisitor wrapper)', () {
    test('populates state.paywallSources for well-formed @PaywallSource',
        () async {
      final after = _StateCaptureVisitor();

      await testBuilder(
        RestageCodegenBuilder(
          BuilderOptions.empty,
          visitors: [const PaywallSourceVisitor(), after],
        ),
        {
          'pkg|lib/paywalls/hello.dart': '''
            $kStubAnnotationsAndBases

            @PaywallSource(id: 'hello', slot: 'primary')
            class HelloPaywall extends StatelessWidget {
              const HelloPaywall();
              Widget build(BuildContext context) => 1;
            }
          ''',
        },
        rootPackage: 'pkg',
        outputs: const {},
      );

      expect(after.observed, hasLength(1));
      final found = after.observed.single;
      expect(found.id, 'hello');
      expect(found.slot, 'primary');
      expect(found.className, 'HelloPaywall');
      expect(found.rootExpression, isNotNull);
    });

    test('leaves state.paywallSources empty when no @PaywallSource classes',
        () async {
      final after = _StateCaptureVisitor();

      await testBuilder(
        RestageCodegenBuilder(
          BuilderOptions.empty,
          visitors: [const PaywallSourceVisitor(), after],
        ),
        {
          'pkg|lib/paywalls/plain.dart': '''
            $kStubAnnotationsAndBases

            class Plain extends StatelessWidget {
              const Plain();
              Widget build(BuildContext context) => 1;
            }
          ''',
        },
        rootPackage: 'pkg',
        outputs: const {},
      );

      expect(after.observed, isEmpty);
    });
  });
}

/// Reads `state.paywallSources` after the previous visitors ran. Lets
/// tests assert on the wrapper's contribution without relying on the
/// builder's post-pass throw behaviour.
final class _StateCaptureVisitor implements LibraryVisitor {
  final List<PaywallSourceFound> observed = [];

  @override
  Future<void> visit(CodegenBuildState state) async {
    observed.addAll(state.paywallSources);
  }
}
