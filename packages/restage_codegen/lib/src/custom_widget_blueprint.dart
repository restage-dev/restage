import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_codegen/src/modal_sheet_recognition.dart';
import 'package:restage_codegen/src/setstate_recognition.dart';
import 'package:restage_codegen/src/widget_classification.dart';

/// One constructor parameter of a custom widget — what the call site binds
/// and the definition body reads as an `args.` reference.
@immutable
final class CustomWidgetParam {
  /// Creates a parameter descriptor.
  const CustomWidgetParam({
    required this.name,
    required this.isNumeric,
    required this.defaultValue,
    this.coalesceFallback,
    this.sourceField,
    this.type,
  });

  /// The `this.x` formal name — matched against call-site arguments and read
  /// as `args.<name>` inside the definition body.
  final String name;

  /// Whether the parameter's static type is `double` or `num`. A numeric
  /// call-site literal bound to such a parameter is coerced to a double
  /// literal, so it survives an rfw `source.v<double>` decode in the body.
  final bool isNumeric;

  /// The resolved parameter type used to preserve its runtime decoder shape.
  final DartType? type;

  /// The constructor default, folded to a scalar — an [int], [double],
  /// [bool], or [String] — or `null` when the parameter has no default (or a
  /// null default). An omitted call-site argument emits this so the inlined
  /// widget renders with the same value the Dart constructor would.
  final Object? defaultValue;

  /// The fallback expression of a null-coalescing optional property: the body
  /// reads this parameter as `<name> ?? <coalesceFallback>` with the same
  /// fallback at every read. Non-null marks the parameter
  /// **completion-required** — the translator gates the body rewrite
  /// (`<name> ?? f` → `args.<name>`) and the call-site completion on this being
  /// non-null. The IN-BLOB lowered value
  /// is taken from the live body expression at translation time (where the
  /// definition-body context resolves a theme-local fallback), NOT from this
  /// stored node; the node itself is retained as the per-property fallback the
  /// future cross-package import metadata will carry. `null` for an ordinary
  /// parameter the body reads directly.
  final Expression? coalesceFallback;

  /// Exact field read by the emitted definition body.
  final FieldElement? sourceField;
}

/// Position of a root parameter in its unnamed constructor.
enum RootContextParamKind {
  /// A required positional parameter.
  requiredPositional,

  /// An optional positional parameter.
  optionalPositional,

  /// A required or optional named parameter.
  named,
}

/// One root constructor parameter and its host-data eligibility.
@immutable
final class RootContextParam {
  /// Creates a root host-data parameter descriptor.
  const RootContextParam({
    required this.name,
    required this.type,
    required this.typeCode,
    required this.kind,
    required this.hostDataShape,
    required this.field,
    required this.isRequired,
    required this.defaultValueCode,
    required this.hasNullDefault,
    this.hostDataProblem,
    this.mountDefaultValueCode,
    this.mountDefaultProblem,
    this.forwardsFlutterKey = false,
    this.usesSuperFormal = false,
    this.usesStatelessWidgetSuperFormal = false,
    this.hasExplicitType = false,
  });

  /// The declared formal name — the `data.context` key the host must supply.
  final String name;

  /// The parameter's static Dart type, nullability included.
  final DartType type;

  /// The declared type spelling visible from the owning library.
  final String? typeCode;

  /// The constructor parameter's positional or named form.
  final RootContextParamKind kind;

  /// The one recursive host-data shape, or `null` when [type] is inadmissible.
  final HostDataShape? hostDataShape;

  /// The structural refusal retained for read-triggered diagnostics.
  final HostDataShapeProblem? hostDataProblem;

  /// Whether [type] is valid host data. Unread parameters may use any type.
  bool get isHostData => hostDataShape != null;

  /// The instance field initialized by this formal, when one exists.
  final FieldElement? field;

  /// Whether callers must supply the constructor parameter.
  final bool isRequired;

  /// The explicit constructor default, or `null` when none is declared.
  final String? defaultValueCode;

  /// The constructor default as resolved from the owning library.
  final String? mountDefaultValueCode;

  /// Why the constructor default cannot be emitted by the owning library.
  final String? mountDefaultProblem;

  /// Whether the explicit constructor default evaluates to `null`.
  final bool hasNullDefault;

  /// Whether this formal reaches Flutter's widget key input.
  final bool forwardsFlutterKey;

  /// Whether the formal uses inherited `super` syntax.
  final bool usesSuperFormal;

  /// Whether a generated `StatelessWidget` may preserve the `super` syntax.
  final bool usesStatelessWidgetSuperFormal;

  /// Whether the formal declares its own type annotation.
  final bool hasExplicitType;

  /// Whether omission would select a non-null Dart default.
  bool get hasNonNullDefault => defaultValueCode != null && !hasNullDefault;

  /// Whether the host may omit this value.
  bool get isNullable => type.nullabilitySuffix == NullabilitySuffix.question;
}

/// One declarative-state field of a custom widget's `State` class — captured
/// by the classifier and consumed by the translator to emit a
/// `widget X { name: initial, … } = …` block and to recognise bare
/// identifiers in `build()` as `state.<name>` references.
@immutable
final class CustomWidgetStateField {
  /// Creates a state-field descriptor.
  const CustomWidgetStateField({
    required this.name,
    required this.isNumeric,
    required this.initialValue,
  });

  /// The field's declared name — emitted as `state.<name>` references inside
  /// the definition body and as the key in the emitted `{ <name>: … }`
  /// initial-state map.
  final String name;

  /// Whether the field's static type is `double` or `num`. A numeric initial
  /// value is coerced to a double literal in the emitted state block so it
  /// survives the binary encoder's `source.v<double>` decode.
  final bool isNumeric;

  /// The field's initialiser, folded to a scalar — an [int], [double],
  /// [bool], [String], or the bare name of an enum constant — or `null` when
  /// the classifier could not fold the initialiser (a runtime call, a
  /// missing initialiser, an unrecognised expression). A null value here is
  /// the signal the translator surfaces as a `stateShapeUnsupported`
  /// diagnostic; no inlined widget ever ships with a null state initial.
  final Object? initialValue;
}

/// One own Widget-returning helper method (or value-returning helper) the
/// classifier captured so the translator can inline its body at each call
/// site — the *named-intermediate inlining* mechanism.
///
/// [params] are the helper's formal parameters, in declaration order; at a
/// call site each is bound to the corresponding argument (the never-emit-wrong
/// arg-binding step). [body] is the helper's single returned expression — the
/// classifier only captures a helper whose body reduces to one. Keyed in
/// [InlinedDefinitions.helpers] by the helper's resolved [Element], so a call
/// is recognised by element identity, never by name (the look-alike-safe
/// rule).
@immutable
final class HelperDef {
  /// Creates a helper definition.
  const HelperDef({required this.params, required this.body});

  /// The helper's formal parameters, in declaration order.
  final List<FormalParameterElement> params;

  /// The helper's single returned expression — inlined at the call site.
  final Expression body;
}

/// Returns all same-unit helpers with one statically inlinable return value.
Map<Element, HelperDef> inlinableHelperDefinitionsIn(AstNode node) =>
    _indexHelpers(node).definitions;

/// Returns the named refusal for each same-unit helper whose body would inline
/// but for a prelude declaration the author fixes in place.
Map<Element, String> refusedHelperDefinitionsIn(AstNode node) =>
    _indexHelpers(node).refusals;

_HelperIndex _indexHelpers(AstNode node) {
  final root = node.root;
  if (root is! CompilationUnit) return const _HelperIndex.empty();
  final cached = _helperIndexCache[root];
  if (cached != null) return cached;
  final index = _HelperIndex(
    definitions: Map<Element, HelperDef>.identity(),
    refusals: Map<Element, String>.identity(),
  );
  root.accept(_HelperDefinitionIndexer(index));
  _helperIndexCache[root] = index;
  return index;
}

/// Whether [invocation] is statically bound within its source artifact.
bool isArtifactHelperInvocation(MethodInvocation invocation) {
  final element = invocation.methodName.element;
  if (element is! ExecutableElement ||
      element.name == 'build' ||
      element.returnType is! InterfaceType) {
    return false;
  }
  if (element is MethodElement && !element.isStatic) {
    if (invocation.target != null) return false;
    final owner = invocation
        .thisOrAncestorOfType<ClassDeclaration>()
        ?.declaredFragment
        ?.element;
    return owner != null && element.enclosingElement == owner;
  }
  if (element is TopLevelFunctionElement ||
      (element is MethodElement && element.isStatic)) {
    final root = invocation.root;
    return root is CompilationUnit &&
        element.library == root.declaredFragment?.element;
  }
  return false;
}

final Expando<_HelperIndex> _helperIndexCache = Expando<_HelperIndex>();

final class _HelperIndex {
  const _HelperIndex({required this.definitions, required this.refusals});

  const _HelperIndex.empty()
      : definitions = const {},
        refusals = const {};

  final Map<Element, HelperDef> definitions;
  final Map<Element, String> refusals;
}

final class _HelperDefinitionIndexer extends RecursiveAstVisitor<void> {
  _HelperDefinitionIndexer(this.index);

  final _HelperIndex index;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _add(node.declaredFragment?.element, node.body);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _add(
      node.declaredFragment?.element,
      node.functionExpression.body,
    );
    super.visitFunctionDeclaration(node);
  }

  void _add(ExecutableElement? element, FunctionBody body) {
    if (element == null || element.returnType is! InterfaceType) return;
    final expression = singleReturnExpressionOf(body);
    if (expression == null) {
      // Only a named prelude refusal is recorded; every other body shape is
      // simply not a helper.
      final problem = preludeDeclarationProblem(body);
      if (problem != null) index.refusals[element] = problem;
      return;
    }
    index.definitions[element] = HelperDef(
      params: element.formalParameters.toList(),
      body: expression,
    );
  }
}

/// The named intermediates the classifier resolved so the translator can
/// inline them into a custom widget's `build()` expression: leading local
/// `final`/`const` bindings and own helper methods. Both are keyed by the
/// intermediate's resolved [Element] so a reference/call is matched by element
/// identity (never name) — the look-alike-safe rule (S13). Empty when the
/// widget uses no inlinable intermediate.
@immutable
final class InlinedDefinitions {
  /// Creates a set of inlinable definitions.
  const InlinedDefinitions({
    this.localBindings = const {},
    this.helpers = const {},
  });

  /// The empty set — a `build()` with no inlinable named intermediate.
  const InlinedDefinitions.empty()
      : localBindings = const {},
        helpers = const {};

  /// Leading `final`/`const` local bindings in `build()`, keyed by the
  /// binding's resolved [Element]; the value is the binding's initializer
  /// expression, resolved-through at each reference site.
  final Map<Element, Expression> localBindings;

  /// Own helper methods invoked in `build()`, keyed by the method's resolved
  /// [Element]; the value carries the helper's params and body.
  final Map<Element, HelperDef> helpers;
}

/// Binds a helper call's [args] to a helper's [params], 1:1, returning a
/// param-element → argument-expression map — or `null` when the binding is not
/// provably 1:1: a positional count mismatch, a missing or extra named
/// argument, or any parameter left to its default. A null binding means the
/// call is NOT inlinable, so the caller defers it with a diagnostic rather
/// than guess a binding — the never-emit-wrong rule applied to argument
/// binding. Shared by the classifier (to gate the resolve-through) and the
/// translator (to emit the bound arguments) so the two agree exactly.
Map<Element, Expression>? bindHelperArguments(
  List<FormalParameterElement> params,
  List<Expression> args,
) {
  final positionalParams = params.where((p) => p.isPositional).toList();
  final namedParams = <String, FormalParameterElement>{
    for (final p in params.where((p) => p.isNamed)) p.name ?? '': p,
  };
  final positionalArgs = <Expression>[];
  final namedArgs = <String, Expression>{};
  for (final arg in args) {
    if (arg is NamedExpression) {
      namedArgs[arg.name.label.name] = arg.expression;
    } else {
      positionalArgs.add(arg);
    }
  }
  if (positionalArgs.length != positionalParams.length) return null;
  if (namedArgs.length != namedParams.length) return null;
  final binding = <Element, Expression>{};
  for (var i = 0; i < positionalParams.length; i++) {
    binding[positionalParams[i]] = positionalArgs[i];
  }
  for (final entry in namedParams.entries) {
    final arg = namedArgs[entry.key];
    if (arg == null) return null;
    binding[entry.value] = arg;
  }
  return binding;
}

/// Everything the transpiler needs to emit one custom widget as an RFW
/// remote-widget definition — the resolved `build()` expression and the
/// constructor parameters.
///
/// Captured by the classifier as a byproduct of the classification walk: the
/// classifier already resolves a widget's `build()` AST to classify it, so it
/// records this blueprint alongside the verdict rather than making a second
/// pass re-resolve the same source. The translator consults it to inline an
/// inlinable-now [ComposableWidget].
@immutable
final class CustomWidgetBlueprint {
  /// Creates a blueprint. [params] is wrapped [List.unmodifiable]; [state]
  /// is wrapped [List.unmodifiable] when provided, or stays `null` for a
  /// stateless widget. [eventHandlers] defaults to empty.
  CustomWidgetBlueprint({
    required this.classKey,
    required this.rfwName,
    required this.buildExpression,
    required List<CustomWidgetParam> params,
    List<CustomWidgetStateField>? state,
    Map<String, RecognisedSetState> eventHandlers = const {},
    List<RecognisedModalSheet> modalSheets = const [],
    this.inlined = const InlinedDefinitions.empty(),
  })  : params = List.unmodifiable(params),
        state = state == null ? null : List.unmodifiable(state),
        eventHandlers = Map.unmodifiable(eventHandlers),
        modalSheets = List.unmodifiable(modalSheets);

  /// Canonical `'<library URI>#<ClassName>'` key — matches the owning
  /// [WidgetClassification.classKey].
  final String classKey;

  /// The RFW widget name this custom widget is emitted and referenced as — the
  /// bare class name. Collisions (two classes, one name; or a clash with a
  /// catalog or the root widget) are diagnosed at emit time.
  final String rfwName;

  /// The resolved `build()` returned expression — the source of the emitted
  /// `widget <rfwName> = …` definition body.
  final Expression buildExpression;

  /// The widget's `this.x` constructor parameters, in declaration order — the
  /// call site binds them and the definition body reads them as `args.`.
  final List<CustomWidgetParam> params;

  /// The widget's `State` fields, in declaration order — the source of the
  /// emitted `widget <rfwName> { <name>: <initial>, … } = …` block, and the
  /// names the translator lowers to `state.<name>` when read in the body.
  ///
  /// `null` for a stateless widget; a (possibly empty) list for a
  /// stateful widget. An empty list means a `StatefulWidget` whose `State`
  /// declared no primitive fields the classifier could capture — the
  /// translator still treats the inlining context as stateful but emits no
  /// state block.
  final List<CustomWidgetStateField>? state;

  /// The State methods referenced as event-handler tear-offs in `build()`,
  /// keyed by method name. Each value is a [RecognisedSetState] verdict —
  /// the translator emits `set state.<field> = …` directly from the verdict
  /// rather than re-resolving the method's AST at translation time.
  /// Empty for a stateless widget, or for a stateful widget whose `build()`
  /// references no State methods. An [SetStateUnrecognised] verdict reaches
  /// the translator as a `stateShapeUnsupported` diagnostic at emit time.
  final Map<String, RecognisedSetState> eventHandlers;

  /// Clean modal-sheet trigger calls captured from inline event-handler
  /// closures. The translator uses the AST node identity to rewrite those
  /// callbacks and hoist the corresponding sheet.
  final List<RecognisedModalSheet> modalSheets;

  /// The named intermediates (local bindings + own helper methods) the
  /// classifier resolved for this widget, so the translator can inline them
  /// into [buildExpression]. Empty for a `build()` that uses no inlinable
  /// intermediate.
  final InlinedDefinitions inlined;
}

/// The output of the classification pre-pass: the per-widget [classifications]
/// (the verdict the translator gates on) plus the [blueprints] (the emission
/// material the translator inlines from).
///
/// Replaces the bare `Map<String, WidgetClassification>` the pre-pass returned
/// before inlining existed — the [WidgetClassification] sealed types are
/// unchanged; only this aggregate is new.
@immutable
final class ClassificationResult {
  /// Creates a result. Both maps are wrapped [Map.unmodifiable].
  ClassificationResult({
    required Map<String, WidgetClassification> classifications,
    required Map<String, CustomWidgetBlueprint> blueprints,
    Map<String, String> collectionRefusals = const {},
  })  : classifications = Map.unmodifiable(classifications),
        blueprints = Map.unmodifiable(blueprints),
        collectionRefusals = Map.unmodifiable(collectionRefusals);

  /// Every custom widget classified this pass, keyed by
  /// [WidgetClassification.classKey].
  final Map<String, WidgetClassification> classifications;

  /// Emission blueprints, keyed by [CustomWidgetBlueprint.classKey] — one per
  /// widget that classified [ComposableWidget]. An imperative or
  /// unclassifiable widget has no blueprint.
  final Map<String, CustomWidgetBlueprint> blueprints;

  /// Static collection refusals keyed by the custom widget they invalidate.
  final Map<String, String> collectionRefusals;
}
