// The analyzer has no public API for building resolved nodes, so this file
// owns every `package:analyzer/src` import in the package.
// ignore_for_file: implementation_imports

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/ast/token.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:build/build.dart';

final Expando<bool> _expanded = Expando('dotShorthandsExpanded');

/// Rewrites every resolved dot shorthand in [node]'s compilation unit to the
/// long form it resolved to, in place, so `.center` reads as
/// `Alignment.center` to every later pass. Unresolved shorthands are kept.
void expandDotShorthands(AstNode? node) {
  if (node == null) return;
  final root = node.root;
  if (_expanded[root] ?? false) return;
  _expanded[root] = true;
  final collector = _ShorthandCollector();
  root.accept(collector);
  // Post-order: inner shorthands are replaced before the ones enclosing them.
  for (final shorthand in collector.found) {
    final longForm = _longForm(shorthand);
    if (longForm == null) continue;
    (shorthand.parent! as AstNodeImpl).replaceChild(
      shorthand as AstNodeImpl,
      longForm,
    );
  }
}

/// Expands the shorthands of every unit in a resolved library.
void expandLibraryDotShorthands(Iterable<CompilationUnit> units) {
  units.forEach(expandDotShorthands);
}

final class _ShorthandCollector extends RecursiveAstVisitor<void> {
  final List<Expression> found = [];

  @override
  void visitDotShorthandConstructorInvocation(
    DotShorthandConstructorInvocation node,
  ) {
    super.visitDotShorthandConstructorInvocation(node);
    found.add(node);
  }

  @override
  void visitDotShorthandInvocation(DotShorthandInvocation node) {
    super.visitDotShorthandInvocation(node);
    found.add(node);
  }

  @override
  void visitDotShorthandPropertyAccess(DotShorthandPropertyAccess node) {
    super.visitDotShorthandPropertyAccess(node);
    found.add(node);
  }
}

ExpressionImpl? _longForm(Expression node) => switch (node) {
      DotShorthandConstructorInvocationImpl() => _constructorInvocation(node),
      DotShorthandInvocationImpl() => _methodInvocation(node),
      DotShorthandPropertyAccessImpl() => _propertyAccess(node),
      _ => null,
    };

InstanceCreationExpressionImpl? _constructorInvocation(
  DotShorthandConstructorInvocationImpl node,
) {
  final element = node.element;
  if (element == null) return null;
  final target = _redirectTarget(element);
  if (target is! InternalConstructorElement) return null;
  // Keeps the instantiated type unless a redirect changed the class built.
  final type = identical(target, element)
      ? node.staticType ?? target.returnType
      : target.returnType;
  final period = node.period;
  final owner = target.enclosingElement;
  final namedType = NamedTypeImpl(
    importPrefix: null,
    name: _ownerToken(owner, period),
    typeArguments: null,
    question: null,
  )
    ..element = owner
    ..type = type;
  final unnamed = target.name == null || target.name == 'new';
  final name = ConstructorNameImpl(
    type: namedType,
    period: unnamed ? null : period,
    name: unnamed ? null : _renamed(node.constructorName, target),
  )..element = target;
  return InstanceCreationExpressionImpl(
    keyword: node.constKeyword,
    constructorName: name,
    typeArguments: node.typeArguments,
    argumentList: node.argumentList,
  )..setPseudoExpressionStaticType(type);
}

MethodInvocationImpl? _methodInvocation(DotShorthandInvocationImpl node) {
  final owner = node.memberName.element?.enclosingElement;
  if (owner == null) return null;
  return MethodInvocationImpl(
    target: _ownerIdentifier(owner, node.period),
    operator: node.period,
    methodName: node.memberName,
    typeArguments: node.typeArguments,
    argumentList: node.argumentList,
  )
    ..staticInvokeType = node.staticInvokeType
    ..setPseudoExpressionStaticType(node.staticType);
}

PrefixedIdentifierImpl? _propertyAccess(DotShorthandPropertyAccessImpl node) {
  final element = node.propertyName.element;
  if (element == null) return null;
  final target = _aliasTarget(element);
  final owner = target.enclosingElement;
  if (owner == null) return null;
  final type = switch (target) {
    PropertyAccessorElement(:final returnType) => returnType,
    _ => node.staticType,
  };
  final identifier = _renamed(node.propertyName, target)
    ..setPseudoExpressionStaticType(type);
  return PrefixedIdentifierImpl(
    prefix: _ownerIdentifier(owner, node.period),
    period: node.period,
    identifier: identifier,
  )..setPseudoExpressionStaticType(type);
}

/// Follows public redirecting factories to the constructor that builds the
/// value, so `.all(4)` in an `EdgeInsetsGeometry` slot reads as
/// `EdgeInsets.all(4)`.
ConstructorElement _redirectTarget(ConstructorElement constructor) {
  final seen = <ConstructorElement>{};
  var current = constructor;
  while (current.isFactory && seen.add(current.baseElement)) {
    final next = current.redirectedConstructor;
    if (next == null || next.isPrivate || next.enclosingElement.isPrivate) {
      break;
    }
    current = next;
  }
  return current;
}

/// Follows static constants that alias a member of a subtype, so `.center`
/// in an `AlignmentGeometry` slot reads as `Alignment.center`.
Element _aliasTarget(Element element) {
  final seen = <Element>{};
  var current = element;
  while (seen.add(current)) {
    final variable = switch (current) {
      PropertyAccessorElement(:final variable) => variable,
      _ => null,
    };
    if (variable == null || !variable.isStatic || !variable.isConst) break;
    var initializer = variable.constantInitializer;
    while (initializer is ParenthesizedExpression) {
      initializer = initializer.expression;
    }
    final referenced = switch (initializer) {
      PrefixedIdentifier(:final identifier) => identifier.element,
      PropertyAccess(:final propertyName) => propertyName.element,
      _ => null,
    };
    if (referenced is! PropertyAccessorElement ||
        !referenced.isStatic ||
        referenced.isPrivate ||
        referenced.enclosingElement is! InterfaceElement ||
        referenced.enclosingElement.isPrivate ||
        !_isSubtypeOwner(
            referenced.enclosingElement, current.enclosingElement)) {
      break;
    }
    current = referenced;
  }
  return current;
}

bool _isSubtypeOwner(Element? owner, Element? of) =>
    owner is InterfaceElement &&
    of is InterfaceElement &&
    owner != of &&
    owner.allSupertypes.any((type) => type.element == of);

/// [identifier] naming [target], spanning the same source range.
SimpleIdentifierImpl _renamed(SimpleIdentifierImpl identifier, Element target) {
  final name = target.name;
  if (name == null || name == identifier.name) {
    return identifier..element = target;
  }
  return SimpleIdentifierImpl(
    token: SyntheticStringToken(
      TokenType.IDENTIFIER,
      name,
      identifier.offset,
      identifier.length,
    ),
  )..element = target;
}

SimpleIdentifierImpl _ownerIdentifier(Element owner, Token period) =>
    SimpleIdentifierImpl(token: _ownerToken(owner, period))..element = owner;

// Zero-length at the period, so the long form keeps the shorthand's span.
StringToken _ownerToken(Element owner, Token period) => SyntheticStringToken(
      TokenType.IDENTIFIER,
      owner.name ?? '',
      period.offset,
      0,
    );

/// Resolves [library] with its dot shorthands in long form.
Future<SomeResolvedLibraryResult> resolveLibraryInLongForm(
  LibraryElement library,
) async {
  final result = await library.session.getResolvedLibraryByElement(library);
  if (result is ResolvedLibraryResult) {
    expandLibraryDotShorthands(result.units.map((unit) => unit.unit));
  }
  return result;
}

/// Resolves [fragment]'s declaration through [resolver] in long form.
Future<AstNode?> resolvedNodeInLongForm(
  Resolver resolver,
  Fragment fragment,
) async {
  final node = await resolver.astNodeFor(fragment, resolve: true);
  expandDotShorthands(node);
  return node;
}
