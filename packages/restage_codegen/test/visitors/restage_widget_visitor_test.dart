import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/codegen_builder.dart';
import 'package:restage_codegen/src/library_visitor.dart';
import 'package:restage_codegen/src/visitors/restage_widget_visitor.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('RestageWidgetVisitor (LibraryVisitor wrapper)', () {
    // Positive-path coverage of `visitRestageWidgets` lives in
    // widget_visitor_test.dart, which uses a workspace-aware test runner so
    // `@RestageWidget` annotations const-evaluate. The wrapper here is a
    // three-line pass-through; this smoke test verifies the wiring (the
    // visitor runs as part of the builder's pipeline and leaves
    // `state.widgetEntries` empty when no annotated classes are present).
    test('leaves state.widgetEntries empty when no @RestageWidget classes',
        () async {
      final after = _StateCaptureVisitor();

      await testBuilder(
        RestageCodegenBuilder(
          BuilderOptions.empty,
          visitors: [const RestageWidgetVisitor(), after],
        ),
        {
          'pkg|lib/paywalls/plain.dart': '''
            class Plain { const Plain(); }
          ''',
        },
        rootPackage: 'pkg',
        outputs: const {},
      );

      expect(after.observed, isEmpty);
    });
  });
}

/// Reads `state.widgetEntries` after the previous visitors ran. Lets tests
/// assert on the wrapper's contribution without relying on the builder's
/// post-pass throw behaviour.
final class _StateCaptureVisitor implements LibraryVisitor {
  final List<WidgetEntry> observed = [];

  @override
  Future<void> visit(CodegenBuildState state) async {
    observed.addAll(state.widgetEntries);
  }
}
