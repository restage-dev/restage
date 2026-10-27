import 'package:restage_codegen/src/closed_callback_lowering.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_shared/restage_shared.dart';

/// Lowers finite widget lists into ordered, lazy builder results.
final class WidgetCollectionLowering {
  WidgetCollectionLowering({
    required this.expressions,
    required this.resultFor,
    this.resolve,
    this.withResolvedSpread,
  });

  final BuilderExpressionLowering expressions;
  final BuilderResult Function(Expression) resultFor;
  final Expression Function(Expression)? resolve;
  final BuilderResult Function(Expression, BuilderResult Function(Expression))?
      withResolvedSpread;
  int _iteration = 0;
  final Set<Expression> _spreads = {};

  /// Resolves a collection's aliases and helpers before lowering its elements.
  BuilderResult lowerSource(Expression source) => _spread(source, false);

  BuilderResult lower(ListLiteral literal) => BuilderResult.sequence([
        for (final element in literal.elements) _element(element),
      ]);

  BuilderResult _element(CollectionElement element) {
    if (element is Expression) return resultFor(element);
    if (element is IfElement) {
      if (element.caseClause != null) {
        throw BuilderLoweringException(
            element, 'Collection patterns are unsupported');
      }
      return BuilderResult.branch(
        expressions.lower(element.expression),
        _element(element.thenElement),
        element.elseElement == null
            ? const BuilderResult.sequence([])
            : _element(element.elseElement!),
      );
    }
    if (element is SpreadElement) {
      return _spread(element.expression, element.isNullAware);
    }
    if (element is ForElement) return _for(element);
    throw BuilderLoweringException(
        element, 'Unsupported widget collection element');
  }

  BuilderResult _spread(Expression source, bool nullAware) {
    if (!_spreads.add(source)) {
      throw BuilderLoweringException(source, 'Recursive widget list spread');
    }
    try {
      BuilderResult lower(Expression resolved) => identical(resolved, source)
          ? _resolvedSpread(source, nullAware)
          : _spread(resolved, nullAware);
      return withResolvedSpread?.call(source, lower) ??
          lower(resolve?.call(source) ?? source);
    } finally {
      _spreads.remove(source);
    }
  }

  BuilderResult _resolvedSpread(Expression source, bool nullAware) {
    if (source is ParenthesizedExpression) {
      return _spread(source.expression, nullAware);
    }
    if (source is NullLiteral && nullAware) {
      return const BuilderResult.sequence([]);
    }
    if (source is ListLiteral) return lower(source);
    final mapped = _mapped(source);
    if (mapped != null) return mapped;
    if (source is ConditionalExpression) {
      return BuilderResult.branch(
        expressions.lower(source.condition),
        _spread(source.thenExpression, nullAware),
        _spread(source.elseExpression, nullAware),
      );
    }
    throw BuilderLoweringException(
        source, 'Widget spreads require an analyzable list expression');
  }

  BuilderResult? _mapped(Expression expression) {
    final eager = <int>[];
    var source = expression;
    if (source is MethodInvocation &&
        source.methodName.name == 'toList' &&
        source.methodName.element?.library?.identifier == 'dart:core') {
      for (final argument in source.argumentList.arguments) {
        if (argument is! NamedArgument || argument.name.lexeme != 'growable')
          throw BuilderLoweringException(
              argument, 'Unsupported widget materialization argument');
        eager.add(expressions.lower(argument.argumentExpression));
      }
      source = source.target!;
    }
    if (source is! MethodInvocation ||
        source.methodName.name != 'map' ||
        source.methodName.element?.library?.identifier != 'dart:core' ||
        source.target == null ||
        source.argumentList.arguments.length != 1) return null;
    final callback = source.argumentList.arguments.single.argumentExpression;
    final resolved = callback is FunctionExpression
        ? (
            body: callback.body,
            parameters: callback.parameters!.parameters
                .map((p) => p.declaredFragment!.element)
                .toList()
          )
        : pureBuilderCallbackFor(
            callback, callback is SimpleIdentifier ? callback.element : null);
    if (resolved == null || resolved.parameters.length != 1)
      throw BuilderLoweringException(
          callback, 'Widget map requires a resolved callback');
    final receiver = expressions.lower(source.target!);
    final type = expressions.nodes[receiver].type;
    if (!{'list', 'iterable'}.contains(type.kind) || type.nullable)
      throw BuilderLoweringException(
          source, 'Widget map requires a finite native sequence');
    String parameter;
    do {
      parameter = 'collection${_iteration++}';
    } while (expressions.parameters.containsKey(parameter));
    final closed = ClosedCallbackLowering<BuilderResult>(expressions,
        result: resultFor,
        sequence: BuilderResult.let,
        branch: BuilderResult.branch);
    var result = closed.scoped(() {
      expressions.parameter(resolved.parameters.single, parameter, type.item!);
      return BuilderResult.forEachItem(
          receiver, parameter, closed.body(resolved.body));
    });
    for (final node in eager.reversed) result = BuilderResult.let(node, result);
    return BuilderResult.let(receiver, result);
  }

  BuilderResult _for(ForElement element) {
    final parts = element.forLoopParts;
    if (element.awaitKeyword != null || parts is! ForEachPartsWithDeclaration) {
      throw BuilderLoweringException(
          element, 'Widget collection loops require a synchronous for-in');
    }
    final variable = parts.loopVariable.declaredFragment?.element;
    if (variable == null) {
      throw BuilderLoweringException(
          parts.loopVariable, 'Unresolved collection loop variable');
    }
    final source = expressions.lower(parts.iterable);
    final type = expressions.nodes[source].type;
    if (!{'list', 'iterable'}.contains(type.kind) || type.nullable) {
      throw BuilderLoweringException(
          parts.iterable, 'Widget collection iteration requires a finite List');
    }
    String parameter;
    do {
      parameter = 'collection${_iteration++}';
    } while (expressions.parameters.containsKey(parameter));
    if (type.kind == 'iterable') {
      final saved = Map.of(expressions.bindings);
      expressions.parameter(variable, parameter, type.item!);
      try {
        return BuilderResult.let(
            source,
            BuilderResult.forEachItem(
                source, parameter, _element(element.body)));
      } finally {
        expressions.bindings
          ..clear()
          ..addAll(saved);
      }
    }
    expressions.parameters[parameter] = ValueType.integer;
    final index = expressions
        .add(ValueNode('parameter', ValueType.integer, name: parameter));
    final item = expressions
        .add(ValueNode('index', type.item!, inputs: [source, index]));
    final saved = Map.of(expressions.bindings);
    expressions.bindings[variable] = item;
    try {
      final body = _element(element.body);
      final length = expressions
          .add(ValueNode('length', ValueType.integer, inputs: [source]));
      return BuilderResult.let(
        source,
        BuilderResult.forEach(length, parameter, BuilderResult.let(item, body)),
      );
    } finally {
      expressions.bindings
        ..clear()
        ..addAll(saved);
    }
  }
}
