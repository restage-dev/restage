import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/closed_callback_lowering.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_shared/restage_shared.dart';

const _nativeScalarDomains = {'int', 'double', 'num', 'String', 'bool', 'Null'};

String? _coreTypeName(DartType? type) =>
    type is InterfaceType && type.element.library.identifier == 'dart:core'
        ? type.element.name
        : null;

DartType? _collectionItem(DartType? type) => type is InterfaceType &&
        {'List', 'Iterable'}.contains(_coreTypeName(type)) &&
        type.typeArguments.length == 1
    ? type.typeArguments.single
    : null;

bool _preservesNativeDomain(
    DartType source, DartType target, TypeSystem types) {
  final from = _coreTypeName(source);
  final to = _coreTypeName(target);
  if (from == 'Null' || to == 'Null') return true;
  if (_nativeScalarDomains.contains(from) && _nativeScalarDomains.contains(to))
    return true;
  if (from == 'List' && to == 'List') {
    return types.isSubtypeOf(
            types.promoteToNonNull(source), types.promoteToNonNull(target)) &&
        _preservesNativeDomain(
            _collectionItem(source)!, _collectionItem(target)!, types);
  }
  return source is InterfaceType &&
      target is InterfaceType &&
      source.element == target.element &&
      source.typeArguments.length == target.typeArguments.length &&
      List.generate(source.typeArguments.length,
              (i) => source.typeArguments[i] == target.typeArguments[i])
          .every((same) => same);
}

void _requireNativeDomain(DartType? source, DartType? target, AstNode site) {
  final unit = site.root;
  final types = unit is CompilationUnit
      ? unit.declaredFragment?.element.typeSystem
      : null;
  if (source == null ||
      target == null ||
      types == null ||
      !_preservesNativeDomain(source, target, types)) {
    throw BuilderLoweringException(site,
        'Collection conversion requires preserved native element domains');
  }
}

/// Lowers resolved native collections through the shared expression engine.
int? lowerCollectionExpression(
    Expression expression, BuilderExpressionLowering lowering) {
  if (expression is CascadeExpression) {
    final receiver = lowering.lower(expression.target);
    final effects = <int>[];
    for (final section in expression.cascadeSections) {
      if (section is! MethodInvocation ||
          section.methodName.name != 'sort' ||
          section.methodName.element?.library?.identifier != 'dart:core')
        throw BuilderLoweringException(
            section, 'Unsupported collection cascade');
      effects.add(_CollectionLowering(lowering).call(section, expression.target,
          'sort', section.argumentList.arguments.toList(),
          receiverNode: receiver));
    }
    var result = receiver;
    for (final effect in effects.reversed)
      result = lowering.add(ValueNode('let', lowering.nodes[receiver].type,
          inputs: [effect, result]));
    return lowering.add(ValueNode('let', lowering.nodes[receiver].type,
        inputs: [receiver, result]));
  }
  if (expression is ListLiteral &&
      expression.elements.any((e) => e is! Expression))
    return _CollectionLowering(lowering).literal(expression);
  Expression? target;
  SimpleIdentifier? member;
  List<Argument> arguments = const [];
  String? method;
  var constructor = false;
  if (expression is MethodInvocation) {
    target = expression.target;
    member = expression.methodName;
    arguments = expression.argumentList.arguments.toList();
    method = member.name;
  } else if (expression is PropertyAccess) {
    target = expression.target;
    member = expression.propertyName;
    method = member.name;
  } else if (expression is PrefixedIdentifier) {
    target = expression.prefix;
    member = expression.identifier;
    method = member.name;
  } else if (expression is InstanceCreationExpression &&
      expression.constructorName.element?.library.identifier == 'dart:core' &&
      expression.constructorName.element?.enclosingElement.name == 'List' &&
      {'of', 'from'}.contains(expression.constructorName.name?.name)) {
    constructor = true;
    method = 'copy';
    arguments = expression.argumentList.arguments.toList();
    target =
        arguments.where((a) => a is! NamedArgument).single.argumentExpression;
  }
  if (target == null ||
      method == null ||
      !kCollectionValueOperations.containsKey('collection.$method'))
    return null;
  if (!constructor && member?.element?.library?.identifier != 'dart:core')
    return null;
  final receiverType = target.staticType;
  if (receiverType is! InterfaceType ||
      receiverType.element.library.identifier != 'dart:core' ||
      !(method == 'compareTo'
              ? {'int', 'double', 'num', 'String'}
              : {'List', 'Iterable'})
          .contains(receiverType.element.name)) return null;
  if (method == 'length' && receiverType.element.name == 'List') return null;
  return _CollectionLowering(lowering)
      .call(expression, target, method, arguments, constructor: constructor);
}

final class _CollectionLowering {
  _CollectionLowering(this.values);
  final BuilderExpressionLowering values;

  int call(Expression expression, Expression receiver, String method,
      List<Argument> arguments,
      {bool constructor = false, int? receiverNode}) {
    final item = _collectionItem(receiver.staticType);
    if (method == 'copy' || method == 'toList') {
      _requireNativeDomain(
          item, _collectionItem(expression.staticType), expression);
    }
    final itemName = _coreTypeName(item);
    if (method == 'join' && !_nativeScalarDomains.contains(itemName)) {
      throw BuilderLoweringException(
          expression, 'Collection join requires native scalar elements');
    }
    String? equality;
    if ({'contains', 'indexOf', 'lastIndexOf'}.contains(method)) {
      const domains = {..._nativeScalarDomains, 'DateTime', 'Duration'};
      if (!domains.contains(itemName) ||
          arguments.isEmpty ||
          !domains.contains(
              _coreTypeName(arguments.first.argumentExpression.staticType))) {
        throw BuilderLoweringException(expression,
            'Collection equality requires a native scalar or temporal domain');
      }
      equality = switch (itemName) {
        'DateTime' => 'datetime',
        'Duration' => 'duration',
        _ => null
      };
    }
    if (method == 'sort' &&
        arguments.isEmpty &&
        !{'int', 'double', 'num', 'String'}.contains(itemName)) {
      throw BuilderLoweringException(expression,
          'Default collection sort requires native comparable scalars');
    }
    final source = receiverNode ?? values.lower(receiver);
    final sourceType = values.nodes[source].type;
    final inputs = <int>[source];
    final ordinary = <int>[];
    final callbacks = <Map<String, Object?>>[];
    Map<String, Object?>? otherwise;
    int? growable;
    var positional = 0;
    for (final argument in arguments) {
      final value = argument.argumentExpression;
      if (constructor && identical(value, receiver)) continue;
      final name = argument is NamedArgument ? argument.name.lexeme : null;
      final callback = name == 'orElse' ||
          (name == null &&
              ({
                        'map',
                        'where',
                        'takeWhile',
                        'skipWhile',
                        'any',
                        'every',
                        'indexWhere',
                        'lastIndexWhere',
                        'firstWhere',
                        'lastWhere',
                        'singleWhere',
                        'reduce',
                        'sort'
                      }.contains(method) &&
                      positional == 0 ||
                  method == 'fold' && positional == 1));
      if (callback) {
        final types = name == 'orElse'
            ? <ValueType>[]
            : switch (method) {
                'fold' => [
                    valueTypeFor(expression.staticType, expression),
                    sourceType.item!
                  ],
                'reduce' || 'sort' => [sourceType.item!, sourceType.item!],
                _ => [sourceType.item!],
              };
        final lowered = _callback(value, types, inputs);
        if (name == 'orElse')
          otherwise = lowered;
        else
          callbacks.add(lowered);
      } else {
        final index = inputs.length;
        inputs.add(values.lower(value));
        if (name == 'growable')
          growable = index;
        else if (name == null)
          ordinary.add(index);
        else
          throw BuilderLoweringException(
              argument, 'Unsupported collection argument');
      }
      if (name == null) positional++;
    }
    if (otherwise != null) callbacks.add(otherwise);
    void defaultArgument(Object? value, ValueType type) {
      ordinary.add(inputs.length);
      inputs.add(values.add(ValueNode('literal', type, value: value)));
    }

    if (method == 'toList' || method == 'copy') {
      if (growable != null)
        ordinary.add(growable);
      else
        defaultArgument(true, ValueType.boolean);
    }
    if ({'indexOf', 'lastIndexOf'}.contains(method) && ordinary.length == 1 ||
        {'indexWhere', 'lastIndexWhere'}.contains(method) && ordinary.isEmpty) {
      final last = method.startsWith('last');
      defaultArgument(
          last ? null : 0, last ? ValueType.nullType : ValueType.integer);
    }
    if (method == 'join' && ordinary.isEmpty)
      defaultArgument('', ValueType.string);
    final result = method == 'sort'
        ? ValueType.nullType
        : valueTypeFor(expression.staticType, expression);
    if (method == 'sort' && !_fresh(source))
      throw BuilderLoweringException(
          expression, 'Sort requires an explicit fresh native List');

    final output = values
        .add(ValueNode('collection.$method', result, inputs: inputs, value: {
      'arguments': ordinary,
      'callbacks': callbacks,
      if (equality != null) 'equality': equality,
      'item': ({'map', 'copy'}.contains(method)
              ? result.item!
              : sourceType.item ?? sourceType)
          .toJson()
    }));
    if (!constructor) return output;
    var ordered = output;
    final eager = <int>[];
    for (final argument in arguments) {
      if (identical(argument.argumentExpression, receiver))
        eager.add(source);
      else if (argument is NamedArgument && argument.name.lexeme == 'growable')
        eager.add(inputs[growable!]);
    }
    for (final input in eager.reversed)
      ordered = values.add(ValueNode('let', result, inputs: [input, ordered]));
    return ordered;
  }

  bool _fresh(int index, [Set<int> visiting = const {}]) {
    if (visiting.contains(index) ||
        values.immutableListLiterals.contains(index)) return false;
    final node = values.nodes[index];
    if (values.mutableListLiterals.contains(index)) return true;
    bool visit(int input) => _fresh(input, {...visiting, index});
    if (node.op == 'local.read') {
      final origin = values.immutableLocalInitializer(node.name!);
      if (origin != null) {
        return _CollectionLowering(origin.$1)._fresh(origin.$2);
      }
      final writes = values.nodes
          .where((n) => n.op == 'local.write' && n.name == node.name);
      return writes.isNotEmpty && writes.every((n) => visit(n.inputs.single));
    }
    return {'collection.toList', 'collection.copy', 'collection.concat'}
            .contains(node.op) ||
        node.op == 'let' && visit(node.inputs.last) ||
        node.op == 'conditional' && node.inputs.skip(1).every(visit);
  }

  // Same-unit body lookup does not evaluate a receiver. Only references whose
  // receiver is implicit or a static namespace may enter that lookup.
  bool _admittedTearOff(Expression expression) {
    final (element, target) = switch (expression) {
      SimpleIdentifier() => (expression.element, null),
      PrefixedIdentifier() => (
          expression.identifier.element,
          expression.prefix
        ),
      PropertyAccess() => (expression.propertyName.element, expression.target),
      _ => (null, null),
    };
    if (element is MethodElement && !element.isStatic) {
      final owner = expression
          .thisOrAncestorOfType<ClassDeclaration>()
          ?.declaredFragment
          ?.element;
      return target == null &&
          owner != null &&
          element.enclosingElement == owner;
    }
    if (element is! TopLevelFunctionElement &&
        !(element is MethodElement && element.isStatic)) return false;
    if (target == null) return true;
    final namespace = switch (target) {
      SimpleIdentifier() => target.element,
      PrefixedIdentifier() => target.identifier.element,
      _ => null,
    };
    return namespace is InterfaceElement || namespace is PrefixElement;
  }

  Map<String, Object?> _callback(
      Expression expression, List<ValueType> types, List<int> inputs) {
    if (expression is! FunctionExpression && !_admittedTearOff(expression)) {
      throw BuilderLoweringException(
          expression, 'Collection callback receiver is unsupported');
    }
    final resolved = expression is FunctionExpression
        ? (
            body: expression.body,
            parameters: expression.parameters!.parameters
                .map((p) => p.declaredFragment!.element)
                .toList()
          )
        : pureBuilderCallbackFor(
            expression,
            switch (expression) {
              SimpleIdentifier() => expression.element,
              PrefixedIdentifier() => expression.identifier.element,
              PropertyAccess() => expression.propertyName.element,
              _ => null,
            });
    if (resolved == null || resolved.parameters.length != types.length)
      throw BuilderLoweringException(
          expression, 'Collection callback requires a resolved closed body');
    final (nested, bindings) = _nested(inputs);
    for (var i = 0; i < types.length; i++)
      nested.parameter(
          resolved.parameters[i], callbackParameterName(i), types[i]);
    final root = closedValueCallback(nested).body(resolved.body);
    final program = nested.program(root);
    program.validate(
        operations: values.operations, context: nested.lexicalContext);
    return {'program': program.encode(), 'bindings': bindings};
  }

  (BuilderExpressionLowering, List<int>) _nested(List<int> inputs) {
    final bindings = <int>[];
    final nested = BuilderExpressionLowering(
        lexicalParent: values,
        capture: (_) =>
            throw StateError('Collection capture escaped its declaration'),
        operations: values.operations,
        extension: (value, lowering) {
          if (value is SimpleIdentifier &&
              !lowering.bindings.containsKey(value.element) &&
              lowering.localFor(value.element) == null &&
              (value.element is VariableElement ||
                  value.element is GetterElement)) {
            final outer = values.lower(value);
            final index = inputs.length;
            inputs.add(outer);
            final slot = bindings.length;
            bindings.add(index);
            return lowering.parameter(
                value.element!, 'outer$slot', values.nodes[outer].type);
          }
          final extended = values.extension?.call(value, lowering);
          if (extended != null) return extended;
          if (value is MethodInvocation && isArtifactHelperInvocation(value)) {
            final helper =
                pureBuilderHelperFor(value, value.methodName.element);
            if (helper != null) return lowering.lowerHelper(helper, value);
          }
          return null;
        });
    return (nested, bindings);
  }

  int literal(ListLiteral literal) {
    final type = valueTypeFor(literal.staticType, literal);
    final nativeItem = _collectionItem(literal.staticType)!;
    var result = values.add(ValueNode('list', type));
    for (final element in literal.elements) {
      final piece = _element(element, type, nativeItem);
      result = values.add(ValueNode('collection.concat', type, inputs: [
        result,
        piece
      ], value: {
        'arguments': [1],
        'callbacks': <Object?>[],
        'item': type.item!.toJson()
      }));
    }
    if (literal.isConst) values.immutableListLiterals.add(result);
    return result;
  }

  int _element(CollectionElement element, ValueType type, DartType nativeItem) {
    int empty() => values.add(ValueNode('list', type));
    if (element is Expression) {
      _requireNativeDomain(element.staticType, nativeItem, element);
      return values
          .add(ValueNode('list', type, inputs: [values.lower(element)]));
    }
    if (element is SpreadElement) {
      if (!(element.isNullAware &&
          _coreTypeName(element.expression.staticType) == 'Null')) {
        _requireNativeDomain(_collectionItem(element.expression.staticType),
            nativeItem, element);
      }
      var source = values.lower(element.expression);
      if (element.isNullAware) {
        final sourceType = values.nodes[source].type;
        source = values.add(ValueNode(
            '??', sourceType.kind == 'Null' ? type : sourceType.nonNull,
            inputs: [source, empty()]));
      }
      final growable = values
          .add(const ValueNode('literal', ValueType.boolean, value: true));
      return values.add(ValueNode('collection.copy', type, inputs: [
        source,
        growable
      ], value: {
        'arguments': [1],
        'callbacks': <Object?>[],
        'item': type.item!.toJson()
      }));
    }
    if (element is IfElement && element.caseClause == null) {
      return values.add(ValueNode('conditional', type, inputs: [
        values.lower(element.expression),
        _element(element.thenElement, type, nativeItem),
        element.elseElement == null
            ? empty()
            : _element(element.elseElement!, type, nativeItem)
      ]));
    }
    if (element is ForElement &&
        element.awaitKeyword == null &&
        element.forLoopParts is ForEachPartsWithDeclaration) {
      final parts = element.forLoopParts as ForEachPartsWithDeclaration;
      final variable = parts.loopVariable.declaredFragment!.element;
      final source = values.lower(parts.iterable);
      final sourceType = values.nodes[source].type;
      if (!{'list', 'iterable'}.contains(sourceType.kind) ||
          sourceType.nullable)
        throw BuilderLoweringException(
            element, 'Collection loop requires a finite sequence');
      final inputs = [source];
      final (nested, bindings) = _nested(inputs);
      nested.parameter(variable, callbackParameterName(0), sourceType.item!);
      final root =
          _CollectionLowering(nested)._element(element.body, type, nativeItem);
      final program = nested.program(root);
      return values
          .add(ValueNode('collection.expand', type, inputs: inputs, value: {
        'arguments': <int>[],
        'callbacks': [
          {'program': program.encode(), 'bindings': bindings}
        ],
        'item': type.item!.toJson()
      }));
    }
    throw BuilderLoweringException(
        element, 'Unsupported scalar collection element');
  }
}
