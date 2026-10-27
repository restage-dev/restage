import 'package:restage_codegen/src/collection_expression_lowering.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:restage_codegen/src/closed_callback_lowering.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/framework_const_values.dart';
import 'package:restage_codegen/src/installed_native_call.dart';
import 'package:restage_codegen/src/theme_recognition.dart';
import 'package:restage_codegen/src/device_recognition.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_shared/restage_shared.dart';

/// A located refusal from pure callback lowering.
final class BuilderLoweringException implements Exception {
  const BuilderLoweringException(this.node, this.reason);
  final AstNode node;
  final String reason;
  @override
  String toString() => '$reason: ${node.toSource()}';
}

/// Resolves a callback's same-unit body with its analyzed native parameters.
({FunctionBody body, List<FormalParameterElement> parameters})?
    pureBuilderCallbackFor(Expression anchor, Element? element) {
  if (element is! ExecutableElement) return null;
  final finder = _PureHelperFinder(element);
  anchor.root.accept(finder);
  final body = finder.body;
  if (body == null) return null;
  return (body: body, parameters: element.formalParameters);
}

/// Resolves same-unit pure helpers without applying eager-inlining restrictions.
HelperDef? pureBuilderHelperFor(Expression anchor, Element? element) {
  final callback = pureBuilderCallbackFor(anchor, element);
  if (callback == null ||
      callback.body.isAsynchronous ||
      callback.body.isGenerator) return null;
  final extracted = extractInlinableBuildBody(callback.body);
  if (extracted == null) {
    final returns = _HelperReturn();
    callback.body.accept(returns);
    if (returns.expression == null) return null;
    return HelperDef(
        params: callback.parameters,
        body: returns.expression!,
        functionBody: callback.body);
  }
  return HelperDef(
      params: callback.parameters,
      body: extracted.expression,
      localBindings: extracted.localBindings);
}

final class _HelperReturn extends RecursiveAstVisitor<void> {
  Expression? expression;
  @override
  void visitReturnStatement(ReturnStatement node) {
    expression ??= node.expression;
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {}
}

final class _AssignedLocal extends RecursiveAstVisitor<void> {
  _AssignedLocal(this.element);
  final Element element;
  bool found = false;
  void destination(Expression expression) {
    while (expression is ParenthesizedExpression) {
      expression = expression.expression;
    }
    if (expression is SimpleIdentifier && expression.element == element) {
      found = true;
    }
  }

  @override
  void visitAssignedVariablePattern(AssignedVariablePattern node) {
    if (node.element == element) found = true;
    super.visitAssignedVariablePattern(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    destination(node.leftHandSide);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    if (const {'++', '--'}.contains(node.operator.lexeme))
      destination(node.operand);
    super.visitPrefixExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    if (const {'++', '--'}.contains(node.operator.lexeme))
      destination(node.operand);
    super.visitPostfixExpression(node);
  }
}

final class _PureHelperFinder extends RecursiveAstVisitor<void> {
  _PureHelperFinder(this.element);
  final Element element;
  FunctionBody? body;
  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.declaredFragment?.element == element)
      body = node.functionExpression.body;
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.declaredFragment?.element == element) body = node.body;
    super.visitMethodDeclaration(node);
  }
}

/// Shared typed lowering for callback and constructor value expressions.
final class BuilderExpressionLowering {
  BuilderExpressionLowering(
      {required this.capture,
      this.parent,
      this.lexicalParent,
      this.extension,
      Map<String, ValueOperation> operations = const {}})
      : operations = {...operations};
  final String Function(Expression expression) capture;
  final BuilderExpressionLowering? parent;
  final BuilderExpressionLowering? lexicalParent;
  final int? Function(Expression, BuilderExpressionLowering)? extension;
  final Map<String, ValueOperation> operations;
  final List<ValueNode> nodes = [];
  final Set<int> mutableListLiterals = {};
  final Set<int> immutableListLiterals = {};
  final Map<Element, int> bindings = {};
  final Map<Element, String> localSlots = {};
  final Map<String, ValueType> locals = {};
  final Map<String, ValueType> outerLocals = {};
  final Map<String, int> _immutableLocalInitializers = {};

  /// The defining value of an immutable lexical slot, including its owner.
  (BuilderExpressionLowering, int)? immutableLocalInitializer(String slot) {
    final node = _immutableLocalInitializers[slot];
    if (node != null) return (this, node);
    if (locals.containsKey(slot)) return null;
    return (lexicalParent ?? parent)?.immutableLocalInitializer(slot);
  }

  (String, ValueType)? localFor(Element? element) {
    final slot = localSlots[element];
    if (slot != null) return (slot, locals[slot] ?? outerLocals[slot]!);
    final outer = (lexicalParent ?? parent)?.localFor(element);
    if (outer != null) outerLocals[outer.$1] = outer.$2;
    return outer;
  }

  /// The proven type of an existing lexical value without evaluating its initializer.
  ValueType? boundValueType(Element? element) =>
      localFor(element)?.$2 ?? _bindingTypeFor(element);

  bool _hasNativeCallableBinding(Element? element) {
    final slot = localSlots[element];
    if (slot != null)
      return (locals[slot] ?? outerLocals[slot])?.kind == 'native';
    final node = bindings[element];
    if (node != null) return nodes[node].type.kind == 'native';
    return (lexicalParent ?? parent)?._hasNativeCallableBinding(element) ??
        false;
  }

  ValueType? _bindingTypeFor(Element? element) {
    final node = bindings[element];
    if (node != null) return nodes[node].type;
    if (contextOwner(element) != null) return builderContextNativeValueType;
    return (lexicalParent ?? parent)?._bindingTypeFor(element);
  }

  ValueOperationContext get lexicalContext =>
      ValueOperationContext(operations: operations, locals: {
        ...?(lexicalParent ?? parent)?.lexicalContext.locals,
        ...?(lexicalParent ?? parent)?.locals
      });

  int declareLocal(VariableDeclaration variable, {required bool mutable}) {
    final element = variable.declaredFragment!.element;
    final value = lower(variable.initializer!);
    localInitializers[element] = variable.initializer!;
    return bindValue(element, value, variable, mutable: mutable);
  }

  /// Retains an evaluated declaration or helper argument at its lexical point.
  int bindValue(Element element, int value, AstNode source,
      {bool mutable = false}) {
    // Aggregates cross nested callback programs through the lexical frame;
    // reconstructing their initializer would repeat its reads and allocations.
    final retainedAggregate =
        const {'iterable', 'list', 'record'}.contains(nodes[value].type.kind);
    if (!mutable && !retainedAggregate) return bindings[element] = value;
    var id = 'local${nodes.length}';
    while (locals.containsKey(id) ||
        outerLocals.containsKey(id) ||
        _hasParentSlot(id)) {
      id = '${id}_';
    }
    final valueType = nodes[value].type;
    final ValueType type;
    if (valueType.kind == 'native') {
      if (element is! VariableElement) {
        throw BuilderLoweringException(
            source, 'A mutable native local requires a declared nominal type');
      }
      final declared = element.type;
      final initializer = source is VariableDeclaration
          ? source.initializer?.staticType
          : source is Expression
              ? source.staticType
              : null;
      if (initializer == null || source.root is! CompilationUnit) {
        throw BuilderLoweringException(
            source, 'A mutable native local requires a resolved initializer');
      }
      final system =
          (source.root as CompilationUnit).declaredFragment!.element.typeSystem;
      final base = declared is InterfaceType &&
          switch (valueType.nativeType) {
            'flutter.Color' => declared.element.name == 'Color' &&
                declared.element.library.identifier == 'dart:ui',
            'flutter.Key' => declared.element.name == 'Key' &&
                declared.element.library.identifier
                    .startsWith('package:flutter/'),
            _ => false,
          };
      if (!base &&
          system.promoteToNonNull(declared) !=
              system.promoteToNonNull(initializer)) {
        throw BuilderLoweringException(source,
            'A mutable native local requires its declared nominal type');
      }
      type = ValueType.native(valueType.nativeType!,
          nullable: declared.nullabilitySuffix == NullabilitySuffix.question);
    } else {
      // Preserve immutable finite projections such as a native Key callback's
      // record instead of attempting to derive its opaque nominal Dart type.
      type = !mutable && retainedAggregate
          ? valueType
          : element is VariableElement
              ? valueTypeFor(element.type, source)
              : valueType;
    }
    locals[id] = type;
    localSlots[element] = id;
    if (!mutable) _immutableLocalInitializers[id] = value;
    return _write(id, type, value);
  }

  bool _hasParentSlot(String id) {
    for (var scope = lexicalParent ?? parent;
        scope != null;
        scope = scope.lexicalParent ?? scope.parent) {
      if (scope.locals.containsKey(id) || scope.outerLocals.containsKey(id))
        return true;
    }
    return false;
  }

  int _write(String slot, ValueType type, int value) {
    if (type.kind == 'double' && nodes[value].type.kind == 'int') {
      value = add(ValueNode('toDouble', ValueType.real, inputs: [value]));
    }
    return add(ValueNode('local.write', nodes[value].type,
        inputs: [value], name: slot));
  }

  int _assignment(Expression destination, Expression? value, String operator,
      {bool postfix = false}) {
    if (destination is! SimpleIdentifier) {
      throw BuilderLoweringException(
          destination, 'Only declared local writes are supported');
    }
    final local = localFor(destination.element);
    if (local == null)
      throw BuilderLoweringException(
          destination, 'Write requires a mutable local');
    final (slot, type) = local;
    if (operator == '=') return _write(slot, type, lower(value!));
    var old = add(ValueNode('local.read', type, name: slot));
    if (operator == '??=') {
      final write = _write(slot, type, lower(value!));
      return add(ValueNode(
          '??', nodes[write].type.nullable ? type : type.nonNull,
          inputs: [old, write]));
    }
    if (type.nullable && _isNonNullable(destination)) {
      old = add(ValueNode('nonNull', type.nonNull, inputs: [old]));
    }
    final op = operator == '++'
        ? '+'
        : operator == '--'
            ? '-'
            : operator.substring(0, operator.length - 1);
    if (!const {'+', '-', '*', '/', '~/', '%'}.contains(op) ||
        !(type.numeric || (type.kind == 'String' && op == '+'))) {
      throw BuilderLoweringException(
          destination, 'Unsupported local compound operator');
    }
    final rhs = value == null
        ? add(const ValueNode('literal', ValueType.integer, value: 1))
        : lower(value);
    final resultType = switch (op) {
      '/' => ValueType.real,
      '~/' => ValueType.integer,
      _ => type.nonNull,
    };
    final updated = add(ValueNode(
        type.kind == 'String' ? 'concat' : op, resultType,
        inputs: [old, rhs]));
    final write = _write(slot, type, updated);
    return postfix
        ? add(ValueNode('let', nodes[old].type, inputs: [write, old]))
        : write;
  }

  final Map<Element, Expression> localInitializers = {};
  final Set<Element> nativeContexts = {};
  final Map<Element, (BuilderExpressionLowering, Expression)> contextAliases =
      {};
  bool nativeCallback = false;
  final Map<String, ValueType> parameters = {};
  final Map<String, ValueType> captureTypes = {};
  final Map<String, String> captureDsl = {};
  final Map<Element, int> _captureBindings = {};
  final Map<Expression, int> _shortenedReceivers = {};
  final Set<Expression> _activeNullAwareAccesses = {};
  final Map<int, String> _nativeBaseTypes = {};

  int _nativeBase(int node, String name) {
    _nativeBaseTypes[node] = name;
    return node;
  }

  /// Whether this output retains the exact native base-class identity.
  bool provesNativeBase(int node, String name) {
    final proofs = <int, bool>{};
    bool visit(int index) => proofs.putIfAbsent(index, () {
          final value = nodes[index];
          if (value.type.kind == 'Null' || _nativeBaseTypes[index] == name)
            return true;
          return switch (value.op) {
            'local.write' => visit(value.inputs.single),
            'local.read' => switch (immutableLocalInitializer(value.name!)) {
                (final owner, final initializer) =>
                  owner.provesNativeBase(initializer, name),
                null => false,
              },
            'nonNull' => visit(value.inputs.single),
            'let' => visit(value.inputs.last),
            'conditional' => value.inputs.skip(1).every(visit),
            '??' => value.inputs.every(visit),
            _ => false,
          };
        });
    return visit(node);
  }

  /// A statically selected token needs no deferred projection.
  String? materialColorToken(int node) {
    final tokensByNode = <int, String?>{};
    String? visit(int node) => tokensByNode.putIfAbsent(node, () {
          final value = nodes[node];
          if (value.op == 'literal' && value.value is Map)
            return (value.value! as Map)['material'] as String?;
          if (value.op == 'argbColor') return '';
          if (value.op == 'record') {
            final index = value.type.fields.keys.toList().indexOf('material');
            if (index >= 0) {
              final field = nodes[value.inputs[index]];
              if (field.op == 'literal') return field.value as String?;
            }
          }
          if (value.op == 'local.write') return visit(value.inputs.single);
          if (value.op == 'local.read') {
            final initializer = immutableLocalInitializer(value.name!);
            return initializer == null
                ? null
                : initializer.$1.materialColorToken(initializer.$2);
          }
          if (value.op == 'let') return visit(value.inputs.last);
          if (value.op == 'nonNull') return visit(value.inputs.single);
          if (value.op == 'conditional' || value.op == '??') {
            final tokens = [
              for (final input
                  in value.inputs.skip(value.op == 'conditional' ? 1 : 0))
                visit(input)
            ];
            if (tokens.every((token) => token == tokens.first))
              return tokens.first;
          }
          return null;
        });
    return visit(node);
  }

  ({Expression access, Expression receiver})? _firstNullAwareAccess(
      Expression expression) {
    if (expression is ParenthesizedExpression) return null;
    final receiver = switch (expression) {
      PropertyAccess(:final target) => target,
      IndexExpression(:final target) => target,
      MethodInvocation(:final target) => target,
      PostfixExpression(:final operand) => operand,
      _ => null,
    };
    if (receiver == null) return null;
    final earlier = _firstNullAwareAccess(receiver);
    if (earlier != null) return earlier;
    final aware = switch (expression) {
      PropertyAccess(:final isNullAware) => isNullAware,
      IndexExpression(:final isNullAware) => isNullAware,
      MethodInvocation(:final isNullAware) => isNullAware,
      _ => false,
    };
    return aware && !_activeNullAwareAccesses.contains(expression)
        ? (access: expression, receiver: receiver)
        : null;
  }

  int _lowerNullShortened(
      Expression expression, Expression access, Expression receiver) {
    _activeNullAwareAccesses.add(access);
    final previous = _shortenedReceivers[receiver];
    try {
      if (_isNonNullable(receiver)) return lower(expression);
      final path = themeReadSegments(receiver)?.join('.');
      final presence = path == null
          ? null
          : 'context:theme:$path.$builderStylePresenceField';
      final nil = add(const ValueNode('literal', ValueType.nullType));
      final int present;
      if (presence != null && builderContextValueType(presence) != null) {
        final name = _contextParameterName(receiver, presence);
        parameters[name] = ValueType.boolean;
        present = add(ValueNode('parameter', ValueType.boolean, name: name));
      } else {
        final input = lower(receiver);
        if (!nodes[input].type.nullable) return lower(expression);
        present = add(ValueNode('!=', ValueType.boolean, inputs: [input, nil]));
        _shortenedReceivers[receiver] = add(
            ValueNode('nonNull', nodes[input].type.nonNull, inputs: [input]));
      }
      final result = lower(expression);
      final type = nodes[result].type;
      return add(ValueNode(
          'conditional',
          ValueType(type.kind,
              nullable: true, item: type.item, fields: type.fields),
          inputs: [present, result, nil]));
    } finally {
      _activeNullAwareAccesses.remove(access);
      if (previous == null) {
        _shortenedReceivers.remove(receiver);
      } else {
        _shortenedReceivers[receiver] = previous;
      }
    }
  }

  int add(ValueNode node) {
    nodes.add(node);
    return nodes.length - 1;
  }

  /// Installs fixed Dart while retaining mutable captures in this lexical frame.
  int lowerInstalledNativeCall(Expression expression,
      {required ValueType resultType,
      InstalledNativeInput? Function(SimpleIdentifier)? borrow,
      bool Function(Expression)? isBorrowedCallable,
      Map<Expression, String?> constantStrings = const {},
      LibraryElement? emissionLibrary,
      required void Function(InstalledNativeCallPlan) install}) {
    final plan = planInstalledNativeCall(expression,
        resultType: resultType,
        borrowFor: borrow,
        isDeclaredCallable: (reference) =>
            reference is SimpleIdentifier &&
                _hasNativeCallableBinding(reference.element) ||
            isBorrowedCallable?.call(reference) == true,
        constantStrings: constantStrings,
        emissionLibrary: emissionLibrary,
        captureFor: (element) {
          final local = localFor(element);
          return local == null
              ? null
              : InstalledNativeCapture(local.$1, local.$2);
        },
        inputFor: (identifier) {
          if (_bindingTypeFor(identifier.element) == null) {
            throw BuilderLoweringException(identifier,
                'Native inputs require an existing callback or helper frame');
          }
          final node = lower(identifier);
          final type = nodes[node].type;
          if (!const {
            'int',
            'double',
            'num',
            'bool',
            'String',
            'Null',
            'native'
          }.contains(type.kind)) {
            throw BuilderLoweringException(identifier,
                'Native operands require original native values, not data projections');
          }
          return InstalledNativeInput(node, type);
        });
    install(plan);
    for (BuilderExpressionLowering? scope = this;
        scope != null;
        scope = scope.lexicalParent ?? scope.parent) {
      final previous = scope.operations['native.call'];
      scope.operations['native.call'] = NativeCallValueOperation({
        if (previous is NativeCallValueOperation) ...previous.declarations,
        plan.key: plan.contract,
      });
    }
    return add(plan.node);
  }

  int parameter(Element element, String name, ValueType type) {
    parameters[name] = type;
    return bindings[element] = add(ValueNode('parameter', type, name: name));
  }

  ValueProgram program(int root) => ValueProgram(
      nodes: List.unmodifiable(nodes),
      root: root,
      captures: Map.unmodifiable(captureTypes),
      parameters: Map.unmodifiable(parameters),
      locals: Map.unmodifiable(locals),
      outerLocals: Map.unmodifiable(outerLocals));
  final Set<Expression> _activeHelpers = {};

  /// Stages source-ordered arguments and immutable locals before helper results.
  int lowerHelper(HelperDef helper, MethodInvocation call) =>
      withHelper(helper, call, (body, eager) {
        var result = helper.functionBody == null
            ? lower(body)
            : closedValueCallback(this).body(helper.functionBody!);
        for (final node in eager.reversed) {
          result =
              add(ValueNode('let', nodes[result].type, inputs: [node, result]));
        }
        return result;
      });

  /// Binds a pure helper for one value or widget-result lowering operation.
  /// [inertNativeArgument] admits only borrowed reads that cannot throw or run code.
  T withHelper<T>(HelperDef helper, MethodInvocation call,
      T Function(Expression body, List<int> eager) visit,
      {bool Function(Expression)? inertNativeArgument}) {
    if (!_activeHelpers.add(helper.body))
      throw BuilderLoweringException(
          call, 'Recursive pure helper is unsupported');
    final saved = Map.of(bindings);
    final savedLocals = Map.of(localInitializers);
    final savedSlots = Map.of(localSlots);
    final savedContexts = Set.of(nativeContexts);
    final savedAliases = Map.of(contextAliases);
    try {
      final arguments = bindHelperArguments(
          helper.params, call.argumentList.arguments.toList());
      if (arguments == null)
        throw BuilderLoweringException(
            call, 'Pure helper arguments must bind exactly');
      final eager = <int>[];
      for (final argument in call.argumentList.arguments) {
        final expression = argument.argumentExpression;
        final owner = expression is SimpleIdentifier
            ? contextOwner(expression.element)
            : null;
        if (owner != null) {
          for (final entry in arguments.entries) {
            if (identical(entry.value, expression))
              contextAliases[entry.key] = (owner, expression);
          }
          continue;
        }
        if (inertNativeArgument?.call(expression) ?? false) continue;
        final node = lower(expression);
        var bound = false;
        for (final entry in arguments.entries) {
          if (!identical(entry.value, expression)) continue;
          final writes = _AssignedLocal(entry.key);
          if (helper.functionBody case final body?) {
            body.accept(writes);
          } else {
            for (final root in helper.roots) root.accept(writes);
          }
          final aggregate = const {'iterable', 'list', 'record'}
              .contains(nodes[node].type.kind);
          eager.add(bindValue(entry.key, node, expression,
              mutable: aggregate && writes.found));
          bound = true;
        }
        if (!bound) eager.add(node);
      }
      localInitializers.addAll(arguments);
      for (final local in helper.localBindings.entries) {
        if (bindContextAlias(local.key, local.value)) continue;
        if (inertNativeArgument?.call(local.value) ?? false) {
          localInitializers[local.key] = local.value;
          continue;
        }
        final node = lower(local.value);
        localInitializers[local.key] = local.value;
        eager.add(bindValue(local.key, node, local.value));
      }
      return visit(helper.body, eager);
    } finally {
      bindings
        ..clear()
        ..addAll(saved);
      localInitializers
        ..clear()
        ..addAll(savedLocals);
      nativeContexts
        ..clear()
        ..addAll(savedContexts);
      contextAliases
        ..clear()
        ..addAll(savedAliases);
      localSlots
        ..clear()
        ..addAll(savedSlots);
      _activeHelpers.remove(helper.body);
    }
  }

  BuilderExpressionLowering? contextOwner(Element? element) {
    for (var scope = this as BuilderExpressionLowering?;
        scope != null;
        scope = scope.parent) {
      final alias = scope.contextAliases[element];
      if (alias != null) return alias.$1;
      if (scope.nativeContexts.contains(element)) return scope;
    }
    return null;
  }

  bool bindContextAlias(Element variable, Expression initializer) {
    if (variable is! VariableElement || !variable.isFinal) return false;
    while (initializer is ParenthesizedExpression) {
      initializer = initializer.expression;
    }
    final owner = initializer is SimpleIdentifier
        ? contextOwner(initializer.element)
        : null;
    if (owner == null) return false;
    contextAliases[variable] = (owner, initializer);
    return true;
  }

  String _contextParameterName(Expression expression, String localName) {
    final references = _BuilderReferences();
    expression.accept(references);
    final owners = references.elements
        .map(contextOwner)
        .whereType<BuilderExpressionLowering>()
        .toSet();
    BuilderExpressionLowering? current = this;
    while (current != null && !current.nativeCallback) {
      current = current.parent;
    }
    if (owners.isEmpty) {
      if (current == null ||
          localName == 'context:device:defaultTargetPlatform') return localName;
      throw BuilderLoweringException(expression,
          'A context projection must use an admitted native callback context');
    }
    if (owners.length != 1)
      throw BuilderLoweringException(
          expression, 'A context projection must name one lexical context');
    final owner = owners.single;
    if (current == null) return localName;
    var depth = 0;
    while (current != null) {
      if (identical(current, owner))
        return depth == 0
            ? localName
            : 'context:ancestor:$depth:${localName.substring('context:'.length)}';
      do {
        current = current!.parent;
      } while (current != null && !current.nativeCallback);
      depth++;
      if (depth > 64) break;
    }
    throw BuilderLoweringException(
        expression, 'Native context is outside the lexical callback scope');
  }

  bool referencesOuter(Expression expression) {
    final references = _BuilderReferences();
    expression.accept(references);
    if (references.elements.any((element) =>
        bindings.containsKey(element) ||
        nativeContexts.contains(element) ||
        contextAliases.containsKey(element))) return false;
    return references.elements.any((element) {
      for (var scope = parent; scope != null; scope = scope.parent) {
        if (scope.bindings.containsKey(element) ||
            scope.nativeContexts.contains(element) ||
            scope.contextAliases.containsKey(element)) return true;
      }
      return false;
    });
  }

  bool _isNativeConstraintsRead(Expression expression) {
    Expression? root = expression;
    while (true) {
      if (root is PropertyAccess) {
        root = root.target;
        continue;
      }
      if (root is PrefixedIdentifier) {
        root = root.prefix;
        continue;
      }
      break;
    }
    final type = root?.staticType;
    return type is InterfaceType &&
        type.nullabilitySuffix == NullabilitySuffix.none &&
        type.element.name == 'BoxConstraints' &&
        type.element.library.identifier.startsWith('package:flutter/');
  }

  bool _isNonNullable(Expression expression) {
    final type = expression.staticType;
    final unit = expression.root;
    return type != null &&
        unit is CompilationUnit &&
        unit.declaredFragment?.element.typeSystem.isNonNullable(type) == true;
  }

  int lower(Expression expression) {
    final e = expression;
    if (e is SimpleIdentifier) {
      final alias = contextAliases[e.element];
      if (alias != null) return lower(alias.$2);
      // Inherited projections alone do not require an opaque context value.
      if (nativeContexts.contains(e.element)) {
        return bindings[e.element] ??
            parameter(e.element!, callbackParameterName(0),
                builderContextNativeValueType);
      }
      final local = localFor(e.element);
      if (local != null) {
        final read = add(ValueNode('local.read', local.$2, name: local.$1));
        return local.$2.nullable && _isNonNullable(e)
            ? add(ValueNode('nonNull', local.$2.nonNull, inputs: [read]))
            : read;
      }
    }
    if (e is AssignmentExpression) {
      if (e.element != null && e.element!.library.identifier != 'dart:core') {
        throw BuilderLoweringException(
            e, 'Custom assignment operator is unsupported');
      }
      return _assignment(e.leftHandSide, e.rightHandSide, e.operator.lexeme);
    }
    if (e is PrefixExpression &&
        const {'++', '--'}.contains(e.operator.lexeme)) {
      return _assignment(e.operand, null, e.operator.lexeme);
    }
    if (e is PostfixExpression &&
        const {'++', '--'}.contains(e.operator.lexeme)) {
      return _assignment(e.operand, null, e.operator.lexeme, postfix: true);
    }
    final shortened = _shortenedReceivers[e];
    if (shortened != null) return shortened;
    final access = _firstNullAwareAccess(e);
    if (access != null)
      return _lowerNullShortened(e, access.access, access.receiver);
    if (parent != null &&
        (e is SimpleIdentifier || _isNativeConstraintsRead(e)) &&
        referencesOuter(e)) {
      final shape = e is SimpleIdentifier
          ? _bindingTypeFor(e.element) ?? valueTypeFor(e.staticType, e)
          : valueTypeFor(e.staticType, e);
      if (!const {'list', 'record'}.contains(shape.kind))
        return _capture(e, shape);
    }

    if (e is ParenthesizedExpression) return lower(e.expression);
    if (e is PostfixExpression && e.operator.lexeme == '!') {
      final operand = lower(e.operand);
      return nodes[operand].type.nullable
          ? add(ValueNode('nonNull', nodes[operand].type.nonNull,
              inputs: [operand]))
          : operand;
    }
    final extended = extension?.call(e, this);
    if (extended != null) return extended;
    final collection = lowerCollectionExpression(e, this);
    if (collection != null) return collection;
    final device = deviceRead(e)?.path;
    final theme = themeReadSegments(e)?.join('.');
    final globalPlatform = device == 'platform' &&
        ((e is SimpleIdentifier &&
                isFlutterTopLevelValue(e, 'defaultTargetPlatform')) ||
            (e is PrefixedIdentifier &&
                isFlutterTopLevelValue(e.identifier, 'defaultTargetPlatform')));
    final localContextName = globalPlatform
        ? 'context:device:defaultTargetPlatform'
        : device != null
            ? 'context:device:$device'
            : theme != null
                ? 'context:theme:$theme'
                : null;
    final contextType = localContextName == null
        ? null
        : builderContextValueType(localContextName);
    if (localContextName != null && contextType != null) {
      final contextName = _contextParameterName(e, localContextName);
      parameters[contextName] = contextType;
      var result = add(ValueNode('parameter', contextType, name: contextName));
      final assertions = <PostfixExpression>[];
      void collect(Expression value) {
        if (value is ParenthesizedExpression) collect(value.expression);
        if (value is PropertyAccess && value.target != null)
          collect(value.target!);
        if (value is PrefixedIdentifier) collect(value.prefix);
        if (value is PostfixExpression && value.operator.lexeme == '!') {
          collect(value.operand);
          assertions.add(value);
        }
      }

      collect(e);
      for (final assertion in assertions.reversed) {
        final operand = assertion.operand;
        if (_isNonNullable(operand)) continue;
        final path = themeReadSegments(operand)?.join('.');
        final presence = path == null
            ? null
            : 'context:theme:$path.${builderStylePresenceField}';
        if (presence != null && builderContextValueType(presence) != null) {
          final name = _contextParameterName(operand, presence);
          parameters[name] = ValueType.boolean;
          final present =
              add(ValueNode('parameter', ValueType.boolean, name: name));
          final yes =
              add(const ValueNode('literal', ValueType.boolean, value: true));
          final no = add(const ValueNode('literal', ValueType.nullType));
          final maybe = add(ValueNode(
              'conditional', const ValueType('bool', nullable: true),
              inputs: [present, yes, no]));
          final check =
              add(ValueNode('nonNull', ValueType.boolean, inputs: [maybe]));
          result = add(ValueNode('let', contextType, inputs: [check, result]));
        } else {
          final check = lower(assertion);
          result = add(ValueNode('let', contextType, inputs: [check, result]));
        }
      }
      return result;
    }

    var constant = canonicalMaterialShade(e) ?? frameworkStaticConst(e);
    final constantElement = switch (e) {
      SimpleIdentifier() => e.element,
      PrefixedIdentifier() => e.identifier.element,
      PropertyAccess() => e.propertyName.element,
      _ => null,
    };
    final constantVariable = constantElement is PropertyAccessorElement
        ? constantElement.variable
        : constantElement;
    if (constantVariable is VariableElement && constantVariable.isConst)
      constant = constantVariable.computeConstantValue();
    if (constant != null) {
      final color = exactColorConstant(constant);
      if (color != null) {
        final node = add(ValueNode('literal', colorValueType, value: color));
        return _nativeBase(node, 'Color');
      }
      final scalar = exactStyleScalarConstant(constant);
      if (scalar != null) {
        final node =
            add(ValueNode('literal', ValueType.integer, value: scalar));
        final type = constant.type;
        return type is InterfaceType &&
                type.element.name == 'FontWeight' &&
                type.element.library.identifier == 'dart:ui'
            ? _nativeBase(node, 'FontWeight')
            : node;
      }
    }
    if (e is InstanceCreationExpression &&
        e.constructorName.element?.library.identifier == 'dart:ui') {
      final owner = e.constructorName.element?.enclosingElement.name;
      final name = e.constructorName.name?.name;
      if (owner == 'Color' &&
          name == null &&
          e.argumentList.arguments.length == 1) {
        final node = lower(e.argumentList.arguments.single.argumentExpression);
        return _nativeBase(
            add(ValueNode('argbColor', colorValueType, inputs: [node])),
            'Color');
      }
      if (owner == 'Color' &&
          (name == 'fromRGBO' || name == 'fromARGB') &&
          e.argumentList.arguments.length == 4) {
        final inputs = [
          for (final argument in e.argumentList.arguments)
            lower(argument.argumentExpression)
        ];
        final modulus =
            add(const ValueNode('literal', ValueType.integer, value: 256));
        final divisor =
            add(const ValueNode('literal', ValueType.integer, value: 255));
        int channel(int input) {
          final byte =
              add(ValueNode('%', ValueType.integer, inputs: [input, modulus]));
          return add(ValueNode('/', ValueType.real, inputs: [byte, divisor]));
        }

        final alpha = name == 'fromARGB' ? channel(inputs[0]) : inputs[3];
        final rgb = name == 'fromARGB' ? inputs.skip(1) : inputs.take(3);
        final fields = [
          alpha,
          ...rgb.map(channel),
          add(const ValueNode('literal', ValueType.string, value: 'sRGB')),
          add(const ValueNode('literal', ValueType.string, value: ''))
        ];
        var result = add(ValueNode('record', colorValueType, inputs: fields));
        for (final input in inputs.reversed) {
          result =
              add(ValueNode('let', colorValueType, inputs: [input, result]));
        }
        return _nativeBase(result, 'Color');
      }
      if (owner == 'Color' && name == 'from') {
        final fields = <String, int>{};
        final eager = <int>[];
        for (final arg in e.argumentList.arguments) {
          if (arg is! NamedArgument)
            throw BuilderLoweringException(
                e, 'Color.from requires named channels');
          final field = const {
            'alpha': 'a',
            'red': 'r',
            'green': 'g',
            'blue': 'b',
            'colorSpace': 'colorSpace'
          }[arg.name.lexeme];
          if (field == null)
            throw BuilderLoweringException(e, 'Unsupported Color channel');
          final node = lower(arg.argumentExpression);
          eager.add(node);
          fields[field] = node;
        }
        fields.putIfAbsent(
            'colorSpace',
            () => add(
                const ValueNode('literal', ValueType.string, value: 'sRGB')));
        fields['material'] =
            add(const ValueNode('literal', ValueType.string, value: ''));
        if (!colorValueType.fields.keys.every(fields.containsKey))
          throw BuilderLoweringException(
              e, 'Color.from requires every channel');
        var result = add(ValueNode('record', colorValueType, inputs: [
          for (final field in colorValueType.fields.keys) fields[field]!
        ]));
        for (final node in eager.reversed)
          result =
              add(ValueNode('let', colorValueType, inputs: [node, result]));
        return _nativeBase(result, 'Color');
      }
      if (owner == 'FontWeight' &&
          name == null &&
          e.argumentList.arguments.length == 1) {
        final argument = e.argumentList.arguments.single.argumentExpression;
        if (argument is IntegerLiteral &&
            argument.value != null &&
            argument.value! >= 1 &&
            argument.value! <= 1000)
          return _nativeBase(lower(argument), 'FontWeight');
        throw BuilderLoweringException(e,
            'A native weight constructor requires a constant integer in 1..1000');
      }
    }
    if (e is ParenthesizedExpression) return lower(e.expression);
    if (e is SimpleIdentifier) {
      final bound = bindings[e.element];
      if (bound != null) {
        final shape = nodes[bound].type;
        if (shape.nullable && _isNonNullable(e))
          return add(ValueNode('nonNull', shape.nonNull, inputs: [bound]));
        return bound;
      }
      final old = _captureBindings[e.element];
      if (old != null) return old;
    }
    ValueType type() => valueTypeFor(e.staticType, e);
    int literal(Object? value, ValueType type) =>
        add(ValueNode('literal', type, value: value));
    if (e is NullLiteral) return literal(null, ValueType.nullType);
    if (e is IntegerLiteral) {
      return e.staticType?.isDartCoreDouble == true
          ? literal(e.value?.toDouble(), ValueType.real)
          : literal(e.value, ValueType.integer);
    }
    if (e is DoubleLiteral) return literal(e.value, ValueType.real);
    if (e is BooleanLiteral) return literal(e.value, ValueType.boolean);
    if (e is SimpleStringLiteral) return literal(e.value, ValueType.string);
    if (e is ListLiteral) {
      if (e.elements.any((item) => item is! Expression))
        throw BuilderLoweringException(
            e, 'A value list literal must contain pure expressions');
      final node = add(ValueNode('list', type(),
          inputs: [for (final item in e.elements) lower(item as Expression)]));
      if (e.isConst) {
        immutableListLiterals.add(node);
      } else {
        mutableListLiterals.add(node);
      }
      return node;
    }
    if (e is StringInterpolation) {
      final parts = <int>[];
      for (final element in e.elements) {
        if (element is InterpolationString)
          parts.add(literal(element.value, ValueType.string));
        if (element is InterpolationExpression)
          parts.add(_stringValue(element.expression));
      }
      return add(ValueNode('concat', ValueType.string, inputs: parts));
    }
    if (e is BinaryExpression) {
      if (const {'==', '!='}.contains(e.operator.lexeme)) {
        final left = e.leftOperand.staticType;
        final right = e.rightOperand.staticType;
        final leftEnum = left is InterfaceType && left.element is EnumElement;
        final rightEnum =
            right is InterfaceType && right.element is EnumElement;
        bool isNull(DartType? type) =>
            type is InterfaceType &&
            type.element.library.identifier == 'dart:core' &&
            type.element.name == 'Null';
        bool nativeWeight(DartType? type) =>
            type is InterfaceType &&
            [type, ...type.allSupertypes].any((t) =>
                t.element.name == 'FontWeight' &&
                t.element.library.identifier == 'dart:ui');
        if ((nativeWeight(left) || nativeWeight(right)) &&
            !isNull(left) &&
            !isNull(right))
          throw BuilderLoweringException(e,
              'FontWeight equality requires native runtime identity; compare its value explicitly');
        if ((_nativeColorType(left) || _nativeColorType(right)) &&
            !isNull(left) &&
            !isNull(right)) {
          throw BuilderLoweringException(e,
              'Color equality requires native runtime identity and cannot use inert color records');
        }
        if ((leftEnum || rightEnum) &&
            !isNull(left) &&
            !isNull(right) &&
            !(leftEnum && rightEnum && left.element == right.element)) {
          throw BuilderLoweringException(e,
              'Enum equality requires matching declared enum identities or null');
        }
      }
      if (!const {
        '+',
        '-',
        '*',
        '/',
        '~/',
        '%',
        '==',
        '!=',
        '<',
        '<=',
        '>',
        '>=',
        '&&',
        '||',
        '??'
      }.contains(e.operator.lexeme))
        throw BuilderLoweringException(e, 'Unsupported pure operator');
      final operatorElement = e.element;
      if (operatorElement != null &&
          !operatorElement.library.identifier.startsWith('dart:'))
        throw BuilderLoweringException(
            e, 'Custom operator execution is unsupported');
      return add(ValueNode(
          e.operator.lexeme == '+' && e.staticType?.isDartCoreString == true
              ? 'concat'
              : e.operator.lexeme,
          type(),
          inputs: [lower(e.leftOperand), lower(e.rightOperand)]));
    }
    if (e is PrefixExpression && const {'!', '-'}.contains(e.operator.lexeme))
      return add(ValueNode(e.operator.lexeme == '-' ? 'negate' : '!', type(),
          inputs: [lower(e.operand)]));
    if (e is ConditionalExpression)
      return add(ValueNode('conditional', type(), inputs: [
        lower(e.condition),
        lower(e.thenExpression),
        lower(e.elseExpression)
      ]));
    if (e is IndexExpression) {
      final input = lower(e.target!);
      if (nodes[input].type.kind != 'list')
        throw BuilderLoweringException(
            e, 'Only inert list indexing is supported');
      return _nullableAccess(
          input,
          e.isNullAware,
          type(),
          (target) => add(ValueNode('index', nodes[target].type.item!,
              inputs: [target, lower(e.index)])));
    }
    Expression? target;
    String? field;
    Element? member;
    if (e is PrefixedIdentifier) {
      target = e.prefix;
      field = e.identifier.name;
      member = e.identifier.element;
    }
    if (e is PropertyAccess) {
      target = e.target;
      field = e.propertyName.name;
      member = e.propertyName.element;
    }
    if (target != null && field != null) {
      if (member is GetterElement &&
          member.variable is FieldElement &&
          (member.variable as FieldElement).isEnumConstant)
        return literal(field, ValueType.string);
      final input = lower(target);
      if (target.staticType case InterfaceType(:final element)) {
        if (element.library.identifier == 'dart:ui' &&
            ((element.name == 'FontWeight' && field == 'value') ||
                (element.name == 'TextDecoration' && field == 'maskValue')))
          return input;
      }
      final nativeType = target.staticType;
      if (field == 'name' &&
          member?.library?.identifier == 'dart:core' &&
          nativeType is InterfaceType &&
          nativeType.element is EnumElement &&
          nodes[input].type.kind == 'String') return input;
      return _nullableAccess(
          input, e is PropertyAccess && e.isNullAware, type(), (input) {
        final targetType = nodes[input].type;
        if (field == 'length' &&
            const {'list', 'String'}.contains(targetType.kind)) {
          return add(ValueNode('length', ValueType.integer, inputs: [input]));
        }
        if (const {'isEven', 'isOdd', 'isFinite', 'isInfinite'}
                .contains(field) &&
            targetType.numeric) {
          return add(ValueNode(field!, ValueType.boolean, inputs: [input]));
        }
        if (targetType.kind == 'record' && targetType.fields[field] != null) {
          return add(ValueNode('field', targetType.fields[field]!,
              inputs: [input], name: field));
        }
        throw BuilderLoweringException(e, 'Unknown or executable member');
      });
    }
    if (e is MethodInvocation) {
      final target = e.target;
      final targetType = target?.staticType;
      if (target != null &&
          targetType is InterfaceType &&
          targetType.element is EnumElement &&
          e.methodName.name == 'toString' &&
          e.argumentList.arguments.isEmpty) {
        return _stringValue(target, nullAware: e.isNullAware);
      }
      if (target != null &&
          const {'floor', 'ceil', 'round', 'toInt', 'toDouble', 'clamp'}
              .contains(e.methodName.name) &&
          e.methodName.element?.library?.identifier == 'dart:core') {
        return add(ValueNode(e.methodName.name, type().nonNull, inputs: [
          lower(target),
          for (final arg in e.argumentList.arguments)
            lower(arg.argumentExpression)
        ]));
      }
      if (target != null &&
          const {'constrainWidth', 'constrainHeight'}
              .contains(e.methodName.name) &&
          e.methodName.element?.library?.identifier
                  .startsWith('package:flutter/') ==
              true) {
        final input = lower(target);
        final dimension =
            e.methodName.name == 'constrainWidth' ? 'Width' : 'Height';
        var value = e.argumentList.arguments.isEmpty
            ? add(ValueNode('field', ValueType.real,
                inputs: [input], name: 'max$dimension'))
            : lower(e.argumentList.arguments.single.argumentExpression);
        if (nodes[value].type.kind != 'double')
          value = add(ValueNode('toDouble', ValueType.real, inputs: [value]));
        return add(ValueNode('clamp', ValueType.real, inputs: [
          value,
          add(ValueNode('field', ValueType.real,
              inputs: [input], name: 'min$dimension')),
          add(ValueNode('field', ValueType.real,
              inputs: [input], name: 'max$dimension'))
        ]));
      }
      throw BuilderLoweringException(
          e, 'Arbitrary call is unsupported in a pure callback');
    }
    if (e is SimpleIdentifier) {
      if (e.element is FormalParameterElement &&
          (e.element! as FormalParameterElement).type.getDisplayString() ==
              'BuildContext')
        throw BuilderLoweringException(
            e, 'BuildContext cannot escape its native callback');
      return _capture(e, type());
    }
    throw BuilderLoweringException(e, 'Unsupported pure expression');
  }

  int _stringValue(Expression expression, {bool nullAware = false}) {
    final type = expression.staticType;
    if (type is InterfaceType && type.element is EnumElement) {
      final method = type.lookUpMethod('toString', type.element.library);
      if (method == null || method.library.identifier != 'dart:core') {
        throw BuilderLoweringException(expression,
            'Enum string conversion with a custom toString implementation is unsupported');
      }
      final input = lower(expression);
      final shape = nodes[input].type;
      final prefix = add(ValueNode('literal', ValueType.string,
          value: '${type.element.name}.'));
      final present = shape.nullable
          ? add(ValueNode('nonNull', shape.nonNull, inputs: [input]))
          : input;
      final text =
          add(ValueNode('concat', ValueType.string, inputs: [prefix, present]));
      if (!shape.nullable) return text;
      final missing = add(const ValueNode('literal', ValueType.nullType));
      final isNull =
          add(ValueNode('==', ValueType.boolean, inputs: [input, missing]));
      final nullText = nullAware
          ? missing
          : add(const ValueNode('literal', ValueType.string, value: 'null'));
      return add(ValueNode(
          'conditional', ValueType('String', nullable: nullAware),
          inputs: [isNull, nullText, text]));
    }
    if (type is! InterfaceType ||
        type.element.library.identifier != 'dart:core' ||
        !const {'String', 'bool', 'int', 'double', 'num', 'Null'}
            .contains(type.element.name)) {
      throw BuilderLoweringException(expression,
          'String conversion requires an inert core scalar or an enum with native string semantics');
    }
    return add(
        ValueNode('string', ValueType.string, inputs: [lower(expression)]));
  }

  int _nullableAccess(
      int input, bool nullAware, ValueType resultType, int Function(int) read) {
    final type = nodes[input].type;
    if (!nullAware || !type.nullable) return read(input);
    final missing =
        add(const ValueNode('literal', ValueType.nullType, value: null));
    final isNull =
        add(ValueNode('==', ValueType.boolean, inputs: [input, missing]));
    final present = add(ValueNode('nonNull', type.nonNull, inputs: [input]));
    final result = read(present);
    return add(ValueNode('conditional', resultType,
        inputs: [isNull, missing, result]));
  }

  int _capture(Expression expression, ValueType shape) {
    if (_nativeColorType(expression.staticType) && parent == null) {
      throw BuilderLoweringException(expression,
          'Native Color host captures require an explicit exact color contract; legacy ARGB host values cannot be used as native colors');
    }
    final name = 'c${captureTypes.length}';
    final dsl = capture(expression);
    if (dsl.isEmpty)
      throw BuilderLoweringException(
          expression, 'Capture could not be lowered');
    captureTypes[name] = shape;
    captureDsl[name] = dsl;
    final result = add(ValueNode('capture', shape, name: name));
    if (expression is SimpleIdentifier && expression.element != null)
      _captureBindings[expression.element!] = result;
    return result;
  }
}

/// Derives inert projections without invoking user getters.
ValueType valueTypeFor(DartType? type, AstNode source,
    [Set<Element> visiting = const {}]) {
  if (type == null)
    throw BuilderLoweringException(source, 'Unresolved expression type');
  final nullable = type.nullabilitySuffix == NullabilitySuffix.question;
  if (type is InterfaceType) {
    final element = type.element;
    final name = element.name;
    if (element.library.identifier == 'dart:core') {
      if (const {'int', 'double', 'num', 'bool', 'String', 'Null'}
          .contains(name))
        return ValueType(name!, nullable: nullable || name == 'Null');
      if (name == 'DateTime')
        return ValueType('record', nullable: nullable, fields: const {
          'microsecondsSinceEpoch': ValueType.integer,
          'isUtc': ValueType.boolean
        });
      if (name == 'Duration')
        return ValueType('record',
            nullable: nullable, fields: durationValueType.fields);
      if (name == 'List' || name == 'Iterable')
        return ValueType(name == 'List' ? 'list' : 'iterable',
            nullable: nullable,
            item: valueTypeFor(type.typeArguments.single, source, visiting));
    }
    if ([type, ...type.allSupertypes].any((type) =>
        type.element.name == 'Color' &&
        type.element.library.identifier == 'dart:ui'))
      return ValueType('record',
          nullable: nullable, fields: colorValueType.fields);
    if (element.library.identifier == 'dart:ui' &&
        const {'FontWeight', 'TextDecoration'}.contains(name))
      return ValueType('int', nullable: nullable);
    if (element is EnumElement) return ValueType('String', nullable: nullable);
    if (name == 'BoxConstraints' &&
        element.library.identifier.startsWith('package:flutter/'))
      return constraintsValueType;
    if (visiting.contains(element))
      throw BuilderLoweringException(
          source, 'Recursive capture shape is unsupported');
    final fields = <String, ValueType>{};
    for (final field in element.fields) {
      if (field.isStatic || field.name == null || field.name!.startsWith('_'))
        continue;
      if (!field.isFinal || !field.isOriginDeclaration)
        throw BuilderLoweringException(
            source, 'Capture requires immutable stored fields');
      fields[field.name!] =
          valueTypeFor(field.type, source, {...visiting, element});
    }
    if (fields.isNotEmpty)
      return ValueType('record', nullable: nullable, fields: fields);
  }
  throw BuilderLoweringException(
      source, 'Unsupported inert value type ${type.getDisplayString()}');
}

/// Closed native constraints projection shared by callback lowering.
const constraintsValueType = builderConstraintsValueType;

final class _BuilderReferences extends RecursiveAstVisitor<void> {
  final Set<Element> elements = {};
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element != null) elements.add(node.element!);
  }
}

bool _nativeColorType(DartType? type) =>
    type is InterfaceType &&
    [type, ...type.allSupertypes].any((t) =>
        t.element.name == 'Color' && t.element.library.identifier == 'dart:ui');

/// Native objects whose reconstructed identity is observable by custom widgets.
String? projectedNativeClass(DartType? type) {
  if (type is! InterfaceType) return null;
  for (final candidate in [type, ...type.allSupertypes]) {
    if (candidate.element.library.identifier == 'dart:ui' &&
        const {'Color', 'FontWeight'}.contains(candidate.element.name))
      return candidate.element.name;
  }
  return null;
}
