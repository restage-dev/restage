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
import 'package:restage_codegen/src/installed_native_call.dart';
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

  /// A DateTime, as its epoch microseconds and UTC flag.
  dateTime,

  /// A color, as its ARGB integer.
  color,

  /// An enum value, as its name.
  enumName,

  /// Edge insets, preserving physical or directional field names.
  edgeInsets,

  /// A text style, as the map a published theme style uses.
  textStyle,

  /// An exact native TextScaler stored in this mount.
  textScaler,

  /// An exact borrowed native value or callback.
  nativeBinding,

  /// A list of crossing values.
  list,

  /// A string-keyed map of crossing values.
  map,

  /// The items a loop walks, published as one map of item values each.
  items,

  /// The position of each item in the list the mount walks.
  itemIndex,
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
  if (type.element.name == 'DateTime' &&
      type.element.library.identifier == 'dart:core') {
    return HoistCrosses(
      HoistValueKind.dateTime,
      SurfaceScreenHostDataObjectShapeV1({
        'microsecondsSinceEpoch': scalar(
          SurfaceScreenHostDataScalarKind.integer,
        ),
        'isUtc': scalar(SurfaceScreenHostDataScalarKind.boolean),
      }),
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
      SurfaceScreenHostDataObjectShapeV1({
        for (final key
            in type.element.name == 'EdgeInsetsDirectional'
                ? ['start', 'top', 'end', 'bottom']
                : ['left', 'top', 'right', 'bottom'])
          key: scalar(SurfaceScreenHostDataScalarKind.doubleValue),
      }),
    );
  }
  if (_isFramework(type, const {'TextScaler'})) {
    return HoistCrosses(
      HoistValueKind.textScaler,
      SurfaceScreenHostDataObjectShapeV1(const {
        'kind': _string,
        'key': _string,
      }),
    );
  }
  if (_isFramework(type, const {'TextStyle'})) {
    return HoistCrosses(HoistValueKind.textStyle, _textStyleShape);
  }
  if ((type.isDartCoreList || type.isDartCoreMap) &&
      type.typeArguments.any(_containsNativeScaler)) {
    return const HoistDoesNotCross();
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

bool _containsNativeScaler(DartType type) =>
    type is InterfaceType &&
    (_isFramework(type, const {'TextScaler'}) ||
        type.typeArguments.any(_containsNativeScaler));

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
    this.nativeContract,
    this.nativeCall,
    this.nativeConstant,
    this.computed = false,
    this.paints = const [],
    this.pattern,
    this.location,
    this.site,
  }) : _template = template;

  /// The node the app computes this value at, when known; not identity.
  final AstNode? site;

  /// This value, first computed at [location].
  HoistedValue at(String location) => withKey(key, location: location);

  /// This value under [key].
  HoistedValue withKey(String key, {String? location}) => HoistedValue(
    key: key,
    label: label,
    kind: kind,
    shape: shape,
    template: _template,
    item: item,
    nativeContract: nativeContract,
    nativeCall: nativeCall,
    nativeConstant: nativeConstant,
    computed: computed,
    paints: paints,
    pattern: pattern,
    location: location ?? this.location,
    site: site,
  );

  /// Where the expression first appears, when recorded; not part of identity.
  final String? location;

  /// How the mount destructures each item, for a value of kind
  /// [HoistValueKind.items].
  final String? pattern;

  /// The compiler-owned context key.
  final String key;

  /// The expression as the developer reads it.
  final String label;

  /// How the value is written.
  final HoistValueKind kind;

  /// The installed native declaration, when this is a borrowed binding.
  final NativeBindingContract? nativeContract;

  /// A lazy installed implementation, rather than a mount-time computation.
  final InstalledNativeCallPlan? nativeCall;

  /// A canonical compiled constant emitted in its library scope.
  final InstalledNativeCallPlan? nativeConstant;

  /// Whether the mount computes this native object rather than borrowing it.
  final bool computed;

  /// The host-data shape the mount publishes.
  final SurfaceScreenHostDataShape shape;

  /// The screen input whose items each carry this value, when it is read
  /// per item of a loop over that input.
  final String? item;

  /// The text style paint fields the expression sets, which a surface keeps
  /// only in part.
  final List<String> paints;

  final String _template;

  /// The value as a template, as [HoistAnalyzer.analyze] writes it.
  String get template => _template;

  /// The mount's Dart source, reading each screen input through [slotOf]
  /// and the current item through [itemSource].
  String mountSource(
    String Function(String parameter) slotOf, {
    String? itemSource,
  }) => mountTemplateSource(_template, slotOf, itemSource: itemSource);

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

/// [template] as mount source: screen inputs through [slotOf], the current
/// item as [itemSource].
String mountTemplateSource(
  String template,
  String Function(String parameter) slotOf, {
  String? itemSource,
}) => template
    .replaceAllMapped(_parameterMarker, (match) => slotOf(match.group(1)!))
    .replaceAll(_itemMarker, itemSource ?? '');
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
    this.node,
  });

  /// The node analyzed, where a recorded build computes the value.
  final AstNode? node;

  /// The expression as the developer reads it.
  final String label;

  /// The mount's source, with screen inputs marked.
  final String template;

  /// The screen input whose items the expression reads, if any.
  final String? item;

  /// The items of this iterable, walked in the mount with [pattern].
  HoistedValue items(DartType type, {required String pattern}) {
    final value = this.value(
      HoistCrosses(
        HoistValueKind.items,
        SurfaceScreenHostDataListShapeV1(
          SurfaceScreenHostDataScalarShapeV1(
            SurfaceScreenHostDataScalarKind.jsonValue,
          ),
        ),
      ),
      type,
    );
    // Each loop's pattern names its own item values.
    final digest = crypto.sha256.convert(utf8.encode('${value.key}\n$pattern'));
    return HoistedValue(
      key: '$kHoistedKeyPrefix${digest.toString().substring(0, 10)}',
      label: label,
      kind: HoistValueKind.items,
      shape: value.shape,
      template: template,
      item: item,
      pattern: pattern,
      site: node,
    );
  }

  /// The value of [expression] for a crossing [verdict].
  HoistedValue value(
    HoistCrosses verdict,
    DartType type, {
    Expression? expression,
    NativeBindingContract? nativeContract,
    bool computed = false,
    String? location,
  }) {
    final typeName = type.getDisplayString();
    final digest = crypto.sha256.convert(
      utf8.encode(
        '${canonicalHoistSource(template)}\n$typeName\n${item ?? ''}'
        '${nativeContract == null ? '' : '\nnative:${jsonEncode(nativeContract.toJson())}'}',
      ),
    );
    return HoistedValue(
      key: '$kHoistedKeyPrefix${digest.toString().substring(0, 10)}',
      label: label,
      kind: verdict.kind,
      nativeContract: nativeContract,
      computed: computed,
      shape: verdict.shape.withLabel(label),
      template: template,
      item: item,
      location: location,
      site: node,
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

/// The position of each item of [item], which an island in its loop reads to
/// find its item in the list the mount walks.
/// [label] reads as source, such as `index of p in plans`.
HoistedValue itemIndexValue(String item, {required String label}) {
  final digest = crypto.sha256.convert(utf8.encode('item index\n$item'));
  return HoistedValue(
    key: '$kHoistedKeyPrefix${digest.toString().substring(0, 10)}',
    label: label,
    kind: HoistValueKind.itemIndex,
    shape: const SurfaceScreenHostDataScalarShapeV1(
      SurfaceScreenHostDataScalarKind.integer,
    ),
    template: '',
    item: item,
  );
}

/// [template] as tokens, so comments, layout and trailing commas drop out
/// and formatting never changes a key.
String canonicalHoistSource(String template) {
  final source = template
      .replaceAllMapped(
        _parameterMarker,
        (match) => switch (_spelled(match[1]!)) {
          final spelled when spelled != match[1] => spelled,
          _ => 'input\$${match[1]}',
        },
      )
      .replaceAll(_itemMarker, r'item$');
  final unit = parseString(
    content: 'final restageValue = $source;',
    throwIfDiagnostics: false,
  ).unit;
  final tokens = <String>[];
  for (
    Token? token = unit.beginToken;
    token != null && !token.isEof;
    token = token.next
  ) {
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
  const HoistNeedsSurfaceValue(
    this.name, {
    this.node,
    this.elements = const {},
  });

  /// The first surface-only name.
  final String name;

  /// Where the expression reads [name].
  final AstNode? node;

  /// Every surface-only declaration the expression reads.
  final Set<Element> elements;
}

/// The expression cannot be written in the mount.
final class HoistUnwritable extends HoistAnalysis {
  /// Creates an unwritable analysis.
  const HoistUnwritable({this.unnamed, this.node});

  /// A declaration the mount's library cannot name, when that is the cause.
  final String? unnamed;

  /// Where the copy stopped: the use of [unnamed], or a restricted call.
  final AstNode? node;
}

/// Names a generated mount declares in its build's scope, which would hide a
/// top-level declaration the app's build reads.
const kMountScopeNames = {
  'context',
  'widget',
  'mounted',
  'setState',
  'onEvent',
  'resolver',
  'errorBuilder',
  'loadingBuilder',
};

/// The part's alias of the top-level [element] named [name]: a constant for
/// a constant, a getter otherwise.
String mountAliasOf(Element element, String name) =>
    element is VariableElement && element.isConst
    ? '_restageTopC\$$name'
    : '_restageTopG\$$name';

/// The declarations of every mount alias [source] uses.
String mountAliasDeclarations(String source) => [
  for (final match in {
    for (final match in RegExp(
      r'\b_restageTop([CG])\$(\w+)\b',
    ).allMatches(source))
      match[0]!: match,
  }.values)
    match[1] == 'C'
        ? 'const ${match[0]} = ${match[2]};'
        : '// ignore: unused_element\nget ${match[0]} => ${match[2]};',
].join('\n');

/// The mount slot naming the screen build's context, which a builder kept in
/// the mount may shadow.
const kRootContext = 'restageRootContext';

/// The mount slot a lifted `State` reads its surface's instance through, as
/// `widget`.
const kStateWidget = 'restageWidget';

/// [kStateWidget] marked in a template.
const kStateWidgetSlot = '\u0000$kStateWidget\u0000';

/// The mount slot naming a lifted `State`'s own `didUpdateWidget`.
const kStateUpdateSlot = '\u0000restageDidUpdateWidget\u0000';

// What a slot reads as in a label or a key.
String _spelled(String slot) => switch (slot) {
  kRootContext => 'context',
  kStateWidget => 'widget',
  // A build local keys as its name, which nothing else in the build
  // resolves to; a local of a block, pattern or loop keys apart from it.
  _ when slot.startsWith(_kHeldLocalPrefix) => slot.substring(
    _kHeldLocalPrefix.length,
  ),
  _ when slot.startsWith(_kInnerLocalPrefix) =>
    'local\$${slot.substring(_kInnerLocalPrefix.length)}',
  _ => slot,
};

const _kHeldLocalPrefix = r'restageHeld$';
const _kInnerLocalPrefix = r'restageInner$';

/// The slot of a local the mount declares ahead under [name]; [inner] when a
/// block, pattern or loop declares it.
String heldLocalSlot(String name, {bool inner = false}) =>
    '${inner ? _kInnerLocalPrefix : _kHeldLocalPrefix}$name';

/// The mount slot holding an instance of a stateless surface.
const kSurfaceInstance = '_restageSurface';

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
    this.isDeclaredCallable = _noDeclaredCallable,
    this.isMountScope = _noMountScope,
    this.keepsItemNames = _noMountScope,
    this.isSurfaceMember = _noMountScope,
    this.outerItem = _noOuterItem,
    this.thisFor = _noThis,
    this.forwardsWidget = _noForward,
    this.mountNameOf = _noMountName,
    this.recordedLocalOf = _noMountName,
  });

  /// The slot a build local the mount neither holds nor walks is keyed by;
  /// a recorded build reads it where the app declares it.
  final String? Function(Element element) recordedLocalOf;

  /// The name the mount declares the local [element] under, or `null` when
  /// it keeps its source name.
  final String? Function(Element element) mountNameOf;

  static String? _noMountName(Element _) => null;

  /// Whether the mount forwards `State.widget`: a lifted `State` reads an
  /// instance of its surface.
  final bool Function() forwardsWidget;

  static bool _noForward() => false;

  /// How the mount spells `this` of [type], when it has one.
  final String? Function(DartType? type) thisFor;

  static String? _noThis(DartType? _) => null;

  /// The item list whose items [item]'s list is computed from, when it is
  /// nested in another loop.
  final String? Function(String item) outerItem;

  static String? _noOuterItem(String _) => null;

  /// Whether an instance member belongs to a stateless surface, which the
  /// mount reads from an instance of it.
  final bool Function(Element element) isSurfaceMember;

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

  /// Whether a callable reference is an existing typed constructor input.
  final bool Function(Expression reference) isDeclaredCallable;

  /// Whether the mount walks [item] itself, so its loop variables keep
  /// their names.
  final bool Function(String item) keepsItemNames;

  /// Whether the mount declares [element] under its own name: a lifted
  /// `State` member or a parameter or local of a builder dissolved into it.
  final bool Function(Element element) isMountScope;

  static bool _noDeclaredCallable(Expression reference) => false;
  static bool _noMountScope(Object _) => false;
  static String? _noBuildArgument(Element element) => null;

  /// Analyzes [expression], writing each node of [holes] as its text and
  /// keying islands as [keys] says.
  HoistAnalysis analyze(
    AstNode expression, {
    Map<AstNode, String> holes = const {},
    Map<AstNode, List<({String before, String after})>> around = const {},
    AstNode? scope,
  }) {
    final writer = _HoistWriter(this, holes)
      ..around = around
      ..scope = scope;
    final template = writer.render(expression, const []);
    if (writer.surfaceValue case final blocked?) {
      return HoistNeedsSurfaceValue(
        blocked.name,
        node: blocked.node,
        elements: writer.blocked,
      );
    }
    if (template == null) {
      return HoistUnwritable(unnamed: writer.unnamed, node: writer.stoppedAt);
    }
    // A label reads as the source wrote the expression.
    final unit = expression.root;
    final contents = unit is CompilationUnit
        ? unit.declaredFragment?.source.contents.data
        : null;
    final label = _labelOf(
      holes.isEmpty && contents != null && expression.end <= contents.length
          ? contents.substring(expression.offset, expression.end)
          : template
                .replaceAllMapped(
                  _parameterMarker,
                  (match) =>
                      match[1] == kRootContext ? 'context' : match.group(1)!,
                )
                .replaceAll(_itemMarker, writer.itemName ?? ''),
    );
    return HoistEvaluable(
      label: label,
      template: template,
      item: writer.item,
      node: expression,
    );
  }
}

final class _HoistWriter {
  _HoistWriter(this.analyzer, this.holes);

  final HoistAnalyzer analyzer;
  final Map<AstNode, String> holes;

  /// Text written around nodes, outermost first; recorded copies only.
  Map<AstNode, List<({String before, String after})>> around = const {};

  /// The scope whose own locals keep their source names; recorded copies
  /// only.
  AstNode? scope;

  HoistNeedsSurfaceValue? surfaceValue;
  final Set<Element> blocked = {};
  bool failed = false;
  String? unnamed;
  AstNode? stoppedAt;
  String? item;
  String? itemName;

  String? render(AstNode node, List<Element> active) {
    final unit = node.root;
    final contents = unit is CompilationUnit
        ? unit.declaredFragment?.source.contents.data
        : null;
    if (contents == null || node.end > contents.length) return null;
    final visitor = _HoistVisitor(this, node, active);
    node.accept(visitor);
    if (failed || surfaceValue != null) return null;
    var source = contents.substring(node.offset, node.end);
    // At one offset, a replacement applies before an insertion.
    final edits = visitor.edits
      ..addAll(_constAround(node, contents))
      ..addAll(_around(node));
    // A hole's text replaces everything inside it, edits included.
    final replaced = [
      for (final edit in edits)
        if (edit.end > edit.start) edit,
    ];
    edits
      ..removeWhere(
        (edit) => replaced.any(
          (hole) =>
              !identical(hole, edit) &&
              hole.start <= edit.start &&
              edit.end <= hole.end &&
              // Text written around the hole itself stays.
              !(edit.start == edit.end &&
                  (edit.start == hole.start || edit.start == hole.end)) &&
              !(edit.start == hole.start && edit.end == hole.end),
        ),
      )
      ..sort(
        (left, right) => switch (right.start.compareTo(left.start)) {
          0 => right.end.compareTo(left.end),
          final order => order,
        },
      );
    for (final edit in edits) {
      source = source.replaceRange(
        edit.start - node.offset,
        edit.end - node.offset,
        edit.text,
      );
    }
    return source;
  }

  // The text written around each node of [around] inside [node], merged per
  // offset so outer text encloses inner text.
  Iterable<({int start, int end, String text})> _around(AstNode node) {
    final before = <int, List<(int, int, String)>>{};
    final after = <int, List<(int, int, String)>>{};
    for (final MapEntry(key: at, value: texts) in around.entries) {
      if (at.offset < node.offset || at.end > node.end) continue;
      // A bare `$name` interpolation needs braces once it is wrapped.
      final bare = switch (at.parent) {
        InterpolationExpression(rightBracket: null) => true,
        _ => false,
      };
      for (final (order, text) in texts.indexed) {
        (before[at.offset] ??= []).add((
          at.length,
          order,
          '${bare && order == 0 ? '{' : ''}${text.before}',
        ));
        (after[at.end] ??= []).add((
          at.length,
          order,
          '${text.after}${bare && order == 0 ? '}' : ''}',
        ));
      }
    }
    int outerFirst((int, int, String) a, (int, int, String) b) =>
        a.$1 != b.$1 ? b.$1.compareTo(a.$1) : a.$2.compareTo(b.$2);
    return [
      for (final MapEntry(:key, :value) in before.entries)
        (
          start: key,
          end: key,
          text: (value..sort(outerFirst)).map((e) => e.$3).join(),
        ),
      for (final MapEntry(:key, :value) in after.entries)
        (
          start: key,
          end: key,
          text: (value..sort((a, b) => outerFirst(b, a)))
              .map((e) => e.$3)
              .join(),
        ),
    ];
  }

  // Removes each `const` from [node] down to a hole: a filled hole is not
  // constant.
  Iterable<({int start, int end, String text})> _constAround(
    AstNode node,
    String contents,
  ) {
    final keywords = <Token>{};
    for (final hole in [
      ...holes.keys,
      ...around.keys,
    ]) {
      if (identical(hole, node) ||
          hole.offset < node.offset ||
          hole.end > node.end) {
        continue;
      }
      // The hole's own text replaces the hole, `const` included.
      for (AstNode? at = hole.parent; at != null; at = at.parent) {
        final keyword = switch (at) {
          InstanceCreationExpression(:final keyword?) => keyword,
          TypedLiteral(:final constKeyword?) => constKeyword,
          RecordLiteral(:final constKeyword?) => constKeyword,
          _ => null,
        };
        if (keyword?.keyword == Keyword.CONST) keywords.add(keyword!);
        if (identical(at, node)) break;
      }
    }
    return [
      for (final keyword in keywords)
        (
          start: keyword.offset,
          end: RegExp(r'\s*').matchAsPrefix(contents, keyword.end)!.end,
          text: '',
        ),
    ];
  }
}

final class _HoistVisitor extends RecursiveAstVisitor<void> {
  _HoistVisitor(this.writer, this.root, this.active);

  final _HoistWriter writer;
  final AstNode root;
  final List<Element> active;
  final List<({int start, int end, String text})> edits = [];

  HoistAnalyzer get analyzer => writer.analyzer;

  // A `$name` interpolation needs braces once its name is rewritten, when
  // the interpolation is part of what is written.
  void _replace(AstNode node, String text) => edits.add((
    start: node.offset,
    end: node.end,
    text: switch (node.parent) {
      final InterpolationExpression interpolation
          when interpolation.rightBracket == null &&
              interpolation.offset >= root.offset &&
              !writer.around.containsKey(node) =>
        '{$text}',
      _ => text,
    },
  ));

  void _fail(AstNode node) {
    writer.stoppedAt ??= node;
    writer.failed = true;
  }

  void _unnamed(AstNode node, String name) {
    if (writer.unnamed == null) {
      writer
        ..unnamed = name
        ..stoppedAt = node;
    }
    _fail(node);
  }

  void _surfaceOnly(AstNode node, String name, {Element? element}) {
    writer.surfaceValue ??= HoistNeedsSurfaceValue(name, node: node);
    if (element != null) writer.blocked.add(element);
  }

  bool _declaredInside(Element element) {
    final fragment = element.firstFragment;
    final root = writer.scope ?? this.root;
    final unit = root.root;
    if (unit is! CompilationUnit) return false;
    final source = unit.declaredFragment?.source;
    return source != null &&
        fragment.libraryFragment?.source == source &&
        fragment.offset >= root.offset &&
        fragment.offset < root.end;
  }

  @override
  void visitThisExpression(ThisExpression node) {
    final spelling = analyzer.thisFor(node.staticType);
    if (spelling == null) {
      _surfaceOnly(node, 'this');
    } else if (spelling != 'this') {
      _replace(node, spelling);
    }
  }

  @override
  void visitSuperExpression(SuperExpression node) =>
      _surfaceOnly(node, 'super');

  @override
  void visitNamedType(NamedType node) {
    final element = node.element;
    if (element == null) {
      if (node.name.lexeme != 'dynamic' && node.name.lexeme != 'void') {
        _fail(node);
      }
    } else if (element is! TypeParameterElement) {
      final spelling = analyzer.namespace.elementName(element);
      if (spelling == null) {
        _unnamed(node, node.name.lexeme);
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
    if (target is ThisExpression ||
        (target is SimpleIdentifier && _isStateWidget(target.element))) {
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
    if (writer.holes[node] case final text?) {
      _replace(node, text);
      return;
    }
    final target = node.target;
    if (target == null) {
      _reference(
        node.methodName,
        node.methodName.element,
        node.methodName.name,
      );
    } else if (target is SimpleIdentifier && target.element is PrefixElement) {
      // A call through an import prefix: the generated part shares the
      // library's imports, so it is written as the app wrote it.
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
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    if (writer.holes[node.expression] case final text?) {
      _replace(node.expression, text);
    } else {
      super.visitExpressionFunctionBody(node);
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (writer.holes[node] case final text?) {
      _replace(node, text);
    } else {
      super.visitInstanceCreationExpression(node);
    }
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    final value = node.expression;
    final text = value == null ? null : writer.holes[value];
    if (value != null && text != null) {
      _replace(value, text);
    } else {
      super.visitReturnStatement(node);
    }
  }

  @override
  void visitArgumentList(ArgumentList node) {
    for (final argument in node.arguments) {
      final value = argument is NamedArgument
          ? argument.argumentExpression
          : argument;
      if (writer.holes[value] case final text?) {
        _replace(value, text);
      } else {
        argument.accept(this);
      }
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.inDeclarationContext() || _isSelector(node)) return;
    // An assignment or increment target resolves through its write element.
    final element =
        node.element ??
        switch (node.parent) {
          CompoundAssignmentExpression(:final writeElement) => writeElement,
          _ => null,
        };
    _reference(node, element, node.name);
  }

  void _reference(AstNode node, Element? raw, String name) {
    if (raw == null) {
      _fail(node);
      return;
    }
    final element = raw is PropertyAccessorElement
        ? raw.variable
        : raw.baseElement;
    final mountName = analyzer.mountNameOf(element);
    if (_declaredInside(element)) {
      // A local the mount declares under another name is read by that name.
      if (writer.scope == null && mountName != null && mountName != name) {
        _replace(node, mountName);
      }
      return;
    }
    // A lifted State's mount forwards `widget`.
    if (_isStateWidget(raw)) {
      if (analyzer.forwardsWidget()) {
        _replace(node, kStateWidgetSlot);
      } else {
        _surfaceOnly(node, name);
      }
      return;
    }
    if (analyzer.isMountScope(element)) {
      final spelled = mountName ?? name;
      if (_promotion(node, element) != null || spelled != name) {
        _write(node, element, spelled);
      }
      return;
    }
    final bound = analyzer.bindingFor(raw) ?? analyzer.bindingFor(element);
    if (bound != null) {
      if (active.contains(element)) {
        _fail(node);
        return;
      }
      final inner = writer.render(bound, [...active, element]);
      if (inner == null) return;
      _write(
        node,
        element,
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
        _replace(node, '\u0000$kRootContext\u0000');
        return;
      }
      if (analyzer.buildArgumentFor(element) case final argument?) {
        _replace(node, argument);
        return;
      }
      // A builder's own parameter, which a recorded copy of its body reads
      // where the app declares it.
      if (analyzer.recordedLocalOf(element) case final slot?) {
        _write(node, element, '\u0000$slot\u0000');
        return;
      }
      _surfaceOnly(node, name);
      return;
    }
    if (element is LocalVariableElement) {
      final item = analyzer.itemLoopFor(element);
      final current = writer.item;
      // Items of nested loops combine; the value belongs to the innermost.
      if (item == null ||
          current != null &&
              !_encloses(current, item) &&
              !_encloses(item, current)) {
        final slot = item == null ? analyzer.recordedLocalOf(element) : null;
        if (slot != null) {
          _write(node, element, '\u0000$slot\u0000');
          return;
        }
        _surfaceOnly(node, name);
        return;
      }
      if (current == null || _encloses(current, item)) {
        writer
          ..item = item
          ..itemName = name;
      }
      final read = analyzer.keepsItemNames(item) ? name : _itemMarker;
      if (read != name || _promotion(node, element) != null) {
        _write(node, element, read);
      }
      return;
    }
    // A function the build declares: the copy runs the build as written, so
    // it reads the function where the app declares it.
    if (element is LocalFunctionElement) {
      if (analyzer.recordedLocalOf(element) case final slot?) {
        _write(node, element, '\u0000$slot\u0000');
      } else {
        _surfaceOnly(node, name);
      }
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
    if (enclosing is LibraryElement && element is! InterfaceElement) {
      final visible = analyzer.namespace.elementName(element);
      // A name the generated mount declares reads through the part's alias.
      spelling = visible == name && kMountScopeNames.contains(name)
          ? mountAliasOf(element, name)
          : visible;
    } else if (element is InterfaceElement) {
      spelling = analyzer.namespace.elementName(element);
    } else if (isStatic) {
      spelling = analyzer.namespace.staticMemberName(element);
    } else if (analyzer.isSurfaceMember(element)) {
      spelling = '\u0000$kSurfaceInstance\u0000.$name';
    } else {
      _surfaceOnly(node, name, element: element);
      return;
    }
    if (spelling == null) {
      _unnamed(node, element.name ?? name);
      return;
    }
    _write(node, element, spelling);
  }

  // Writes [text] for the read at [node], cast to the type the surface
  // promoted it to.
  void _write(AstNode node, Element element, String text) {
    final type = _promotion(node, element);
    if (type == null) {
      _replace(node, text);
      return;
    }
    final code = analyzer.namespace.typeCode(type);
    if (code == null) {
      _unnamed(node, type.getDisplayString());
      return;
    }
    _replace(node, '($text as $code)');
  }

  // The promoted type of the read at [node] when it differs from the
  // declared one; the part ignores the casts a copied guard makes redundant.
  DartType? _promotion(AstNode node, Element element) {
    if (element is! VariableElement || node is! Expression) return null;
    final type = node.staticType;
    if (type == null || type is DynamicType || type == element.type) {
      return null;
    }
    return type;
  }

  bool _isStateWidget(Element? element) => analyzer.isStateWidget(element);

  // Whether the loop over [outer] items encloses the loop over [inner], or
  // they are the same.
  bool _encloses(String outer, String inner) {
    for (String? item = inner; item != null; item = analyzer.outerItem(item)) {
      if (item == outer) return true;
    }
    return false;
  }
}

bool _isSelector(SimpleIdentifier identifier) => switch (identifier.parent) {
  ConstructorName(:final name) when identical(name, identifier) => true,
  MethodInvocation(:final methodName) when identical(methodName, identifier) =>
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
