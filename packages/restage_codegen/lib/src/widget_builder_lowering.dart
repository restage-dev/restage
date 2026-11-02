import 'dart:convert';
import 'package:restage_codegen/src/closed_callback_lowering.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_shared/restage_shared.dart';

/// Lowers an analyzed callback to typed values and RFW builder bodies.
final class WidgetBuilderLowering {
  WidgetBuilderLowering({
    required this.expressions,
    required this.contract,
    required this.scope,
    required this.translateBody,
    this.helperFor,
    this.resolve,
    this.withConditionalBranch,
    this.withHelperBody,
    this.nativeKey,
  });
  final BuilderExpressionLowering expressions;
  final WidgetBuilderContract contract;
  final String scope;
  final String Function(Expression) translateBody;
  final HelperDef? Function(MethodInvocation)? helperFor;
  final Expression Function(Expression)? resolve;
  final BuilderResult Function(
    ConditionalExpression,
    Expression,
    BuilderResult Function(),
  )?
  withConditionalBranch;
  final BuilderResult Function(
    HelperDef,
    MethodInvocation,
    BuilderResult Function(),
  )?
  withHelperBody;
  final String? Function(Expression)? nativeKey;
  final List<String> bodies = [];
  Map<String, int>? _outputs;

  /// Whether values are being projected from the returned widget tree.
  bool get isProjectingBody => _outputs != null;
  List<int>? _eager;
  Expression? _keyExpression;
  int? _keyNode;
  final List<int> _guards = [];
  T guarded<T>(Expression condition, bool selected, T Function() action) {
    var node = expressions.lower(condition);
    if (!selected)
      node = expressions.add(ValueNode('!', ValueType.boolean, inputs: [node]));
    _guards.add(node);
    try {
      return action();
    } finally {
      _guards.removeLast();
    }
  }

  String lower(FunctionExpression callback) {
    final parameters = callback.parameters?.parameters;
    if (parameters == null ||
        parameters.any((parameter) => parameter.declaredFragment == null))
      throw BuilderLoweringException(
        callback,
        'Unresolved callback parameters',
      );
    return lowerCallbackBody(callback.body, [
      for (final parameter in parameters) parameter.declaredFragment!.element,
    ]);
  }

  /// Lowers an inline or tearoff callback through identical native control flow.
  String lowerCallbackBody(
    FunctionBody body,
    List<FormalParameterElement> parameters,
  ) {
    expressions.nativeCallback = true;
    if (parameters.length != contract.parameters.length ||
        body.isAsynchronous ||
        body.isGenerator)
      throw BuilderLoweringException(
        body,
        'Malformed pure widget callback signature',
      );
    for (var i = 0; i < parameters.length; i++) {
      final kind = contract.parameters[i];
      if (kind == WidgetBuilderParameter.buildContext) {
        expressions.nativeContexts.add(parameters[i]);
        continue;
      }
      expressions.parameter(
        parameters[i],
        callbackParameterName(i),
        switch (kind) {
          WidgetBuilderParameter.boxConstraints => constraintsValueType,
          WidgetBuilderParameter.orientation => ValueType.string,
          WidgetBuilderParameter.itemIndex => ValueType.integer,
          _ => throw StateError('Native context is not a value'),
        },
      );
    }
    final result = switch (body) {
      ExpressionFunctionBody() => _result(body.expression),
      BlockFunctionBody() => _statements(body.block.statements.toList()),
      _ => throw BuilderLoweringException(body, 'Unsupported callback body'),
    };
    return encodeResult(result);
  }

  /// Lowers a resolved pure helper used directly as a native callback.
  String lowerDefinition(HelperDef helper) {
    expressions.nativeCallback = true;
    if (helper.params.length != contract.parameters.length)
      throw BuilderLoweringException(
        helper.body,
        'Callback helper signature differs',
      );
    for (var i = 0; i < helper.params.length; i++) {
      final kind = contract.parameters[i];
      if (kind == WidgetBuilderParameter.buildContext) {
        expressions.nativeContexts.add(helper.params[i]);
      } else {
        expressions.parameter(
          helper.params[i],
          callbackParameterName(i),
          switch (kind) {
            WidgetBuilderParameter.boxConstraints => constraintsValueType,
            WidgetBuilderParameter.orientation => ValueType.string,
            WidgetBuilderParameter.itemIndex => ValueType.integer,
            _ => throw StateError('Invalid native parameter'),
          },
        );
      }
    }
    final locals = <int>[];
    for (final local in helper.localBindings.entries) {
      if (expressions.bindContextAlias(local.key, local.value)) continue;
      final node = expressions.lower(local.value);
      expressions.localInitializers[local.key] = local.value;
      locals.add(expressions.bindValue(local.key, node, local.value));
    }
    var result = helper.functionBody == null
        ? _result(helper.body)
        : _closed.body(helper.functionBody!);
    for (final local in locals.reversed) {
      result = BuilderResult.let(local, result);
    }
    return encodeResult(result);
  }

  /// Lowers one widget result using the same body frame and expression graph.
  BuilderResult resultFor(Expression expression) => _result(expression);

  /// Encodes a callback or finite child collection through installed runtime plumbing.
  String encodeResult(BuilderResult result, {bool collection = false}) {
    if (expressions.nodes.isEmpty)
      expressions.add(
        const ValueNode('literal', ValueType.boolean, value: true),
      );
    final program = BuilderProgram(
      values: expressions.program(0),
      result: result,
      bodyCount: bodies.length,
      nullableResult: collection || contract.nullableResult,
      collection: collection,
    );
    program.validate(
      operations: expressions.operations,
      context: expressions.lexicalContext,
    );
    return '$kBuilderContinuationWidgetName(version: 1, program: ${jsonEncode(program.encode())}, captures: {${expressions.captureDsl.entries.map((e) => '${e.key}: ${e.value}').join(', ')}}, bodies: [${bodies.join(', ')}])';
  }

  /// Projects only demanded primitive values into the active body frame.
  String value(
    Expression expression, {
    bool asDouble = false,
    bool requireNativeBaseType = false,
    bool requireNonNull = false,
    String? nativeDestination,
  }) {
    final nativeClass =
        nativeDestination ?? projectedNativeClass(expression.staticType);
    final nativeType = expression.staticType;
    if (requireNativeBaseType &&
        nativeClass != null &&
        nativeClass != 'Color' &&
        nativeType is InterfaceType &&
        !nativeType.isDartCoreNull &&
        (nativeType.element.name != nativeClass ||
            nativeType.element.library.identifier != 'dart:ui')) {
      throw BuilderLoweringException(
        expression,
        '$nativeClass cannot cross a custom constructor boundary without proof of its native base runtime subtype.',
      );
    }
    var node = expressions.lower(expression);
    if (requireNativeBaseType &&
        nativeClass != null &&
        !(nativeClass == 'Color' &&
            expressions.nodes[node].type.kind == 'native' &&
            expressions.nodes[node].type.nativeType == 'flutter.Color') &&
        !expressions.provesNativeBase(node, nativeClass)) {
      throw BuilderLoweringException(
        expression,
        '$nativeClass cannot cross a custom constructor boundary without proof of its native base runtime subtype.',
      );
    }
    // A dynamic value takes Dart's implicit cast to its declared type.
    if (nativeType is DynamicType) {
      final argument = switch (expression.parent) {
        final NamedArgument named => named,
        _ => expression,
      };
      final declared = argument.correspondingParameter?.type;
      ValueType? expected;
      try {
        expected = valueTypeFor(declared, expression);
      } on BuilderLoweringException {
        // Skips destinations the value language cannot describe.
      }
      if (expected != null && !expected.accepts(expressions.nodes[node].type)) {
        throw BuilderLoweringException(
          expression,
          'This dynamic value does not match its destination.',
        );
      }
    }
    if (requireNonNull && expressions.nodes[node].type.nullable) {
      throw BuilderLoweringException(
        expression,
        'This native $nativeClass destination requires a non-null value.',
      );
    }
    if (asDouble && expressions.nodes[node].type.kind == 'int')
      node = expressions.add(
        ValueNode('toDouble', ValueType.real, inputs: [node]),
      );
    if (_isColorShape(expressions.nodes[node].type))
      return _projectColor(node, expression);
    return _projectNode(node, expression);
  }

  bool _isColorShape(ValueType type) =>
      type.kind == 'record' &&
      colorValueType.accepts(type.nonNull) &&
      type.nonNull.accepts(colorValueType);

  String _projectColor(int node, Expression expression) {
    final shape = expressions.nodes[node].type;
    int? isNull;
    String? nullReference;
    if (shape.nullable) {
      final nil = expressions.add(
        const ValueNode('literal', ValueType.nullType),
      );
      isNull = expressions.add(
        ValueNode('==', ValueType.boolean, inputs: [node, nil]),
      );
      nullReference = _projectNode(isNull, expression);
      node = expressions.add(
        ValueNode('nonNull', shape.nonNull, inputs: [node]),
      );
    }
    final fields = <String>[];
    for (final field in colorValueType.fields.entries) {
      final token = field.key == 'material'
          ? expressions.materialColorToken(node)
          : null;
      if (token != null) {
        fields.add('material: ${jsonEncode(token)}');
        continue;
      }
      var value = expressions.add(
        ValueNode('field', field.value, inputs: [node], name: field.key),
      );
      if (isNull != null) {
        final fallback = expressions.add(
          ValueNode(
            'literal',
            field.value,
            value: field.value.kind == 'String'
                ? (field.key == 'material' ? '' : 'sRGB')
                : 0.0,
          ),
        );
        value = expressions.add(
          ValueNode(
            'conditional',
            field.value,
            inputs: [isNull, fallback, value],
          ),
        );
      }
      fields.add('${field.key}: ${_projectNode(value, expression)}');
    }
    final result = '{${fields.join(', ')}}';
    return nullReference == null
        ? result
        : 'switch $nullReference {false: $result}';
  }

  /// Captures inert native constraints as finite scalar frame projections.
  String captureValue(Expression expression) {
    final node = expressions.lower(expression);
    final shape = expressions.nodes[node].type;
    if (_isColorShape(shape)) return _projectColor(node, expression);
    if (shape.kind != 'record') return _projectNode(node, expression);
    final type = expression.staticType;
    if (type is! InterfaceType ||
        type.nullabilitySuffix != NullabilitySuffix.none ||
        type.element.name != 'BoxConstraints' ||
        !type.element.library.identifier.startsWith('package:flutter/')) {
      throw BuilderLoweringException(
        expression,
        'Only inert native constraints can cross an aggregate callback frame',
      );
    }
    String project(int index, ValueType type) {
      if (type.kind != 'record') return _projectNode(index, expression);
      return '{${type.fields.entries.map((field) {
        final node = expressions.add(ValueNode('field', field.value, inputs: [index], name: field.key));
        return '${field.key}: ${project(node, field.value)}';
      }).join(', ')}}';
    }

    return project(node, shape);
  }

  String _projectNode(int node, Expression expression) {
    if (expressions.nodes[node].type.kind == 'native') {
      return _projectNativeNode(node, expression);
    }
    for (final guard in _guards.reversed) {
      final type = expressions.nodes[node].type;
      final Object? empty = type.nullable
          ? null
          : switch (type.kind) {
              'bool' => false,
              'int' => 0,
              'double' => 0.0,
              'num' => 0,
              'String' => '',
              _ => throw BuilderLoweringException(
                expression,
                'Only primitive values can cross a builder frame',
              ),
            };
      final fallback = expressions.add(
        ValueNode('literal', type, value: empty),
      );
      node = expressions.add(
        ValueNode('conditional', type, inputs: [guard, node, fallback]),
      );
    }
    final outputs = _outputs;
    if (outputs == null)
      throw BuilderLoweringException(
        expression,
        'Value is outside a builder body',
      );
    final name = 'v${outputs.length}';
    outputs[name] = node;
    _eager!.add(node);
    final reference = '$scope.values.$name';
    return expressions.nodes[node].type.nullable
        ? 'switch $scope.nulls.$name {false: $reference}'
        : reference;
  }

  /// Keeps an installed native result in the callback's lexical frame.
  String nativeValue(
    Expression expression,
    int Function(Expression, BuilderExpressionLowering) lower,
  ) => _projectNativeNode(lower(expression, expressions), expression);

  String _projectNativeNode(int node, Expression expression) {
    final type = expressions.nodes[node].type;
    if (type.kind != 'native' || _eager == null) {
      throw BuilderLoweringException(
        expression,
        'Native values require an active native body frame',
      );
    }
    var slot = 'n${expressions.nodes.length}';
    while (expressions.locals.containsKey(slot) ||
        expressions.lexicalContext.locals.containsKey(slot)) {
      slot = '${slot}_';
    }
    expressions.locals[slot] = type;
    var write = expressions.add(
      ValueNode('local.write', type, inputs: [node], name: slot),
    );
    for (final guard in _guards.reversed) {
      final nil = expressions.add(
        const ValueNode('literal', ValueType.nullType),
      );
      final effect = expressions.add(
        ValueNode('let', ValueType.nullType, inputs: [write, nil]),
      );
      write = expressions.add(
        ValueNode(
          'conditional',
          ValueType.nullType,
          inputs: [guard, effect, nil],
        ),
      );
    }
    _eager!.add(write);
    return '{kind: "nativeLocal", slot: ${jsonEncode(slot)}, '
        'type: ${jsonEncode(type.nativeType)}, nullable: ${type.nullable}}';
  }

  /// Whether this expression reads an already evaluated native Key in this frame.
  bool hasNativeKeyValue(Expression expression) {
    while (expression is ParenthesizedExpression ||
        expression is PostfixExpression && expression.operator.lexeme == '!') {
      expression = expression is ParenthesizedExpression
          ? expression.expression
          : (expression as PostfixExpression).operand;
    }
    if (expression is! SimpleIdentifier) return false;
    final type = expressions.boundValueType(expression.element);
    return type?.kind == 'native' && type?.nativeType == 'flutter.Key';
  }

  /// Stages the root key at its authored argument position.
  void observeKey(Expression expression) {
    if (identical(expression, _keyExpression)) {
      _eager!.add(_keyNode!);
      return;
    }
    if (expression is NullLiteral ||
        hasNativeKeyValue(expression) ||
        nativeKey?.call(expression) != null)
      return;
    throw BuilderLoweringException(
      expression,
      'A deferred body supports a scalar ValueKey on its root widget',
    );
  }

  /// Preserves eager helper arguments inside a constructed widget body.
  String translateHelper(
    HelperDef helper,
    MethodInvocation call,
  ) => expressions.withHelper(helper, call, (body, eager) {
    for (var node in eager) {
      for (final guard in _guards.reversed) {
        final yes = expressions.add(
          const ValueNode('literal', ValueType.boolean, value: true),
        );
        final no = expressions.add(
          const ValueNode('literal', ValueType.boolean, value: false),
        );
        final evaluate = expressions.add(
          ValueNode('let', ValueType.boolean, inputs: [node, yes]),
        );
        node = expressions.add(
          ValueNode(
            'conditional',
            ValueType.boolean,
            inputs: [guard, evaluate, no],
          ),
        );
      }
      _eager!.add(node);
    }
    final functionBody = helper.functionBody;
    if (functionBody == null) return translateBody(body);
    final start = _eager!.length;
    return ClosedCallbackLowering<String>(
      expressions,
      result: translateBody,
      sequence: (node, value) {
        for (final guard in _guards.reversed) {
          final nil = expressions.add(
            const ValueNode('literal', ValueType.nullType),
          );
          final effect = expressions.add(
            ValueNode('let', ValueType.nullType, inputs: [node, nil]),
          );
          node = expressions.add(
            ValueNode(
              'conditional',
              ValueType.nullType,
              inputs: [guard, effect, nil],
            ),
          );
        }
        _eager!.insert(start, node);
        return value;
      },
      guardBranch: (condition, selected, action) {
        _guards.add(
          selected
              ? condition
              : expressions.add(
                  ValueNode('!', ValueType.boolean, inputs: [condition]),
                ),
        );
        try {
          return action();
        } finally {
          _guards.removeLast();
        }
      },
      branch: (condition, yes, no) =>
          'switch ${_projectNode(condition, call)} {true: $yes, default: $no}',
    ).body(functionBody);
  });

  /// Stages helper arguments before constructing its widget or collection result.
  BuilderResult withHelperResult(
    HelperDef helper,
    MethodInvocation call,
    BuilderResult Function(Expression) lower,
  ) {
    BuilderResult stage() => expressions.withHelper(
      helper,
      call,
      (body, eager) {
        var result = helper.functionBody == null
            ? lower(body)
            : ClosedCallbackLowering<BuilderResult>(
                expressions,
                result: lower,
                sequence: BuilderResult.let,
                branch: BuilderResult.branch,
              ).body(helper.functionBody!);
        for (final node in eager.reversed) {
          result = BuilderResult.let(node, result);
        }
        return result;
      },
      inertNativeArgument: (argument) {
        final type = argument.staticType;
        return type is InterfaceType &&
            [type, ...type.allSupertypes].any(
              (candidate) =>
                  candidate.element.name == 'Key' &&
                  candidate.element.library.identifier.startsWith(
                    'package:flutter/',
                  ),
            ) &&
            nativeKey?.call(argument) != null;
      },
    );
    return withHelperBody?.call(helper, call, stage) ?? stage();
  }

  BuilderResult _result(Expression expression) {
    final resolved = resolve?.call(expression) ?? expression;
    if (resolved is MethodInvocation) {
      final helper = helperFor?.call(resolved);
      if (helper != null) return withHelperResult(helper, resolved, _result);
    }
    if (resolved is ParenthesizedExpression)
      return _result(resolved.expression);
    if (resolved is NullLiteral) return const BuilderResult.nullResult();
    if (resolved is ConditionalExpression) {
      BuilderResult branch(Expression value) =>
          withConditionalBranch?.call(resolved, value, () => _result(value)) ??
          _result(value);
      return BuilderResult.branch(
        expressions.lower(resolved.condition),
        branch(resolved.thenExpression),
        branch(resolved.elseExpression),
      );
    }
    final saved = _outputs;
    final savedEager = _eager;
    final savedKeyExpression = _keyExpression;
    final savedKeyNode = _keyNode;
    _keyExpression = null;
    _keyNode = null;
    final eager = <int>[];
    _eager = eager;
    final output = <String, int>{};
    _outputs = output;
    try {
      int? key;
      var keyType = 'Object';
      if (resolved is InstanceCreationExpression) {
        for (final argument in resolved.argumentList.arguments) {
          if (argument is NamedArgument && argument.name.lexeme == 'key') {
            final keyExpr = argument.argumentExpression;
            if (keyExpr is NullLiteral) continue;
            if (hasNativeKeyValue(keyExpr)) {
              key = expressions.lower(keyExpr);
              keyType = 'nativeKey';
              _keyExpression = keyExpr;
              _keyNode = key;
              continue;
            }
            final native = nativeKey?.call(keyExpr);
            if (native != null) {
              final name = 'c${expressions.captureTypes.length}';
              final type = ValueType.native(
                'flutter.Key',
                nullable:
                    keyExpr.staticType?.nullabilitySuffix ==
                    NullabilitySuffix.question,
              );
              expressions.captureTypes[name] = type;
              expressions.captureDsl[name] = native;
              key = expressions.add(ValueNode('capture', type, name: name));
              keyType = 'nativeKey';
              _keyExpression = keyExpr;
              _keyNode = key;
              continue;
            }
            if (keyExpr is! InstanceCreationExpression ||
                keyExpr.constructorName.element?.enclosingElement.name !=
                    'ValueKey' ||
                keyExpr.argumentList.arguments.length != 1)
              throw BuilderLoweringException(
                keyExpr,
                'Builder child key must be a scalar ValueKey',
              );
            final keyValue =
                keyExpr.argumentList.arguments.single.argumentExpression;
            final valueType = keyValue.staticType;
            if (keyValue is! NullLiteral &&
                !(valueType is InterfaceType &&
                    valueType.element.library.identifier == 'dart:core' &&
                    const {
                      'String',
                      'int',
                      'double',
                      'num',
                      'bool',
                      'Null',
                    }.contains(valueType.element.name))) {
              throw BuilderLoweringException(
                keyValue,
                'ValueKey values must have an inert scalar core type',
              );
            }
            key = expressions.lower(keyValue);
            final resolvedType = keyExpr.staticType;
            if (resolvedType is! InterfaceType ||
                resolvedType.typeArguments.length != 1)
              throw BuilderLoweringException(
                keyExpr,
                'Unresolved ValueKey generic type',
              );
            final generic = resolvedType.typeArguments.single;
            keyType = generic is DynamicType
                ? 'dynamic'
                : generic is InterfaceType &&
                      generic.element.library.identifier == 'dart:core'
                ? '${generic.element.name}${generic.nullabilitySuffix == NullabilitySuffix.question ? '?' : ''}'
                : throw BuilderLoweringException(
                    keyExpr,
                    'ValueKey requires an inert core generic type',
                  );
            if ((keyType == 'double' || keyType == 'double?') &&
                expressions.nodes[key].type.kind == 'int') {
              key = expressions.add(
                ValueNode('toDouble', ValueType.real, inputs: [key]),
              );
            }
            _keyExpression = keyExpr;
            _keyNode = key;
          }
        }
      }
      final body = translateBody(expression);
      final index = bodies.length;
      bodies.add('($scope) => $body');
      var result = BuilderResult.body(
        index,
        values: output,
        key: key,
        keyType: keyType,
      );
      for (final node in eager.reversed) {
        result = BuilderResult.let(node, result);
      }
      return result;
    } finally {
      _outputs = saved;
      _eager = savedEager;
      _keyExpression = savedKeyExpression;
      _keyNode = savedKeyNode;
    }
  }

  ClosedCallbackLowering<BuilderResult> get _closed =>
      ClosedCallbackLowering<BuilderResult>(
        expressions,
        result: _result,
        sequence: BuilderResult.let,
        branch: BuilderResult.branch,
      );
  BuilderResult _statements(List<Statement> statements) =>
      _closed.statements(statements);
}
