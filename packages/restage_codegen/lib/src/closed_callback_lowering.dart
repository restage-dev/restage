import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_shared/restage_shared.dart';

/// Shared lexical statement lowering for closed value and widget callbacks.
final class ClosedCallbackLowering<T> {
  ClosedCallbackLowering(
    this.expressions, {
    required this.result,
    required this.sequence,
    required this.branch,
    this.guardBranch,
  });
  final BuilderExpressionLowering expressions;
  final T Function(Expression) result;
  final T Function(int, T) sequence;
  final T Function(int, T, T) branch;
  final T Function(int, bool, T Function())? guardBranch;

  T body(FunctionBody body) {
    if (body.isAsynchronous || body.isGenerator) {
      throw BuilderLoweringException(
        body,
        'Closed callback must be synchronous',
      );
    }
    return switch (body) {
      ExpressionFunctionBody() => result(body.expression),
      BlockFunctionBody() => statements(body.block.statements.toList()),
      _ => throw BuilderLoweringException(body, 'Unsupported callback body'),
    };
  }

  T scoped(T Function() action) {
    final bindings = Map.of(expressions.bindings);
    final slots = Map.of(expressions.localSlots);
    final initializers = Map.of(expressions.localInitializers);
    final aliases = Map.of(expressions.contextAliases);
    try {
      return action();
    } finally {
      expressions.bindings
        ..clear()
        ..addAll(bindings);
      expressions.localSlots
        ..clear()
        ..addAll(slots);
      expressions.localInitializers
        ..clear()
        ..addAll(initializers);
      expressions.contextAliases
        ..clear()
        ..addAll(aliases);
    }
  }

  T statements(List<Statement> statements, [T Function()? done]) {
    if (statements.isEmpty) {
      if (done != null) return done();
      throw StateError('Closed callback must return a value');
    }
    final statement = statements.first;
    final rest = statements.skip(1).toList();
    T next() => this.statements(rest, done);
    if (statement is ReturnStatement && statement.expression != null)
      return result(statement.expression!);
    if (statement is VariableDeclarationStatement) {
      if (statement.variables.isLate)
        throw BuilderLoweringException(
          statement,
          'Late local initialization is unsupported',
        );
      final eager = <int>[];
      for (final variable in statement.variables.variables) {
        if (variable.initializer == null || variable.declaredFragment == null) {
          throw BuilderLoweringException(
            variable,
            'Local requires an initializer',
          );
        }
        if (expressions.bindContextAlias(
          variable.declaredFragment!.element,
          variable.initializer!,
        ))
          continue;
        eager.add(
          expressions.declareLocal(
            variable,
            mutable:
                !statement.variables.isFinal && !statement.variables.isConst,
          ),
        );
      }
      var value = next();
      for (final node in eager.reversed) {
        value = sequence(node, value);
      }
      return value;
    }
    if (statement is ExpressionStatement) {
      final value = expressions.lower(statement.expression);
      return sequence(value, next());
    }
    if (statement is Block) {
      return scoped(() => this.statements(statement.statements.toList(), next));
    }
    if (statement is IfStatement) {
      final condition = expressions.lower(statement.expression);
      List<Statement> items(Statement? value) => value == null
          ? []
          : value is Block
          ? value.statements.toList()
          : [value];
      final returns = _Returns();
      statement.accept(returns);
      if (!returns.found) {
        int effect(Statement? value) {
          final lower = closedValueCallback(expressions);
          return lower.scoped(
            () => lower.statements(
              items(value),
              () => expressions.add(
                const ValueNode('literal', ValueType.nullType),
              ),
            ),
          );
        }

        final yes = effect(statement.thenStatement);
        final no = effect(statement.elseStatement);
        final effectNode = expressions.add(
          ValueNode(
            'conditional',
            ValueType.nullType,
            inputs: [condition, yes, no],
          ),
        );
        return sequence(effectNode, next());
      }
      T arm(Statement? statement, bool selected) => scoped(() {
        T lower() => this.statements(items(statement), next);
        return guardBranch == null
            ? lower()
            : guardBranch!(condition, selected, lower);
      });
      final yes = arm(statement.thenStatement, true);
      final no = arm(statement.elseStatement, false);
      return branch(condition, yes, no);
    }
    throw BuilderLoweringException(
      statement,
      'Unsupported closed callback statement',
    );
  }
}

/// Builds scalar returns and sequencing with the existing value graph.
ClosedCallbackLowering<int> closedValueCallback(
  BuilderExpressionLowering expressions,
) => ClosedCallbackLowering(
  expressions,
  result: expressions.lower,
  sequence: (node, value) => expressions.add(
    ValueNode('let', expressions.nodes[value].type, inputs: [node, value]),
  ),
  branch: (condition, yes, no) {
    final a = expressions.nodes[yes].type;
    final b = expressions.nodes[no].type;
    final base = a.kind == 'Null' ? b : a;
    final type = ValueType(
      base.kind,
      nullable: a.nullable || b.nullable,
      item: base.item,
      fields: base.fields,
    );
    return expressions.add(
      ValueNode('conditional', type, inputs: [condition, yes, no]),
    );
  },
);

final class _Returns extends RecursiveAstVisitor<void> {
  bool found = false;
  @override
  void visitReturnStatement(ReturnStatement node) {
    found = true;
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {}
}
