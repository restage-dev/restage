import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/dart_source_parsing.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/theme_recognition.dart';

/// [value], an evaluated constant, written back as a literal expression, or
/// `null` when part of it has no literal form.
///
/// The literal compiles exactly as if it were written at [anchor]: issues it
/// raises report there, and each construction keeps the constructor the
/// constant was built with (see [constructionConstructor]).
Expression? constValueLiteral(DartObject value, {required Expression anchor}) {
  final writer = _LiteralWriter(anchor.toSource());
  final source = writer.write(value);
  if (source == null) return null;
  final unit = parseUnresolvedDart(
    'final _ = $source;',
    path: '<constant ${anchor.toSource()}>',
  );
  final declaration = unit.declarations.singleOrNull;
  if (declaration is! TopLevelVariableDeclaration) return null;
  final literal = declaration.variables.variables.single.initializer;
  if (literal == null) return null;
  final constructions = <InstanceCreationExpression>[];
  final references = <PrefixedIdentifier>[];
  literal.accept(_ConstructionCollector(constructions, references));
  if (constructions.length != writer.constructors.length) return null;
  if (references.length != writer.references.length) return null;
  for (var i = 0; i < references.length; i++) {
    final (:owner, :member) = writer.references[i];
    _elements[references[i].prefix] = owner;
    _elements[references[i].identifier] = member;
  }
  for (var i = 0; i < constructions.length; i++) {
    final constructor = writer.constructors[i];
    if (constructor != null) _constructors[constructions[i]] = constructor;
  }
  _anchors[unit] = anchor;
  return literal;
}

/// The constructor [node] calls: its resolved one, or for a construction
/// inside a [constValueLiteral], the one the constant was built with.
ConstructorElement? constructionConstructor(InstanceCreationExpression node) =>
    node.constructorName.element ?? _constructors[node];

/// The element [identifier] names: its resolved one, or for a static member
/// written inside a [constValueLiteral], the member the constant equals.
Element? identifierElement(SimpleIdentifier identifier) =>
    identifier.element ?? _elements[identifier];

/// The source expression a node of a [constValueLiteral] stands for, or
/// `null` when [node] is ordinary source.
Expression? constValueAnchor(AstNode node) {
  final root = node.root;
  return root is CompilationUnit ? _anchors[root] : null;
}

final Expando<ConstructorElement> _constructors =
    Expando<ConstructorElement>('constant constructors');
final Expando<Expression> _anchors = Expando<Expression>('constant anchors');
final Expando<Element> _elements = Expando<Element>('constant members');

final class _ConstructionCollector extends RecursiveAstVisitor<void> {
  _ConstructionCollector(this.found, this.references);

  final List<InstanceCreationExpression> found;
  final List<PrefixedIdentifier> references;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    found.add(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    references.add(node);
    super.visitPrefixedIdentifier(node);
  }
}

/// Writes a constant as Dart source, recording each construction's
/// constructor in the order the parser visits them.
final class _LiteralWriter {
  _LiteralWriter(this.anchor);

  /// The reference being written, which must not be written back as itself.
  final String anchor;

  final List<ConstructorElement?> constructors = [];
  final List<({Element owner, Element member})> references = [];

  String? write(DartObject value) {
    if (value.isNull) return 'null';
    final scalar = _scalar(value);
    if (scalar != null) return scalar;
    final alias = _frameworkAlias(value.variable);
    if (alias != null) return alias;
    final type = value.type;
    if (type is! InterfaceType) return null;
    final element = type.element;
    if (element is EnumElement) return _enumValue(value, element);
    final list = value.toListValue();
    if (list != null) return _list(list);
    final map = value.toMapValue();
    if (map != null) return _map(map);
    if (_isWidget(type)) return null;
    final color = _color(value, type);
    if (color != null) return color;
    if (isFrameworkValueTypeLibrary(element)) {
      final mark = references.length;
      final named = _staticConstName(value, element);
      if (named != null && named != anchor) return named;
      references.length = mark;
    }
    return _construction(value);
  }

  /// `Owner.member` when [variable] is, or is declared as, a public static
  /// constant of a framework class, such as `Icons.star` or `Curves.easeIn`.
  String? _frameworkAlias(VariableElement? variable) {
    var current = variable;
    for (var depth = 0; current != null && depth < 8; depth++) {
      final owner = current.enclosingElement;
      if (current is FieldElement &&
          current.isStatic &&
          current.isConst &&
          owner is InterfaceElement &&
          isFrameworkValueTypeLibrary(current) &&
          !(current.name ?? '_').startsWith('_')) {
        final mark = references.length;
        final source = _reference(owner, current);
        if (source != null && source != anchor) return source;
        references.length = mark;
        return null;
      }
      final initializer = current.constantInitializer;
      final element = switch (initializer) {
        SimpleIdentifier(:final element) => element,
        PrefixedIdentifier(:final identifier) => identifier.element,
        PropertyAccess(:final propertyName) => propertyName.element,
        _ => null,
      };
      final next =
          element is PropertyAccessorElement ? element.variable : element;
      current = next is VariableElement && next.isConst ? next : null;
    }
    return null;
  }

  String? _scalar(DartObject value) {
    final string = value.toStringValue();
    if (string != null) return dartStringLiteral(string);
    final boolean = value.toBoolValue();
    if (boolean != null) return '$boolean';
    final integer = value.toIntValue();
    if (integer != null) return '$integer';
    final real = value.toDoubleValue();
    if (real != null) return real.isFinite ? '$real' : null;
    return null;
  }

  String? _enumValue(DartObject value, EnumElement element) {
    final name =
        value.variable?.name ?? value.getField('_name')?.toStringValue();
    final field = name == null ? null : element.getField(name);
    return field == null ? null : _reference(element, field);
  }

  /// `Type.member`, recording the elements it names.
  String? _reference(InterfaceElement owner, FieldElement field) {
    final type = owner.name;
    final name = field.name;
    final getter = field.getter;
    if (type == null || name == null || getter == null) return null;
    references.add((owner: owner, member: getter));
    return '$type.$name';
  }

  String? _list(List<DartObject> items) {
    final written = <String>[];
    for (final item in items) {
      final source = write(item);
      if (source == null) return null;
      written.add(source);
    }
    return '[${written.join(', ')}]';
  }

  String? _map(Map<DartObject?, DartObject?> entries) {
    final written = <String>[];
    for (final MapEntry(:key, :value) in entries.entries) {
      if (key == null || value == null) return null;
      final keySource = write(key);
      final valueSource = write(value);
      if (keySource == null || valueSource == null) return null;
      written.add('$keySource: $valueSource');
    }
    return '{${written.join(', ')}}';
  }

  /// A `Color` or a subclass of it, written as its ARGB value.
  String? _color(DartObject value, InterfaceType type) {
    final isColor = [type, ...type.allSupertypes].any(
      (candidate) =>
          candidate.element.name == 'Color' &&
          isFrameworkValueTypeLibrary(candidate.element),
    );
    if (!isColor) return null;
    final argb = _argb(value);
    if (argb == null) return null;
    constructors.add(null);
    return 'const Color(0x${argb.toRadixString(16).padLeft(8, '0')})';
  }

  int? _argb(DartObject value) {
    final legacy = _field(value, 'value')?.toIntValue();
    if (legacy != null) return legacy;
    final space = _field(value, 'colorSpace');
    final spaceName =
        space?.variable?.name ?? space?.getField('_name')?.toStringValue();
    if (spaceName != null && spaceName != 'sRGB') return null;
    int? channel(String name) {
      final component = _field(value, name)?.toDoubleValue();
      return component == null ? null : (component * 255).round() & 0xff;
    }

    final a = channel('a');
    final r = channel('r');
    final g = channel('g');
    final b = channel('b');
    if (a == null || r == null || g == null || b == null) return null;
    return a << 24 | r << 16 | g << 8 | b;
  }

  /// A field of [value], looked up through its superclasses.
  DartObject? _field(DartObject value, String name) {
    for (DartObject? current = value;
        current != null;
        current = current.getField('(super)')) {
      final field = current.getField(name);
      if (field != null) return field;
    }
    return null;
  }

  /// `Type.member` when [value] equals a public static constant of its class.
  String? _staticConstName(DartObject value, InterfaceElement element) {
    for (final field in element.fields) {
      final name = field.name;
      if (!field.isStatic || !field.isConst || name == null) continue;
      if (name.startsWith('_')) continue;
      if (field.computeConstantValue() == value) {
        return _reference(element, field);
      }
    }
    return null;
  }

  String? _construction(DartObject value) {
    final invocation = value.constructorInvocation;
    if (invocation == null) return null;
    final constructor = invocation.constructor;
    final type = constructor.enclosingElement.name;
    final name = constructor.name;
    if (type == null || type.startsWith('_')) return null;
    if (name != null && name.startsWith('_')) return null;
    final mark = (constructors.length, references.length);
    constructors.add(constructor);
    String? fail() {
      constructors.length = mark.$1;
      references.length = mark.$2;
      return null;
    }

    final arguments = <String>[];
    for (final argument in invocation.positionalArguments) {
      final source = write(argument);
      if (source == null) return fail();
      arguments.add(source);
    }
    for (final MapEntry(:key, :value) in invocation.namedArguments.entries) {
      final source = write(value);
      if (source == null) return fail();
      arguments.add('$key: $source');
    }
    final callee =
        name == null || name.isEmpty || name == 'new' ? type : '$type.$name';
    return 'const $callee(${arguments.join(', ')})';
  }

  bool _isWidget(InterfaceType type) => [type, ...type.allSupertypes].any(
        (candidate) =>
            candidate.element.name == 'Widget' &&
            isFrameworkValueTypeLibrary(candidate.element),
      );
}
