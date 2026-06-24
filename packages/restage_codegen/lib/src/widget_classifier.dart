import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/const_folding.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/modal_sheet_recognition.dart';
import 'package:restage_codegen/src/motion_recognition.dart';
import 'package:restage_codegen/src/navigation_recognition.dart';
import 'package:restage_codegen/src/number_format_recognition.dart';
import 'package:restage_codegen/src/setstate_recognition.dart';
import 'package:restage_codegen/src/theme_recognition.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:restage_shared/restage_shared.dart' show kSupportedCurveNames;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Canonical `'<library URI>#<ClassName>'` key for [cls] — how a custom
/// widget is keyed in the classification result map. Never carries a
/// constructor suffix, so it matches both [WidgetEntry.flutterType] and the
/// key the translator derives from a resolved widget construction.
String customWidgetKey(ClassElement cls) =>
    '${cls.library.identifier}#${cls.name ?? '<unnamed>'}';

/// The chain of supertype elements above [cls], nearest first.
Iterable<InterfaceElement> _supertypeChain(ClassElement cls) sync* {
  var supertype = cls.supertype;
  while (supertype != null) {
    yield supertype.element;
    supertype = supertype.element.supertype;
  }
}

/// Unwraps an implicit getter/setter to the variable it backs, so a bare
/// field reference and a field-getter reference resolve alike.
Element? _unwrapAccessor(Element? element) =>
    element is PropertyAccessorElement ? element.variable : element;

/// The `this.x` constructor formals of [constructor] as [CustomWidgetParam]s
/// in declaration order — the widget fields a call site passes, and that the
/// emitted remote-widget definition reads as `args.x` references.
///
/// Returns `null` when a parameter carries a default value the constant
/// folder cannot evaluate to a scalar: such a widget cannot be inlined
/// faithfully (an omitted argument could not reproduce the Dart default).
List<CustomWidgetParam>? _constructorParams(
  ConstructorElement constructor,
  Map<String, Expression> coalescedFallbacks,
) {
  final params = <CustomWidgetParam>[];
  for (final parameter in constructor.formalParameters) {
    if (parameter is! FieldFormalParameterElement) continue;
    final name = parameter.name;
    if (name == null) continue;
    final defaultObject = parameter.computeConstantValue();
    Object? defaultValue;
    if (defaultObject != null && !defaultObject.isNull) {
      defaultValue = decodeConstScalar(defaultObject);
      if (defaultValue == null) return null;
    }
    params.add(
      CustomWidgetParam(
        name: name,
        isNumeric: _isNumericType(parameter.type),
        defaultValue: defaultValue,
        coalesceFallback: coalescedFallbacks[name],
      ),
    );
  }
  return params;
}

/// Whether [type] is `double` or `num` — a numeric parameter whose call-site
/// value is coerced to a double literal for emission.
bool _isNumericType(DartType type) {
  if (type is! InterfaceType) return false;
  final name = type.element.name;
  return name == 'double' || name == 'num';
}

/// The bespoke structured value types the translator lowers to RFW maps /
/// lists outside the catalog decompose path — a construction of one of these
/// is pure composition (its arguments are still walked, so a runtime-computed
/// argument is still caught).
///
/// This is the classifier's stable base set. The full recognised set is this
/// UNION the catalog's `structuredTypes` (the decompose-able types —
/// `TextStyle`, `ButtonStyle`, the shape borders, …), so the classifier's
/// value vocabulary stays reconciled with the translator's WITHOUT a
/// hand-maintained mirror of the decompose types. The recognition is
/// deliberately over-broad in the SAFE direction: a value type the classifier
/// recognises but the translator cannot lower produces a translator
/// diagnostic, backstopped by the catalog value-type floor — never a silent
/// wrong blob.
const Set<String> kStructuredValueTypeNames = {
  'Alignment',
  'AlignmentDirectional',
  'AssetImage',
  'Border',
  'BorderRadius',
  'BorderRadiusDirectional',
  'BorderSide',
  'BoxDecoration',
  'BoxShadow',
  'Color',
  'DecorationImage',
  'EdgeInsets',
  'EdgeInsetsDirectional',
  'LinearGradient',
  'Locale',
  'NetworkImage',
  'Offset',
  'Paint',
  'RadialGradient',
  'Radius',
  'Size',
  'SweepGradient',
  'TextStyle',
};

/// Framework namespaces whose members are static named constants the translator
/// lowers — `Colors.*` (packed colours), `Icons.*` / `CupertinoIcons.*` (icon
/// codepoints). A prefixed reference into one of these is pure composition; the
/// translator is the strict gate on whether the specific member resolves.
const Set<String> kFrameworkConstNamespaces = {
  'Colors',
  'Icons',
  'CupertinoIcons',
};

/// Framework classes whose members are static named constants (NOT Dart enums,
/// so the const/enum folder cannot fold them) but which the translator lowers to
/// their bare member-name string, decoded by a string-name enum decoder
/// (`PropertyType.fontWeight` via `enumValue<FontWeight>`, `textDecoration` via
/// `RestageDecoders.textDecoration`). Each class here is design-verified that
/// every member round-trips its emitted name through the decoder — FontWeight's
/// `normal`/`bold` aliases are canonicalised to their `wN` name in the
/// translator, and TextDecoration's four members decode directly. A prefixed
/// reference into one of these, element-gated to the real framework class, is
/// pure composition. `Curves` is included but, unlike the other two, is pinned
/// per-member to the supported curve vocabulary (the per-member check in
/// `_isFrameworkEnumLikeConst`): its decoder vocabulary is a strict subset of
/// Flutter's `Curves` members, and the classifier (custom-widget body) path has
/// no validator backstop, so a member outside the supported set defers rather
/// than emitting a name the decoder would silently null.
const Set<String> kFrameworkEnumLikeConstClasses = {
  'FontWeight',
  'TextDecoration',
  'Curves',
};

/// `(class, member)` pairs of structured-value static-const members the
/// translator already lowers to their map/list/scalar shape — `BorderSide.none`
/// (a `{width, style}` map via `_borderSideExpression`) and the `.zero`
/// const-factory siblings (`EdgeInsets`/`EdgeInsetsDirectional` → a 4-element
/// list, `BorderRadius`/`BorderRadiusDirectional` → the scalar `0`, `Offset` →
/// an `{x, y}` map). Unlike the enum-string classes above, these lower to
/// structured shapes, not bare member names. The set is member-SPECIFIC (only
/// the pairs the translator provably lowers): e.g. `Offset.infinite` is a real
/// static const the translator does NOT lower, so it is absent and stays
/// fail-closed. Recognition is element-gated to the real framework class (the
/// `_isStructuredConstMember` check); the translator's lowering arms are each
/// already look-alike-gated, so the two paths stay symmetric.
const Set<(String, String)> kStructuredConstMembers = {
  ('BorderSide', 'none'),
  ('EdgeInsets', 'zero'),
  ('EdgeInsetsDirectional', 'zero'),
  ('BorderRadius', 'zero'),
  ('BorderRadiusDirectional', 'zero'),
  ('Offset', 'zero'),
};

/// `State` lifecycle methods — their presence makes a widget imperative.
const Set<String> _kLifecycleMethods = {
  'initState',
  'dispose',
  'didChangeDependencies',
  'didUpdateWidget',
  'deactivate',
  'activate',
  'reassemble',
};

enum _WidgetKind { stateless, stateful }

/// Walks a resolved `@RestageWidget` custom widget and classifies it as
/// pure-composition (class 4a — transpilable) or imperative (class 4b), or
/// reports it unclassifiable when this codegen increment cannot reach a
/// verdict.
///
/// One instance is reused for a whole build pass: [classify] is memoized in
/// [results], and recursion into composed custom widgets shares that memo.
final class WidgetClassifier {
  /// Creates a classifier validating composed widgets against [catalog],
  /// recognising helper calls through [helpers], and reaching widget source
  /// through [astNodeFor] (production wires
  /// `resolver.astNodeFor(_, resolve: true)`).
  WidgetClassifier({
    required this.catalog,
    required this.astNodeFor,
    HelperRegistry? helpers,
  }) : helpers = helpers ?? HelperRegistry();

  /// Merged catalog — tells catalog-widget composition apart from a nested
  /// custom widget to recurse into.
  final Catalog catalog;

  /// Registry of recognised paywall-helper calls — a helper call inside a
  /// custom widget classifies as composition, not as a Dart call.
  final HelperRegistry helpers;

  /// Resolved-AST provider for an element's fragment.
  final Future<AstNode?> Function(Fragment fragment) astNodeFor;

  /// `flutterType` of every merged-catalog widget — a set, for O(1)
  /// catalog-membership lookups during the walk.
  late final Set<String> _catalogFlutterTypes = {
    for (final w in catalog.widgets) w.flutterType,
  };

  /// Names of the catalog's decompose-able structured types (`TextStyle`,
  /// `ButtonStyle`, the shape borders, …). The catalog IS the single source
  /// of truth for the decompose set, so the classifier recognises exactly the
  /// structured-value constructions the translator can lower via decomposition
  /// — no hand-maintained mirror, no classifier↔translator drift.
  late final Set<String> _catalogStructuredTypeNames = {
    for (final s in catalog.structuredTypes) s.name,
  };

  final Map<String, WidgetClassification> _results = {};
  final Map<String, CustomWidgetBlueprint> _blueprints = {};
  final Set<String> _inProgress = {};

  /// Every widget classified so far this pass, keyed by
  /// [WidgetClassification.classKey] — the map the translator consults.
  Map<String, WidgetClassification> get results => Map.unmodifiable(_results);

  /// Emission blueprints for every widget that classified [ComposableWidget]
  /// this pass, keyed by [WidgetClassification.classKey]. A `4b` /
  /// unclassifiable widget contributes no blueprint.
  Map<String, CustomWidgetBlueprint> get blueprints =>
      Map.unmodifiable(_blueprints);

  /// Classifies [widgetClass] (a resolved `@RestageWidget` class), recursing
  /// into every custom widget it composes. Memoized; a composition cycle
  /// resolves to [UnclassifiableWidget].
  Future<WidgetClassification> classify(ClassElement widgetClass) async {
    final key = customWidgetKey(widgetClass);
    final cached = _results[key];
    if (cached != null) return cached;
    if (_inProgress.contains(key)) {
      return UnclassifiableWidget(
        key,
        reason: 'the widget is part of a composition cycle',
      );
    }
    _inProgress.add(key);
    final WidgetClassification result;
    try {
      result = await _classify(widgetClass, key);
    } finally {
      _inProgress.remove(key);
    }
    _results[key] = result;
    return result;
  }

  Future<WidgetClassification> _classify(
    ClassElement widgetClass,
    String key,
  ) async {
    final kind = _widgetKind(widgetClass);
    if (kind == null) {
      return UnclassifiableWidget(
        key,
        reason: 'the class is neither a StatelessWidget nor a StatefulWidget',
      );
    }

    var buildHost = widgetClass;
    ClassElement? stateClass;
    if (kind == _WidgetKind.stateful) {
      stateClass = await _resolveStateClass(widgetClass);
      if (stateClass == null) {
        return UnclassifiableWidget(
          key,
          reason: "the widget's State class could not be resolved",
        );
      }
      buildHost = stateClass;
    }

    final buildMethod =
        buildHost.methods.where((m) => m.name == 'build').firstOrNull;
    if (buildMethod == null) {
      return UnclassifiableWidget(key, reason: 'no build() method was found');
    }
    final node = await astNodeFor(buildMethod.firstFragment);
    if (node is! MethodDeclaration) {
      return UnclassifiableWidget(
        key,
        reason: "the widget's build() source was not available "
            'to the transpiler',
      );
    }
    final extracted = extractInlinableBuildBody(node.body);
    if (extracted == null) {
      return UnclassifiableWidget(
        key,
        reason: 'build() body is not a single returned expression',
      );
    }
    final returnExpr = extracted.expression;
    // Capture leading `final` local bindings (name element → initializer) so a
    // reference to one resolves-through to its initializer in the walk and the
    // translator. `const` locals are not captured — they fold at the use site.
    final localBindings = <Element, Expression>{};
    for (final variable in extracted.finalLocals) {
      final element = variable.declaredFragment?.element;
      final initializer = variable.initializer;
      if (element != null && initializer != null) {
        localBindings[element] = initializer;
      }
    }

    final walk = _Walk(this, widgetClass, stateClass, localBindings);
    if (stateClass != null) {
      await walk.classifyStateShape(stateClass);
    }
    await walk.classify(returnExpr);
    final classification = walk.toClassification(key);
    if (classification is! ComposableWidget) return classification;

    // A class-4a widget is a candidate for inlining. Capture the emission
    // material now, while the resolved build() expression is in hand —
    // re-resolving its source in a later pass would be wasted work.
    final constructors = widgetClass.constructors;
    if (constructors.length > 1) {
      // Disambiguating which constructor a call site targets is a tracked
      // follow-up; until then a positional call could mis-map arguments.
      return UnclassifiableWidget(
        key,
        reason: 'the widget declares multiple constructors, which this '
            'transpiler increment does not disambiguate for inlining',
      );
    }
    final params = _constructorParams(
      constructors.single,
      walk.coalescedParams,
    );
    if (params == null) {
      return UnclassifiableWidget(
        key,
        reason: 'a constructor parameter has a default value the transpiler '
            'cannot fold to a literal',
      );
    }
    final eventHandlers = <String, RecognisedSetState>{};
    if (stateClass != null) {
      final stateFieldNames = walk.stateFields.map((f) => f.name).toSet();
      final methods = walk.eventHandlerMethods.toList();
      // The handler ASTs are resolved in parallel — each `astNodeFor` is an
      // independent I/O-bound resolution, and recognition itself is purely
      // synchronous on the resulting node. Order maps back to [methods] so
      // the verdicts land on the right method names.
      final methodNodes = await Future.wait([
        for (final method in methods) astNodeFor(method.firstFragment),
      ]);
      for (var i = 0; i < methods.length; i++) {
        final methodName = methods[i].name ?? '<unnamed>';
        final methodNode = methodNodes[i];
        if (methodNode is MethodDeclaration) {
          eventHandlers[methodName] = recogniseSetState(
            methodNode,
            stateFieldNames: stateFieldNames,
          );
        } else {
          eventHandlers[methodName] = const SetStateUnrecognised(
            reason: 'the method source was not available to the transpiler',
          );
        }
      }
    }
    _blueprints[key] = CustomWidgetBlueprint(
      classKey: key,
      rfwName: widgetClass.name ?? '<unnamed>',
      buildExpression: returnExpr,
      params: params,
      // A stateful widget always carries a (possibly empty) state list; a
      // stateless widget has none. The translator gates its stateful-context
      // lowering on the list being non-null, not non-empty.
      state: stateClass == null ? null : walk.stateFields,
      eventHandlers: eventHandlers,
      modalSheets: walk.modalSheets,
      // The own helper methods (and, later, local bindings) the walk
      // resolved-through — the translator inlines them at the call site.
      inlined: walk.inlinedDefinitions,
    );
    return classification;
  }

  /// Whether [cls] is a `StatelessWidget` or `StatefulWidget` subclass.
  _WidgetKind? _widgetKind(ClassElement cls) {
    for (final element in _supertypeChain(cls)) {
      if (element.name == 'StatelessWidget') return _WidgetKind.stateless;
      if (element.name == 'StatefulWidget') return _WidgetKind.stateful;
    }
    return null;
  }

  /// Resolves the `State` subclass a `StatefulWidget`'s `createState()`
  /// returns — from the declared return type, then the returned instance.
  Future<ClassElement?> _resolveStateClass(ClassElement widget) async {
    final createState =
        widget.methods.where((m) => m.name == 'createState').firstOrNull;
    if (createState == null) return null;
    final returnType = createState.returnType;
    if (returnType is InterfaceType) {
      final element = returnType.element;
      if (element is ClassElement && element.name != 'State') {
        return element;
      }
    }
    final node = await astNodeFor(createState.firstFragment);
    if (node is MethodDeclaration) {
      final returned = singleReturnExpressionOf(node.body);
      if (returned is InstanceCreationExpression) {
        final element = returned.constructorName.type.element;
        if (element is ClassElement) return element;
      }
    }
    return null;
  }

  /// Whether a construction of [cls] via [constructorName] (null = the
  /// unnamed constructor) is one of the merged catalog's widgets. The match
  /// is constructor-aware, mirroring the translator's `flutterType` lookup —
  /// a named-constructor catalog entry is matched only by that constructor.
  bool isCatalogWidget(ClassElement cls, {String? constructorName}) {
    final key = customWidgetKey(cls);
    final fullKey = (constructorName == null || constructorName.isEmpty)
        ? key
        : '$key.$constructorName';
    return _catalogFlutterTypes.contains(fullKey);
  }

  /// Whether [cls] carries an `@RestageWidget` annotation.
  bool isCustomWidget(ClassElement cls) =>
      firstAnnotation(cls, 'RestageWidget') != null;
}

/// Mutable per-classification accumulator: walks one widget's `build()`
/// expression, collecting the inlining mechanisms it needs, the imperative
/// constructs that block it, and the custom widgets it composes.
class _Walk {
  _Walk(
    this._classifier,
    this._widgetClass,
    this._stateClass,
    this._localBindings,
  );

  final WidgetClassifier _classifier;
  final ClassElement _widgetClass;
  final ClassElement? _stateClass;

  /// Leading `final` local bindings in `build()` (element → initializer) — a
  /// reference to one resolves-through to its initializer. Captured before the
  /// walk; carried onto the blueprint for the translator.
  final Map<Element, Expression> _localBindings;

  final Set<InliningMechanism> _mechanisms = {};
  final List<Blocker> _blockers = [];
  final List<String> _composed = [];
  final List<CustomWidgetStateField> _stateFields = [];
  final Set<MethodElement> _eventHandlerMethods = {};
  final List<RecognisedModalSheet> _modalSheets = [];
  String? _unclassifiableReason;
  IssueCode? _unclassifiableDiagnosticCode;

  /// Own helper methods resolved-through during the walk, keyed by the
  /// helper's resolved [Element] — the emission material the translator
  /// inlines at each call site. Captured here (the walk already resolves the
  /// helper AST to recurse into it) so the translator never re-resolves.
  final Map<Element, HelperDef> _capturedHelpers = {};

  /// Helper elements currently on the resolve-through stack — the cycle guard.
  /// A helper that (transitively) calls itself is diagnosed, never looped.
  final Set<Element> _helperStack = {};

  /// Active helper-parameter bindings (param element → bound argument
  /// expression) while resolving-through a parameterized helper body. A
  /// reference to a bound parameter resolves-through to its argument,
  /// classified in the caller's context. Added on helper entry, removed on
  /// exit; element-keyed so nested helpers and same-named params don't
  /// collide.
  final Map<Element, Expression> _paramBindings = {};

  /// Optional constructor properties the body reads as `<name> ?? <fallback>`,
  /// keyed by property name with the fallback expression — the call-site
  /// completion material the translator hoists. A property here is read ONLY
  /// coalesced (a property read both directly and coalesced is rejected by the
  /// uniform-coalescing gate, since the call site cannot complete it
  /// consistently).
  final Map<String, Expression> _coalescedParams = {};

  /// Constructor-property names the body reads directly (a bare `args.<name>`
  /// read), tracked so the uniform-coalescing gate can reject a property read
  /// both directly and coalesced.
  final Set<String> _bareParamReads = {};

  /// The optional-property fallbacks recognised during the walk — carried onto
  /// the blueprint so the translator completes omitted/explicit-null call
  /// sites with the fallback's lowered value.
  Map<String, Expression> get coalescedParams => _coalescedParams;

  /// The captured named intermediates for the blueprint.
  InlinedDefinitions get inlinedDefinitions => InlinedDefinitions(
        helpers: Map.of(_capturedHelpers),
        localBindings: Map.of(_localBindings),
      );

  /// The `State` fields captured by [classifyStateShape], in declaration
  /// order — passed to the blueprint when a stateful widget classifies
  /// [ComposableWidget]. Empty for a stateless widget.
  List<CustomWidgetStateField> get stateFields => _stateFields;

  /// The State methods referenced as event-handler tear-offs in `build()`,
  /// collected during the walk. The classifier resolves each to a
  /// [RecognisedSetState] verdict after the walk completes, so the
  /// translator emits `set state.<field> = …` directly from the verdict.
  Set<MethodElement> get eventHandlerMethods => _eventHandlerMethods;

  /// Modal-sheet trigger calls captured from inline event-handler closures.
  List<RecognisedModalSheet> get modalSheets => _modalSheets;

  /// Validates a `State` class's shape: a lifecycle method or a non-primitive
  /// field is an imperative construct; a State holding only primitive fields
  /// contributes the declarative-state mechanism.
  ///
  /// The field check is intentionally shallow — field *types* only, not
  /// mutation sites. Initialisers are folded here (so the blueprint carries
  /// the emitted state-block's initial values), but a non-foldable
  /// initialiser is **not** a blocker; it lands as a null `initialValue` on
  /// the captured `CustomWidgetStateField`, and the translator's emit-time
  /// validation surfaces it as a `stateShapeUnsupported` diagnostic. An
  /// over-broad declarative-state tag here is safe: a declarative-state
  /// widget carries a deferred mechanism and is never inlined directly.
  Future<void> classifyStateShape(ClassElement stateClass) async {
    // The State-level motion signal: a non-primitive field of an
    // animation-controller-family type (element-gated on `package:flutter/`)
    // means this widget drives imperative animation, so its (already-deferred)
    // lifecycle-method AND motion-field diagnostics NAME the catalog motion
    // widgets to adopt. The lifecycle blocker is enriched too because
    // classifyStateShape adds it BEFORE the field blocker and the diagnostic
    // surfaces the first dead-end blocker — without this the author would see
    // a generic lifecycle message and never the motion hint. A lifecycle
    // method in a non-motion State keeps its generic detail (the
    // look-alike-safe direction — a `Timer` / stream / focus node is not
    // animation).
    final hasMotionField = stateClass.fields.any(
      (field) => !field.isStatic && isImperativeMotionType(field.type),
    );
    for (final method in stateClass.methods) {
      if (_kLifecycleMethods.contains(method.name)) {
        await _memberBlocker(
          BlockerKind.asyncOrLifecycle,
          method,
          hasMotionField
              ? motionDeferMessage()
              : 'the State lifecycle method ${method.name}()',
        );
      }
    }
    final primitiveFields = <FieldElement>[];
    for (final field in stateClass.fields) {
      if (field.isStatic) continue;
      if (_isPrimitiveType(field.type)) {
        primitiveFields.add(field);
      } else {
        await _memberBlocker(
          BlockerKind.nonSimpleState,
          field,
          isImperativeMotionType(field.type)
              ? motionDeferMessage()
              : "the non-primitive State field '${field.name}'",
        );
      }
    }
    // Each `_foldFieldInitialiser` awaits an independent AST resolution; run
    // them in parallel so a stateful widget with N primitive fields pays one
    // round-trip instead of N.
    final initialValues = await Future.wait([
      for (final field in primitiveFields) _foldFieldInitialiser(field),
    ]);
    for (var i = 0; i < primitiveFields.length; i++) {
      final field = primitiveFields[i];
      _stateFields.add(
        CustomWidgetStateField(
          name: field.name ?? '<unnamed>',
          isNumeric: _isNumericType(field.type),
          initialValue: initialValues[i],
        ),
      );
    }
    if (primitiveFields.isNotEmpty) {
      _mechanisms.add(InliningMechanism.declarativeState);
    }
  }

  /// Folds [field]'s declared initialiser to an [int], [double], [bool],
  /// [String], or the bare name of an enum constant — or returns `null` when
  /// the classifier cannot fold it (a runtime call, an unrecognised
  /// expression, or a missing initialiser). Returning `null` is not a
  /// blocker; the translator surfaces it as a `stateShapeUnsupported`
  /// diagnostic at emit time.
  Future<Object?> _foldFieldInitialiser(FieldElement field) async {
    final node = await _classifier.astNodeFor(field.firstFragment);
    if (node is! VariableDeclaration) return null;
    final initializer = node.initializer;
    if (initializer == null) return null;
    return tryFoldConstant(initializer) ?? enumConstantName(initializer);
  }

  Future<void> _memberBlocker(
    BlockerKind kind,
    Element member,
    String detail,
  ) async {
    final node = await _classifier.astNodeFor(member.firstFragment);
    final location = node != null
        ? _locationOf(node)
        : '${customWidgetKey(_widgetClass)}@${member.name ?? '<unnamed>'}';
    // The member's own name is the structured aggregation subject (a lifecycle
    // method or a non-primitive state field — `initState`, `controller`).
    _blockers.add(
      Blocker(
        kind: kind,
        location: location,
        detail: detail,
        idiomSubject: member.name ?? '<unnamed>',
      ),
    );
  }

  /// Classifies [expr] (and, recursively, its sub-expressions), folding the
  /// outcome into this accumulator.
  Future<void> classify(Expression? expr) async {
    if (expr == null) return;
    // A reference to a bound helper parameter resolves-through to its argument,
    // classified in the caller's context — the inlined body's structure. A
    // reference to a leading `final` local resolves-through to its initializer.
    if (expr is SimpleIdentifier) {
      final boundArg = _paramBindings[expr.element];
      if (boundArg != null) {
        await classify(boundArg);
        return;
      }
      final localInitializer = _localBindings[expr.element];
      if (localInitializer != null) {
        await classify(localInitializer);
        return;
      }
    }
    if (expr is InstanceCreationExpression) {
      await _construction(expr);
      return;
    }
    if (expr is NamedExpression) {
      await classify(expr.expression);
      return;
    }
    if (expr is ListLiteral) {
      for (final element in expr.elements) {
        if (element is Expression) {
          await classify(element);
        } else {
          _unclassifiable('a list with a spread / if / for element this '
              'transpiler increment does not yet expand');
        }
      }
      return;
    }
    if (expr is MethodInvocation) {
      await _methodInvocation(expr);
      return;
    }
    // A const-object field access (`const _skin = Skin(...); _skin.label`) —
    // consulted ahead of the PropertyAccess / PrefixedIdentifier arms via the
    // SAME resolver the translator folds against, so the classifier's verdict
    // can never diverge from what the translator emits: foldable → the
    // constant-folding mechanism (transpilable); recognised-but-unfoldable →
    // deferred (the translator loud-defers the same access).
    if (_tryConstObjectField(expr)) return;
    if (expr is PropertyAccess) {
      _propertyAccess(expr);
      return;
    }
    if (expr is BinaryExpression) {
      // `<optional property> ?? <context-independent fallback>` — the
      // null-coalescing optional-property idiom. Recognised before the generic
      // runtime-computed-value blocker so the canonical themable-default shape
      // lowers via call-site completion.
      if (expr.operator.lexeme == '??' && await _tryClassifyCoalesce(expr)) {
        return;
      }
      _binaryExpression(expr);
      return;
    }
    if (expr is ConditionalExpression) {
      await classify(expr.condition);
      await classify(expr.thenExpression);
      await classify(expr.elseExpression);
      return;
    }
    if (expr is PrefixedIdentifier) {
      _prefixedIdentifier(expr);
      return;
    }
    if (expr is FunctionExpression) {
      _unclassifiable('an inline event-handler closure, which this '
          'transpiler increment does not yet analyse');
      return;
    }
    if (_isPlainLiteral(expr)) return;
    if (expr is SimpleIdentifier) {
      _identifier(expr);
      return;
    }
    _unclassifiable(
      'an expression this transpiler increment does not yet recognise '
      '(${expr.runtimeType})',
    );
  }

  Future<void> _construction(InstanceCreationExpression expr) async {
    final type = expr.constructorName.type.element;
    if (type is! ClassElement) {
      _unclassifiable('a widget construction whose type did not resolve');
      return;
    }
    if (_isWidgetClass(type)) {
      if (type.name == 'CustomPaint') {
        _blocker(BlockerKind.customPainter, expr, _truncateSource(expr));
        return;
      }
      if (_classifier.isCatalogWidget(
        type,
        constructorName: expr.constructorName.name?.name,
      )) {
        await _classifyArguments(expr);
        return;
      }
      if (_classifier.isCustomWidget(type)) {
        await _composeCustomWidget(type, expr);
        return;
      }
      _blocker(
        BlockerKind.unrecognisedComposedWidget,
        expr,
        _truncateSource(expr),
      );
      return;
    }
    if (_isStructuredValueType(type)) {
      await _classifyArguments(expr);
      return;
    }
    // A directly-constructed Flutter spring (`SpringDescription` /
    // `SpringSimulation`) is imperative animation — name the catalog spring
    // widget to adopt. Element-gated on `package:flutter/`; a customer
    // look-alike of the same name falls through to the generic reason.
    final springTarget = springAdoptTarget(expr);
    _unclassifiable(
      springTarget != null
          ? motionDeferMessage(springTarget)
          : "a construction of '${type.name}', which this transpiler increment "
              'does not yet recognise',
    );
  }

  Future<void> _classifyArguments(InstanceCreationExpression expr) async {
    final type = expr.constructorName.type.element;
    final isCatalogWidget = type is ClassElement &&
        _isWidgetClass(type) &&
        _classifier.isCatalogWidget(
          type,
          constructorName: expr.constructorName.name?.name,
        );
    for (final arg in expr.argumentList.arguments) {
      if (isCatalogWidget && _tryClassifyNavigationTrigger(arg)) {
        continue;
      }
      if (isCatalogWidget && _tryClassifyModalSheetTrigger(arg)) {
        continue;
      }
      await classify(arg);
    }
  }

  bool _tryClassifyNavigationTrigger(Expression arg) {
    if (arg is! NamedExpression) return false;

    final outcome = recogniseNavigationTrigger(arg.expression);
    if (outcome is NavigationNotRecognised) return false;
    _unclassifiable(
      'screen navigation is only lowered from a paywall root in this '
      'increment, not inside a custom widget',
      diagnosticCode: IssueCode.navigationFormUnsupported,
    );
    return true;
  }

  bool _tryClassifyModalSheetTrigger(Expression arg) {
    if (arg is! NamedExpression) return false;
    final slotName = arg.name.label.name;
    final isTriggerSlot = isModalSheetTriggerSlotName(slotName);

    switch (recogniseModalSheetTrigger(arg.expression)) {
      case ModalSheetRecognised(:final sheet):
        if (!isTriggerSlot) {
          _unclassifiable(
            kModalSheetTriggerSlotUnsupportedReason,
            diagnosticCode: IssueCode.modalSheetFormUnsupported,
          );
          return true;
        }
        _mechanisms
          ..add(InliningMechanism.declarativeState)
          ..add(InliningMechanism.modalSheet);
        _modalSheets.add(sheet);
        return true;
      case ModalSheetResultDropped(:final reason):
        _unclassifiable(
          reason,
          diagnosticCode: IssueCode.modalSheetFormUnsupported,
        );
        return true;
      case ModalSheetNotRecognised():
        return false;
    }
  }

  /// Recurses into a composed `@RestageWidget` custom widget [type], folding
  /// its verdict into this one: a composable widget rolls its required
  /// mechanisms up transitively; an imperative widget blocks this one;
  /// an unclassifiable widget makes this one unclassifiable too.
  Future<void> _composeCustomWidget(
    ClassElement type,
    InstanceCreationExpression expr,
  ) async {
    final nested = await _classifier.classify(type);
    _composed.add(nested.classKey);
    switch (nested) {
      case ComposableWidget():
        _mechanisms.addAll(nested.requiredMechanisms);
      case ImperativeWidget():
        // Inherit the composed child's disposition: composing a merely
        // reducible-not-yet child makes THIS widget reducible-not-yet too, not
        // a genuine dead end. Only a provably-imperative child propagates a
        // dead-end disposition upward.
        _blocker(
          BlockerKind.composesImperativeWidget,
          expr,
          _truncateSource(expr),
          dispositionOverride: nested.disposition,
        );
      case UnclassifiableWidget():
        _unclassifiable(
          "the custom widget '${type.name}', which this transpiler "
          'increment does not yet classify (${nested.reason})',
        );
    }
    // The arguments passed at this call site are still part of this
    // widget's build() and must be classified.
    await _classifyArguments(expr);
  }

  Future<void> _methodInvocation(MethodInvocation expr) async {
    // A bare `Theme.of(c)` or `DefaultTextStyle.of(c)` call without a
    // trailing property chain produces an object (ThemeData / TextStyle)
    // that cannot be emitted as a blob primitive — the chained form is
    // handled at _propertyAccess. So an unchained Flutter `.of(c)` call is
    // a Dart call from the blob's perspective, just like any other.
    if (_isRegisteredHelper(expr)) {
      // A recognised paywall helper — composition, not a Dart call.
      return;
    }
    // A Widget-/value-returning helper resolving by ELEMENT to the widget's own
    // instance method, OR a top-level function / static method in the widget's
    // own LIBRARY — named-intermediate inlining. Resolve-through to the
    // helper's body so the existing walk validates the inlined composition;
    // a customer look-alike of the same name resolves to a different element
    // (or a different library) and is NOT inlined (the S13 look-alike-safe
    // rule).
    final inlinable = _resolveInlinableHelper(expr);
    if (inlinable != null) {
      await _inlineHelper(inlinable, expr);
      return;
    }
    // The structured-value FACTORIES authors reach for — `EdgeInsets.all`,
    // `BorderRadius.circular`, `Color.fromARGB`, `Border.all` — are factory /
    // named CONSTRUCTORS, so they parse as InstanceCreationExpression and are
    // recognised by `_construction` (the structured-value path). A true static
    // *method* on a value type (`ButtonStyle.styleFrom`, `EdgeInsets.lerp`) is
    // NOT lowered by the translator, so it stays a `dartCall` — a `reducible`
    // deferral ("not supported yet"), which is the honest disposition.
    // Recognising it here would make the classifier claim composable for a
    // construct emission then fails to lower (a `classifierOnly` over-claim).
    //
    // A NumberFormat `.format()` formatting idiom keeps the `dartCall`
    // deferral (reducible) but names the catalog widget to adopt — the same
    // adopt-target the direct-paywall translator names, single-sourced so the
    // two paths never drift. Element-gated on `package:intl/`; a customer
    // look-alike falls through to the generic truncated-source detail.
    final formatAdoptTarget = numberFormatAdoptTarget(expr);
    _blocker(
      BlockerKind.dartCall,
      expr,
      formatAdoptTarget != null
          ? numberFormatDeferMessage(formatAdoptTarget)
          : _truncateSource(expr),
    );
  }

  /// The inlinable helper [expr] is a call to, or `null` when [expr] is not an
  /// inlinable helper call. Three shapes, all element-resolved (never
  /// name-matched), all excluding `build`:
  ///
  ///   * an own *instance* method of this widget's own class (or its `State`),
  ///     called bare (`_x(...)`) — the original named-intermediate rule;
  ///   * a top-level function declared in the widget's own library
  ///     (`_header()`);
  ///   * a `static` method whose declaring class is in the widget's own library
  ///     (`Helpers.row(...)`).
  ///
  /// The same-LIBRARY boundary (element identity, not name) is the
  /// look-alike-safe gate: a same-named top-level/static helper in ANOTHER
  /// library resolves to a different element and is NOT inlined — it falls
  /// through to the `dartCall` defer. Cross-library/cross-package helper
  /// resolution is out of scope.
  ExecutableElement? _resolveInlinableHelper(MethodInvocation expr) {
    final element = expr.methodName.element;
    if (element is! ExecutableElement || element.name == 'build') return null;
    // Scope: only a Widget-/value-RETURNING helper inlines. A function whose
    // return is a callback (a `FunctionType`, e.g. an event-handler factory
    // like a customer `paywallPurchase`) or `void`/`dynamic` is a Dart call,
    // not a composition helper — it must defer as a `dartCall`, not be pulled
    // into the inline path (which would then fail to classify its body). A
    // Widget or a value type is an `InterfaceType`.
    if (element.returnType is! InterfaceType) return null;
    // An own instance method, called bare — the original rule.
    if (element is MethodElement && !element.isStatic) {
      if (expr.target != null) return null;
      final owner = element.enclosingElement;
      return (owner == _widgetClass || owner == _stateClass) ? element : null;
    }
    // A top-level function or a static method declared in the widget's own
    // library. A target (the class reference for a static) is permitted; the
    // element's library identity is the gate.
    if (element is TopLevelFunctionElement ||
        (element is MethodElement && element.isStatic)) {
      return element.library == _widgetClass.library ? element : null;
    }
    return null;
  }

  /// Resolves [helper]'s body and recurses the walk into it so the inlined
  /// composition is validated in place; captures `(params, body)` for the
  /// translator to inline at the call site. A helper whose body is not a
  /// single returned expression, or whose source is unavailable, is a
  /// `dartCall` deferral. A recursive helper (already on [_helperStack]) is
  /// unclassifiable — diagnosed, never looped.
  Future<void> _inlineHelper(
    ExecutableElement helper,
    MethodInvocation call,
  ) async {
    if (!_helperStack.add(helper)) {
      _unclassifiable(
        "a recursive helper call ('${helper.name}'), which this transpiler "
        'increment cannot inline',
      );
      return;
    }
    try {
      final node = await _classifier.astNodeFor(helper.firstFragment);
      // A method (own instance, or a static) is a `MethodDeclaration`; a
      // top-level function is a `FunctionDeclaration` — both carry a
      // `FunctionBody` the single-return extractor reads.
      final fnBody = switch (node) {
        MethodDeclaration() => node.body,
        FunctionDeclaration() => node.functionExpression.body,
        _ => null,
      };
      if (fnBody == null) {
        _blocker(BlockerKind.dartCall, call, _truncateSource(call));
        return;
      }
      final body = singleReturnExpressionOf(fnBody);
      if (body == null) {
        _blocker(BlockerKind.dartCall, call, _truncateSource(call));
        return;
      }
      // Bind the call's arguments to the helper's parameters, 1:1. A binding
      // that is not provably 1:1 (count/name mismatch, a defaulted param) is
      // NOT inlinable — defer with a diagnostic rather than guess.
      final params = helper.formalParameters.toList();
      final binding = bindHelperArguments(
        params,
        call.argumentList.arguments.toList(),
      );
      if (binding == null) {
        _blocker(BlockerKind.dartCall, call, _truncateSource(call));
        return;
      }
      _capturedHelpers[helper] = HelperDef(params: params, body: body);
      // Resolve-through the helper body with the parameter bindings active, so
      // each parameter reference classifies as its bound argument (the inlined
      // composition). The bindings are removed on exit so a sibling call's
      // arguments don't leak.
      _paramBindings.addAll(binding);
      try {
        await classify(body);
      } finally {
        binding.keys.forEach(_paramBindings.remove);
      }
    } finally {
      _helperStack.remove(helper);
    }
  }

  /// Whether [expr] is a call to a registered paywall helper, recognised the
  /// same way the translator recognises one — so the classifier agrees with
  /// its own construct table.
  bool _isRegisteredHelper(MethodInvocation expr) {
    if (expr.target != null) return false;
    final helpers = _classifier.helpers;
    final element = expr.methodName.element;
    if (element != null) {
      return helpers.find(
            expr.methodName.name,
            element.library?.identifier ?? '',
          ) !=
          null;
    }
    return helpers.findByNameOnly(expr.methodName.name) != null;
  }

  /// Classifies a const-object field access — a reference to an instance field
  /// of a `const` object. Returns `false` when [expr] is not one (the caller
  /// falls through to its normal arms). Consults the SAME resolver the
  /// translator folds against: a foldable access (its initializer is reachable
  /// for AST substitution, or its value is a cross-file / defaulted scalar)
  /// marks the constant-folding mechanism — transpilable; a recognised-but-
  /// unfoldable access is deferred, exactly as the translator loud-defers it,
  /// so the two never diverge on what folds.
  bool _tryConstObjectField(Expression expr) {
    if (!isConstObjectFieldAccess(expr)) return false;
    if (resolveConstObjectFieldInitializer(expr) != null ||
        tryScalarFoldConstObjectField(expr) != null) {
      _mechanisms.add(InliningMechanism.constantFolding);
      return true;
    }
    _unclassifiable(
      "a const-object field reference ('${expr.toSource()}') whose value "
      'cannot be folded (its initializer is not in this file and it is not a '
      'scalar)',
    );
    return true;
  }

  void _propertyAccess(PropertyAccess expr) {
    // Binding-aware: `scheme.x.y` where `final scheme = Theme.of(c)...;` is in
    // scope resolves through the captured local bindings to a theme read.
    if (isThemeReadChain(expr, bindings: _localBindings)) {
      _mechanisms.add(InliningMechanism.themeAsData);
      return;
    }
    _unclassifiable(
      'a property access this transpiler increment does not yet recognise',
    );
  }

  void _binaryExpression(BinaryExpression expr) {
    if (tryFoldConstant(expr) != null) {
      // A build-time-constant compute the shared folder evaluates to a
      // literal — the same boundary the translator folds against.
      _mechanisms.add(InliningMechanism.constantFolding);
      return;
    }
    if (_referencesRuntimeData(expr)) {
      _blocker(BlockerKind.runtimeComputedValue, expr, _truncateSource(expr));
      return;
    }
    // A constant expression the folder does not evaluate (e.g. a
    // non-arithmetic operator) — not runtime data, but not inlinable by this
    // increment either.
    _unclassifiable(
      'a constant expression this transpiler increment does not yet fold',
    );
  }

  /// Whether [expr], used inside a compute, must be treated as runtime data
  /// — i.e. it is not a provable build-time constant.
  ///
  /// Conservative by design: anything not provably a literal or a constant
  /// reads as runtime data. A false 4b (rejecting a foldable expression) is
  /// safe; a false 4a (folding a runtime value) would wrongly place the
  /// widget in the inlinable set, so the doubt resolves toward runtime.
  bool _referencesRuntimeData(Expression expr) {
    if (expr is BinaryExpression) {
      return _referencesRuntimeData(expr.leftOperand) ||
          _referencesRuntimeData(expr.rightOperand);
    }
    if (expr is PrefixExpression) {
      return _referencesRuntimeData(expr.operand);
    }
    if (expr is ParenthesizedExpression) {
      return _referencesRuntimeData(expr.expression);
    }
    if (_isPlainLiteral(expr)) return false;
    if (expr is SimpleIdentifier) return !_isConstLike(expr.element);
    if (expr is PrefixedIdentifier) {
      return !_isConstLike(expr.identifier.element);
    }
    // A call, a property access, or anything else inside a compute is not a
    // provable constant.
    return true;
  }

  /// Recognises `<optional property> ?? <fallback>` where the left is a bare
  /// read of an own optional constructor property and the fallback is
  /// context-independent (does not read the widget's own args/state). Records
  /// the coalescing for call-site completion and classifies the fallback so its
  /// mechanisms/blockers fold into this widget's verdict — exactly as if the
  /// fallback were a direct value. Returns false (the caller falls through to
  /// the runtime-computed-value blocker) when the shape misses these gates.
  Future<bool> _tryClassifyCoalesce(BinaryExpression expr) async {
    final paramName = _coalesceLeftParam(expr.leftOperand);
    if (paramName == null) return false;
    final fallback = expr.rightOperand;
    // Gate: a fallback reading the widget's own args/state is context-dependent
    // — hoisting it to the call site would change its meaning — so it defers.
    if (_referencesOwnArgsOrState(fallback)) return false;
    // Gate (uniform coalescing, the identical-fallback half): the same
    // property coalesced with a DIFFERENT fallback elsewhere cannot be
    // completed with one value at the call site. (`.toSource()` inequality
    // over-defers two textually-distinct-but-equal fallbacks — safe direction.)
    final existing = _coalescedParams[paramName];
    if (existing != null && existing.toSource() != fallback.toSource()) {
      _unclassifiable(
        "the optional property '$paramName' is read with two different "
        '`?? <fallback>` values, which cannot be completed consistently at a '
        'call site',
      );
      return true;
    }
    await classify(fallback);
    _coalescedParams[paramName] = fallback;
    return true;
  }

  /// The own optional-property name read by [left] — a bare `color` in a
  /// stateless build, or `widget.color` in a State build — or null when [left]
  /// is not such a read.
  String? _coalesceLeftParam(Expression left) {
    final inner = left is ParenthesizedExpression ? left.expression : left;
    if (inner is SimpleIdentifier) return _ownParamName(inner.element);
    if (inner is PrefixedIdentifier && inner.prefix.name == 'widget') {
      return _ownParamName(inner.identifier.element);
    }
    return null;
  }

  /// The constructor-property name [element] reads, or null when [element] is
  /// not an own `this.x` constructor-formal field of the widget class.
  String? _ownParamName(Element? element) {
    final resolved = _unwrapAccessor(element);
    if (resolved is FieldElement &&
        resolved.enclosingElement == _widgetClass &&
        _isConstructorParameter(resolved)) {
      return resolved.name;
    }
    return null;
  }

  /// Whether [expr] reads the widget's own constructor args or State fields —
  /// the context-dependent forms a coalesce fallback may not take.
  bool _referencesOwnArgsOrState(Expression expr) {
    final finder = _OwnArgsStateFinder(this);
    expr.accept(finder);
    return finder.found;
  }

  void _identifier(SimpleIdentifier expr) {
    final member = _ownMember(expr.element);
    if (member != null) {
      final paramName = _ownParamName(expr.element);
      if (paramName != null) _bareParamReads.add(paramName);
      _markIfEventHandler(member);
      return;
    }
    if (_tryConstOrEnum(expr, expr.element)) return;
    _unclassifiable(
      "an identifier ('${expr.name}') that is not a constructor argument, "
      'State field, or constant',
    );
  }

  void _prefixedIdentifier(PrefixedIdentifier expr) {
    final member = _ownMember(expr.identifier.element);
    if (member != null) {
      if (expr.prefix.name == 'widget') {
        final paramName = _ownParamName(expr.identifier.element);
        if (paramName != null) _bareParamReads.add(paramName);
      }
      _markIfEventHandler(member);
      return;
    }
    // A framework named-constant reference — `Colors.transparent`,
    // `Icons.add`, `CupertinoIcons.heart`. These are static consts (a `Color`
    // / `IconData`), not enum values, so `_tryConstOrEnum` cannot fold them;
    // the translator lowers them (a packed colour / an icon codepoint), so
    // they are pure composition. (A `Colors.X` the translator's curated subset
    // cannot resolve produces a translator diagnostic — the safe direction,
    // floor-backstopped.)
    if (_isFrameworkConstNamespace(expr)) return;
    if (_tryConstOrEnum(expr, expr.identifier.element)) return;
    // A framework enum-like-const value — `FontWeight.w600`,
    // `TextDecoration.underline`. These classes have static-const members (not
    // Dart `enum`s, so `_tryConstOrEnum` cannot fold them), but the translator
    // lowers each to its bare member-name string, which the slot's string-name
    // decoder resolves (`enumValue<FontWeight>` / `RestageDecoders.textDecoration`).
    // Element-gated to the real framework class: a customer class with the same
    // name defers (its member would otherwise be lowered to the framework
    // string — a value-substitution silent-wrong the floor cannot catch).
    if (_isFrameworkEnumLikeConst(expr)) return;
    // A structured-value static-const member — `BorderSide.none`,
    // `EdgeInsets.zero` and the `.zero` siblings. The translator lowers each to
    // its map/list/scalar shape; the classifier recognises the curated
    // `(class, member)` pairs, element-gated to the real framework class, so a
    // custom widget using one inlines. A customer look-alike defers (its member
    // would otherwise reach the framework lowering — a value-substitution
    // silent-wrong the structured floor cannot catch).
    if (_isStructuredConstMember(expr)) return;
    // A theme read through a bound `final` theme-local — `scheme.primary`
    // where `final scheme = Theme.of(c).colorScheme;` is in scope. The prefix
    // resolves element-keyed against the captured local bindings.
    if (isThemeReadChain(expr, bindings: _localBindings)) {
      _mechanisms.add(InliningMechanism.themeAsData);
      return;
    }
    _unclassifiable(
      "a reference '${expr.name}' this transpiler increment does not yet "
      'recognise',
    );
  }

  /// Whether [expr] is a `Colors.*` / `Icons.*` / `CupertinoIcons.*` named
  /// constant reference into the real Flutter framework. The prefix must both
  /// be one of [kFrameworkConstNamespaces] AND resolve to a `package:flutter/`
  /// class — element-resolved, so a customer class that happens to be named
  /// `Colors` is NOT promoted to composable and then lowered against the
  /// translator's hard-coded Material table (which would silently emit the
  /// wrong value, a path the catalog value-type floor cannot catch because any
  /// `int` is a valid colour).
  ///
  /// An UNRESOLVED prefix (`element == null`) is NOT promoted — it defers.
  /// The classifier always runs on resolved ASTs in production, so a null
  /// element means genuinely-unresolvable input; promoting it on the name
  /// alone would re-open the silent-wrong in a degraded/error-recovery build,
  /// so the safe direction is to defer (the recognised-set is intentionally
  /// the resolved-real-Flutter case only).
  bool _isFrameworkConstNamespace(PrefixedIdentifier expr) {
    if (!kFrameworkConstNamespaces.contains(expr.prefix.name)) return false;
    return libraryIsFlutter(expr.prefix.element);
  }

  /// Whether [expr] is a `<Class>.<member>` reference into one of the real
  /// framework [kFrameworkEnumLikeConstClasses] (`FontWeight` / `TextDecoration`).
  /// The prefix must both name one of those classes AND resolve to a framework
  /// value-type library (they live in `dart:ui`, re-exported by
  /// `package:flutter/` — the same library set the translator gates `Color` /
  /// `Offset` against). A customer class of the same name (its own package) is
  /// NOT promoted: its member would otherwise be lowered to the framework enum
  /// string, a value-substitution silent-wrong the string-decoded floor cannot
  /// catch. An unresolved prefix defers.
  bool _isFrameworkEnumLikeConst(PrefixedIdentifier expr) {
    if (!kFrameworkEnumLikeConstClasses.contains(expr.prefix.name)) {
      return false;
    }
    if (!isFrameworkValueTypeLibrary(expr.prefix.element)) return false;
    // `Curves` carries a per-member validity pin: its decoder vocabulary is a
    // strict subset of Flutter's `Curves` members, and the classifier
    // (custom-widget body) path has no validator backstop (the curve floor
    // backstops the catalog/translator path only). So a member outside
    // `kSupportedCurveNames` must defer rather than emit a name the decoder
    // would silently null. FontWeight/TextDecoration need no per-member filter:
    // every member round-trips (FontWeight aliases canonicalise in the
    // translator).
    if (expr.prefix.name == 'Curves') {
      return kSupportedCurveNames.contains(expr.identifier.name);
    }
    return true;
  }

  /// Whether [expr] is one of the curated structured-value static-const member
  /// pairs ([kStructuredConstMembers]) the translator lowers —
  /// `BorderSide.none` and the `.zero` siblings. Element-gated to a framework
  /// value-type library (the same gate the enum-like-const arm uses): a
  /// customer class of the same name is NOT promoted — its member would
  /// otherwise reach the framework lowering, a value-substitution silent-wrong.
  /// An unresolved prefix defers.
  bool _isStructuredConstMember(PrefixedIdentifier expr) {
    if (!kStructuredConstMembers
        .contains((expr.prefix.name, expr.identifier.name))) {
      return false;
    }
    return isFrameworkValueTypeLibrary(expr.prefix.element);
  }

  /// A reference to an own *method* is an event-handler tear-off. In a
  /// stateful walk the classifier marks the widget as needing declarative
  /// state and records the method element so a post-walk pass can
  /// recognise its setState shape. In a stateless walk a method tear-off
  /// has no RFW representation — `set state.X = …` requires a State, and
  /// arbitrary Dart callbacks cannot be emitted — so the construct
  /// disqualifies the widget instead.
  void _markIfEventHandler(Element member) {
    if (member is! MethodElement) return;
    if (_stateClass == null) {
      _unclassifiable(
        "a method tear-off ('${member.name}') referenced as an event "
        'handler in a stateless widget — the transpiler can emit only '
        'state mutations and named event handlers',
      );
      return;
    }
    _mechanisms.add(InliningMechanism.declarativeState);
    _eventHandlerMethods.add(member);
  }

  /// Classifies a reference [expr] (resolving to [element]) that is an enum
  /// value or a constant: an enum value is plain composition; a constant the
  /// shared folder can evaluate contributes the constant-folding mechanism.
  /// Returns false when [expr] is neither — the caller reports it
  /// unclassifiable.
  bool _tryConstOrEnum(Expression expr, Element? element) {
    final resolved = _unwrapAccessor(element);
    if (resolved is FieldElement && resolved.isEnumConstant) {
      // An enum value renders as its bare name — plain composition.
      return true;
    }
    if (tryFoldConstant(expr) != null) {
      _mechanisms.add(InliningMechanism.constantFolding);
      return true;
    }
    return false;
  }

  /// Whether [element] resolves to a `const` variable or enum value.
  bool _isConstLike(Element? element) {
    final resolved = _unwrapAccessor(element);
    return (resolved is FieldElement && resolved.isConst) ||
        (resolved is TopLevelVariableElement && resolved.isConst);
  }

  /// The field or method of the widget class — or, for a `StatefulWidget`,
  /// its `State` class — that [element] resolves to, or `null` when
  /// [element] is neither.
  ///
  /// A widget-class field is accepted only when a constructor binds it via a
  /// `this.x` formal: the translator emits exactly those as `args.`
  /// references. A widget field with its own initializer is instance state
  /// the translator cannot emit, so it is rejected here (then read as a
  /// constant, or left unclassifiable). A `State`-class field is declarative
  /// state (a `state.` reference); a method of either class is an
  /// event-handler tear-off.
  Element? _ownMember(Element? element) {
    final resolved = _unwrapAccessor(element);
    final Element? owner;
    if (resolved is MethodElement) {
      owner = resolved.enclosingElement;
    } else if (resolved is FieldElement) {
      owner = resolved.enclosingElement;
      if (owner == _widgetClass && !_isConstructorParameter(resolved)) {
        return null;
      }
    } else {
      return null;
    }
    return (owner == _widgetClass || owner == _stateClass) ? resolved : null;
  }

  /// Whether [field] is bound by a `this.x` constructor formal — the only
  /// widget fields the translator can emit as `args.` references.
  bool _isConstructorParameter(FieldElement field) {
    final owner = field.enclosingElement;
    if (owner is! ClassElement) return false;
    for (final constructor in owner.constructors) {
      for (final parameter in constructor.formalParameters) {
        if (parameter is FieldFormalParameterElement &&
            parameter.field == field) {
          return true;
        }
      }
    }
    return false;
  }

  /// Whether [cls] is a `Widget` subclass — composed into the tree — as
  /// opposed to a value object such as `EdgeInsets`.
  bool _isWidgetClass(ClassElement cls) =>
      cls.name == 'Widget' ||
      _supertypeChain(cls).any((e) => e.name == 'Widget');

  /// Whether [cls] is one of the structured value types the translator
  /// already lowers — its construction is pure composition. Recognises both
  /// the bespoke base set ([kStructuredValueTypeNames]) and the catalog's
  /// decompose-able structured types (the single source of truth for the
  /// decompose set), so the classifier's value vocabulary stays reconciled
  /// with the translator's without a hand-maintained mirror.
  bool _isStructuredValueType(ClassElement cls) =>
      kStructuredValueTypeNames.contains(cls.name) ||
      _classifier._catalogStructuredTypeNames.contains(cls.name);

  /// Whether [type] can become an RFW `state` value — bool / int / double /
  /// num / String, or any enum.
  bool _isPrimitiveType(DartType type) {
    if (type is! InterfaceType) return false;
    final element = type.element;
    if (element is EnumElement) return true;
    const primitives = {'bool', 'int', 'double', 'num', 'String'};
    return primitives.contains(element.name);
  }

  bool _isPlainLiteral(Expression expr) =>
      expr is IntegerLiteral ||
      expr is DoubleLiteral ||
      expr is BooleanLiteral ||
      expr is NullLiteral ||
      expr is SimpleStringLiteral;

  void _blocker(
    BlockerKind kind,
    AstNode node,
    String detail, {
    CustomWidgetDisposition? dispositionOverride,
  }) {
    _blockers.add(
      Blocker(
        kind: kind,
        location: _locationOf(node),
        detail: detail,
        idiomSubject: _idiomSubjectOf(node),
        dispositionOverride: dispositionOverride,
      ),
    );
  }

  /// The structured aggregation subject for a blocker on [node] — the
  /// AST-resolved identifier the coverage idiom histogram keys on, read
  /// structurally rather than parsed from the display detail. A construction
  /// yields its (named-)constructor type (`CustomPaint`, `LayoutBuilder`); a
  /// method invocation yields `receiver.method` (`ButtonStyle.styleFrom`) or
  /// the bare method name; a binary/prefix expression recurses to its leading
  /// operand; a bare/prefixed identifier is its own name. Any other node falls
  /// back to the truncated source.
  String _idiomSubjectOf(AstNode node) => switch (node) {
        InstanceCreationExpression(:final constructorName) =>
          _constructionSubject(constructorName),
        MethodInvocation(:final target, :final methodName) => switch (target) {
            SimpleIdentifier(:final name) => '$name.${methodName.name}',
            PrefixedIdentifier(:final name) => '$name.${methodName.name}',
            _ => methodName.name,
          },
        PrefixedIdentifier(:final name) => name,
        SimpleIdentifier(:final name) => name,
        BinaryExpression(:final leftOperand) => _idiomSubjectOf(leftOperand),
        PrefixExpression(:final operand) => _idiomSubjectOf(operand),
        ParenthesizedExpression(:final expression) =>
          _idiomSubjectOf(expression),
        _ => _truncateSource(node),
      };

  /// The `Type` or `Type.namedCtor` subject of a construction, from the
  /// resolved type element (the source text when unresolved).
  String _constructionSubject(ConstructorName constructorName) {
    final typeName =
        constructorName.type.element?.name ?? constructorName.type.toSource();
    final ctor = constructorName.name?.name;
    return ctor == null ? typeName : '$typeName.$ctor';
  }

  void _unclassifiable(
    String reason, {
    IssueCode diagnosticCode = IssueCode.customWidgetUnclassified,
  }) {
    if (diagnosticCode != IssueCode.customWidgetUnclassified) {
      _unclassifiableReason = reason;
      _unclassifiableDiagnosticCode = diagnosticCode;
      return;
    }
    _unclassifiableReason ??= reason;
    _unclassifiableDiagnosticCode ??= diagnosticCode;
  }

  String _locationOf(AstNode node) {
    final key = customWidgetKey(_widgetClass);
    final unit = node.root;
    if (unit is CompilationUnit) {
      final loc = unit.lineInfo.getLocation(node.offset);
      return '$key@${loc.lineNumber}:${loc.columnNumber}';
    }
    return '$key@offset:${node.offset}';
  }

  /// Resolves the accumulated walk into a verdict. A definite blocker wins
  /// over an unclassifiable construct (an imperative widget stays imperative
  /// even if a sibling construct was not understood).
  WidgetClassification toClassification(String key) {
    // Uniform-coalescing gate: a property read both directly and as
    // `prop ?? fallback` cannot be completed consistently at the call site (a
    // completed value would feed the direct read too), so it defers.
    final mixedRead =
        _coalescedParams.keys.where(_bareParamReads.contains).firstOrNull;
    if (mixedRead != null) {
      return UnclassifiableWidget(
        key,
        reason: "build() reads '$mixedRead' both directly and as "
            "'$mixedRead ?? <fallback>'; a property read both ways cannot be "
            'completed consistently at the call site',
      );
    }
    // A definite blocker wins over an unclassifiable construct (including a
    // named modal-sheet diagnostic): an imperative widget cannot be remote-
    // rendered at all, so the author sees that root cause first.
    if (_blockers.isNotEmpty) {
      return ImperativeWidget(key, blockers: _blockers);
    }
    final reason = _unclassifiableReason;
    final diagnosticCode = _unclassifiableDiagnosticCode;
    if (reason != null) {
      if (diagnosticCode != null &&
          diagnosticCode != IssueCode.customWidgetUnclassified) {
        return UnclassifiableWidget(
          key,
          reason: 'build() uses $reason',
          diagnosticCode: diagnosticCode,
        );
      }
      return UnclassifiableWidget(key, reason: 'build() uses $reason');
    }
    return ComposableWidget(
      key,
      requiredMechanisms: _mechanisms,
      composedCustomWidgets: _composed,
    );
  }
}

/// Collapses [node]'s source to one line and caps its length, for quoting the
/// offending construct into a diagnostic message.
String _truncateSource(AstNode node) {
  final collapsed = node.toSource().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= 60) return collapsed;
  return '${collapsed.substring(0, 59)}...';
}

/// Finds whether an expression reads the walked widget's own constructor args
/// (`color` / `widget.color`) or `State` fields — the context-dependent forms a
/// coalesce fallback may not take. Name-matched against the captured State
/// fields (a false positive defers, the safe direction).
class _OwnArgsStateFinder extends RecursiveAstVisitor<void> {
  _OwnArgsStateFinder(this._walk);

  final _Walk _walk;
  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_walk._ownParamName(node.element) != null ||
        _walk._stateFields.any((f) => f.name == node.name)) {
      found = true;
    } else {
      // A fallback that reaches own args/state THROUGH a captured `final` local
      // or a bound helper parameter is still context-dependent — resolve the
      // binding and recurse so the hidden own-arg/state read is caught.
      final bound = _walk._localBindings[node.element] ??
          _walk._paramBindings[node.element];
      bound?.accept(this);
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == 'widget' &&
        _walk._ownParamName(node.identifier.element) != null) {
      found = true;
    }
    super.visitPrefixedIdentifier(node);
  }
}

/// Classifies every `@RestageWidget` custom widget referenced anywhere in the
/// given paywall [rootExpressions], recursing into each widget it composes.
///
/// Returns a [ClassificationResult] — the per-widget verdicts (keyed by
/// [WidgetClassification.classKey], the map the translator consults to
/// recognise a custom widget instead of erroring it) plus the emission
/// blueprints for the class-4a widgets. This is the build pass's
/// classification pre-pass: it runs before translation because reaching a
/// widget's source AST is asynchronous, whereas the translator's dispatch is
/// synchronous.
Future<ClassificationResult> classifyReferencedCustomWidgets({
  required Iterable<Expression> rootExpressions,
  required Catalog catalog,
  required Future<AstNode?> Function(Fragment fragment) astNodeFor,
  HelperRegistry? helpers,
}) async {
  final classifier = WidgetClassifier(
    catalog: catalog,
    astNodeFor: astNodeFor,
    helpers: helpers,
  );
  final entryPoints = <ClassElement>{};
  final collector = _CustomWidgetCollector(entryPoints);
  for (final root in rootExpressions) {
    root.accept(collector);
  }
  for (final widgetClass in entryPoints) {
    await classifier.classify(widgetClass);
  }
  return ClassificationResult(
    classifications: classifier.results,
    blueprints: classifier.blueprints,
  );
}

/// Collects the `@RestageWidget`-annotated classes constructed anywhere in a
/// paywall's `build()` expression — the classifier's entry points.
class _CustomWidgetCollector extends RecursiveAstVisitor<void> {
  _CustomWidgetCollector(this._entryPoints);

  final Set<ClassElement> _entryPoints;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.element;
    if (type is ClassElement &&
        firstAnnotation(type, 'RestageWidget') != null) {
      _entryPoints.add(type);
    }
    super.visitInstanceCreationExpression(node);
  }
}
