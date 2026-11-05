import 'dart:convert';
import 'package:restage_codegen/src/closed_callback_lowering.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
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
      _bind(parameters[i], i, body);
    }
    final result = switch (body) {
      ExpressionFunctionBody() => _result(body.expression),
      BlockFunctionBody() => _statements(body.block.statements.toList()),
      _ => throw BuilderLoweringException(body, 'Unsupported callback body'),
    };
    return encodeResult(result);
  }

  // Binds parameter [i] of a callback whose body is [body].
  void _bind(FormalParameterElement parameter, int i, AstNode body) {
    final kind = contract.parameters[i];
    if (kind == WidgetBuilderParameter.buildContext) {
      expressions.nativeContexts.add(parameter);
      return;
    }
    if (kind == WidgetBuilderParameter.child) {
      final read = _ReadOf(parameter);
      body.accept(read);
      if (read.found case final found?) {
        throw BuilderLoweringException(
          found,
          'A builder passes its child through in the app',
        );
      }
      return;
    }
    expressions.parameter(parameter, callbackParameterName(i), switch (kind) {
      WidgetBuilderParameter.boxConstraints => constraintsValueType,
      WidgetBuilderParameter.orientation => ValueType.string,
      WidgetBuilderParameter.itemIndex => ValueType.integer,
      WidgetBuilderParameter.data => valueTypeFor(parameter.type, body),
      WidgetBuilderParameter.buildContext || WidgetBuilderParameter.child =>
        throw StateError('Native context is not a value'),
    });
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
      _bind(helper.params[i], i, helper.functionBody ?? helper.body);
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

  /// Reads the value the app's builder records under [key] as a parameter of
  /// the delivered body; `null` for a [type] a recording can't carry.
  int? recordedValue(String key, ValueType type) {
    if (!contract.isAppValueSignature ||
        !const {
          'bool',
          'int',
          'double',
          'num',
          'String',
          'Null',
        }.contains(type.kind)) {
      return null;
    }
    final name = '$kRecordedBuilderParameterPrefix$key';
    expressions.parameters[name] = type;
    return expressions.add(ValueNode('parameter', type, name: name));
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

final class _ReadOf extends RecursiveAstVisitor<void> {
  _ReadOf(this.element);
  final Element element;
  SimpleIdentifier? found;
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element?.baseElement == element.baseElement) found ??= node;
  }
}

/// An app builder whose body is delivered while Flutter's builder stays in
/// the app, passing each app value as data.
final class AppValueSlot {
  const AppValueSlot._(this.contract, this.data, this._types);

  /// The callback's signature.
  final WidgetBuilderContract contract;

  /// The shape of each app value parameter, by parameter name.
  final Map<String, ValueType> data;

  final List<DartType> _types;

  /// The slot for [callback], or `null` when its signature is not the
  /// context, app values the app can project, then at most one child.
  static AppValueSlot? of(FunctionExpression callback) {
    final parameters = callback.parameters?.parameters;
    final type = callback.staticType;
    if (parameters == null ||
        parameters.any((p) => !p.isRequiredPositional) ||
        type is! FunctionType ||
        !_isFlutter(type.returnType, 'Widget', subtype: true) ||
        type.returnType.nullabilitySuffix != NullabilitySuffix.none) {
      return null;
    }
    final kinds = <WidgetBuilderParameter>[];
    final data = <String, ValueType>{};
    final types = [
      for (final parameter in parameters)
        if (parameter.declaredFragment?.element.type case final type?) type,
    ];
    if (types.length != parameters.length) return null;
    for (final (i, parameter) in types.indexed) {
      if (i == 0) {
        if (!_isFlutter(parameter, 'BuildContext')) return null;
        kinds.add(WidgetBuilderParameter.buildContext);
      } else if (i == types.length - 1 && _isFlutter(parameter, 'Widget')) {
        kinds.add(WidgetBuilderParameter.child);
      } else {
        if (appValueProjection(parameter, '') == null) return null;
        try {
          data[callbackParameterName(i)] = valueTypeFor(parameter, callback);
        } on BuilderLoweringException {
          return null;
        }
        kinds.add(WidgetBuilderParameter.data);
      }
    }
    final contract = WidgetBuilderContract(parameters: kinds);
    return contract.isAppValueSignature
        ? AppValueSlot._(contract, data, types)
        : null;
  }

  /// The signature as fit compares it: each parameter's kind and shape.
  String get signature =>
      '(${[
        for (final (i, kind) in contract.parameters.indexed) switch (data[callbackParameterName(i)]) {
            final shape? => jsonEncode(_sorted(shape.toJson())),
            null => kind.name,
          },
      ].join(', ')})';

  /// The island-build local holding the binding of the builder argument
  /// [argument].
  static String bindingName(String argument) => '_restageBinding\$$argument';

  /// Source constructing the slot's binding for the payload argument at
  /// [path] of the island's [source] in [context].
  String binding(
    String source,
    String context,
    String path, {
    String sdk = '',
  }) =>
      '${sdk}RestageBuilderBinding('
      '${sdk}RestageValueBinding.dataSource($source, $context), '
      'const <Object>[${dartStringLiteral(path)}], '
      'contract: const ${sdk}WidgetBuilderContract(parameters: [${contract.parameters.map((p) => '${sdk}WidgetBuilderParameter.${p.name}').join(', ')}]), '
      'data: const <String, ${sdk}ValueType>{${data.entries.map((e) => '${dartStringLiteral(e.key)}: ${valueTypeSource(e.value, sdk: sdk)}').join(', ')}})';

  /// Source of an island's build [template] that owns a binding, named by
  /// [bindingName], for each of [slots], its app builders by argument.
  static String owning(
    String template,
    Map<String, AppValueSlot> slots, {
    required String source,
    required String context,
    String sdk = '',
  }) =>
      '${sdk}RestageBuilderBinding.construct((_restageBindings) { ${[
        for (final MapEntry(key: argument, value: slot) in slots.entries) ...[
          'final ${bindingName(argument)} = '
              '${slot.binding(source, context, argument, sdk: sdk)};',
          '_restageBindings.add(${bindingName(argument)});',
        ],
      ].join(' ')} return $template; })';

  /// The names a callback for [callback] declares: its own parameter names,
  /// so a copy of its body resolves, with a fresh name for each wildcard.
  static List<String> parameterNames(FunctionExpression callback) => [
    for (final (i, parameter)
        in (callback.parameters?.parameters ?? const <FormalParameter>[])
            .indexed)
      switch (parameter.name?.lexeme) {
        final name? when name != '_' => name,
        _ => '_restageArg$i',
      },
  ];

  /// Source of Flutter's builder, rendering the delivered body through
  /// [binding] with each app value projected; [sdk] prefixes runtime names.
  ///
  /// With [body], the builder declares [names] and runs [body]: a copy of
  /// the app's closure body that records into [kSlotRecordingName] and
  /// returns `[kSlotRenderName](<the app's value>)` at each return.
  String callback(
    String binding, {
    String sdk = '',
    List<String>? names,
    String? body,
  }) {
    names ??= [
      for (var i = 0; i < _types.length; i++) '_restageArg$i',
    ];
    final values = [
      for (final (i, kind) in contract.parameters.indexed)
        if (kind == WidgetBuilderParameter.data)
          '${dartStringLiteral(callbackParameterName(i))}: '
              '${appValueProjection(_types[i], names[i], sdk: sdk)}',
    ];
    final build =
        '$binding.build(${names.first}, '
        '<String, Object?>{${values.join(', ')}}';
    if (body == null) return '(${names.join(', ')}) => $build)';
    return '(${names.join(', ')}) { '
        'final $kSlotRecordingName = ${sdk}RestageRecording(); '
        '$kSlotRenderName(Object? _) => '
        '$build, recorded: $kSlotRecordingName.values); '
        '$body }';
  }
}

/// The recording a copied builder body records into.
const String kSlotRecordingName = '_restageSlotRecording';

/// The function a copied builder body returns through, given the app's own
/// value, which it evaluates as the app does.
const String kSlotRenderName = '_restageRender';

// [json] with every map's keys in order, so field order is no change.
Object? _sorted(Object? json) => switch (json) {
  final Map<String, Object?> map => {
    for (final key in map.keys.toList()..sort()) key: _sorted(map[key]),
  },
  _ => json,
};

bool _isColor(InterfaceType type) => [type, ...type.allSupertypes].any(
  (t) => t.element.name == 'Color' && t.element.library.identifier == 'dart:ui',
);

bool _isFlutter(DartType type, String name, {bool subtype = false}) =>
    type is InterfaceType &&
    [type, if (subtype) ...type.allSupertypes].any(
      (type) =>
          type.element.name == name &&
          type.element.library.identifier.startsWith('package:flutter/'),
    );

/// Dart source projecting [source], an app value of [type], into the data
/// [valueTypeFor] describes; `null` for a shape with no projection yet.
String? appValueProjection(
  DartType type,
  String source, {
  int depth = 0,
  String sdk = '',
}) {
  if (type is! InterfaceType) return null;
  final element = type.element;
  final name = element.name;
  final library = element.library.identifier;
  final core = library == 'dart:core';
  if (core && const {'int', 'double', 'num', 'bool', 'String'}.contains(name)) {
    return source;
  }
  final nullable = type.nullabilitySuffix != NullabilitySuffix.none;
  final v = nullable ? '_restagePresent$depth' : source;
  String? projected;
  if (core && name == 'DateTime') {
    projected =
        "<String, Object?>{'microsecondsSinceEpoch': "
        "$v.microsecondsSinceEpoch, 'isUtc': $v.isUtc}";
  } else if (core && name == 'Duration') {
    projected = "<String, Object?>{'microseconds': $v.inMicroseconds}";
  } else if (core && name == 'List') {
    final item = '_restageItem$depth';
    final each = appValueProjection(
      type.typeArguments.single,
      item,
      depth: depth + 1,
      sdk: sdk,
    );
    if (each != null) projected = '<Object?>[for (final $item in $v) $each]';
  } else if (_isColor(type)) {
    projected = '${sdk}RestageBuilderBinding.color($v)';
  } else if (element is EnumElement) {
    projected = '$v.name';
  } else if (!library.startsWith('dart:') &&
      !library.startsWith('package:flutter/') &&
      element.typeParameters.isEmpty) {
    final fields = <String>[];
    for (final field in element.fields) {
      final fieldName = field.name;
      if (field.isStatic || fieldName == null || fieldName.startsWith('_')) {
        continue;
      }
      final value = field.isFinal && !field.isLate && field.isOriginDeclaration
          ? appValueProjection(
              field.type,
              '$v.$fieldName',
              depth: depth + 1,
              sdk: sdk,
            )
          : null;
      if (value == null) return null;
      fields.add('${dartStringLiteral(fieldName)}: $value');
    }
    if (fields.isNotEmpty)
      projected = '<String, Object?>{${fields.join(', ')}}';
  }
  if (projected == null) return null;
  return nullable
      ? 'switch ($source) { final $v? => $projected, null => null }'
      : projected;
}

/// Dart source of a const [type].
String valueTypeSource(ValueType type, {String sdk = ''}) {
  if (type.kind == 'native') throw StateError('A native value has no data');
  return '${sdk}ValueType(${dartStringLiteral(type.kind)}'
      '${type.nullable ? ', nullable: true' : ''}'
      '${type.item == null ? '' : ', item: ${valueTypeSource(type.item!, sdk: sdk)}'}'
      '${type.fields.isEmpty ? '' : ', fields: {${type.fields.entries.map((e) => '${dartStringLiteral(e.key)}: ${valueTypeSource(e.value, sdk: sdk)}').join(', ')}}'})';
}
