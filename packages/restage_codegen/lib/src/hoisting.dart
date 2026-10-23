import 'dart:convert';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/owning_library_namespace.dart';
import 'package:restage_codegen/src/theme_recognition.dart';
import 'package:restage_shared/restage_shared.dart';

/// Prefix of every context key the compiler owns.
const String kHoistedKeyPrefix = '_h';

/// Whether [name] has the shape of a compiler-owned context key.
bool isHoistedKey(String name) => RegExp(r'^_h[0-9a-f]{10}$').hasMatch(name);

/// How a value of one static type is written into the surface's data.
enum HoistValueKind {
  /// `bool`, `int`, `double`, `num` or `String`, as is.
  scalar,

  /// A color, as its ARGB integer.
  color,

  /// An enum value, as its name.
  enumName,

  /// Edge insets, as `[left, top, right, bottom]`.
  edgeInsets,

  /// A text style, as the map a published theme style uses.
  textStyle,

  /// A list of crossing values.
  list,

  /// A string-keyed map of crossing values.
  map,
}

/// What a static type makes of a value that crosses into a surface.
sealed class HoistTypeVerdict {
  const HoistTypeVerdict();
}

/// The type crosses as data with [shape].
final class HoistCrosses extends HoistTypeVerdict {
  /// Creates a crossing verdict.
  const HoistCrosses(this.kind, this.shape);

  /// How the value is written.
  final HoistValueKind kind;

  /// The host-data shape the mount publishes.
  final SurfaceScreenHostDataShape shape;
}

/// The type is a widget.
final class HoistIsWidget extends HoistTypeVerdict {
  /// Creates a widget verdict.
  const HoistIsWidget();
}

/// The type cannot cross.
final class HoistDoesNotCross extends HoistTypeVerdict {
  /// Creates a refusing verdict.
  const HoistDoesNotCross();
}

/// Classifies [type] for crossing into a surface.
HoistTypeVerdict classifyHoistType(DartType? type) {
  if (type is! InterfaceType) return const HoistDoesNotCross();
  final nullable = type.nullabilitySuffix == NullabilitySuffix.question;
  final inner = _classifyNonNull(type);
  if (inner is! HoistCrosses || !nullable) return inner;
  return HoistCrosses(
    inner.kind,
    SurfaceScreenHostDataNullableShapeV1(inner.shape),
  );
}

HoistTypeVerdict _classifyNonNull(InterfaceType type) {
  SurfaceScreenHostDataShape scalar(SurfaceScreenHostDataScalarKind kind) =>
      SurfaceScreenHostDataScalarShapeV1(kind);
  if (type.isDartCoreBool) {
    return HoistCrosses(
      HoistValueKind.scalar,
      scalar(SurfaceScreenHostDataScalarKind.boolean),
    );
  }
  if (type.isDartCoreInt) {
    return HoistCrosses(
      HoistValueKind.scalar,
      scalar(SurfaceScreenHostDataScalarKind.integer),
    );
  }
  if (type.isDartCoreDouble) {
    return HoistCrosses(
      HoistValueKind.scalar,
      scalar(SurfaceScreenHostDataScalarKind.doubleValue),
    );
  }
  if (type.isDartCoreNum) {
    return HoistCrosses(
      HoistValueKind.scalar,
      scalar(SurfaceScreenHostDataScalarKind.number),
    );
  }
  if (type.isDartCoreString) {
    return HoistCrosses(
      HoistValueKind.scalar,
      scalar(SurfaceScreenHostDataScalarKind.string),
    );
  }
  if (type.element is EnumElement) {
    return HoistCrosses(
      HoistValueKind.enumName,
      scalar(SurfaceScreenHostDataScalarKind.string),
    );
  }
  if (_isFramework(type, const {'Color'})) {
    return HoistCrosses(
      HoistValueKind.color,
      scalar(SurfaceScreenHostDataScalarKind.integer),
    );
  }
  if (_isFramework(
    type,
    const {'EdgeInsets', 'EdgeInsetsDirectional'},
  )) {
    return HoistCrosses(
      HoistValueKind.edgeInsets,
      SurfaceScreenHostDataListShapeV1(
        scalar(SurfaceScreenHostDataScalarKind.doubleValue),
      ),
    );
  }
  if (_isFramework(type, const {'TextStyle'})) {
    return HoistCrosses(HoistValueKind.textStyle, _textStyleShape);
  }
  if (type.isDartCoreList && type.typeArguments.length == 1) {
    final item = classifyHoistType(type.typeArguments.single);
    return item is HoistCrosses
        ? HoistCrosses(
            HoistValueKind.list,
            SurfaceScreenHostDataListShapeV1(item.shape),
          )
        : const HoistDoesNotCross();
  }
  if (type.isDartCoreMap &&
      type.typeArguments.length == 2 &&
      type.typeArguments.first.isDartCoreString &&
      type.typeArguments.first.nullabilitySuffix == NullabilitySuffix.none) {
    final value = classifyHoistType(type.typeArguments.last);
    return value is HoistCrosses
        ? HoistCrosses(
            HoistValueKind.map,
            SurfaceScreenHostDataMapShapeV1(value.shape),
          )
        : const HoistDoesNotCross();
  }
  if (_isFramework(type, const {'Widget'})) return const HoistIsWidget();
  return const HoistDoesNotCross();
}

const _int = SurfaceScreenHostDataScalarShapeV1(
  SurfaceScreenHostDataScalarKind.integer,
);
const _double = SurfaceScreenHostDataScalarShapeV1(
  SurfaceScreenHostDataScalarKind.doubleValue,
);
const _string = SurfaceScreenHostDataScalarShapeV1(
  SurfaceScreenHostDataScalarKind.string,
);
const _bool = SurfaceScreenHostDataScalarShapeV1(
  SurfaceScreenHostDataScalarKind.boolean,
);

/// The text style fields an app-computed style carries, by the shape each
/// is written in; every field is omitted when unset.
final Map<String, SurfaceScreenHostDataShape> kHoistedTextStyleFields = {
  'inherit': _bool,
  'color': _int,
  'backgroundColor': _int,
  'fontSize': _double,
  'fontWeight': _string,
  'fontStyle': _string,
  'letterSpacing': _double,
  'wordSpacing': _double,
  'textBaseline': _string,
  'height': _double,
  'leadingDistribution': _string,
  'locale': _string,
  'foreground': _paintShape,
  'background': _paintShape,
  'shadows': SurfaceScreenHostDataListShapeV1(
    SurfaceScreenHostDataObjectShapeV1({
      'color': _int,
      'offset': SurfaceScreenHostDataObjectShapeV1(const {
        'x': _double,
        'y': _double,
      }),
      'blurRadius': _double,
    }),
  ),
  'fontFeatures': SurfaceScreenHostDataListShapeV1(
    SurfaceScreenHostDataObjectShapeV1(
      const {'feature': _string, 'value': _int},
    ),
  ),
  'fontVariations': SurfaceScreenHostDataListShapeV1(
    SurfaceScreenHostDataObjectShapeV1(
      const {'axis': _string, 'value': _double},
    ),
  ),
  // One line's name, or a list of names for combined lines.
  'decoration': const SurfaceScreenHostDataScalarShapeV1(
    SurfaceScreenHostDataScalarKind.jsonValue,
  ),
  'decorationColor': _int,
  'decorationStyle': _string,
  'decorationThickness': _double,
  'debugLabel': _string,
  'fontFamily': _string,
  'fontFamilyFallback': const SurfaceScreenHostDataListShapeV1(_string),
  'overflow': _string,
};

final SurfaceScreenHostDataShape _paintShape =
    SurfaceScreenHostDataObjectShapeV1(const {
  'color': _int,
  'blendMode': _string,
  'filterQuality': _string,
  'isAntiAlias': _bool,
});

final SurfaceScreenHostDataShape _textStyleShape =
    SurfaceScreenHostDataObjectShapeV1({
  for (final MapEntry(:key, :value) in kHoistedTextStyleFields.entries)
    key: SurfaceScreenHostDataNullableShapeV1(value),
});

bool _isFramework(InterfaceType type, Set<String> names) =>
    [type, ...type.allSupertypes].any(
      (candidate) =>
          names.contains(candidate.element.name) &&
          isFrameworkValueTypeLibrary(candidate.element),
    );

/// A value the generated mount computes and passes under [key].
@immutable
final class HoistedValue {
  /// Creates a hoisted value.
  const HoistedValue({
    required this.key,
    required this.label,
    required this.kind,
    required this.shape,
    required String template,
    this.item,
    this.paints = const [],
  }) : _template = template;

  /// The compiler-owned context key.
  final String key;

  /// The expression as the developer reads it.
  final String label;

  /// How the value is written.
  final HoistValueKind kind;

  /// The host-data shape the mount publishes.
  final SurfaceScreenHostDataShape shape;

  /// The screen input whose items each carry this value, when it is read
  /// per item of a loop over that input.
  final String? item;

  /// The text style paint fields the expression sets, which a surface keeps
  /// only in part.
  final List<String> paints;

  final String _template;

  /// The mount's Dart source, reading each screen input through [slotOf]
  /// and the current item through [itemSource].
  String mountSource(
    String Function(String parameter) slotOf, {
    String? itemSource,
  }) =>
      _template
          .replaceAllMapped(
            _parameterMarker,
            (match) => slotOf(match.group(1)!),
          )
          .replaceAll(_itemMarker, itemSource ?? '');

  @override
  bool operator ==(Object other) =>
      other is HoistedValue &&
      other.key == key &&
      other.label == label &&
      other._template == _template;

  @override
  int get hashCode => Object.hash(key, label, _template);
}

final RegExp _parameterMarker = RegExp('\u0000([A-Za-z0-9_\$]+)\u0000');
const String _itemMarker = '\u0001';

/// What the mount can make of one expression.
sealed class HoistAnalysis {
  const HoistAnalysis();
}

/// The mount can evaluate the expression.
final class HoistEvaluable extends HoistAnalysis {
  /// Creates an evaluable analysis.
  const HoistEvaluable({
    required this.label,
    required this.template,
    this.item,
  });

  /// The expression as the developer reads it.
  final String label;

  /// The mount's source, with screen inputs marked.
  final String template;

  /// The screen input whose items the expression reads, if any.
  final String? item;

  /// The value of [expression] for a crossing [verdict].
  HoistedValue value(
    HoistCrosses verdict,
    DartType type, {
    Expression? expression,
  }) {
    final typeName = type.getDisplayString();
    final digest = crypto.sha256.convert(
      utf8.encode('${_canonicalSource(template)}\n$typeName\n${item ?? ''}'),
    );
    return HoistedValue(
      key: '$kHoistedKeyPrefix${digest.toString().substring(0, 10)}',
      label: label,
      kind: verdict.kind,
      shape: verdict.shape.withLabel(label),
      template: template,
      item: item,
      paints: verdict.kind == HoistValueKind.textStyle && expression != null
          ? _paintsSet(expression)
          : const [],
    );
  }
}

/// The `foreground` and `background` arguments [expression] passes to a
/// text style.
List<String> _paintsSet(Expression expression) {
  final names = <String>{};
  expression.accept(_PaintArguments(names));
  return names.toList()..sort();
}

final class _PaintArguments extends RecursiveAstVisitor<void> {
  _PaintArguments(this.names);

  final Set<String> names;

  @override
  void visitNamedArgument(NamedArgument node) {
    final name = node.name.lexeme;
    final type = node.argumentExpression.staticType;
    if ((name == 'foreground' || name == 'background') &&
        type is InterfaceType &&
        _isFramework(type, const {'Paint'})) {
      names.add(name);
    }
    super.visitNamedArgument(node);
  }
}

/// [source] printed from its syntax, so comments and formatting never change
/// the label.
String _labelOf(String source) {
  final result = parseString(
    content: 'final restageValue = $source;',
    throwIfDiagnostics: false,
  );
  final declaration = result.unit.declarations.firstOrNull;
  final initializer =
      declaration is TopLevelVariableDeclaration && result.errors.isEmpty
          ? declaration.variables.variables.single.initializer
          : null;
  return initializer?.toSource() ?? source.replaceAll(RegExp(r'\s+'), ' ');
}

/// [template]'s tokens, so formatting never changes a key.
String _canonicalSource(String template) {
  final source = template
      .replaceAllMapped(_parameterMarker, (match) => 'input\$${match[1]}')
      .replaceAll(_itemMarker, r'item$');
  final unit = parseString(
    content: 'final restageValue = $source;',
    throwIfDiagnostics: false,
  ).unit;
  final tokens = <String>[];
  for (Token? token = unit.beginToken;
      token != null && !token.isEof;
      token = token.next) {
    final next = token.next?.lexeme;
    if (token.lexeme == ',' && (next == ')' || next == ']' || next == '}')) {
      continue;
    }
    tokens.add(token.lexeme);
  }
  return tokens.join(' ');
}

/// The expression reads [name], which only the surface has.
final class HoistNeedsSurfaceValue extends HoistAnalysis {
  /// Creates a refusal naming [name].
  const HoistNeedsSurfaceValue(this.name, {this.isBuildArgument = false});

  /// The surface-only name.
  final String name;

  /// Whether [name] is an argument of `build` other than its context.
  final bool isBuildArgument;
}

/// The expression cannot be written in the mount.
final class HoistUnwritable extends HoistAnalysis {
  /// Creates an unwritable analysis.
  const HoistUnwritable({this.unnamed});

  /// A declaration the mount's library cannot name, when that is the cause.
  final String? unnamed;
}

/// Decides what the generated mount can evaluate.
final class HoistAnalyzer {
  /// Creates an analyzer.
  HoistAnalyzer({
    required this.namespace,
    required this.rootParamFor,
    required this.bindingFor,
    required this.itemLoopFor,
    required this.isStateWidget,
    this.rootContext,
    this.buildArgumentFor = _noBuildArgument,
  });

  /// The screen build's `BuildContext` parameter; only it is the mount's.
  final Element? rootContext;

  /// Whether a getter is `State.widget`.
  final bool Function(Element? element) isStateWidget;

  /// The library that owns the generated mount.
  final OwningLibraryNamespace namespace;

  /// The screen input a field or getter reads, if any.
  final RootContextParam? Function(Element? element) rootParamFor;

  /// The expression a helper parameter or prelude local stands for.
  final Expression? Function(Element element) bindingFor;

  /// The screen input a loop variable walks item by item, if the mount can
  /// add values to those items.
  final String? Function(Element element) itemLoopFor;

  /// The name the mount's build gives a parameter of the screen's build
  /// after its context, if it has one.
  final String? Function(Element element) buildArgumentFor;

  static String? _noBuildArgument(Element element) => null;

  /// Analyzes [expression].
  HoistAnalysis analyze(Expression expression) {
    final writer = _HoistWriter(this);
    final template = writer.render(expression, const []);
    if (writer.surfaceValue case final blocked?) return blocked;
    if (template == null) return HoistUnwritable(unnamed: writer.unnamed);
    final label = _labelOf(
      template
          .replaceAllMapped(_parameterMarker, (match) => match.group(1)!)
          .replaceAll(_itemMarker, writer.itemName ?? ''),
    );
    return HoistEvaluable(
      label: label,
      template: template,
      item: writer.item,
    );
  }
}

final class _HoistWriter {
  _HoistWriter(this.analyzer);

  final HoistAnalyzer analyzer;
  HoistNeedsSurfaceValue? surfaceValue;
  bool failed = false;
  String? unnamed;
  String? item;
  String? itemName;

  String? render(Expression node, List<Element> active) {
    final unit = node.root;
    final contents = unit is CompilationUnit
        ? unit.declaredFragment?.source.contents.data
        : null;
    if (contents == null || node.end > contents.length) return null;
    final visitor = _HoistVisitor(this, node, active);
    node.accept(visitor);
    if (failed || surfaceValue != null) return null;
    var source = contents.substring(node.offset, node.end);
    final edits = visitor.edits
      ..sort((left, right) => right.start.compareTo(left.start));
    for (final edit in edits) {
      source = source.replaceRange(
        edit.start - node.offset,
        edit.end - node.offset,
        edit.text,
      );
    }
    return source;
  }
}

final class _HoistVisitor extends RecursiveAstVisitor<void> {
  _HoistVisitor(this.writer, this.root, this.active);

  final _HoistWriter writer;
  final Expression root;
  final List<Element> active;
  final List<({int start, int end, String text})> edits = [];

  HoistAnalyzer get analyzer => writer.analyzer;

  void _replace(AstNode node, String text) =>
      edits.add((start: node.offset, end: node.end, text: text));

  void _fail() => writer.failed = true;

  void _unnamed(String name) {
    writer.unnamed ??= name;
    _fail();
  }

  void _surfaceOnly(String name, {bool isBuildArgument = false}) =>
      writer.surfaceValue ??=
          HoistNeedsSurfaceValue(name, isBuildArgument: isBuildArgument);

  bool _declaredInside(Element element) {
    final fragment = element.firstFragment;
    final unit = root.root;
    if (unit is! CompilationUnit) return false;
    final source = unit.declaredFragment?.source;
    return source != null &&
        fragment.libraryFragment?.source == source &&
        fragment.offset >= root.offset &&
        fragment.offset < root.end;
  }

  @override
  void visitThisExpression(ThisExpression node) => _surfaceOnly('this');

  @override
  void visitSuperExpression(SuperExpression node) => _surfaceOnly('super');

  @override
  void visitNamedType(NamedType node) {
    final element = node.element;
    if (element == null) {
      if (node.name.lexeme != 'dynamic' && node.name.lexeme != 'void') {
        _fail();
      }
    } else if (element is! TypeParameterElement) {
      final spelling = analyzer.namespace.elementName(element);
      if (spelling == null) {
        _unnamed(node.name.lexeme);
        return;
      }
      edits.add(
        (
          start: node.importPrefix?.offset ?? node.name.offset,
          end: node.name.end,
          text: spelling,
        ),
      );
    }
    node.typeArguments?.accept(this);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final prefix = node.prefix.element;
    final member = node.identifier.element;
    if (prefix is PrefixElement) {
      _reference(node, member, node.identifier.name);
      return;
    }
    if (_isStateWidget(prefix)) {
      final param = analyzer.rootParamFor(member);
      if (param != null) {
        _replace(node, '\u0000${param.name}\u0000');
        return;
      }
    }
    node.prefix.accept(this);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target;
    if (target is SimpleIdentifier && _isStateWidget(target.element)) {
      final param = analyzer.rootParamFor(node.propertyName.element);
      if (param != null) {
        _replace(node, '\u0000${param.name}\u0000');
        return;
      }
    }
    target?.accept(this);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    if (target == null) {
      _reference(
        node.methodName,
        node.methodName.element,
        node.methodName.name,
      );
    } else {
      target.accept(this);
    }
    node.typeArguments?.accept(this);
    node.argumentList.accept(this);
  }

  @override
  void visitNamedArgument(NamedArgument node) =>
      node.argumentExpression.accept(this);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.inDeclarationContext() || _isSelector(node)) return;
    _reference(node, node.element, node.name);
  }

  void _reference(AstNode node, Element? raw, String name) {
    if (raw == null) {
      _fail();
      return;
    }
    final element =
        raw is PropertyAccessorElement ? raw.variable : raw.baseElement;
    if (_declaredInside(element)) return;
    final bound = analyzer.bindingFor(raw) ?? analyzer.bindingFor(element);
    if (bound != null) {
      if (active.contains(element)) {
        _fail();
        return;
      }
      final inner = writer.render(bound, [...active, element]);
      if (inner == null) return;
      _replace(
        node,
        bound is Identifier ||
                bound is PropertyAccess ||
                bound is MethodInvocation ||
                bound is ParenthesizedExpression ||
                bound is Literal
            ? inner
            : '($inner)',
      );
      return;
    }
    if (element is FormalParameterElement) {
      final root = analyzer.rootContext?.baseElement;
      if (root != null && identical(element.baseElement, root)) {
        _replace(node, 'context');
        return;
      }
      if (analyzer.buildArgumentFor(element) case final argument?) {
        _replace(node, argument);
        return;
      }
      _surfaceOnly(
        name,
        isBuildArgument: root != null &&
            identical(
              element.baseElement.enclosingElement,
              root.enclosingElement,
            ),
      );
      return;
    }
    if (element is LocalVariableElement) {
      final item = analyzer.itemLoopFor(element);
      if (item == null || (writer.item ?? item) != item) {
        _surfaceOnly(name);
        return;
      }
      writer
        ..item = item
        ..itemName = name;
      _replace(node, _itemMarker);
      return;
    }
    final param = analyzer.rootParamFor(element);
    if (param != null) {
      _replace(node, '\u0000${param.name}\u0000');
      return;
    }
    final enclosing = element.enclosingElement;
    final isStatic = switch (element) {
      VariableElement(:final isStatic) => isStatic,
      ExecutableElement(:final isStatic) => isStatic,
      _ => false,
    };
    final String? spelling;
    if (enclosing is LibraryElement || element is InterfaceElement) {
      spelling = analyzer.namespace.elementName(element);
    } else if (isStatic) {
      spelling = analyzer.namespace.staticMemberName(element);
    } else {
      _surfaceOnly(name);
      return;
    }
    if (spelling == null) {
      _unnamed(element.name ?? name);
      return;
    }
    _replace(node, spelling);
  }

  bool _isStateWidget(Element? element) => analyzer.isStateWidget(element);
}

bool _isSelector(SimpleIdentifier identifier) => switch (identifier.parent) {
      ConstructorName(:final name) when identical(name, identifier) => true,
      MethodInvocation(:final methodName)
          when identical(methodName, identifier) =>
        true,
      PrefixedIdentifier(identifier: final selector)
          when identical(selector, identifier) =>
        true,
      PropertyAccess(:final propertyName)
          when identical(propertyName, identifier) =>
        true,
      Label() => true,
      _ => false,
    };
