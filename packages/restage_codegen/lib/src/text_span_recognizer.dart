import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/lowering_targets.dart';
import 'package:restage_shared/restage_shared.dart'
    show kTextSpanRecognizerVoidCallbacks, kTextSpanRecognizerDetailCallbacks;

/// An analyzed native recognizer constructor and its simple assignments.
final class TextSpanRecognizerRecipe {
  TextSpanRecognizerRecipe({
    required this.kind,
    required this.constructor,
    required this.configuration,
    required this.callbacks,
    required this.callbackElements,
  });

  /// Wire discriminator for the exact native type.
  final String kind;

  /// Fresh constructor expression that establishes object identity.
  final Expression constructor;

  /// Supported constructor arguments, preserving supplied nulls.
  final Map<String, Expression> configuration;

  /// Native callback assignments in source order.
  final Map<String, Expression> callbacks;

  /// Resolved native callback setters for occurrence attribution.
  final Map<String, Element?> callbackElements;
}

/// Existing references borrow their owner's recognizer without changing it.
bool isBorrowedTextSpanRecognizer(Expression source) {
  var expression = source;
  while (expression is ParenthesizedExpression) {
    expression = expression.expression;
  }
  if (expression is! SimpleIdentifier &&
      expression is! PrefixedIdentifier &&
      expression is! PropertyAccess) return false;
  final element = switch (expression) {
    SimpleIdentifier() => expression.element,
    PrefixedIdentifier() => expression.element,
    PropertyAccess() => expression.propertyName.element,
    _ => null,
  };
  final variable =
      element is PropertyAccessorElement ? element.variable : element;
  if (element is PropertyAccessorElement && !element.isOriginVariable)
    return false;
  if (variable is! VariableElement) return false;
  if (expression is PropertyAccess &&
      !_isExistingRecognizerOwner(expression.target)) return false;
  final type = expression.staticType;
  if (type is! InterfaceType) return false;
  return [type, ...type.allSupertypes].any(
    (type) =>
        type.element.name == 'GestureRecognizer' &&
        type.element.library.identifier ==
            'package:flutter/src/gestures/recognizer.dart',
  );
}

bool _isExistingRecognizerOwner(Expression? expression) {
  if (expression is ParenthesizedExpression)
    return _isExistingRecognizerOwner(expression.expression);
  if (expression is ThisExpression) return true;
  final element = switch (expression) {
    SimpleIdentifier() => expression.element,
    PrefixedIdentifier() => expression.element,
    PropertyAccess() => expression.propertyName.element,
    _ => null,
  };
  if (element is PropertyAccessorElement && !element.isOriginVariable)
    return false;
  if (element is! VariableElement && element is! PropertyAccessorElement)
    return false;
  if (expression is PropertyAccess)
    return _isExistingRecognizerOwner(expression.target);
  if (expression is PrefixedIdentifier &&
      expression.prefix.element is! PrefixElement)
    return _isExistingRecognizerOwner(expression.prefix);
  return true;
}

/// Refuses subclasses and executable recognizer configuration.
TextSpanRecognizerRecipe readTextSpanRecognizer(
  Expression source, {
  required Expression Function(Expression) resolve,
  Iterable<Expression> bindings = const [],
}) {
  Expression unwrap(Expression value) {
    var current = resolve(value);
    while (current is ParenthesizedExpression) {
      current = resolve(current.expression);
    }
    return current;
  }

  final expression = unwrap(source);
  final target = unwrap(
    expression is CascadeExpression ? expression.target : expression,
  );
  String? name;
  String? member;
  InterfaceElement? element;
  late NodeList<Argument> arguments;
  if (target is InstanceCreationExpression) {
    name = instanceCreationTypeName(target);
    member = instanceCreationMemberName(target);
    final resolved = target.constructorName.type.element;
    element = resolved is InterfaceElement ? resolved : null;
    if (element != null) {
      name = element.name;
      member = target.constructorName.element == element.unnamedConstructor
          ? null
          : member ?? 'named';
    }
    arguments = target.argumentList.arguments;
  } else if (target is MethodInvocation && target.target == null) {
    name = target.methodName.name;
    final resolved = target.methodName.element;
    if (resolved is ConstructorElement) element = resolved.enclosingElement;
    if (resolved != null && element == null)
      throw ArgumentError(
        'The recognizer must be a native Flutter constructor.',
      );
    arguments = target.argumentList.arguments;
  } else {
    throw ArgumentError(
      'TextSpan.recognizer requires a fresh native constructor cascade.',
    );
  }
  final (kind, origin) = switch (name) {
    'TapGestureRecognizer' => ('tap', 'package:flutter/src/gestures/tap.dart'),
    'DoubleTapGestureRecognizer' => (
        'doubleTap',
        'package:flutter/src/gestures/multitap.dart',
      ),
    'LongPressGestureRecognizer' => (
        'longPress',
        'package:flutter/src/gestures/long_press.dart',
      ),
    _ => throw ArgumentError(
        'Only native tap, double-tap, and long-press recognizers are supported.',
      ),
  };
  if (member != null ||
      (element != null &&
          (element.library.identifier != origin || element.name != name))) {
    throw ArgumentError(
      'The recognizer must resolve to its exact native Flutter constructor.',
    );
  }
  final config = <String, Expression>{};
  final callbacks = <String, Expression>{};
  final callbackElements = <String, Element?>{};
  final constructorFields = {
    'supportedDevices',
    if (kind == 'tap') ...['preAcceptSlopTolerance', 'postAcceptSlopTolerance'],
    if (kind == 'longPress') ...['duration', 'postAcceptSlopTolerance'],
  };
  for (final argument in arguments) {
    if (argument is! NamedArgument)
      throw ArgumentError('Recognizer constructor arguments must be named.');
    final field = argument.name.lexeme;
    final value = unwrap(argument.argumentExpression);
    if ((field == 'debugOwner' ||
            (field == 'allowedButtonsFilter' && kind == 'longPress')) &&
        value is NullLiteral) continue;
    if (!constructorFields.contains(field))
      throw ArgumentError(
        'Unsupported recognizer constructor argument: $field.',
      );
    config[field] = value;
  }
  if (expression is CascadeExpression) {
    for (final section in expression.cascadeSections) {
      if (section is! AssignmentExpression || section.operator.lexeme != '=') {
        throw ArgumentError(
          'Recognizer cascades support only simple field assignments.',
        );
      }
      final left = section.leftHandSide;
      if (left is! PropertyAccess || !left.isCascaded)
        throw ArgumentError('Unsupported recognizer assignment.');
      final field = left.propertyName.name;
      if (!kTextSpanRecognizerVoidCallbacks[kind]!.contains(field) &&
          !kTextSpanRecognizerDetailCallbacks[kind]!.containsKey(field)) {
        throw ArgumentError(
          'Unsupported recognizer field $field.',
        );
      }
      if (callbacks.containsKey(field))
        throw ArgumentError(
          'A recognizer callback cannot be assigned more than once.',
        );
      callbacks[field] = section.rightHandSide;
      callbackElements[field] =
          section.writeElement ?? left.propertyName.element;
    }
  }
  _requireSingleLocalUse(source);
  _requireSingleLocalUse(target);
  for (final binding in bindings) {
    final resolved = unwrap(binding);
    final boundTarget =
        resolved is CascadeExpression ? unwrap(resolved.target) : resolved;
    if (identical(boundTarget, target)) _requireSingleLocalUse(binding);
  }
  return TextSpanRecognizerRecipe(
    kind: kind,
    constructor: target,
    configuration: config,
    callbacks: callbacks,
    callbackElements: callbackElements,
  );
}

void _requireSingleLocalUse(Expression expression) {
  final visited = <Element>{};

  AstNode scopeFor(AstNode node) {
    var scope = node;
    while (scope.parent != null &&
        scope is! FunctionExpression &&
        scope is! MethodDeclaration &&
        scope is! CompilationUnit) {
      scope = scope.parent!;
    }
    return scope;
  }

  VariableDeclaration? containingValue(AstNode node) {
    for (var parent = node.parent; parent != null; parent = parent.parent) {
      if (parent is VariableDeclaration) return parent;
      if (parent is FunctionExpression ||
          parent is MethodDeclaration ||
          parent is CompilationUnit) return null;
    }
    return null;
  }

  void check(Element element, AstNode source) {
    if (!visited.add(element)) return;
    final uses = _RecognizerLocalUses(element);
    scopeFor(source).accept(uses);
    if (uses.references.length > 1) {
      throw ArgumentError(
        'A recognizer or its containing value cannot be shared across multiple uses.',
      );
    }
    for (final reference in uses.references) {
      final owner = uses.declaration;
      if (owner != null && !identical(scopeFor(owner), scopeFor(reference))) {
        throw ArgumentError(
          'A captured recognizer value requires proven installed ownership.',
        );
      }
      for (var parent = reference.parent;
          parent != null && !identical(parent, scopeFor(reference));
          parent = parent.parent) {
        if ((parent is ForElement ||
                parent is ForStatement ||
                parent is WhileStatement ||
                parent is DoStatement) &&
            (owner == null ||
                owner.offset < parent.offset ||
                owner.end > parent.end)) {
          throw ArgumentError(
            'A recognizer or its containing value cannot be shared across repeated uses.',
          );
        }
      }
      final declaration = containingValue(reference);
      final alias = declaration?.declaredFragment?.element;
      if (alias != null) check(alias, declaration!);
    }
  }

  if (expression is SimpleIdentifier) {
    final element = expression.element;
    if (element != null) check(element, expression);
  }
  final declaration = containingValue(expression);
  final element = declaration?.declaredFragment?.element;
  if (element != null) check(element, declaration!);
}

final class _RecognizerLocalUses extends RecursiveAstVisitor<void> {
  _RecognizerLocalUses(this.element);
  final Element element;
  final references = <SimpleIdentifier>[];
  VariableDeclaration? declaration;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.declaredFragment?.element == element) declaration = node;
    super.visitVariableDeclaration(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element == element) references.add(node);
  }
}
