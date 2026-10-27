import 'dart:convert';
import 'package:restage_codegen/src/closed_callback_lowering.dart';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/device_recognition.dart';
import 'package:restage_codegen/src/theme_recognition.dart';
import 'package:restage_shared/restage_shared.dart';

/// Lowers pure native scalar callbacks through the shared value evaluator.
final class ScalarCallbackLowering {
  ScalarCallbackLowering(
      {required this.capture,
      required this.contract,
      this.resolve,
      this.helperFor,
      this.operations = const {
        ...kCollectionValueOperations,
        ...kGridValueOperations,
        ...kIntlValueOperations
      },
      this.valueExtension,
      this.parent});
  final String Function(Expression) capture;
  final Expression Function(Expression)? resolve;
  final ScalarCallbackContract contract;
  final BuilderExpressionLowering? parent;
  final HelperDef? Function(MethodInvocation)? helperFor;
  final Map<String, ValueOperation> operations;
  final int? Function(Expression, BuilderExpressionLowering)? valueExtension;
  late final BuilderExpressionLowering expressions = BuilderExpressionLowering(
      parent: parent,
      capture: capture,
      operations: operations,
      extension: _extension);

  String lower(FunctionExpression callback) {
    final parameters = callback.parameters?.parameters;
    if (parameters == null ||
        parameters.any((p) => p.declaredFragment == null)) {
      throw BuilderLoweringException(
          callback, 'Unresolved scalar callback parameters');
    }
    return lowerBody(callback.body,
        parameters.map((p) => p.declaredFragment!.element).toList());
  }

  /// Lowers a resolved native callback body with its exact parameter elements.
  String lowerBody(FunctionBody body, List<FormalParameterElement> parameters) {
    if (body.isAsynchronous || body.isGenerator) {
      throw BuilderLoweringException(
          body, 'A pure callback must be synchronous');
    }
    _bind(parameters, body);
    return _encode(_body(body, expressions), body);
  }

  /// Lowers a same-unit callback helper through the shared lexical bindings.
  String lowerDefinition(HelperDef helper) {
    _bind(helper.params, helper.functionBody ?? helper.body,
        locals: helper.localBindings.values);
    final eager = <int>[];
    for (final local in helper.localBindings.entries) {
      final node = expressions.lower(local.value);
      expressions.localInitializers[local.key] = local.value;
      eager.add(expressions.bindValue(local.key, node, local.value));
    }
    var root = helper.functionBody == null
        ? expressions.lower(helper.body)
        : _body(helper.functionBody!, expressions);
    for (final node in eager.reversed) {
      root = expressions.add(
          ValueNode('let', expressions.nodes[root].type, inputs: [node, root]));
    }
    return _encode(root, helper.body);
  }

  void _bind(List<FormalParameterElement> parameters, AstNode body,
      {Iterable<Expression> locals = const []}) {
    if (parameters.length != contract.parameters.length) {
      throw BuilderLoweringException(body, 'Scalar callback signature differs');
    }
    for (var i = 0; i < parameters.length; i++) {
      final element = parameters[i];
      switch (contract.parameters[i]) {
        case ScalarCallbackParameter.itemIndex:
          expressions.parameter(
              element, callbackParameterName(i), ValueType.integer);
        case ScalarCallbackParameter.widget:
          break;
        case ScalarCallbackParameter.valueKey:
          final probe = _KeyValueTypes(helperFor);
          body.accept(probe);
          for (final local in locals) {
            local.accept(probe);
          }
          if (probe.types.isNotEmpty) {
            expressions.parameter(element, callbackParameterName(i),
                ValueType('record', fields: probe.types));
          }
      }
    }
  }

  String _encode(int root, AstNode body) {
    final expected = ValueType('int', nullable: contract.nullableResult);
    if (!expected.accepts(expressions.nodes[root].type)) {
      throw BuilderLoweringException(
          body, 'Scalar callback must return int or null');
    }
    final program = expressions.program(root);
    program.validate(
        operations: operations, context: expressions.lexicalContext);
    validateScalarCallbackProgramContract(program, contract);
    return '__RestageBuilderContinuation(version:1,program:${jsonEncode(program.encode())},captures:{${expressions.captureDsl.entries.map((e) => '${e.key}:${e.value}').join(',')}})';
  }

  int? _extension(Expression expression, BuilderExpressionLowering lowering) {
    final extended = valueExtension?.call(expression, lowering);
    if (extended != null) return extended;
    if (expression is SimpleIdentifier &&
        !lowering.bindings.containsKey(expression.element)) {
      final bound = resolve?.call(expression);
      if (bound != null && !identical(bound, expression))
        return lowering.lower(bound);
    }
    if (expression is AsExpression) {
      final projection = _keyProjection(expression.staticType, expression);
      if (projection != null) {
        final key = lowering.lower(expression.expression);
        final shape = lowering.nodes[key].type;
        if (shape.fields[projection.$1] == null) {
          throw BuilderLoweringException(
              expression, 'Key cast has no native scalar projection');
        }
        final value = lowering.add(ValueNode('field', projection.$2,
            inputs: [key], name: projection.$1));
        return lowering.add(ValueNode('let', shape, inputs: [value, key]));
      }
    }
    final (target, member) = switch (expression) {
      PropertyAccess() => (expression.target, expression.propertyName),
      PrefixedIdentifier() => (expression.prefix, expression.identifier),
      _ => (null, null),
    };
    if (target != null && member?.name == 'value') {
      final projection = _keyProjection(target.staticType, expression);
      if (projection != null) {
        final key = lowering.lower(target);
        if (lowering.nodes[key].type.fields[projection.$1] == null) {
          throw BuilderLoweringException(
              expression, 'Key value has no native scalar projection');
        }
        return lowering.add(ValueNode('field', projection.$2,
            inputs: [key], name: projection.$1));
      }
    }
    if (expression is MethodInvocation &&
        expression.methodName.name == 'indexWhere' &&
        expression.methodName.element?.library?.identifier == 'dart:core' &&
        expression.target != null &&
        expression.argumentList.arguments.length == 1) {
      final callback =
          expression.argumentList.arguments.single.argumentExpression;
      if (callback is! FunctionExpression ||
          callback.parameters?.parameters.length != 1) {
        throw BuilderLoweringException(
            expression, 'Index predicate requires a pure closure');
      }
      final list = lowering.lower(expression.target!);
      final listType = lowering.nodes[list].type;
      if (listType.kind != 'list' || listType.nullable) {
        throw BuilderLoweringException(
            expression, 'Index predicate requires a list');
      }
      final parameter =
          callback.parameters!.parameters.single.declaredFragment?.element;
      if (parameter == null) {
        throw BuilderLoweringException(
            callback, 'Unresolved predicate parameter');
      }
      final outer = <int>[];
      late final BuilderExpressionLowering predicate;
      predicate = BuilderExpressionLowering(
          lexicalParent: lowering,
          capture: (_) =>
              throw StateError('Predicate capture escaped its bindings'),
          operations: operations,
          extension: (value, nested) {
            if (deviceRead(value) != null || themeReadSegments(value) != null) {
              final node = lowering.lower(value);
              final index = outer.indexOf(node);
              final slot = index < 0 ? outer.length : index;
              if (index < 0) outer.add(node);
              final name = 'outer$slot';
              final type = lowering.nodes[node].type;
              nested.parameters[name] = type;
              return nested.add(ValueNode('parameter', type, name: name));
            }
            if (value is SimpleIdentifier &&
                !nested.bindings.containsKey(value.element) &&
                (value.element is VariableElement ||
                    value.element is GetterElement)) {
              final node = lowering.lower(value);
              final index = outer.indexOf(node);
              final slot = index < 0 ? outer.length : index;
              if (index < 0) outer.add(node);
              return nested.parameter(
                  value.element!, 'outer$slot', lowering.nodes[node].type);
            }
            return _extension(value, nested);
          });
      predicate.parameter(parameter, 'item', listType.item!);
      final root = _body(callback.body, predicate);
      final program = predicate.program(root);
      program.validate(
          operations: operations,
          context: ValueOperationContext(
              operations: operations,
              locals: {...lowering.outerLocals, ...lowering.locals}));
      return lowering.add(ValueNode('grid.indexWhere', ValueType.integer,
          inputs: [list, ...outer], value: program.encode()));
    }
    if (expression is MethodInvocation) {
      final helper = helperFor?.call(expression);
      if (helper != null) return lowering.lowerHelper(helper, expression);
    }
    return null;
  }

  int _body(FunctionBody body, BuilderExpressionLowering lowering) =>
      closedValueCallback(lowering).body(body);
}

(String, ValueType)? _keyProjection(DartType? target, AstNode node) {
  if (target is! InterfaceType ||
      target.element.name != 'ValueKey' ||
      target.element.library.identifier !=
          'package:flutter/src/foundation/key.dart' ||
      target.typeArguments.length != 1) return null;
  final type = valueTypeFor(target.typeArguments.single, node);
  if (!const {'String', 'int', 'double', 'num', 'bool'}.contains(type.kind)) {
    throw BuilderLoweringException(node, 'Key cast requires a scalar generic');
  }
  return ('${type.kind}${type.nullable ? '?' : ''}', type);
}

final class _KeyValueTypes extends RecursiveAstVisitor<void> {
  _KeyValueTypes(this.helperFor);
  final HelperDef? Function(MethodInvocation)? helperFor;
  final Set<Expression> _visitedHelpers = {};
  final Set<Expression> _activeHelpers = {};
  final types = <String, ValueType>{};
  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    final helper = helperFor?.call(node);
    if (helper == null) return;
    if (_activeHelpers.contains(helper.body)) {
      throw BuilderLoweringException(
          node, 'Recursive pure helper is unsupported');
    }
    if (!_visitedHelpers.add(helper.body)) return;
    _activeHelpers.add(helper.body);
    try {
      for (final local in helper.localBindings.values) {
        local.accept(this);
      }
      (helper.functionBody ?? helper.body).accept(this);
    } finally {
      _activeHelpers.remove(helper.body);
    }
  }

  @override
  void visitAsExpression(AsExpression node) {
    final projection = _keyProjection(node.staticType, node);
    if (projection != null) types[projection.$1] = projection.$2;
    super.visitAsExpression(node);
  }
}
