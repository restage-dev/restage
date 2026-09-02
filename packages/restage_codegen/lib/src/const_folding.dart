import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

/// Evaluates [expr] to a compile-time-constant scalar — an [int], [double],
/// [bool], or [String] — or returns `null` when [expr] is not a constant this
/// codegen increment folds.
///
/// This is the single constant-folding boundary the classifier (to tag the
/// `constantFolding` mechanism) and the translator (to emit a folded literal)
/// both consult, so the two never diverge. Foldable: literals; references to
/// `const` variables / fields; and `+ - * / ~/ %` (plus unary `-`) over
/// folded operands — `+` also concatenates two folded Strings. Anything else
/// — a runtime value, an enum constant, an unfolded operator — yields `null`.
Object? tryFoldConstant(Expression expr) {
  if (expr is IntegerLiteral) return expr.value;
  // An overflowing literal (`1e400`) parses to a non-finite double, which has
  // no representable RFW (or JSON) value. Filter it here so it never folds to a
  // bare `Infinity` — matching the sibling fold arms (`decodeConstScalar`,
  // `_foldBinary`) and the translator's emit guard. The state-field / setState
  // path consumes folds directly, so this is the only point that closes that
  // path's non-finite-literal escape.
  if (expr is DoubleLiteral) return expr.value.isFinite ? expr.value : null;
  if (expr is BooleanLiteral) return expr.value;
  if (expr is SimpleStringLiteral) return expr.value;
  if (expr is ParenthesizedExpression) return tryFoldConstant(expr.expression);
  if (expr is PrefixExpression) return _foldPrefix(expr);
  if (expr is BinaryExpression) return _foldBinary(expr);
  if (expr is SimpleIdentifier) return _foldConstReference(expr.element);
  if (expr is PrefixedIdentifier) {
    return _foldConstReference(expr.identifier.element);
  }
  return null;
}

/// Folds a unary-minus over a folded numeric operand; any other prefix
/// operator is not foldable.
Object? _foldPrefix(PrefixExpression expr) {
  if (expr.operator.lexeme != '-') return null;
  final operand = tryFoldConstant(expr.operand);
  if (operand is int) return -operand;
  if (operand is double) return -operand;
  return null;
}

/// Folds an arithmetic binary expression over two folded operands. `+` over
/// two Strings concatenates; every other operator requires numeric operands.
Object? _foldBinary(BinaryExpression expr) {
  final left = tryFoldConstant(expr.leftOperand);
  final right = tryFoldConstant(expr.rightOperand);
  if (left == null || right == null) return null;
  if (expr.operator.lexeme == '+' && left is String && right is String) {
    return left + right;
  }
  if (left is! num || right is! num) return null;
  final num? value;
  switch (expr.operator.lexeme) {
    case '+':
      value = left + right;
    case '-':
      value = left - right;
    case '*':
      value = left * right;
    case '/':
      value = left / right;
    case '~/':
      // `~/` and `%` by zero throw — leave such an expression unfolded.
      value = right == 0 ? null : left ~/ right;
    case '%':
      value = right == 0 ? null : left % right;
    default:
      value = null;
  }
  if (value == null) return null;
  // A non-finite result (a `/ 0` infinity, an overflow) has no RFW literal.
  if (value is double && !value.isFinite) return null;
  return value;
}

/// Folds a reference whose [element] is a `const` variable or field to its
/// constant value. An enum constant yields `null` — the translator emits it
/// as a bare name through its own enum path, not as a folded literal.
Object? _foldConstReference(Element? element) {
  var resolved = element;
  if (resolved is PropertyAccessorElement) {
    resolved = resolved.variable;
  }
  if (resolved is FieldElement) {
    if (!resolved.isConst || resolved.isEnumConstant) return null;
    return _foldConstValue(resolved);
  }
  if (resolved is TopLevelVariableElement) {
    if (!resolved.isConst) return null;
    return _foldConstValue(resolved);
  }
  // A `const` local declared in the `build()` body — the body-shape rule
  // (`singleReturnExpressionOf`) allows leading const locals before the single
  // return, and a reference to one folds to its literal value here. A `final` /
  // `var` local is not const → folds to null → never reaches a transpilable
  // body.
  if (resolved is LocalVariableElement) {
    if (!resolved.isConst) return null;
    return _foldConstValue(resolved);
  }
  return null;
}

/// The scalar value of const [element], or `null` when that value comes from
/// the build environment — see [dependsOnBuildEnvironment].
Object? _foldConstValue(VariableElement element) =>
    dependsOnBuildEnvironment(element)
        ? null
        : decodeConstScalar(element.computeConstantValue());

/// Decodes a constant [value] to a plain scalar — [int], [double], [bool], or
/// [String] — or `null` for any other shape. Shared with the
/// `@RestageProperty` default-value decoder, so both read a constant the same
/// way.
///
/// A non-finite double (`infinity` / `NaN`) decodes to `null`: it has no
/// representable RFW (or JSON) literal, and `infinity` as an operand throws
/// the `~/` operator — so it must not flow on as a foldable scalar.
Object? decodeConstScalar(DartObject? value) {
  if (value == null) return null;
  final number = value.toIntValue() ?? value.toDoubleValue();
  if (number != null) {
    if (number is double && !number.isFinite) return null;
    return number;
  }
  return value.toBoolValue() ?? value.toStringValue();
}

/// Whether const [element]'s value comes from the build environment — a
/// `fromEnvironment` / `hasEnvironment` constant anywhere in its initializer
/// graph, which covers the framework's build-mode constants. Folding one would
/// bake a build-time answer into published output, so callers refuse the fold.
bool dependsOnBuildEnvironment(Element element) {
  final seen = Set<Element>.identity();
  final pending = <Element>[element];
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    if (!seen.add(current) || current is! VariableElement) continue;
    final initializer = current.constantInitializer;
    if (initializer == null) continue;
    final scan = _BuildEnvironmentScan();
    initializer.accept(scan);
    if (scan.found) return true;
    pending.addAll(scan.references);
  }
  return false;
}

/// Finds a direct environment constant in one initializer, and collects the
/// declarations it names so the caller can follow them.
final class _BuildEnvironmentScan extends RecursiveAstVisitor<void> {
  bool found = false;
  final List<Element> references = [];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructor = node.constructorName.element;
    final name = constructor?.name;
    if ((name == 'fromEnvironment' || name == 'hasEnvironment') &&
        (constructor?.library.isDartCore ?? false)) {
      found = true;
      return;
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = _unwrapAccessor(node.element);
    if (element != null) references.add(element);
    super.visitSimpleIdentifier(node);
  }
}

/// Returns the bare name of an enum constant when [expr] is a `Foo.bar`
/// reference whose `bar` resolves to an `EnumElement.isEnumConstant`. An
/// enum constant has no scalar value (so [tryFoldConstant] returns null on
/// one), but its bare name is the form the translator emits — and the
/// classifier captures as a State-field initial value. Returns `null` when
/// [expr] is not an enum constant reference.
String? enumConstantName(Expression expr) {
  if (expr is! PrefixedIdentifier) return null;
  final element = expr.identifier.element;
  final resolved =
      element is PropertyAccessorElement ? element.variable : element;
  if (resolved is FieldElement && resolved.isEnumConstant) {
    return expr.identifier.name;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Const-object field access — the structured-reference sibling of
// [tryFoldConstant].
//
// A reference to an INSTANCE field of a `const` VALUE — `const _skin =
// BrandSkin(headline: 'X', primary: Color(0xFF112233)); … _skin.headline` —
// is a compile-time constant, but [tryFoldConstant] declines it: the field
// element is a (non-const) instance field, and `decodeConstScalar` decodes
// only scalars (so a `Color` field never folds via a reference). Such a
// reference therefore used to fall through every translator arm to the
// enum-name fallback and emit the FIELD NAME — a silent wrong-render for a
// String slot, a loud type-mismatch for a structured slot.
//
// These three functions close that class. They are [tryFoldConstant]'s
// co-consulted siblings: BOTH the classifier (to tag the fold transpilable /
// defer consistently) and the translator (to fold or loud-defer) consult the
// same boundary, so the two never diverge on what folds. [tryFoldConstant]
// keeps its scalar-only contract untouched.
//
// The discriminator is the safety crux: the RECEIVER must be a const VALUE (a
// const top-level / local variable, or a static-const field, holding an
// instance — or itself a const-object field access) AND the IDENTIFIER must be
// an INSTANCE field of that value. An enum reference (the prefix is a TYPE, the
// identifier an enum constant) and a static-const
// reference (`Tokens.gap`, `Palette.brand` — the identifier is a STATIC field)
// are NOT const-object field accesses and stay on their existing paths. A
// non-const (`final` / runtime) receiver is likewise not recognised — it is a
// runtime read this fold cannot serve.
//
// Folding is a hybrid: β (AST substitution) where the bound initializer
// expression is reachable in the same compilation unit — re-translated through
// the existing value recipes, so the fold is byte-identical to the inline
// literal by construction, scalar AND structured; α (DartObject scalar fold)
// as the cross-file / defaulted-field fallback — scalar only, deliberately no
// structured DartObject→DSL emitter (that is where divergence/duplication would
// creep in; β owns structured). A recognised const-object field access that
// neither β nor α can fold must be deferred LOUD by the caller — never the
// silent field-name emit.

/// Whether [expr] is a const-object field access — a reference to an INSTANCE
/// field of a const VALUE. See the section comment for the discriminator and
/// why enum / static-const / non-const-receiver references are excluded.
///
/// The recognition is independent of whether the field can actually be folded:
/// a recognised-but-unfoldable access is the caller's signal to defer LOUD, not
/// to fall through to the bare-name emit.
bool isConstObjectFieldAccess(Expression expr) {
  final access = _asFieldAccess(expr);
  return access != null &&
      canResolveConstObjectFieldReceiver(expr) &&
      _receiverIsConstValue(access.receiver);
}

/// Whether [expr] selects an instance field that can follow a const receiver.
bool canResolveConstObjectFieldReceiver(Expression expr) {
  final access = _asFieldAccess(expr);
  final field = access == null ? null : _unwrapAccessor(access.field);
  return field is FieldElement && !field.isStatic && !field.isEnumConstant;
}

/// Resolves a const-object field access [expr] to the AST initializer
/// expression bound to that field in the receiver's constructor call —
/// `_skin.headline` → the `'X'` literal, `_skin.primary` → the `Color(0x…)`
/// constructor — for the caller to re-translate through the existing value
/// recipes (β). Returns `null` when [expr] is not a const-object field access,
/// when the receiver's declaration is not reachable in the same compilation
/// unit (a cross-file const), or when the field is not bound by a field-formal
/// argument in the constructor call (e.g. it relies on a default — α's job).
Expression? resolveConstObjectFieldInitializer(Expression expr) {
  if (!isConstObjectFieldAccess(expr)) return null;
  final access = _asFieldAccess(expr)!;
  final field = _unwrapAccessor(access.field);
  if (field is! FieldElement) return null;
  final ctorCall = _receiverInstanceCreation(access.receiver);
  if (ctorCall == null) return null;
  return _boundArgumentForField(ctorCall, field);
}

/// Resolves [expr] after its receiver has reached [resolvedReceiver].
Expression? resolveConstObjectFieldInitializerFromReceiver(
  Expression expr,
  Expression resolvedReceiver, {
  required bool receiverIsConstValue,
}) {
  if (!canResolveConstObjectFieldReceiver(expr)) return null;
  final field = _unwrapAccessor(_asFieldAccess(expr)!.field);
  if (field is! FieldElement) return null;
  final ctorCall =
      resolvedReceiver is InstanceCreationExpression && receiverIsConstValue
          ? resolvedReceiver
          : _receiverInstanceCreation(resolvedReceiver);
  return ctorCall == null ? null : _boundArgumentForField(ctorCall, field);
}

/// Folds a const-object field access [expr] to a plain scalar — [int],
/// [double], [bool], or [String] — via the analyzer's constant evaluation
/// (α). This closes the silent-wrong-render bug for the cross-file and
/// defaulted-field cases β cannot reach, and is scalar-only by design: a
/// structured field (a `Color` / `EdgeInsets`) yields `null` (β folds those
/// from the AST; this never re-implements the structured emitters as a
/// DartObject→DSL path). Returns `null` when [expr] is not a const-object
/// field access or its value is not a scalar.
Object? tryScalarFoldConstObjectField(Expression expr) {
  if (!isConstObjectFieldAccess(expr)) return null;
  final access = _asFieldAccess(expr)!;
  final receiverValue = _receiverConstValue(access.receiver);
  if (receiverValue == null) return null;
  return decodeConstScalar(receiverValue.getField(access.fieldName));
}

/// The unified scalar-constant boundary for codegen sites that read a const
/// scalar DIRECTLY — outside the translator's `_translate` dispatch (so the
/// const-object-field hook there does not run): an event-name scan, a map
/// literal key, a `Duration` unit. Composes [tryFoldConstant] (a plain const
/// scalar — literal, const-scalar reference, folded arithmetic) with
/// [tryScalarFoldConstObjectField] (a const-object SCALAR field), so these
/// bypass sites fold exactly what emission folds and can never diverge from it.
/// [tryFoldConstant] keeps its scalar-only contract untouched; this only adds
/// the const-object-field scalar on top.
Object? tryFoldScalarConstant(Expression expr) =>
    tryFoldConstant(expr) ?? tryScalarFoldConstObjectField(expr);

/// Whether [expr] resolves to a const variable declaration, excluding enum
/// values and instance fields.
bool isConstDeclarationReference(Expression expr) =>
    constDeclarationElement(expr) != null;

/// The const declaration referenced by [expr], or null for another shape.
Element? constDeclarationElement(Expression expr) {
  if (expr is! SimpleIdentifier && expr is! PrefixedIdentifier) return null;
  final element = _receiverElement(expr);
  return _isConstValueElement(element) ? element : null;
}

/// The initializer of a const identifier declared in this compilation unit.
Expression? resolveConstIdentifierInitializer(Expression expr) {
  final element = constDeclarationElement(expr);
  if (element == null) return null;
  final unit = expr.root;
  if (unit is! CompilationUnit) return null;
  // Avoid walking this unit for declarations owned by another library.
  if (element.firstFragment.libraryFragment != unit.declaredFragment) {
    return null;
  }
  return _findVariableDeclaration(element, unit)?.initializer;
}

/// Resolves a same-unit const declaration to its authored initializer.
Expression? resolveConstDeclarationInitializer(Expression expr) {
  final resolved = _receiverElement(expr);
  if (resolved == null || !_isConstValueElement(resolved)) return null;
  final unit = expr.root;
  if (unit is! CompilationUnit) return null;
  return _findVariableDeclaration(resolved, unit)?.initializer;
}

/// Unwraps a getter [PropertyAccessorElement] to its backing variable so an
/// element comparison sees the [FieldElement], not the synthetic getter —
/// mirroring [_foldConstReference]'s accessor unwrap.
Element? _unwrapAccessor(Element? element) =>
    element is PropertyAccessorElement ? element.variable : element;

/// The `(receiver, field-element, field-name)` of a `<receiver>.<field>`
/// access, for a [PrefixedIdentifier] (`_skin.headline`) or a [PropertyAccess]
/// (`_x.a.b`). Returns `null` for any other expression — and for a cascade
/// section (`..x`), whose target is `null`.
({Expression receiver, Element? field, String fieldName})? _asFieldAccess(
  Expression expr,
) {
  if (expr is PrefixedIdentifier) {
    return (
      receiver: expr.prefix,
      field: expr.identifier.element,
      fieldName: expr.identifier.name,
    );
  }
  if (expr is PropertyAccess) {
    final target = expr.target;
    if (target == null) return null;
    return (
      receiver: target,
      field: expr.propertyName.element,
      fieldName: expr.propertyName.name,
    );
  }
  return null;
}

/// Whether [receiver] resolves to a const VALUE — a const variable / static-
/// const field holding an instance, or itself a (nested) const-object field
/// access whose value is a const object.
bool _receiverIsConstValue(Expression receiver) {
  if (isConstObjectFieldAccess(receiver)) return true;
  return _isConstValueElement(_receiverElement(receiver));
}

/// The element a field-access receiver resolves to (accessor-unwrapped).
Element? _receiverElement(Expression receiver) {
  if (receiver is SimpleIdentifier) return _unwrapAccessor(receiver.element);
  if (receiver is PrefixedIdentifier) {
    return _unwrapAccessor(receiver.identifier.element);
  }
  if (receiver is PropertyAccess) {
    return _unwrapAccessor(receiver.propertyName.element);
  }
  return null;
}

/// Whether [element] is a const value-holding declaration — a const top-level
/// variable, a const local, or a static-const field (never an enum constant).
bool _isConstValueElement(Element? element) {
  final resolved = _unwrapAccessor(element);
  if (resolved is TopLevelVariableElement) return resolved.isConst;
  if (resolved is LocalVariableElement) return resolved.isConst;
  if (resolved is FieldElement) {
    return resolved.isStatic && resolved.isConst && !resolved.isEnumConstant;
  }
  return false;
}

/// The [InstanceCreationExpression] the const-value [receiver] evaluates to,
/// found in the same compilation unit (β is same-unit only — a cross-file const
/// declaration is not reachable synchronously and falls to α / loud-defer).
InstanceCreationExpression? _receiverInstanceCreation(Expression receiver) {
  // Nested: the receiver is itself a const-object field access whose bound
  // initializer must itself be a const object construction.
  if (isConstObjectFieldAccess(receiver)) {
    final inner = resolveConstObjectFieldInitializer(receiver);
    return inner is InstanceCreationExpression ? inner : null;
  }
  final element = _receiverElement(receiver);
  if (!_isConstValueElement(element)) return null;
  final unit = receiver.root;
  if (unit is! CompilationUnit) return null;
  final initializer = _findVariableDeclaration(element!, unit)?.initializer;
  return initializer is InstanceCreationExpression ? initializer : null;
}

/// The argument expression bound to [field] in [ctorCall] — element-safe: it
/// matches the field-formal parameter (`this.field`) whose `.field` IS [field],
/// then returns the named or positional argument bound to it. Returns `null`
/// when no field-formal initialises [field] (the constructor sets it some other
/// way the fold cannot follow) or when the field relies on its default (not
/// passed — α folds a scalar default; a structured default loud-defers).
Expression? _boundArgumentForField(
  InstanceCreationExpression ctorCall,
  FieldElement field,
) {
  final ctor = ctorCall.constructorName.element;
  if (ctor is! ConstructorElement) return null;
  final params = ctor.formalParameters;
  FieldFormalParameterElement? fieldParam;
  for (final p in params) {
    if (p is FieldFormalParameterElement && p.field == field) {
      fieldParam = p;
      break;
    }
  }
  if (fieldParam == null) return null;
  final args = ctorCall.argumentList.arguments;
  if (fieldParam.isNamed) {
    final name = fieldParam.name;
    for (final arg in args) {
      if (arg is NamedExpression && arg.name.label.name == name) {
        return arg.expression;
      }
    }
    return null;
  }
  final positionalParams = params.where((p) => p.isPositional).toList();
  final index = positionalParams.indexOf(fieldParam);
  if (index < 0) return null;
  final positionalArgs =
      args.where((a) => a is! NamedExpression).toList(growable: false);
  if (index >= positionalArgs.length) return null;
  return positionalArgs[index];
}

/// The const [DartObject] the const-value [receiver] evaluates to — for α's
/// scalar fold. Recurses through a nested const-object field access via
/// [DartObject.getField], and otherwise computes the receiver declaration's
/// constant value (cross-file safe — the analyzer evaluates it).
DartObject? _receiverConstValue(Expression receiver) {
  if (isConstObjectFieldAccess(receiver)) {
    final access = _asFieldAccess(receiver)!;
    return _receiverConstValue(access.receiver)?.getField(access.fieldName);
  }
  final element = _receiverElement(receiver);
  if (!_isConstValueElement(element)) return null;
  return _computeConstValue(element!);
}

/// Computes the constant value of a const value-holding [element] — refusing a
/// value that comes from the build environment, as the scalar fold does.
DartObject? _computeConstValue(Element element) {
  if (dependsOnBuildEnvironment(element)) return null;
  if (element is TopLevelVariableElement) return element.computeConstantValue();
  if (element is FieldElement) return element.computeConstantValue();
  if (element is LocalVariableElement) return element.computeConstantValue();
  return null;
}

/// Finds the [VariableDeclaration] for [target] anywhere in [unit] — a
/// top-level / static const, or a `const` local in a build body — by matching
/// `declaredFragment.element`, the same element-keyed lookup the classifier's
/// local-binding capture uses.
VariableDeclaration? _findVariableDeclaration(
  Element target,
  CompilationUnit unit,
) =>
    (_constVariableIndexes[unit] ??= _ConstVariableIndex(unit))[target];

final Expando<_ConstVariableIndex> _constVariableIndexes =
    Expando<_ConstVariableIndex>('const variable declarations');

final class _ConstVariableIndex extends RecursiveAstVisitor<void> {
  _ConstVariableIndex(CompilationUnit unit) {
    unit.accept(this);
  }

  final Map<Element, VariableDeclaration> _declarations =
      Map<Element, VariableDeclaration>.identity();

  VariableDeclaration? operator [](Element element) => _declarations[element];

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final element = node.declaredFragment?.element;
    if (element != null) _declarations[element] = node;
    super.visitVariableDeclaration(node);
  }
}
