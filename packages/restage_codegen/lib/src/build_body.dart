import 'package:analyzer/dart/ast/ast.dart';

/// The single expression a `build()`-style method [body] returns, or `null`
/// when [body] is not a single returned expression — it has non-const locals,
/// multiple statements, control flow, or a value-less `return;`.
///
/// This is the body-shape rule both the paywall `@PaywallSource` visitor and
/// the custom-widget classifier enforce: a transpilable `build()` reduces to
/// exactly one returned widget expression.
///
/// Leading `const` local declarations are permitted before the single return:
/// a `const` local is inert compile-time data, and a reference to it folds to
/// its literal value at the translation site, so the body still reduces to one
/// returned widget. A `final` / `var` local is NOT const-foldable and still
/// disqualifies the body (that shape needs state authoring, not a const fold).
Expression? singleReturnExpressionOf(FunctionBody body) {
  // Shares the body-shape walk with [extractInlinableBuildBody]; the stricter
  // contract here is that a leading `final` local still disqualifies the body
  // (only `const` locals, which fold to literals, are permitted before the
  // single return). So accept the extracted return expression only when no
  // `final` local was captured.
  final extracted = extractInlinableBuildBody(body);
  if (extracted == null || extracted.finalLocals.isNotEmpty) return null;
  return extracted.expression;
}

/// The single returned [expression] of a custom-widget `build()`, plus the
/// leading `final` local declarations ([finalLocals]) the classifier inlines
/// at their use sites.
class InlinableBuildBody {
  /// Creates an extracted build body.
  const InlinableBuildBody({
    required this.expression,
    required this.finalLocals,
  });

  /// The single returned expression.
  final Expression expression;

  /// Leading `final` local declarations to inline (each has an initializer).
  /// `const` locals are NOT listed — a reference to one folds to its literal
  /// value at the use site, so it needs no inlining.
  final List<VariableDeclaration> finalLocals;
}

/// Like [singleReturnExpressionOf], but for the custom-widget classifier: it
/// also permits leading `final` local declarations (each returned in
/// [InlinableBuildBody.finalLocals] for the caller to inline), in addition to
/// the `const` locals [singleReturnExpressionOf] already allows. A `var`
/// (reassignable) local, a declaration without an initializer, a non-empty
/// `return;`, or any non-declaration statement before the return disqualifies
/// the body — returning `null`, the honest "not a single returned expression"
/// shape. This is custom-widget-only; the `@PaywallSource` path keeps the
/// stricter [singleReturnExpressionOf].
InlinableBuildBody? extractInlinableBuildBody(FunctionBody body) {
  if (body is ExpressionFunctionBody) {
    return InlinableBuildBody(
      expression: body.expression,
      finalLocals: const [],
    );
  }
  if (body is! BlockFunctionBody) return null;
  final statements = body.block.statements;
  if (statements.isEmpty) return null;
  final last = statements.last;
  if (last is! ReturnStatement) return null;
  final returnExpr = last.expression;
  if (returnExpr == null) return null;
  final finalLocals = <VariableDeclaration>[];
  for (final stmt in statements.take(statements.length - 1)) {
    if (stmt is! VariableDeclarationStatement) return null;
    final keyword = stmt.variables.keyword?.lexeme;
    if (keyword != 'const' && keyword != 'final') return null;
    for (final variable in stmt.variables.variables) {
      if (variable.initializer == null) return null;
      if (keyword == 'final') finalLocals.add(variable);
    }
  }
  return InlinableBuildBody(expression: returnExpr, finalLocals: finalLocals);
}
