import 'package:meta/meta.dart';
import 'package:restage_codegen/src/library_visitor.dart';
import 'package:restage_codegen/src/source_visitor.dart';

/// [LibraryVisitor] that walks `@PaywallSource`-annotated classes via
/// the free [visitPaywallSources] helper. The walk stays a pure
/// function for direct unit testing; this adapter pipes its results
/// onto the shared [CodegenBuildState].
@internal
final class PaywallSourceVisitor implements LibraryVisitor {
  /// Const constructor.
  const PaywallSourceVisitor();

  @override
  Future<void> visit(CodegenBuildState state) async {
    final result = await visitPaywallSources(state.library, state.assetId);
    state.issues.addAll(result.issues);
    state.paywallSources.addAll(result.sources);
  }
}
