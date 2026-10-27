import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import 'builder_expression_lowering.dart';
import 'const_folding.dart' show resolveConstDeclarationInitializer;

/// Resolved declarations and constant values used by a compiled expression.
List<String> nativeExpressionProvenance(Expression expression) {
  final visitor = _Provenance(expression);
  expression.accept(visitor);
  return visitor.symbols.toList()..sort();
}

/// The analyzer's actual constant, including a static function tearoff.
DartObject? installedNativeConstantValue(Expression expression) {
  final unit = expression.root;
  if (unit is! CompilationUnit || unit.declaredFragment == null) return null;
  return expression.computeConstantValue()?.value;
}

/// Follows local const aliases to their original resolved initializer.
/// Library and class constants keep their authoritative named declaration.
Expression installedNativeConstantExpression(Expression expression) {
  final seen = <Element>{};
  while (true) {
    if (expression is ParenthesizedExpression) {
      expression = expression.expression;
      continue;
    }
    final element = expression is SimpleIdentifier ? expression.element : null;
    if (element is! LocalVariableElement || !element.isConst) return expression;
    if (!seen.add(element) || seen.length > 64) {
      throw BuilderLoweringException(
          expression, 'Native constant alias exceeds its declaration limit');
    }
    final initializer = resolveConstDeclarationInitializer(expression);
    if (initializer == null) {
      throw BuilderLoweringException(expression,
          'Native constant alias requires its original declaration');
    }
    expression = initializer;
  }
}

/// A fixed executable invoked by an installed expression.
typedef InstalledNativeInvocation = ({
  ExecutableElement target,
  ArgumentList arguments,
});

/// Restricted lookup capabilities must keep their validated call site.
String? installedIntlLookupFamily(Element? element) {
  final member = element?.baseElement;
  return member?.enclosingElement?.name == 'Intl' &&
          (member?.library?.identifier.startsWith('package:intl/') ?? false) &&
          const {'message', 'plural', 'gender', 'select'}.contains(member?.name)
      ? member!.name
      : null;
}

/// Qualifies callable values before any inputs or adapters are installed.
List<InstalledNativeInvocation> qualifyInstalledNativeCallables(
    Expression expression,
    {required bool Function(Expression) isDeclaredCallable}) {
  final visitor = _NativeCallables(expression, isDeclaredCallable);
  expression.accept(visitor);
  return visitor.invocations;
}

/// Resolves only declarations and analyzer-proved constant callable values.
ExecutableElement? installedNativeCallableDeclaration(Expression expression) {
  final constant = installedNativeConstantValue(expression)?.toFunctionValue();
  if (constant != null) return constant;
  final element = _referenceElement(expression);
  return element is ExecutableElement && element is! PropertyAccessorElement
      ? element
      : null;
}

/// A statically resolved invocation; unknown callable values remain unproved.
InstalledNativeInvocation? installedNativeFixedInvocation(
    Expression expression) {
  final Expression reference;
  final ArgumentList arguments;
  if (expression is FunctionExpressionInvocation) {
    reference = expression.function;
    arguments = expression.argumentList;
  } else if (expression is MethodInvocation) {
    reference = expression.methodName.name == 'call' &&
            _callableType(expression.target?.staticType)
        ? expression.target!
        : expression.methodName;
    arguments = expression.argumentList;
  } else {
    return null;
  }
  final target = installedNativeCallableDeclaration(reference);
  return target == null ? null : (target: target, arguments: arguments);
}

bool _callableType(DartType? type) =>
    type is FunctionType || type?.isDartCoreFunction == true;

Element? _referenceElement(Expression expression) => switch (expression) {
      SimpleIdentifier() => expression.element,
      PrefixedIdentifier() => expression.identifier.element,
      PropertyAccess() => expression.propertyName.element,
      _ => null,
    };

final class _NativeCallables extends GeneralizingAstVisitor<void> {
  _NativeCallables(this.root, this.isDeclaredCallable);
  final Expression root;
  final bool Function(Expression) isDeclaredCallable;
  final invocations = <InstalledNativeInvocation>[];
  final qualified = <Expression>{};
  final resolving = <Element>{};

  Never refuse(AstNode node) => throw BuilderLoweringException(node,
      'Native callable requires a fixed declaration or an existing typed native binding');

  ExecutableElement? callable(Expression value, {bool invoked = false}) {
    qualified.add(value);
    if (value is ParenthesizedExpression) {
      return callable(value.expression, invoked: invoked);
    }
    if (value is FunctionReference) {
      return callable(value.function, invoked: invoked);
    }
    if (value is PostfixExpression && value.operator.lexeme == '!') {
      return callable(value.operand, invoked: invoked);
    }
    if (value is AsExpression) {
      return callable(value.expression, invoked: invoked);
    }
    if (value is ConditionalExpression) {
      // A selection may retain an existing capability, but cannot select a
      // restricted lookup declaration in place of a fixed call site.
      callable(value.thenExpression);
      callable(value.elseExpression);
      return null;
    }
    if (value is BinaryExpression && value.operator.lexeme == '??') {
      callable(value.leftOperand);
      callable(value.rightOperand);
      return null;
    }
    if (value is AssignmentExpression &&
        const {'=', '??='}.contains(value.operator.lexeme)) {
      if (!isDeclaredCallable(value.leftHandSide)) refuse(value);
      callable(value.leftHandSide);
      return callable(value.rightHandSide);
    }
    if (value is NullLiteral) return null;
    if (value is FunctionExpression) return null;
    final declaration = installedNativeCallableDeclaration(value);
    if (declaration != null) {
      if (declaration is LocalFunctionElement && !inside(declaration))
        refuse(value);
      return fixed(declaration, value, invoked: invoked);
    }
    final element = _referenceElement(value);
    // Only immutable declarations inside this inspected expression are followed.
    // External final/getter/factory values have no installed authority proof.
    if (element is LocalVariableElement && element.isFinal && inside(element)) {
      if (!resolving.add(element) || resolving.length > 64) refuse(value);
      final finder = _CallableInitializer(element);
      root.accept(finder);
      final initializer = finder.initializer;
      if (initializer == null) refuse(value);
      final result = callable(initializer, invoked: invoked);
      resolving.remove(element);
      return result;
    }
    final declaredType = switch (element) {
      VariableElement() => element.type,
      PropertyAccessorElement() => element.variable.type,
      _ => null,
    };
    if ((value.staticType ?? declaredType) is FunctionType &&
        isDeclaredCallable(value)) {
      return null;
    }
    return refuse(value);
  }

  bool inside(Element element) {
    final offset = element.firstFragment.nameOffset;
    return offset != null && offset >= root.offset && offset < root.end;
  }

  ExecutableElement fixed(ExecutableElement target, AstNode source,
      {required bool invoked}) {
    _requireClosedNativeCallable(target, source);
    if (!invoked && installedIntlLookupFamily(target) != null) {
      throw BuilderLoweringException(
          source, 'Intl lookup tearoffs require a fixed validated invocation');
    }
    return target;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_callableType(node.staticType)) callable(node);
    final member = node.methodName.element;
    ExecutableElement? target;
    if (node.methodName.name == 'call' &&
        node.target != null &&
        _callableType(node.target!.staticType)) {
      target = callable(node.target!, invoked: true);
    } else if (member is ExecutableElement &&
        member is! PropertyAccessorElement) {
      if (member is LocalFunctionElement && !inside(member)) {
        target = callable(node.methodName, invoked: true);
      } else {
        target = fixed(member, node, invoked: true);
      }
    } else {
      if (node.target != null &&
          node.target is! ThisExpression &&
          member is PropertyAccessorElement &&
          !member.isStatic) {
        refuse(node);
      }
      target = callable(node.methodName, invoked: true);
    }
    if (target != null) {
      invocations.add((target: target, arguments: node.argumentList));
    }
    node.target?.accept(this);
    node.typeArguments?.accept(this);
    node.argumentList.accept(this);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (_callableType(node.staticType)) callable(node);
    final target = callable(node.function, invoked: true);
    if (target != null) {
      invocations.add((target: target, arguments: node.argumentList));
    }
    node.function.accept(this);
    node.typeArguments?.accept(this);
    node.argumentList.accept(this);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    // A const tearoff may be invoked at a separately validated fixed call site.
    final initializer = node.initializer;
    if (node.declaredFragment?.element.isConst == true && initializer != null) {
      if (installedNativeConstantValue(initializer)?.toFunctionValue() !=
          null) {
        callable(initializer, invoked: true);
      }
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitNode(AstNode node) {
    if (node is Expression && !qualified.contains(node)) {
      final parent = node.parent;
      final selector = node is SimpleIdentifier &&
          (node.inDeclarationContext() ||
              parent is PrefixedIdentifier && parent.identifier == node ||
              parent is PropertyAccess && parent.propertyName == node ||
              parent is ConstructorName ||
              parent is NamedType);
      if (!selector) {
        if (_callableType(node.staticType)) {
          callable(node);
        } else if (installedNativeConstantValue(node) case final constant?) {
          _constantIdentity(constant, node, onCallable: (target) {
            fixed(target, node, invoked: false);
          });
        }
      }
    }
    super.visitNode(node);
  }
}

final class _CallableInitializer extends RecursiveAstVisitor<void> {
  _CallableInitializer(this.element);
  final Element element;
  Expression? initializer;
  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.declaredFragment?.element == element)
      initializer = node.initializer;
    super.visitVariableDeclaration(node);
  }
}

void _requireClosedNativeCallable(Element? element, AstNode source) {
  final declaration = element?.baseElement;
  if (declaration?.library?.identifier == 'dart:core' &&
      declaration?.enclosingElement?.name == 'Function' &&
      declaration?.name == 'apply') {
    throw BuilderLoweringException(source,
        'Function.apply generic dispatch is outside closed typed native calls');
  }
}

String _elementIdentity(Element element) {
  final names = <String>[];
  for (Element? current = element.baseElement;
      current != null && current is! LibraryElement;
      current = current.enclosingElement) {
    names.add(current.name ?? '<unnamed>');
  }
  return '${element.library?.identifier}#${names.reversed.join('.')}';
}

Object? _typeIdentity(DartType type) => {
      'kind': type.getDisplayString(),
      if (type.alias case final alias?)
        'alias': [
          _elementIdentity(alias.element),
          ...alias.typeArguments.map(_typeIdentity)
        ],
      if (type is InterfaceType) ...{
        'element': _elementIdentity(type.element),
        'arguments': type.typeArguments.map(_typeIdentity).toList(),
      },
      if (type is FunctionType) ...{
        'return': _typeIdentity(type.returnType),
        'parameters':
            type.formalParameters.map((p) => _typeIdentity(p.type)).toList(),
      },
      if (type is RecordType) ...{
        'positional':
            type.positionalFields.map((p) => _typeIdentity(p.type)).toList(),
        'named': {
          for (final p in type.namedFields) p.name: _typeIdentity(p.type)
        },
      },
      if (type is TypeParameterType)
        'parameter': _elementIdentity(type.element),
    };

Object? _constantIdentity(DartObject value, AstNode source,
    {int depth = 0, void Function(ExecutableElement)? onCallable}) {
  if (depth > 128)
    throw BuilderLoweringException(
        source, 'Native constant exceeds identity depth');
  Object? nested(DartObject? child) {
    if (child == null)
      throw BuilderLoweringException(
          source, 'Native constant identity is unresolved');
    return _constantIdentity(child, source,
        depth: depth + 1, onCallable: onCallable);
  }

  if (value.isNull) return null;
  final function = value.toFunctionValue();
  if (function != null) {
    _requireClosedNativeCallable(function, source);
    onCallable?.call(function);
    return {'function': _elementIdentity(function)};
  }
  final typeValue = value.toTypeValue();
  if (typeValue != null) return {'type': _typeIdentity(typeValue)};
  if (!value.hasKnownValue)
    throw BuilderLoweringException(
        source, 'Native constant identity is unresolved');
  final type = value.type;
  final Object? state;
  if (value.toBoolValue() case final scalar?) {
    state = scalar;
  } else if (value.toIntValue() case final scalar?) {
    state = scalar;
  } else if (value.toDoubleValue() case final scalar?) {
    state = scalar.toString();
  } else if (value.toStringValue() case final scalar?) {
    state = scalar;
  } else if (value.toSymbolValue() case final scalar?) {
    if (scalar.split('.').any((part) => part.startsWith('_'))) {
      throw BuilderLoweringException(source,
          'Private Symbol constants require their declaring-library identity');
    }
    state = {'symbol': scalar};
  } else if (value.toListValue() case final list?) {
    state = list.map(nested).toList();
  } else if (value.toSetValue() case final set?) {
    state = set.map(nested).toList();
  } else if (value.toMapValue() case final map?) {
    state = [
      for (final entry in map.entries) [nested(entry.key), nested(entry.value)]
    ];
  } else if (value.toRecordValue() case final record?) {
    state = {
      'positional': record.positional.map(nested).toList(),
      'named': {
        for (final name in record.named.keys.toList()..sort())
          name: nested(record.named[name])
      }
    };
  } else if (type is InterfaceType) {
    final fields = type.element.fields
        .where((f) => !f.isStatic && f.isOriginDeclaration)
        .toList()
      ..sort((a, b) => a.name!.compareTo(b.name!));
    state = {
      for (final field in fields)
        field.name!: nested(value.getField(field.name!)),
      if (value.getField('(super)') case final superclass?)
        '(super)': nested(superclass)
    };
  } else {
    throw BuilderLoweringException(
        source, 'Native constant identity is unsupported');
  }
  return {'type': type == null ? null : _typeIdentity(type), 'value': state};
}

final class _Provenance extends GeneralizingAstVisitor<void> {
  _Provenance(this.source);
  final Expression source;
  final symbols = <String>{};
  final constants = <Element>{};

  void element(Element? element) {
    if (element == null) return;
    _requireClosedNativeCallable(element, source);
    symbols.add(_elementIdentity(element));
    final variable =
        element is PropertyAccessorElement ? element.variable : element;
    if (variable is VariableElement &&
        variable.isConst &&
        constants.add(variable)) {
      final value = variable.computeConstantValue();
      if (value == null)
        throw BuilderLoweringException(
            source, 'Native constant identity is unresolved');
      symbols.add(
          'constant:${_elementIdentity(variable)}:${jsonEncode(_constantIdentity(value, source))}');
    }
  }

  @override
  void visitNode(AstNode node) {
    if (node is Expression) {
      final type = node.staticType;
      if (type != null) symbols.add('type:${jsonEncode(_typeIdentity(type))}');
    }
    if (node is SimpleIdentifier) element(node.element);
    if (node is NamedType) element(node.element);
    if (node is ConstructorReferenceNode) element(node.element);
    if (node is ExtensionOverride) element(node.element);
    if (node is BinaryExpression) element(node.element);
    if (node is PrefixExpression) element(node.element);
    if (node is PostfixExpression) element(node.element);
    if (node is AssignmentExpression) element(node.element);
    if (node is IndexExpression) element(node.element);
    if (node is Annotation) element(node.element);
    if (node is SymbolLiteral) {
      final value = installedNativeConstantValue(node);
      if (value != null)
        symbols.add('constant:${jsonEncode(_constantIdentity(value, node))}');
    }
    if (node is InstanceCreationExpression && node.isConst) {
      final value = installedNativeConstantValue(node);
      if (value == null)
        throw BuilderLoweringException(
            node, 'Native constant identity is unresolved');
      symbols.add('constant:${jsonEncode(_constantIdentity(value, node))}');
    }
    super.visitNode(node);
  }
}
