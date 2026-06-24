import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/codegen_builder.dart';
import 'package:restage_codegen/src/library_visitor.dart';
import 'package:test/test.dart';

void main() {
  group('RestageCodegenBuilder visitor registration', () {
    test('dispatches to registered visitors in order', () async {
      final first = _RecordingVisitor();
      final second = _RecordingVisitor();

      final builder = RestageCodegenBuilder(
        BuilderOptions.empty,
        visitors: [first, second],
      );

      await testBuilder(
        builder,
        const {
          'pkg|lib/paywalls/hello.dart': '''
            class Hello {
              const Hello();
            }
          ''',
        },
        rootPackage: 'pkg',
        outputs: const {},
      );

      expect(first.invocations, 1);
      expect(second.invocations, 1);
      expect(
        first.observedAssets.single.toString(),
        'pkg|lib/paywalls/hello.dart',
      );
      expect(
        second.observedAssets.single.toString(),
        'pkg|lib/paywalls/hello.dart',
      );
    });

    test('runs with no visitors registered (no-op build)', () async {
      final builder = RestageCodegenBuilder(BuilderOptions.empty);

      await testBuilder(
        builder,
        const {
          'pkg|lib/paywalls/hello.dart': '''
            class Hello {
              const Hello();
            }
          ''',
        },
        rootPackage: 'pkg',
        outputs: const {},
      );
      // No assertion needed — if dispatch crashed on an empty visitor
      // list, testBuilder would surface the throw.
    });

    test('hand-authored .rfwtxt input bypasses the visitor pipeline', () async {
      // Sanity-check: visitors only ever see resolved Dart libraries.
      // The .rfwtxt parse-and-encode path runs before the resolver and
      // must not invoke any registered visitor.
      final recorder = _RecordingVisitor();

      final builder = RestageCodegenBuilder(
        BuilderOptions.empty,
        visitors: [recorder],
      );

      await testBuilder(
        builder,
        const {
          'pkg|lib/paywalls/raw.rfwtxt': '''
            import restage.core;
            widget X = SizedBox();
          ''',
        },
        rootPackage: 'pkg',
        // Output content varies with rfw_formats encoding; the assertion
        // here is just that no visitor ran for this input.
      );

      expect(recorder.invocations, 0);
    });
  });
}

final class _RecordingVisitor implements LibraryVisitor {
  int invocations = 0;
  final List<AssetId> observedAssets = [];

  @override
  Future<void> visit(CodegenBuildState state) async {
    invocations++;
    observedAssets.add(state.assetId);
  }
}
