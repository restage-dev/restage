import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// The single expression a `build()`-style method [body] returns, or `null`
/// when [body] is not a single returned expression — it has non-const locals,
/// multiple statements, control flow, or a value-less `return;`.
///
/// `createState()` and helper bodies keep this strict contract; source build
/// bodies use [extractInlinableBuildBody] to capture leading final locals.
Expression? singleReturnExpressionOf(FunctionBody body) {
  // Shares the body-shape walk with [extractInlinableBuildBody]; the stricter
  // contract here is that a leading `final` local still disqualifies the body
  // (only `const` locals, which fold to literals, are permitted before the
  // single return). So accept the extracted return expression only when no
  // `final` local was captured.
  final extracted = extractInlinableBuildBody(body);
  if (extracted == null || extracted.finalLocals.isNotEmpty) return null;
  return extracted.expression;
}

/// The single returned [expression] of a custom-widget `build()`, plus the
/// leading `final` local declarations ([finalLocals]) the classifier inlines
/// at their use sites.
class InlinableBuildBody {
  /// Creates an extracted build body.
  const InlinableBuildBody({
    required this.expression,
    required this.declarations,
    required this.finalLocals,
  });

  /// The single returned expression.
  final Expression expression;

  /// Every leading `const` or `final` declaration.
  final List<VariableDeclaration> declarations;

  /// Leading `final` local declarations to inline (each has an initializer).
  /// `const` locals are NOT listed — a reference to one folds to its literal
  /// value at the use site, so it needs no inlining.
  final List<VariableDeclaration> finalLocals;

  /// [finalLocals] keyed by declared element — so a local shadowing a
  /// parameter or field still resolves to the local.
  Map<Element, Expression> get localBindings => {
        for (final variable in finalLocals)
          if (variable.declaredFragment?.element case final element?)
            if (variable.initializer case final initializer?)
              element: initializer,
      };
}

/// Extracts one returned expression after initialized simple `final` or
/// `const` declarations; every other body shape returns `null`.
InlinableBuildBody? extractInlinableBuildBody(FunctionBody body) =>
    _inspectBuildBody(body).body;

/// Names the leading declaration that refuses [body] in a way the author fixes
/// in place — grouped, or missing its initializer — or `null`.
String? preludeDeclarationProblem(FunctionBody body) =>
    _inspectBuildBody(body).declarationProblem;

({InlinableBuildBody? body, String? declarationProblem}) _inspectBuildBody(
  FunctionBody body,
) {
  const refused = (body: null, declarationProblem: null);
  if (body is ExpressionFunctionBody) {
    return (
      body: InlinableBuildBody(
        expression: body.expression,
        declarations: const [],
        finalLocals: const [],
      ),
      declarationProblem: null,
    );
  }
  if (body is! BlockFunctionBody) return refused;
  final statements = body.block.statements;
  if (statements.isEmpty) return refused;
  final last = statements.last;
  if (last is! ReturnStatement) return refused;
  final returnExpr = last.expression;
  if (returnExpr == null) return refused;
  final declarations = <VariableDeclaration>[];
  final finalLocals = <VariableDeclaration>[];
  for (final stmt in statements.take(statements.length - 1)) {
    if (stmt is! VariableDeclarationStatement) return refused;
    if (stmt.variables.lateKeyword != null) return refused;
    final keyword = stmt.variables.keyword?.lexeme;
    if (keyword != 'const' && keyword != 'final') return refused;
    final variables = stmt.variables.variables;
    if (variables.length != 1) {
      final names =
          variables.map((variable) => variable.name.lexeme).join(', ');
      return (
        body: null,
        declarationProblem: "the grouped declaration '$names'; split it into "
            'one declaration per variable',
      );
    }
    final variable = variables.single;
    if (variable.initializer == null) {
      return (body: null, declarationProblem: _kUninitializedDeclaration);
    }
    declarations.add(variable);
    if (keyword == 'final') finalLocals.add(variable);
  }
  return (
    body: InlinableBuildBody(
      expression: returnExpr,
      declarations: declarations,
      finalLocals: finalLocals,
    ),
    declarationProblem: null,
  );
}

const String _kUninitializedDeclaration =
    'a const or final local has no resolved declaration or initializer; '
    'initialize one simple variable per declaration';

/// Returns why [body]'s local bindings are unsafe to inline, or `null`.
String? inlinableBuildBodyProblem(InlinableBuildBody body) {
  for (final variable in body.declarations) {
    if (variable.initializer == null ||
        variable.declaredFragment?.element == null) {
      return _kUninitializedDeclaration;
    }
  }
  final bindings = body.localBindings;
  if (bindings.length != body.finalLocals.length) {
    return 'the final locals in build() could not be resolved uniquely; '
        'initialize one simple final variable per declaration';
  }
  if (bindings.isEmpty) return null;

  final bindingElements = bindings.keys.toSet();
  final sourceDependencies = _bindingDependencies(bindings, bindingElements);

  final active = <Element>{};
  final complete = <Element>{};
  bool reachesCycle(Element element) {
    if (complete.contains(element)) return false;
    if (!active.add(element)) return true;
    for (final dependency in sourceDependencies[element] ?? const <Element>{}) {
      if (reachesCycle(dependency)) return true;
    }
    active.remove(element);
    complete.add(element);
    return false;
  }

  for (final element in bindings.keys) {
    if (reachesCycle(element)) {
      return "the local '${element.name ?? '<unnamed>'}' participates in a "
          'cyclic build() binding; rewrite the final locals without cycles';
    }
  }

  // Value reachability follows the emitted output, which discards key operands;
  // source reachability follows the authored text, and the two together tell a
  // local nothing reads from one only a discarded key reads.
  final valueReachable = _reachableBindings(
    _referencedBindings(
      body.expression,
      bindingElements,
      discardWidgetKeys: true,
    ),
    _bindingDependencies(bindings, bindingElements, discardWidgetKeys: true),
  );
  final sourceReachable = _reachableBindings(
    _referencedBindings(body.expression, bindingElements),
    sourceDependencies,
  );
  for (final element in bindings.keys) {
    if (valueReachable.contains(element)) continue;
    final name = element.name ?? '<unnamed>';
    return sourceReachable.contains(element)
        ? "the local '$name' is read only as a widget key, and compiled output "
            'discards key operands; inline the key expression or remove the '
            'local together with its key: argument'
        : "the local '$name' is declared in build() but never read; remove it "
            'or use it';
  }
  return null;
}

Set<Element> _reachableBindings(
  Set<Element> roots,
  Map<Element, Set<Element>> dependencies,
) {
  final reachable = <Element>{};
  final pending = roots.toList();
  while (pending.isNotEmpty) {
    final element = pending.removeLast();
    if (!reachable.add(element)) continue;
    pending.addAll(dependencies[element] ?? const <Element>{});
  }
  return reachable;
}

Map<Element, Set<Element>> _bindingDependencies(
  Map<Element, Expression> bindings,
  Set<Element> bindingElements, {
  bool discardWidgetKeys = false,
}) =>
    {
      for (final entry in bindings.entries)
        entry.key: _referencedBindings(
          entry.value,
          bindingElements,
          discardWidgetKeys: discardWidgetKeys,
        ),
    };

/// Whether [argument] is a Flutter widget's runtime-only `key:` argument.
bool isDiscardedWidgetKeyArgument(NamedExpression argument) {
  if (argument.name.label.name != 'key') return false;
  final parameter = argument.name.label.element;
  if (parameter is! FormalParameterElement ||
      !_isFlutterKeyType(parameter.type)) {
    return false;
  }
  final constructor = parameter.enclosingElement;
  if (constructor is! ConstructorElement) return false;
  final owner = constructor.enclosingElement;
  if (owner is! ClassElement) return false;
  return _isFlutterWidgetClass(owner);
}

Set<Element> _referencedBindings(
  Expression expression,
  Set<Element> bindings, {
  bool discardWidgetKeys = false,
}) {
  final collector = _ReferencedBindingCollector(
    bindings,
    discardWidgetKeys: discardWidgetKeys,
  );
  expression.accept(collector);
  return collector.elements;
}

final class _ReferencedBindingCollector extends RecursiveAstVisitor<void> {
  _ReferencedBindingCollector(
    this.bindings, {
    required this.discardWidgetKeys,
  });

  final Set<Element> bindings;
  final bool discardWidgetKeys;
  final Set<Element> elements = {};

  @override
  void visitNamedExpression(NamedExpression node) {
    if (discardWidgetKeys && isDiscardedWidgetKeyArgument(node)) return;
    super.visitNamedExpression(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element != null && bindings.contains(element)) elements.add(element);
    super.visitSimpleIdentifier(node);
  }
}

bool _isFlutterKeyType(DartType type) {
  final seenTypeParameters = <TypeParameterElement>{};
  var candidateType = type;
  while (candidateType is TypeParameterType) {
    if (!seenTypeParameters.add(candidateType.element)) return false;
    candidateType = candidateType.bound;
  }
  if (candidateType is! InterfaceType) return false;
  return <InterfaceType>[candidateType, ...candidateType.allSupertypes].any(
    (candidate) =>
        candidate.element.name == 'Key' &&
        candidate.element.library.identifier.startsWith('package:flutter/'),
  );
}

bool _isFlutterWidgetClass(ClassElement element) {
  ClassElement? current = element;
  while (current != null) {
    if (current.name == 'Widget' &&
        current.library.identifier.startsWith('package:flutter/')) {
      return true;
    }
    final superclass = current.supertype?.element;
    current = superclass is ClassElement ? superclass : null;
  }
  return false;
}
