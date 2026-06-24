import 'package:analyzer/dart/ast/ast.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/const_folding.dart';

/// Result of recognising a State method as a candidate single-assignment
/// `setState` event handler. The translator gates `set state.<field> = …`
/// emission on this verdict — a literal-RHS assignment becomes a
/// [SetStateLiteral], a same-field bool flip becomes a [SetStateBoolFlip],
/// and anything outside the recognised shape is a [SetStateUnrecognised]
/// the translator surfaces as a `stateShapeUnsupported` diagnostic.
@immutable
sealed class RecognisedSetState {
  const RecognisedSetState();
}

/// A `setState(() => <field> = <literal>)` (or block-statement equivalent)
/// where the right-hand side folds to a [bool], [int], [double], [String],
/// or the bare name of an enum constant.
@immutable
final class SetStateLiteral extends RecognisedSetState {
  /// Creates a recognised literal-RHS assignment.
  const SetStateLiteral({required this.fieldName, required this.value});

  /// The State field being assigned — matches one of the
  /// classifier-captured field names.
  final String fieldName;

  /// The folded right-hand side: a [bool], [int], [double], [String], or the
  /// bare name of an enum constant (carried as a [String]).
  final Object value;
}

/// A `setState(() => <field> = !<field>)` (or `!this.<field>`, with an
/// optional explicit `this` on the left, too) — a bool flip of the same
/// field. The translator emits this as the no-negation
/// `switch state.<field> { true: false, false: true }` shape RFW data
/// accepts (RFW has no `!` operator on a state read).
@immutable
final class SetStateBoolFlip extends RecognisedSetState {
  /// Creates a recognised bool-flip assignment.
  const SetStateBoolFlip({required this.fieldName});

  /// The State field being flipped — matches one of the classifier-captured
  /// field names and is the same field on both sides of the assignment.
  final String fieldName;
}

/// A State method whose body is not a recognised single-assignment
/// `setState`. Carries an author-facing [reason] the translator quotes in
/// its `stateShapeUnsupported` diagnostic.
@immutable
final class SetStateUnrecognised extends RecognisedSetState {
  /// Creates an unrecognised result. [reason] is rendered into the
  /// translator's diagnostic, so it should be a clear noun phrase the
  /// author can act on.
  const SetStateUnrecognised({required this.reason});

  /// The specific subcase, for the diagnostic message — e.g.
  /// `"the body is not a single setState(...) call"` or
  /// `"the assignment's right-hand side is not a literal or a same-field
  /// bool flip"`.
  final String reason;
}

/// Recognises the shape of [method] as a [SetStateLiteral] /
/// [SetStateBoolFlip] / [SetStateUnrecognised] verdict.
///
/// The method's body must reduce to a single `setState(() { … })` call
/// whose function body contains exactly one assignment to a State field
/// listed in [stateFieldNames]; the right-hand side must be a folded
/// scalar literal or a same-field bool flip (`!<field>` or `!this.<field>`).
/// Everything else yields a [SetStateUnrecognised] with an author-facing
/// reason — multi-statement bodies, non-setState calls, multi-assignment
/// setState, non-literal RHS, and so on.
///
/// Recognition is purely syntactic: it matches on the resolved AST shape
/// and the field-name set passed in, with no element resolution beyond what
/// `tryFoldConstant` already needs for an enum-constant or const-reference
/// right-hand side.
RecognisedSetState recogniseSetState(
  MethodDeclaration method, {
  required Set<String> stateFieldNames,
}) {
  if (stateFieldNames.isEmpty) {
    return const SetStateUnrecognised(
      reason: 'the State has no primitive fields that could be set',
    );
  }
  final body = method.body;
  final innerCall = _extractSingleCall(body);
  if (innerCall == null) {
    return const SetStateUnrecognised(
      reason: 'the method body is not a single setState(...) call',
    );
  }
  if (innerCall.methodName.name != 'setState' || innerCall.target != null) {
    return const SetStateUnrecognised(
      reason: 'the method body calls something other than setState(...)',
    );
  }
  final args = innerCall.argumentList.arguments;
  if (args.length != 1 || args.single is! FunctionExpression) {
    return const SetStateUnrecognised(
      reason: 'setState(...) is not called with a single closure argument',
    );
  }
  final closure = args.single as FunctionExpression;
  final assignment = _extractSingleAssignment(closure.body);
  if (assignment == null) {
    return const SetStateUnrecognised(
      reason: 'the setState closure does not contain a single assignment '
          'expression',
    );
  }
  final lhsField = _stateFieldName(assignment.leftHandSide, stateFieldNames);
  if (lhsField == null) {
    return const SetStateUnrecognised(
      reason: 'the assignment does not target a recognised State field',
    );
  }
  if (assignment.operator.lexeme != '=') {
    return SetStateUnrecognised(
      reason: 'the assignment uses ${assignment.operator.lexeme} rather '
          'than `=` — only direct assignment of a literal or a same-field '
          'bool flip is recognised',
    );
  }
  final rhsBoolFlipField =
      _boolFlipField(assignment.rightHandSide, stateFieldNames);
  if (rhsBoolFlipField != null) {
    if (rhsBoolFlipField != lhsField) {
      return SetStateUnrecognised(
        reason: "the bool flip reads '$rhsBoolFlipField' but assigns to "
            "'$lhsField' — only a same-field flip is recognised",
      );
    }
    return SetStateBoolFlip(fieldName: lhsField);
  }
  final value = tryFoldConstant(assignment.rightHandSide) ??
      enumConstantName(assignment.rightHandSide);
  if (value != null) {
    return SetStateLiteral(fieldName: lhsField, value: value);
  }
  return const SetStateUnrecognised(
    reason: 'the assignment right-hand side is not a recognised literal or '
        'same-field bool flip — only constant scalars, enum values, and '
        '`!<field>` flips are emitted',
  );
}

/// Returns the [MethodInvocation] the method's body reduces to when it is a
/// single expression-bodied or block-with-one-expression-statement method,
/// or `null` for any richer shape.
MethodInvocation? _extractSingleCall(FunctionBody body) {
  if (body is ExpressionFunctionBody) {
    final expr = body.expression;
    if (expr is MethodInvocation) return expr;
    return null;
  }
  if (body is BlockFunctionBody) {
    final stmts = body.block.statements;
    if (stmts.length != 1) return null;
    final stmt = stmts.single;
    if (stmt is ExpressionStatement && stmt.expression is MethodInvocation) {
      return stmt.expression as MethodInvocation;
    }
    return null;
  }
  return null;
}

/// Returns the [AssignmentExpression] [body] reduces to when it is a single
/// expression-bodied or block-with-one-expression-statement closure body,
/// or `null` for any richer shape.
AssignmentExpression? _extractSingleAssignment(FunctionBody body) {
  if (body is ExpressionFunctionBody) {
    final expr = body.expression;
    if (expr is AssignmentExpression) return expr;
    return null;
  }
  if (body is BlockFunctionBody) {
    final stmts = body.block.statements;
    if (stmts.length != 1) return null;
    final stmt = stmts.single;
    if (stmt is ExpressionStatement &&
        stmt.expression is AssignmentExpression) {
      return stmt.expression as AssignmentExpression;
    }
    return null;
  }
  return null;
}

/// Returns the State-field name [expr] refers to, when it is either a bare
/// `<field>` identifier or a `this.<field>` property access naming one of
/// the declared State fields. Returns `null` otherwise.
String? _stateFieldName(Expression expr, Set<String> stateFieldNames) {
  if (expr is SimpleIdentifier && stateFieldNames.contains(expr.name)) {
    return expr.name;
  }
  if (expr is PropertyAccess &&
      expr.target is ThisExpression &&
      stateFieldNames.contains(expr.propertyName.name)) {
    return expr.propertyName.name;
  }
  return null;
}

/// Returns the field name from a `!<field>` or `!this.<field>` prefix
/// expression, when the operand names one of the declared State fields.
/// Returns `null` for any other expression.
String? _boolFlipField(Expression expr, Set<String> stateFieldNames) {
  if (expr is! PrefixExpression || expr.operator.lexeme != '!') return null;
  return _stateFieldName(expr.operand, stateFieldNames);
}
