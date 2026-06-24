import 'package:meta/meta.dart';
import 'package:restage_codegen/src/library_visitor.dart';
import 'package:restage_codegen/src/widget_visitor.dart';

/// [LibraryVisitor] that walks `@RestageWidget`-annotated customer classes.
///
/// Thin adapter around the free [visitRestageWidgets] function — the AST
/// walk lives there as a pure helper so it can be unit-tested independently
/// of the build pipeline; this class wires it into the codegen builder's
/// shared state.
@internal
final class RestageWidgetVisitor implements LibraryVisitor {
  /// Const constructor.
  const RestageWidgetVisitor();

  @override
  Future<void> visit(CodegenBuildState state) async {
    final result = visitRestageWidgets(state.library, state.assetId);
    state.issues.addAll(result.issues);
    state.widgetEntries.addAll(result.widgets);
  }
}
