import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/const_folding.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/draggable_sheet_recognition.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/factory_variant_fields.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/modal_sheet_recognition.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:restage_codegen/src/navigation_recognition.dart';
import 'package:restage_codegen/src/number_format_recognition.dart';
import 'package:restage_codegen/src/recipe_dispatcher.dart';
import 'package:restage_codegen/src/rfw_emitter.dart';
import 'package:restage_codegen/src/segmented_button_recognition.dart';
import 'package:restage_codegen/src/setstate_recognition.dart';
import 'package:restage_codegen/src/single_select_recognition.dart';
import 'package:restage_codegen/src/structured_value_emitter.dart';
import 'package:restage_codegen/src/theme_recognition.dart';
import 'package:restage_codegen/src/toggle_buttons_recognition.dart';
import 'package:restage_codegen/src/translator_recipe.dart';
import 'package:restage_codegen/src/widget_catalog/translator_tables.g.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        ThemeContractValueKind,
        kCapturedEventValueKey,
        kMaxInlineSpanDepth,
        kRestageFormattedTextProps,
        kSupportedCurveNames,
        kThemeContractPathKinds,
        kThemeContractPaths;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const String _kRestageFlutterSdkLibraryOrigin = 'package:restage';

/// The synthetic-strategy marker on the uniform `borderRadius` slot. The
/// decompose interception gates on it so an asymmetric / `.all` BorderRadius
/// reaches the per-corner splice only on widgets that own that slot.
const String _kBorderRadiusCircularSynthetic = 'borderRadiusCircular';

/// The synthetic-strategy marker on each per-corner radius slot. The splice
/// keys all-four-or-none membership on it (the authoritative catalog
/// convention the reconstruction side reads), not on the property name alone.
const String _kBorderRadiusCornerSynthetic = 'borderRadiusCorner';

/// The asymmetric / `.all` BorderRadius ctor names the decompose path routes
/// through the per-corner recognition. `circular` is intentionally absent so it
/// keeps flowing the frozen construct-variant transform unchanged.
const Set<String> _kAsymmetricBorderRadiusCtors = {
  'only',
  'vertical',
  'horizontal',
  'all',
};

/// Prefix of the per-corner sentinel produced by the BorderRadius recognition
/// (see `StructuredValueEmitter`). The splice keys off this prefix.
const String _kBorderRadiusCornerSentinel = '__rfw_border_radius_corners(';

/// Corner name (as the sentinel emits) → the per-corner catalog property name.
/// Mirrors the reconstruction side's `borderRadius<Corner>` convention; the
/// recognition stays widget-agnostic (it emits the bare corner name).
const Map<String, String> _kBorderRadiusCornerProperty = {
  'topLeft': 'borderRadiusTopLeft',
  'topRight': 'borderRadiusTopRight',
  'bottomLeft': 'borderRadiusBottomLeft',
  'bottomRight': 'borderRadiusBottomRight',
};

/// Result of translating a single Dart `Expression` AST node into an RFW
/// DSL fragment.
@immutable
final class TranslationResult {
  /// Constructor. [issues], [widgetDefinitions], and
  /// [widgetDefinitionStates] are wrapped unmodifiable to honour the
  /// [@immutable] contract.
  TranslationResult({
    required this.dsl,
    required List<Issue> issues,
    this.navigation,
    this.suppressed = false,
    Map<String, String> widgetDefinitions = const {},
    Map<String, Map<String, String>> widgetDefinitionStates = const {},
    Map<String, String> rootWidgetState = const {},
  })  : issues = List.unmodifiable(issues),
        widgetDefinitions = Map.unmodifiable(widgetDefinitions),
        widgetDefinitionStates = Map.unmodifiable(widgetDefinitionStates),
        rootWidgetState = Map.unmodifiable(rootWidgetState);

  /// The DSL fragment, e.g. `"42"` or `'event "name" {}'`. Empty string if
  /// translation failed and one or more [issues] were collected.
  final String dsl;

  /// Issues collected during this translation (unmodifiable).
  final List<Issue> issues;

  /// Synthesised screen-navigation lowering metadata for the build step.
  final NavigationLowering? navigation;

  /// Whether the build should intentionally skip this artifact without
  /// treating the translation as a build failure.
  final bool suppressed;

  /// RFW remote-widget definitions emitted while translating, keyed by
  /// blob-safe widget name and valued by the definition body DSL. Empty
  /// unless the paywall references an inlinable custom widget; each entry is
  /// prepended to the library as a `widget <name> = <body>;` declaration.
  final Map<String, String> widgetDefinitions;

  /// Per-stateful-definition initial-state map: rfwName → field-name →
  /// literal-DSL. Drives the emitter's `widget X { name: initial, … } = body;`
  /// rendering. Empty for a paywall whose inlined widgets are all stateless;
  /// each entry corresponds to an rfwName in [widgetDefinitions].
  final Map<String, Map<String, String>> widgetDefinitionStates;

  /// Root widget initial-state map: field-name → literal-DSL. Empty for a
  /// stateless root source.
  final Map<String, String> rootWidgetState;
}

/// Internal build artifact describing a lowered paywall-root navigation flow.
@immutable
final class NavigationLowering {
  /// Creates navigation lowering metadata.
  NavigationLowering({
    required this.entryId,
    required List<NavigationTransition> transitions,
    required this.terminatingEvent,
  }) : transitions = List.unmodifiable(transitions);

  /// The source id of the entry paywall.
  final String entryId;

  /// Synthetic events from the entry screen to pushed paywall screens.
  final List<NavigationTransition> transitions;

  /// Reserved SDK event that terminates the flow.
  final String terminatingEvent;

  /// Stable JSON representation for the internal `.navplan` sidecar.
  Map<String, Object?> toJson() => {
        'entryId': entryId,
        'transitions': [
          for (final transition in transitions) transition.toJson(),
        ],
        'terminatingEvent': terminatingEvent,
      };
}

/// One synthetic navigation transition emitted into a `.navplan` artifact.
@immutable
final class NavigationTransition {
  /// Creates a navigation transition.
  const NavigationTransition({required this.event, required this.pushedId});

  /// Synthetic event fired from the entry paywall.
  final String event;

  /// Pushed `@PaywallSource(id:)` screen id.
  final String pushedId;

  /// Stable JSON representation for one `.navplan` transition.
  Map<String, Object?> toJson() => {
        'event': event,
        'pushedId': pushedId,
      };
}

/// Translates Dart `Expression` AST nodes into RFW DSL fragments.
///
/// The same translator instance can be reused for multiple paywalls in one
/// build pass. Source location context (the `sourcePath` / `lineInfo`
/// arguments) set via [translate] is scoped to that single call; the
/// instance itself stores no per-call state between calls.
final class ExpressionTranslator {
  /// Creates a translator that resolves widget classes through [catalog]
  /// and helper-call patterns through [helpers].
  ExpressionTranslator({
    required this.catalog,
    required this.helpers,
    this.customWidgetClassifications = const <String, WidgetClassification>{},
    this.customWidgetBlueprints = const <String, CustomWidgetBlueprint>{},
  }) : _isFrameworkValueType = isFrameworkValueTypeLibrary;

  /// Test-only override of the framework-value-type predicate the
  /// value-substitution gate keys on. Production is strict-by-default
  /// ([isFrameworkValueTypeLibrary] — `dart:` / `package:flutter/`), and that
  /// deferral of a resolved customer look-alike is proven through the
  /// PRODUCTION constructor by the value-substitution sweep tests. The seam
  /// exists because the synthetic-catalog tests mount their decompose-recipe
  /// identities AND their value-type stubs at one non-framework URI
  /// (`package:restage_codegen/_expr_probe.dart`), so a synthetic test must
  /// declare its own framework set via [frameworkLibraryPredicate] (see
  /// `helpers.syntheticFrameworkLibrary`). `@visibleForTesting` keeps it off
  /// every production path.
  @visibleForTesting
  ExpressionTranslator.forTesting({
    required this.catalog,
    required this.helpers,
    required bool Function(Element?) frameworkLibraryPredicate,
    this.customWidgetClassifications = const <String, WidgetClassification>{},
    this.customWidgetBlueprints = const <String, CustomWidgetBlueprint>{},
  }) : _isFrameworkValueType = frameworkLibraryPredicate;

  /// The framework-value-type predicate the value-substitution gate keys on —
  /// [isFrameworkValueTypeLibrary] in production, overridden only via
  /// `forTesting`.
  final bool Function(Element?) _isFrameworkValueType;

  /// Emits the RFW DSL for structured value types (EdgeInsets / Color / Offset /
  /// Border / ShapeBorder / Gradient / BoxShadow / Locale / FontFeature /
  /// FontVariation / TextDecoration / Alignment), delegating back to this
  /// translator's primitives through injected closures. `late final` so the
  /// method tear-offs bind to a fully-constructed `this`.
  late final StructuredValueEmitter _structured = StructuredValueEmitter(
    translate: _translate,
    translateDoubleScalar: _translateDoubleScalar,
    stripParens: _stripParens,
    stringLiteral: _stringLiteral,
    frameworkOrUnresolved: _frameworkOrUnresolved,
    resolveBoundIdentifier: _resolveBoundIdentifier,
    isResolvedNonFrameworkCtor: _isResolvedNonFrameworkCtor,
    deferFrameworkConstLookalike: _deferFrameworkConstLookalike,
    deferFrameworkCtorLookalike: _deferFrameworkCtorLookalike,
    conditionalSwitch: _conditionalSwitch,
    validateThemeValueForSlot: _validateThemeValueForSlot,
    locationOf: _locationOf,
  );

  static final RegExp _rfwIdentifierPattern =
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// The inlining mechanisms this codegen increment implements. A
  /// [ComposableWidget] is inlinable when its required mechanisms are a
  /// subset of this set; composition itself is always implemented (and is
  /// not an [InliningMechanism] member). Shared by the paywall-body inline
  /// path ([_tryInlineCustomWidget]) and the standalone emit-confirmation
  /// probe ([attemptInlineEmit]) so the two agree on the gate.
  static const Set<InliningMechanism> _kImplementedMechanisms = {
    InliningMechanism.constantFolding,
    InliningMechanism.themeAsData,
    InliningMechanism.declarativeState,
  };

  static const Set<String> _kCarriedTextSpanProps = {
    'text',
    'style',
    'children',
  };

  static const Set<String> _kDeferredTextSpanProps = {
    'recognizer',
    'semanticsLabel',
    'locale',
    'spellOut',
    'mouseCursor',
    'onEnter',
    'onExit',
  };

  static const Set<String> _kTextInterpolationTextRichCarryProps = {
    'textAlign',
    'maxLines',
    'inherit',
    'color',
    'backgroundColor',
    'fontFamily',
    'fontSize',
    'fontWeight',
    'fontStyle',
    'letterSpacing',
    'wordSpacing',
    'textBaseline',
    'height',
    'leadingDistribution',
    'locale',
    'foreground',
    'background',
    'shadows',
    'fontFeatures',
    'fontVariations',
    'decoration',
    'decorationColor',
    'decorationStyle',
    'decorationThickness',
    'debugLabel',
    'fontFamilyFallback',
    'fontPackage',
    'overflow',
  };

  /// Merged widget catalog the translator validates against.
  final Catalog catalog;

  /// The catalog `Text` entry, resolved once. A `TextSpan.style` reuses the
  /// flat-`Text` style decomposition so nested span styles share the exact
  /// encoding flat `Text` styles use; caching here keeps the recursive span
  /// walk from re-scanning the catalog per styled node.
  late final WidgetEntry? _textStyleCatalogEntry =
      catalog.widgets.firstWhereOrNull((w) => w.name == 'Text') ??
          catalog.widgets.firstWhereOrNull(
            (w) => w.flutterType.endsWith('#Text'),
          );

  /// Registry of recognized helper calls.
  final HelperRegistry helpers;

  /// Classification of every `@RestageWidget` custom widget referenced by the
  /// paywalls in this build pass, keyed by `'<library URI>#<ClassName>'`
  /// ([customWidgetKey]). Populated by the build pass's classification
  /// pre-pass; empty when no custom widgets are referenced. The translator
  /// consults it to recognise a custom widget — emitting a classified
  /// diagnostic — instead of erroring it as an unknown widget.
  final Map<String, WidgetClassification> customWidgetClassifications;

  /// Emission blueprints for the class-4a custom widgets referenced this
  /// build pass, keyed by `'<library URI>#<ClassName>'` ([customWidgetKey]).
  /// The translator inlines an inlinable-now widget from its blueprint —
  /// emitting an RFW remote-widget definition — rather than deferring it.
  final Map<String, CustomWidgetBlueprint> customWidgetBlueprints;

  /// The walk-scoped translation state, bundled into one immutable value so a
  /// push/pop is a single whole-object swap: save `_walk`, set it to a
  /// `copyWith` of the touched subset, restore the saved value in `finally`.
  /// The eleven walk-scoped fields are read off `_walk`.
  _WalkContext _walk = _WalkContext.initial();

  // Per-call location context, set at the start of each [translate] call.
  String? _currentSourcePath;
  LineInfo? _currentLineInfo;

  // Per-call accumulator for the custom-widget definitions emitted while
  // translating (rfwName → body DSL), set at the start of each [translate]
  // call and surfaced on the result. Null outside a translate() call.
  Map<String, String>? _currentWidgetDefinitions;

  // Per-call accumulator for the stateful-definition initial-state maps
  // emitted while translating (rfwName → field-name → literal-DSL). Null
  // outside a translate() call.
  Map<String, Map<String, String>>? _currentWidgetDefinitionStates;

  // Owner of each emitted RFW widget name this call (rfwName → classKey) —
  // bookkeeping that detects two custom widgets claiming one name. Null
  // outside a translate() call.
  Map<String, String>? _currentDefinitionOwners;

  // Lowered coalesce fallbacks discovered while translating a definition body,
  // keyed by classKey then property name: the value a call site that omits (or
  // passes explicit null) the property is completed with. Populated once per
  // definition (the body is translated on first claim, before its call sites),
  // and read by [_customWidgetCallArgs]. Persistent across the whole translate
  // pass — not saved/restored — so later call sites of an
  // already-translated widget still complete.
  final Map<String, Map<String, String>> _completionFallbacks = {};

  // Screen-navigation walk-scoped state. These three fields were added (with
  // the navigation lowering) after the walk-scoped fields were bundled into
  // [_walk], and are intentionally kept as plain host fields with explicit
  // save/restore in [translate] rather than folded into [_WalkContext] — a
  // documented hybrid that preserves the navigation lowering's exact field
  // semantics verbatim. The 11 original walk-scoped fields (argNames/
  // stateFields/eventHandlers/…/validatedCoalesceParams/paramBindings/
  // modalSheet/modalSheetCloseFlag) live on [_walk]; these three ride alongside.
  //
  // Active root paywall screen-navigation lowering. The context lets event
  // slots rewrite exact Navigator.push triggers to synthetic events and lets
  // flow-screen adapter translations rewrite Navigator.pop(context) to `back`.
  _NavigationEmitContext? _currentNavigation;

  // Whether the current paywall translation is for the flow-screen adapter
  // artifact rather than the standalone paywall artifact.
  bool _flowScreenContext = false;

  // Whether the current translation intentionally suppresses its output
  // artifact without failing the build.
  bool _currentTranslationSuppressed = false;

  /// Table-driven dispatcher. A registered recipe short-circuits the
  /// hand-authored per-type dispatch; an unregistered call falls through.
  late final RecipeDispatcher _recipeDispatcher = RecipeDispatcher(
    recipes: kTranslatorRecipes,
    translate: _translate,
    translateDouble: _translateDoubleScalar,
    // Inject the (forTesting-aware) framework-value-type predicate so the
    // member-table nested-value gate defers a resolved customer look-alike
    // consistently with the hand-authored helpers.
    isFrameworkLibrary: _isFrameworkValueType,
  );

  /// Native catalog lookups are needed only for structured decomposition.
  /// Keep construction lazy so translator tests with synthetic catalog
  /// fragments do not pay native validation unless they exercise recipes.
  late final NativeCatalogIndex _nativeCatalogIndex =
      NativeCatalogIndex(catalog);

  /// Translates a single Dart [expr] into a DSL fragment.
  ///
  /// [sourcePath] and [lineInfo] improve issue location strings from byte
  /// offsets to `file:line:column`. Both default to null (offset-only
  /// fallback).
  TranslationResult translate(
    Expression expr, {
    String? sourcePath,
    LineInfo? lineInfo,
    String? entryId,
    List<CustomWidgetStateField>? rootState,
    Map<String, RecognisedSetState> rootEventHandlers = const {},
    Element? buildContextParameter,
    bool flowScreenContext = false,
  }) {
    final saved = _walk;
    final savedNavigation = _currentNavigation;
    final savedFlowScreenContext = _flowScreenContext;
    final savedSuppressed = _currentTranslationSuppressed;
    _currentSourcePath = sourcePath;
    _currentLineInfo = lineInfo;
    _walk = _walk.copyWith(
      argNames: const {},
      stateFields: rootState == null
          ? null
          : {for (final field in rootState) field.name: field},
      eventHandlers: rootEventHandlers,
      rootStateContext: rootState != null,
      inlined: const InlinedDefinitions.empty(),
    );
    _currentNavigation = null;
    _flowScreenContext = flowScreenContext;
    _currentTranslationSuppressed = false;
    final issues = <Issue>[];
    final widgetDefinitions = <String, String>{};
    final widgetDefinitionStates = <String, Map<String, String>>{};
    final rootWidgetState = <String, String>{};
    final definitionOwners = <String, String>{};
    _currentWidgetDefinitions = widgetDefinitions;
    _currentWidgetDefinitionStates = widgetDefinitionStates;
    _currentDefinitionOwners = definitionOwners;
    var dsl = '';
    var suppressed = false;
    NavigationLowering? navigationLowering;
    try {
      final modalSheet = _findSingleRootModalSheetTrigger(expr, issues);
      final navigationTriggers = entryId == null || issues.isNotEmpty
          ? const <RecognisedNavigation>[]
          : _findRootNavigationTriggers(
              expr,
              issues,
              buildContextParameter: buildContextParameter,
            );
      final navigationContext = issues.isEmpty && entryId != null
          ? _createNavigationContext(
              entryId: entryId,
              expr: expr,
              triggers: navigationTriggers,
              issues: issues,
              buildContextParameter: buildContextParameter,
            )
          : null;
      final rootShapeIssue = issues.isEmpty
          ? _validateRootStateShape(rootState, rootEventHandlers, expr)
          : null;
      if (rootShapeIssue != null) issues.add(rootShapeIssue);
      if (issues.isEmpty) {
        if (rootState != null) {
          rootWidgetState.addAll({
            for (final field in rootState)
              field.name: _stateInitialLiteral(field),
          });
        }
        if (modalSheet != null) {
          final flag = _mintModalSheetFlag(rootState);
          final syntheticField = CustomWidgetStateField(
            name: flag,
            isNumeric: false,
            initialValue: false,
          );
          // The trigger and dismiss sites emit `set state.<flag> = …` directly,
          // so no synthetic event-handler registration is needed; registering
          // one would only risk shadowing a real author handler of the same
          // name in the shared handler map.
          rootWidgetState[flag] = 'false';
          _walk = _walk.copyWith(
            stateFields: {...?_walk.stateFields, flag: syntheticField},
            modalSheet: _ModalSheetEmitContext(
              sheet: modalSheet,
              flagName: flag,
            ),
          );
        }
        _currentNavigation = navigationContext;
        if (navigationContext != null && navigationContext.hasTransitions) {
          navigationLowering = navigationContext.toLowering();
        }
        dsl = _translate(expr, issues);
        final context = _walk.modalSheet;
        if (context != null && issues.isEmpty) {
          dsl = _emitModalSheetRoot(
            context,
            underlayDsl: dsl,
            issues: issues,
          );
        }
        if (context != null && issues.isNotEmpty) dsl = '';
        if (navigationContext != null &&
            (issues.any((issue) => !issue.code.isBuildNotice) ||
                _currentTranslationSuppressed)) {
          dsl = '';
          navigationLowering = null;
        }
      }
    } finally {
      _walk = saved;
      // Capture the working suppression flag for the result BEFORE restoring
      // it, then restore the three plain-host navigation fields ([_walk] above
      // has already restored the 11 bundled walk-scoped fields).
      suppressed = _currentTranslationSuppressed;
      _currentNavigation = savedNavigation;
      _flowScreenContext = savedFlowScreenContext;
      _currentTranslationSuppressed = savedSuppressed;
      _currentWidgetDefinitions = null;
      _currentWidgetDefinitionStates = null;
      _currentDefinitionOwners = null;
      // Clear the per-call source context so it never lingers past this call —
      // a helper invoked directly (not through `translate`) would otherwise
      // read a stale source path / line info from a previous translation.
      _currentSourcePath = null;
      _currentLineInfo = null;
    }
    return TranslationResult(
      dsl: dsl,
      issues: issues,
      navigation: navigationLowering,
      suppressed: suppressed,
      widgetDefinitions: widgetDefinitions,
      widgetDefinitionStates: widgetDefinitionStates,
      rootWidgetState: rootWidgetState,
    );
  }

  /// Attempts the strict inline emit of [classification]/[blueprint]
  /// standalone — running the same mechanism gate, RFW-name-collision check,
  /// State-shape validation, and definition-body translation the paywall-body
  /// inline path ([_tryInlineCustomWidget]) runs — and returns the result.
  ///
  /// It emits no call site (a standalone widget has none); only the
  /// definition body is measured. The widget is **emit-confirmed inlinable**
  /// exactly when the returned result has no issues AND carries a definition
  /// (`widgetDefinitions` non-empty). Any other outcome — an unimplemented
  /// required mechanism, a name collision with the paywall root or a catalog
  /// widget, a non-foldable State shape, or an unrecognised body expression —
  /// means it does not inline today.
  ///
  /// Note this measures *whether* the translator emits, not whether the
  /// emit is faithful: a body whose only defect is a silently-degraded value
  /// (the enum-name / non-finite-double fallback that adds no issue) still
  /// emits a definition and counts as confirmed. That silent-fidelity-loss
  /// class is a separate concern from this emit-confirmation metric.
  ///
  /// It runs the same strict checks as the paywall-body inline path
  /// (`_tryInlineCustomWidget`), but NOT the two further gates the *full*
  /// production build applies after translation — `parseLibraryFile` of the
  /// emitted DSL and the post-emit `validateModelAgainstCatalog` model-walk
  /// (see `codegen_builder`). So a body that translates issue-free but whose
  /// emitted DSL would fail one of those would still count confirmed here.
  /// The metric is therefore a (safe-direction) **over-confirming upper
  /// bound** — it never under-counts inlinable; the residual is narrow and is
  /// closed when the post-L12 conversion runs the full real-catalog emit.
  ///
  /// Internal to the coverage-measurement tooling (the harness + the
  /// standalone CLI). Callers map the result to an `EmitOutcome`.
  TranslationResult attemptInlineEmit(
    WidgetClassification classification,
    CustomWidgetBlueprint blueprint,
  ) {
    _currentSourcePath = null;
    _currentLineInfo = null;
    final issues = <Issue>[];
    final definitions = <String, String>{};
    final definitionStates = <String, Map<String, String>>{};

    TranslationResult resultWith(List<Issue> reported) => TranslationResult(
          dsl: '',
          issues: reported,
          widgetDefinitions: definitions,
          widgetDefinitionStates: definitionStates,
        );

    // Only a ComposableWidget whose required mechanisms are all implemented
    // can inline; anything else has no definition to emit (→ not confirmed).
    if (classification is! ComposableWidget ||
        classification.requiredMechanisms
            .difference(_kImplementedMechanisms)
            .isNotEmpty) {
      return resultWith(issues);
    }

    final name = blueprint.rfwName;
    // A name that shadows the paywall root or a catalog widget would make a
    // reference in the blob ambiguous — the same diagnostic the inline path
    // raises.
    if (name == paywallRootWidgetName ||
        catalog.widgets.any((w) => w.name == name)) {
      issues.add(
        _nameCollisionIssue(
          blueprint.classKey,
          name,
          name == paywallRootWidgetName
              ? 'the paywall root widget'
              : 'the catalog widget',
        ),
      );
      return resultWith(issues);
    }

    // State-shape validation (non-foldable initialiser / unrecognised
    // setState body) — surfaced before body translation, as the inline path
    // does.
    final shapeIssue =
        _validateStateShape(blueprint, blueprint.buildExpression);
    if (shapeIssue != null) {
      issues.add(shapeIssue);
      return resultWith(issues);
    }

    // Translate the definition body in the inline context the production path
    // uses: constructor params lower to `args.`, State fields to `state.`,
    // event handlers from the classifier-captured verdicts. Fresh
    // accumulators let a transitively-composed custom widget register; the
    // widget pre-claims its own RFW name.
    final saved = _walk;
    final stateFields = blueprint.state;
    _walk = _walk.copyWith(
      argNames: blueprint.params.map((p) => p.name).toSet(),
      params: {for (final p in blueprint.params) p.name: p},
      classKey: blueprint.classKey,
      validatedCoalesceParams: {},
      stateFields: stateFields == null
          ? null
          : {for (final field in stateFields) field.name: field},
      eventHandlers: blueprint.eventHandlers,
      rootStateContext: false,
      inlined: blueprint.inlined,
    );
    _currentWidgetDefinitions = definitions;
    _currentWidgetDefinitionStates = definitionStates;
    _currentDefinitionOwners = <String, String>{name: blueprint.classKey};
    try {
      definitions[name] = _translate(blueprint.buildExpression, issues);
      if (stateFields != null && stateFields.isNotEmpty) {
        definitionStates[name] = {
          for (final field in stateFields)
            field.name: _stateInitialLiteral(field),
        };
      }
    } finally {
      _walk = saved;
      _currentWidgetDefinitions = null;
      _currentWidgetDefinitionStates = null;
      _currentDefinitionOwners = null;
    }

    return TranslationResult(
      dsl: name,
      issues: issues,
      widgetDefinitions: definitions,
      widgetDefinitionStates: definitionStates,
    );
  }

  String _translate(Expression expr, List<Issue> issues) {
    // Parenthesis is semantically transparent — unwrap it uniformly so every
    // type-dispatch below (and at the slot/param entry points that pre-resolve
    // before dispatching) sees through it. A PARTIAL unwrap would be a new
    // asymmetry: e.g. a parenthesized conditional at a numeric slot reaching
    // the generic path instead of the per-branch-coercing slot path, emitting
    // bare ints the runtime `v<double>` decode silently nulls.
    if (expr is ParenthesizedExpression) {
      return _translate(expr.expression, issues);
    }
    if (expr is FunctionExpression) {
      final navigation = _currentNavigation;
      if (navigation != null) {
        final pop = recogniseNavigatorPopBack(expr);
        switch (pop) {
          case NavigatorPopBackRecognised(:final contextIdentifier):
            if (navigation.hasTransitions) {
              // A paywall with a recognised push is a flow ENTRY. An entry's
              // Navigator.pop is a host dismiss, not a flow back — back()
              // no-ops at the initial flow screen — so it cannot be lowered
              // as in-flow back. Fatal-defer in both artifacts; the entry
              // dismisses via the skip terminator.
              issues.add(
                _navigationUnsupportedIssue(
                  "an entry paywall's Navigator.pop cannot be lowered as a "
                  "flow back; dismiss via paywallEvent('skip')",
                  expr,
                ),
              );
              return '';
            }
            if (_flowScreenContext) {
              if (!_usesBuildContextParameter(contextIdentifier)) {
                issues.add(
                  _navigationUnsupportedIssue(
                    'Navigator.pop with a non-build-context targets a '
                    'different navigator and cannot be lowered as in-flow '
                    'back',
                    expr,
                  ),
                );
                return '';
              }
              return 'event "back" {}';
            }
            _currentTranslationSuppressed = true;
            issues.add(
              Issue(
                code: IssueCode.navigationStandaloneArtifactSkipped,
                message:
                    'this paywall uses an in-flow Navigator.pop (back); its '
                    'standalone blob is not emitted — it renders as a flow '
                    "screen. Use paywallEvent('close') for a standalone "
                    'dismiss, or present it via a flow.',
                location: _locationOf(expr),
              ),
            );
            return '';
          case NavigatorPopResultUnsupported(:final reason):
            issues.add(_navigationUnsupportedIssue(reason, expr));
            return '';
          case NavigatorPopNotRecognised():
            break;
        }

        final trigger = recogniseNavigationTrigger(expr);
        switch (trigger) {
          case NavigationRecognised(navigation: final recognised):
            final eventName = navigation.eventFor(recognised);
            if (eventName != null) return 'event "$eventName" {}';
          case NavigationResultDropped(:final reason) ||
                NavigationFormUnsupported(:final reason):
            issues.add(_navigationUnsupportedIssue(reason, expr));
            return '';
          case NavigationNotRecognised():
            break;
        }
      }
      final modalSheet = _walk.modalSheet;
      if (modalSheet != null) {
        final trigger = recogniseModalSheetTrigger(expr);
        switch (trigger) {
          case ModalSheetRecognised(:final sheet):
            if (identical(sheet.call, modalSheet.sheet.call)) {
              return 'set state.${modalSheet.flagName} = true';
            }
          case ModalSheetResultDropped(:final reason):
            issues.add(_modalSheetUnsupportedIssue(reason, expr));
            return '';
          case ModalSheetNotRecognised():
            break;
        }
      }
      final closeFlag = _walk.modalSheetCloseFlag;
      if (closeFlag != null) {
        final close = recogniseModalSheetCloseHandler(expr);
        switch (close) {
          case ModalSheetCloseRecognised():
            return 'set state.$closeFlag = false';
          case ModalSheetCloseUnsupported(:final reason):
            issues.add(_modalSheetUnsupportedIssue(reason, expr));
            return '';
          case ModalSheetCloseNotRecognised():
            break;
        }
      }
    }
    if (expr is SimpleStringLiteral) {
      return _stringLiteral(expr.value);
    }
    if (expr is StringInterpolation) {
      return _stringInterpolation(expr, issues);
    }
    // Adjacent string literals (`'a' 'b'`) concatenate at compile time. Handle
    // the all-literal form here; a mixed adjacent string that includes an
    // interpolated segment falls through to the unsupported-expression path
    // rather than silently dropping the interpolation.
    if (expr is AdjacentStrings &&
        expr.strings.every((s) => s is SimpleStringLiteral)) {
      return _stringLiteral(
        expr.strings.map((s) => (s as SimpleStringLiteral).value).join(),
      );
    }
    if (expr is IntegerLiteral) {
      final v = expr.value;
      if (v == null) {
        issues.add(
          Issue(
            code: IssueCode.integerLiteralOverflow,
            message:
                'Integer literal overflows int64 and cannot be represented '
                'in the RFW format.',
            location: _locationOf(expr),
          ),
        );
        return '';
      }
      return v.toString();
    }
    if (expr is DoubleLiteral) {
      // An overflowing literal (`1e400`) parses to a non-finite double, which
      // has no representable RFW value and would otherwise emit the bare token
      // `Infinity`. Refuse it loud (the literal funnel for the non-finite
      // guard; the named-const funnel is in `_prefixedIdentifier`).
      if (!expr.value.isFinite) {
        issues.add(_nonFiniteNumericIssue(expr));
        return '';
      }
      return expr.value.toString();
    }
    // Unary minus on a numeric literal. The analyzer parses `-1.5` as
    // `PrefixExpression('-', DoubleLiteral(1.5))`, so the negative
    // literal needs an explicit case. Restricting the operand to
    // numeric literals keeps the surface predictable; arbitrary
    // expression negation lands as a sibling extension when needed.
    if (expr is PrefixExpression &&
        expr.operator.lexeme == '-' &&
        (expr.operand is IntegerLiteral || expr.operand is DoubleLiteral)) {
      return '-${_translate(expr.operand, issues)}';
    }
    if (expr is BooleanLiteral) {
      return expr.value.toString();
    }
    if (expr is NullLiteral) {
      return 'null';
    }
    if (expr is ListLiteral) {
      return _listLiteral(expr, issues);
    }
    if (expr is SetOrMapLiteral) {
      return _setOrMapLiteral(expr, issues);
    }
    if (expr is ConditionalExpression) {
      return _conditionalExpression(expr, issues);
    }
    // Null-coalescing optional property — `<prop> ?? <fallback>`. Handled here
    // (not only at the catalog-slot path) so a `??` nested inside a structured
    // value (`Border.all(color: color ?? scheme.primary)`) is rewritten too.
    // The fallback was validated against its slot in
    // `_validateThemeValueForSlot` before the rewrite. Inert outside an inline
    // (no `_walk.params`).
    final coalesce = _coalesceParamAt(expr);
    if (coalesce != null) {
      return _translateCoalesce(coalesce, issues);
    }
    // A const-object field access — a reference to an INSTANCE field of a
    // `const` object (`const _skin = Skin(...); _skin.headline`). Fold it to
    // the field's value, ahead of the PrefixedIdentifier / PropertyAccess arms
    // so it never reaches their enum / bare-name fall-throughs:
    //   β — re-translate the bound initializer AST through the existing value
    //       recipes (byte-identical to the inline literal, scalar AND
    //       structured: `_skin.primary` → `Color(0x…)` → `0x…`);
    //   α — fold a cross-file / defaulted SCALAR via the analyzer's const
    //       evaluation (closes the silent-wrong-render bug everywhere);
    //   else — a recognised const-object field access neither can fold defers
    //       LOUD (never the silent field-name emit). [tryFoldConstant] stays
    //       scalar-only; this is its co-consulted structured-reference sibling,
    //       the same boundary the classifier consults so the two never diverge.
    if (isConstObjectFieldAccess(expr)) {
      final initializer = resolveConstObjectFieldInitializer(expr);
      if (initializer != null) return _translate(initializer, issues);
      final scalar = tryScalarFoldConstObjectField(expr);
      if (scalar != null) return _foldedLiteral(scalar);
      issues.add(_constObjectFieldUnresolvedIssue(expr));
      return '';
    }
    if (expr is PrefixedIdentifier) {
      return _prefixedIdentifier(expr, issues);
    }
    if (expr is SimpleIdentifier) {
      // A reference to a bound helper parameter resolves-through to its
      // argument, translated in the caller's context — element-keyed, so it
      // is matched before any name-based arg/state lowering and a helper param
      // sharing a name with a constructor parameter cannot be mislowered.
      final boundArg = _walk.paramBindings[expr.element];
      if (boundArg != null) {
        return _translate(boundArg, issues);
      }
      // A reference to a leading `final` local binding resolves-through to its
      // initializer (element-keyed, before the name-based lowerings).
      final localInitializer = _walk.inlined.localBindings[expr.element];
      if (localInitializer != null) {
        return _translate(localInitializer, issues);
      }
      // The arg/state/handler matches below are NAME-based. A `const` local
      // declared in the build() body (permitted by the body-shape rule) can
      // shadow a same-named constructor parameter or State field; it must fold
      // to its literal value, NOT be lowered to an `args.`/`state.` runtime
      // reference (a value-wrong blob the floor cannot catch — any reference is
      // structurally valid). The element disambiguates: a resolved
      // `LocalVariableElement` is definitively a local, never a param/field/
      // handler, so it skips the name matches and falls through to constant
      // folding. (An unresolved identifier — null element — keeps the
      // name-based behavior; the shadowing path requires the element-aware
      // classifier to fold first, which requires resolution, so it never
      // reaches here unresolved.)
      if (expr.element is! LocalVariableElement) {
        // A bare identifier resolving to a State event-handler method —
        // lowered to a `set state.<field> = …` handler emitted from the
        // classifier-captured verdict.
        final handler = _walk.eventHandlers[expr.name];
        if (handler != null) {
          return _emitSetStateHandler(handler, expr.name, issues, expr);
        }
        // A bare identifier resolving to a State field of the stateful
        // custom-widget definition currently being translated — lowered to the
        // RFW `state.` namespace. Guarded by [_walk.stateFields] being
        // non-null (we are inside a stateful walk) and the name being a
        // declared State field, so identifiers outside a stateful walk and
        // accidental name collisions outside that scope fall through.
        final stateFields = _walk.stateFields;
        if (stateFields != null && stateFields.containsKey(expr.name)) {
          return 'state.${expr.name}';
        }
        if (_walk.argNames.contains(expr.name)) {
          // A constructor-parameter reference inside a custom-widget definition
          // body — lowered to the RFW `args.` namespace. In a stateful walk,
          // the State's `build()` reaches constructor params via `widget.X`
          // instead, but `_walk.argNames` is still populated so another
          // stateless-only path stays consistent.
          return 'args.${expr.name}';
        }
      }
    }
    if (expr is InstanceCreationExpression) {
      return _instanceCreation(expr, issues);
    }
    if (expr is MethodInvocation) {
      return _methodInvocation(expr, issues);
    }
    if (expr is CascadeExpression) {
      return _structured.cascadeExpression(expr, issues);
    }
    if (expr is PropertyAccess) {
      // Theme-as-data: a `Theme.of(<ident>).<x>(.<y>)` chain lowers to a
      // `data.theme.<x>.<y>` reference. Non-matching shapes deliberately
      // fall through to the const-fold + unrecognised-expression chain.
      final themePath = _recognizeThemeRead(expr);
      if (themePath != null) {
        return _themeRead(themePath, _locationOf(expr), issues);
      }
    }
    // Constant-folding fallback — a const reference or const arithmetic
    // expression the cases above did not handle folds to a literal.
    final folded = tryFoldConstant(expr);
    if (folded != null) {
      return _foldedLiteral(folded);
    }
    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        capabilityGapSubject: 'expression:${expr.runtimeType}',
        message: 'Unsupported expression: ${expr.runtimeType} `$expr`. '
            'See the supported expression subset.',
        location: _locationOf(expr),
      ),
    );
    return '';
  }

  /// Renders a folded constant — an [int], [double], [bool], or [String] —
  /// as an RFW DSL literal fragment.
  String _foldedLiteral(Object value) {
    if (value is String) return _stringLiteral(value);
    return value.toString();
  }

  /// The loud-defer diagnostic for a recognised const-object field access that
  /// can neither β-substitute (its initializer is not reachable in this
  /// compilation unit) nor α-scalar-fold (a cross-file non-scalar value, or
  /// the member is a computed getter rather than a stored const field). Shared
  /// by the `_translate` hook and the slot-value path so both defer with the
  /// same actionable message — never the silent field-name emit.
  Issue _constObjectFieldUnresolvedIssue(Expression expr) => Issue(
        code: IssueCode.constObjectFieldUnresolved,
        message: 'Cannot fold the const-object field reference '
            "'${expr.toSource()}' to a value: it is not a same-file stored "
            'const field this codegen can substitute (it may be a cross-file '
            'non-scalar value, or a computed getter rather than a stored '
            'const field). Inline the value at the use site, or make it a '
            'stored const field in the same file.',
        location: _locationOf(expr),
      );

  String _stringLiteral(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }

  String _stringInterpolation(StringInterpolation expr, List<Issue> issues) {
    final segments = <_InterpSegment>[];

    for (final element in expr.elements) {
      if (element is InterpolationString) {
        if (element.value.isNotEmpty) {
          segments.add(_InterpSegment.literal(element.value));
        }
      } else if (element is InterpolationExpression) {
        final inner = element.expression;
        final dsl = _stringInterpolationExpression(inner, issues);
        if (dsl != null) segments.add(_InterpSegment.dataRef(dsl));
      }
    }

    // Encode each segment and emit the synthetic sentinel string that the
    // Text-construction rewrite path recognises. Format:
    //   __rfw_interp("<literal>", data.ref.path, ...)
    // Quoted strings are DSL literals; unquoted are DSL state-ref expressions.
    final encoded = segments.map((s) {
      if (s.kind == _InterpKind.literal) {
        return '"${_escapeForDsl(s.text)}"';
      }
      return s.text;
    }).toList();

    return '__rfw_interp(${encoded.join(', ')})';
  }

  String _escapeForDsl(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n');

  String? _stringInterpolationExpression(
    Expression inner,
    List<Issue> issues,
  ) {
    if (inner is MethodInvocation && inner.target == null) {
      final resolvedElement = inner.methodName.element;
      HelperDefinition? helper;
      if (resolvedElement != null) {
        // Strictly match (name, library) — same rationale as
        // _methodInvocation: a resolved non-SDK call must not fall back to the
        // name-only path.
        final libUri = resolvedElement.library?.identifier ?? '';
        helper = helpers.find(inner.methodName.name, libUri);
      } else {
        // Unresolved element — best-effort name-only fallback.
        helper = helpers.findByNameOnly(inner.methodName.name);
      }
      if (helper == null) {
        issues.add(
          Issue(
            code: IssueCode.unsupportedInterpolation,
            message: 'Could not resolve the interpolated expression '
                '${inner.toSource()} to a recognized helper. Ensure the '
                'helper is imported from the SDK.',
            location: _locationOf(inner),
          ),
        );
        return null;
      }
      if (helper.returnCategory != HelperReturnCategory.string) {
        issues.add(
          Issue(
            code: IssueCode.unsupportedHelperPosition,
            message: 'Only helpers that return a String value may appear '
                'inside string interpolation; ${helper.name} returns '
                '${helper.returnCategory.name}.',
            location: _locationOf(inner),
          ),
        );
        return null;
      }
      return _translate(inner, issues);
    }

    final resolved = _resolveBoundIdentifier(inner);
    if (resolved is SimpleIdentifier) {
      final field = _walk.stateFields?[resolved.name];
      if (field != null && !field.isNumeric && field.initialValue is String) {
        return 'state.${resolved.name}';
      }
    }

    issues.add(
      Issue(
        code: IssueCode.unsupportedInterpolation,
        message: 'Only recognized String helpers or String State fields may '
            'appear inside string interpolation. Found: ${inner.runtimeType} '
            '${inner.toSource()}.',
        location: _locationOf(inner),
      ),
    );
    return null;
  }

  String _listLiteral(ListLiteral expr, List<Issue> issues) {
    final parts = <String>[];
    for (final element in expr.elements) {
      if (element is Expression) {
        parts.add(_translate(element, issues));
      } else {
        // Spread (`...`), collection-`if`, collection-`for`. The analyzer
        // surfaces these as `CollectionElement` subtypes that aren't
        // `Expression`.
        issues.add(
          Issue(
            code: IssueCode.unsupportedCollectionFlow,
            message: 'Spread, collection-if, and collection-for are not '
                'supported in paywall list literals. Use a static list of '
                'children.',
            location: _locationOf(expr),
          ),
        );
      }
    }
    return '[${parts.join(', ')}]';
  }

  String _setOrMapLiteral(SetOrMapLiteral expr, List<Issue> issues) {
    final parts = <String>[];
    for (final element in expr.elements) {
      if (element is MapLiteralEntry) {
        final key = _mapLiteralKey(element.key, issues);
        final value = _translate(element.value, issues);
        parts.add('$key: $value');
        continue;
      }
      issues.add(
        Issue(
          code: IssueCode.unsupportedCollectionFlow,
          message: 'Set literals, spreads, collection-if, and collection-for '
              'are not supported in map literals. Use a static string-keyed '
              'map.',
          location: _locationOf(expr),
        ),
      );
    }
    return '{ ${parts.join(', ')} }';
  }

  String _mapLiteralKey(Expression expr, List<Issue> issues) {
    String? key;
    if (expr is SimpleStringLiteral) {
      key = expr.value;
    } else {
      // The unified scalar boundary, so a const-object scalar field used as a
      // map key folds consistently with emission (this path bypasses _translate
      // and so the const-object hook there).
      final folded = tryFoldScalarConstant(expr);
      if (folded is String) key = folded;
    }
    if (key == null) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'Map literal keys must be string constants.',
          location: _locationOf(expr),
        ),
      );
      return '';
    }
    if (!_rfwIdentifierPattern.hasMatch(key)) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'Map literal key "$key" is not a valid RFW identifier.',
          location: _locationOf(expr),
        ),
      );
      return '';
    }
    return key;
  }

  String _prefixedIdentifier(
    PrefixedIdentifier expr,
    List<Issue> issues,
  ) {
    final prefix = expr.prefix.name;
    final identifier = expr.identifier.name;

    // `widget.<X>` inside a stateful walk — the State's `build()` reaches
    // a `StatefulWidget` constructor parameter through the inherited
    // `widget` field. Lowers to `args.<X>` provided X is a declared
    // constructor parameter. Stateless walks never see `widget.` (their
    // build() reads constructor params as bare identifiers), so the branch
    // is gated on the stateful-walk marker.
    if (prefix == 'widget' &&
        _walk.stateFields != null &&
        _walk.argNames.contains(identifier)) {
      return 'args.$identifier';
    }
    if (prefix == 'widget' && _walk.rootStateContext) {
      issues.add(
        Issue(
          code: IssueCode.stateShapeUnsupported,
          message: 'Root source State.build() cannot read widget.$identifier. '
              'Root sources are not called by another RFW widget, so there is '
              'no args.$identifier binding to emit. Move the value into a '
              'constant, host data, or an explicit supported State field.',
          location: _locationOf(expr),
        ),
      );
      return '';
    }

    if (prefix == 'Colors') {
      // The `Colors.*` arm lowers against a hard-coded Material colour table,
      // so it must fire ONLY for the real `package:flutter` `Colors` — a
      // customer class that happens to be named `Colors` would otherwise be
      // lowered to the Material int instead of the author's value, a
      // value-wrong blob the colour floor cannot catch (any int is a valid
      // colour). An unresolved prefix defers too (never name-match).
      if (!_prefixResolvesToFlutter(expr.prefix)) {
        return _deferFrameworkConstLookalike(expr, prefix, identifier, issues);
      }
      final color = _kMaterialColors[identifier];
      if (color != null) return color;
      issues.add(
        Issue(
          code: IssueCode.unresolvedIdentifier,
          message: "Unsupported Material color 'Colors.$identifier'. "
              'Supported colors: ${_kMaterialColors.keys.join(", ")}.',
          location: _locationOf(expr),
        ),
      );
      return '';
    }

    if (prefix == 'Icons' || prefix == 'CupertinoIcons') {
      // Const `IconData` field on `Icons` / `CupertinoIcons`. Resolve
      // the constant so the emitted DSL carries the integer codepoint
      // the rfw `iconCodepoint` decoder expects — without resolution
      // the identifier would fall through to the enum-string branch
      // and the runtime would reject the property type. Gated to the real
      // `package:flutter` namespaces so no name-only path survives: a
      // customer class named `Icons` (or an unresolved prefix) defers.
      if (!_prefixResolvesToFlutter(expr.prefix)) {
        return _deferFrameworkConstLookalike(expr, prefix, identifier, issues);
      }
      return _resolveIconCodepoint(expr, issues);
    }

    // The const-factory `.zero` accessors lower to the same value as their
    // explicit zero constructors (`EdgeInsets.all(0)` / `BorderRadius` zero) —
    // without this they fall through to the bare-name path and emit `"zero"`,
    // which the value-type floor then rejects. Gated to the real framework
    // type: a resolved customer `EdgeInsets` / `BorderRadius` look-alike with a
    // `zero` member defers rather than lowering as the framework zero value
    // (the value-substitution silent-wrong). NOTE the two predicates in this
    // method are intentionally NOT the same: the `Colors`/`Icons` arms above
    // use `_prefixResolvesToFlutter` (defer-on-null — they lower against a
    // hard-coded table, so a degraded-build unresolved prefix must not re-open
    // the table-substitution); these value-type arms use
    // `_frameworkOrUnresolved` (name-fallback-on-null — they compute from the
    // author's own args, so an unresolved prefix safely keeps the
    // synthetic-test affordance).
    if ((prefix == 'EdgeInsets' || prefix == 'EdgeInsetsDirectional') &&
        identifier == 'zero') {
      if (!_frameworkOrUnresolved(expr.prefix.element)) {
        return _deferFrameworkConstLookalike(expr, prefix, identifier, issues);
      }
      return '[0.0, 0.0, 0.0, 0.0]';
    }
    if ((prefix == 'BorderRadius' || prefix == 'BorderRadiusDirectional') &&
        identifier == 'zero') {
      if (!_frameworkOrUnresolved(expr.prefix.element)) {
        return _deferFrameworkConstLookalike(expr, prefix, identifier, issues);
      }
      return '0';
    }
    // `Offset.zero` lowers to the same `{x, y}` map the `Offset(0, 0)` ctor
    // produces — without this it falls through to the bare-name path and
    // emits `"zero"`, which the value-type floor then rejects. Element-gated
    // like the sibling `.zero` accessors: a resolved customer `Offset`
    // look-alike with a `zero` member defers rather than lowering as the
    // framework zero value.
    if (prefix == 'Offset' && identifier == 'zero') {
      if (!_frameworkOrUnresolved(expr.prefix.element)) {
        return _deferFrameworkConstLookalike(expr, prefix, identifier, issues);
      }
      return '{x: 0.0, y: 0.0}';
    }

    // A `FontWeight.<member>` reference. A resolved CUSTOMER class named
    // `FontWeight` must NOT lower to a framework weight name — its `.w600`
    // would otherwise emit `"w600"`, which the `enumValue<FontWeight>` decoder
    // resolves to the REAL framework weight (a value-substitution silent-wrong
    // the fontWeight floor cannot catch, since any `"wN"` is a valid weight).
    // Defer it; an UNRESOLVED prefix keeps the name path below (the
    // synthetic-test affordance — the shared name-fallback-on-null
    // convention). For the resolved framework class, canonicalise the member to
    // its `wN` decoder name: the aliases `FontWeight.normal` / `.bold` lower by
    // name to `"normal"` / `"bold"`, which are NOT in `FontWeight.values[].name`
    // — the decoder would null them (a silent drop the invariant forbids) —
    // whereas resolving the const to its weight gives the canonical `w400` /
    // `w700`. A resolved member whose const cannot be canonicalised DEFERS
    // diagnosed — never a name passthrough that nulls.
    if (prefix == 'FontWeight') {
      if (!_frameworkOrUnresolved(expr.prefix.element)) {
        return _deferFrameworkConstLookalike(expr, prefix, identifier, issues);
      }
      if (_isFrameworkValueType(expr.prefix.element)) {
        final canonical = _canonicalFontWeightName(expr);
        if (canonical != null) return '"$canonical"';
        issues.add(
          Issue(
            code: IssueCode.unresolvedIdentifier,
            message: "Couldn't resolve 'FontWeight.$identifier' to a canonical "
                'font weight (w100-w900). Use a standard FontWeight value.',
            location: _locationOf(expr),
          ),
        );
        return '';
      }
    }

    // A `TextDecoration.<member>` reference. Like FontWeight, a resolved
    // CUSTOMER class named `TextDecoration` must NOT lower to the bare member
    // name — the runtime defaults an unknown decoration string to
    // `TextDecoration.none`, a silent drop for the author's own type. Defer the
    // resolved-customer case; the real framework class (and an unresolved
    // synthetic prefix) keeps the member-name path below, which the decoder
    // resolves.
    if (prefix == 'TextDecoration' &&
        !_frameworkOrUnresolved(expr.prefix.element)) {
      return _deferFrameworkConstLookalike(expr, prefix, identifier, issues);
    }

    // A `Curves.<member>` reference. Like FontWeight/TextDecoration, a resolved
    // CUSTOMER class named `Curves` must NOT lower to the bare member name: the
    // curve decoder would resolve a coincidentally-supported name (e.g.
    // `easeIn`) to the REAL framework curve — a value-substitution silent-wrong
    // the curve validator backstop cannot catch, since it only rejects names
    // OUTSIDE the supported set. Defer the resolved-customer case; the real
    // framework class (and an unresolved synthetic prefix) keeps the
    // member-name path below, where the catalog validator backstops the
    // supported curve set on the direct-paywall path.
    if (prefix == 'Curves' && !_frameworkOrUnresolved(expr.prefix.element)) {
      return _deferFrameworkConstLookalike(expr, prefix, identifier, issues);
    }

    // A theme read through a bound `final` theme-local — `scheme.primary`
    // where `final scheme = Theme.of(c).colorScheme;` is in scope. Recognised
    // element-keyed against the active local bindings; inert outside an inline
    // (empty bindings → a bare `scheme.primary` is not a theme read and falls
    // through). Placed before the const/enum fall-throughs so the chain is
    // lowered to its `data.theme.*` reference rather than emitting `"primary"`.
    final themeSegments = _recognizeThemeRead(expr);
    if (themeSegments != null) {
      return _themeRead(themeSegments, _locationOf(expr), issues);
    }

    // A const variable / static-const field — `Tokens.gap` — folds to its
    // literal value. (An enum value is const too, but tryFoldConstant returns
    // null for it, so it falls through to the enum-name path below.)
    final folded = tryFoldConstant(expr);
    if (folded != null) {
      return _foldedLiteral(folded);
    }

    // A non-finite `double` constant — `double.infinity` / `.negativeInfinity`
    // / `.nan` (or any const that evaluates to one) — does not const-fold (the
    // fold path returns null for non-finite) and would otherwise fall through
    // to the bare-name path below and emit `"infinity"`: a string in a numeric
    // slot the runtime silently nulls. Refuse it loud (the named-const funnel
    // for the non-finite guard). A FINITE const (`double.maxFinite`) folds
    // above and never reaches here.
    if (_isNonFiniteDoubleConstant(expr)) {
      issues.add(_nonFiniteNumericIssue(expr));
      return '';
    }

    // Enum reference: `MainAxisAlignment.center` → "center". The catalog
    // declares which property accepts which enum; runtime/validation paths
    // confirm the value is recognized.
    return '"$identifier"';
  }

  /// Whether [expr] is a constant that evaluates to a non-finite double —
  /// `double.infinity` / `.negativeInfinity` / `.nan`, or a customer `const`
  /// equal to one. Reached only after [tryFoldConstant] declined [expr] (a
  /// finite const already folded), so this is the non-finite-or-unresolved
  /// case.
  ///
  /// The three `dart:core` `double` non-finite members are matched by name
  /// first — a pure check that short-circuits the common framework case and
  /// stays valid when the prefix is unresolved (the synthetic-test
  /// affordance). `double` is a built-in type a customer cannot usefully
  /// shadow, so the name match carries no value-substitution risk. Anything
  /// else falls to the resolved path: a customer `const` whose value is a
  /// non-finite double.
  bool _isNonFiniteDoubleConstant(PrefixedIdentifier expr) {
    if (expr.prefix.name == 'double' &&
        const {'infinity', 'negativeInfinity', 'nan'}
            .contains(expr.identifier.name)) {
      return true;
    }
    final variable = _unwrapPropertyAccessor(expr.identifier.element);
    if (variable is FieldElement && variable.isStatic && variable.isConst) {
      final value = variable.computeConstantValue()?.toDoubleValue();
      if (value != null) return !value.isFinite;
    }
    return false;
  }

  /// A loud diagnostic for the non-finite numeric value at [node] — its source
  /// text (e.g. `double.infinity`, `1e400`) names the offending value.
  Issue _nonFiniteNumericIssue(AstNode node) => Issue(
        code: IssueCode.nonFiniteNumericValue,
        message: 'A non-finite double (`${node.toSource()}`) has no '
            'representable value in the RFW format and is silently dropped by '
            'the runtime decode. Use a finite number. For a full-width layout, '
            'size the widget with a finite width or an expanding/fractional '
            'layout widget instead of `double.infinity`.',
        location: _locationOf(node),
      );

  /// The canonical `wN` decoder name for a resolved `FontWeight.<member>`
  /// reference, or `null` when the member's const cannot be resolved to a
  /// canonical weight (the caller then defers diagnosed). Resolving the const
  /// (`computeConstantValue`, the `_resolveIconCodepoint` precedent) folds the
  /// aliases (`normal` → `w400`, `bold` → `w700`) onto the same `wN` name the
  /// `enumValue<FontWeight>(FontWeight.values, …)` decoder matches, so every
  /// member round-trips rather than the bare alias name nulling the decoder.
  String? _canonicalFontWeightName(PrefixedIdentifier expr) {
    final element = expr.identifier.element;
    if (element is! PropertyAccessorElement) return null;
    final weight = element.variable
        .computeConstantValue()
        ?.getField('value')
        ?.toIntValue();
    if (weight == null) return null;
    // The decoder's vocabulary is exactly the nine `w100`..`w900` members of
    // `FontWeight.values`; a non-canonical weight has no matching name.
    if (weight < 100 || weight > 900 || weight % 100 != 0) return null;
    return 'w$weight';
  }

  String _resolveIconCodepoint(
    PrefixedIdentifier expr,
    List<Issue> issues,
  ) {
    final element = expr.identifier.element;
    if (element is PropertyAccessorElement) {
      final codepoint = element.variable
          .computeConstantValue()
          ?.getField('codePoint')
          ?.toIntValue();
      if (codepoint != null) return '$codepoint';
    }
    issues.add(
      Issue(
        code: IssueCode.unresolvedIdentifier,
        message: "Couldn't resolve '${expr.prefix.name}.${expr.identifier.name}"
            "' to a const IconData with an integer 'codePoint' field. "
            'Confirm the icon package is in pubspec.yaml and the identifier '
            'is spelled correctly.',
        location: _locationOf(expr),
      ),
    );
    // Empty-string sentinel matches the rest of the translator — callers
    // gate on `translation.issues.isNotEmpty` and never read this value,
    // and any additional caller that does will fail the downstream
    // `parseLibraryFile` step loudly rather than emit a bogus codepoint.
    return '';
  }

  /// Whether [prefix] resolves to a class in `package:flutter/` — the strict
  /// gate for the `Colors` / `Icons` / `CupertinoIcons` special arms. Mirrors
  /// the inlining classifier's framework-const recognition: a customer class
  /// that happens to be named `Colors` / `Icons` must NOT enter those arms, and
  /// an UNRESOLVED prefix (`element == null`) is NOT recognised — it defers.
  /// The translator runs on resolved ASTs in production, so a null element is
  /// genuinely-unresolvable input; name-matching it would re-open the
  /// silent-wrong in a degraded/error-recovery build, so the safe direction is
  /// to defer (the recognised set is the resolved-real-Flutter case only).
  bool _prefixResolvesToFlutter(SimpleIdentifier prefix) =>
      libraryIsFlutter(prefix.element);

  /// True when [element] is unresolved (`null` — a synthetic-test input) OR
  /// resolves to a framework value-type library (`dart:` / `package:flutter/`).
  /// The value-type recognition arms that also serve unresolved synthetic
  /// inputs (the bare-call `_methodInvocation` arms, the `.zero` const-factory
  /// arms) gate on this: a resolved CUSTOMER look-alike (non-null,
  /// non-framework) defers — closing the value-substitution silent-wrong —
  /// while an unresolved reference keeps the name-based recognition. Production
  /// always resolves, so the unresolved branch is the test affordance, not a
  /// production vector.
  bool _frameworkOrUnresolved(Element? element) =>
      element == null || _isFrameworkValueType(element);

  /// Lowers a const `Duration(...)` to its total **milliseconds** (an int) —
  /// the flat representation the `duration` property decoder reads
  /// (`Duration(milliseconds: ms)`). Every named unit argument must fold to a
  /// const int; a sub-millisecond total cannot be represented and defers with a
  /// diagnostic rather than silently truncating. Recognised by name, consistent
  /// with the translator's other value-type recipes.
  String _duration(
    NodeList<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    const unitMicros = <String, int>{
      'days': Duration.microsecondsPerDay,
      'hours': Duration.microsecondsPerHour,
      'minutes': Duration.microsecondsPerMinute,
      'seconds': Duration.microsecondsPerSecond,
      'milliseconds': Duration.microsecondsPerMillisecond,
      'microseconds': 1,
    };
    // Accumulate in BigInt so an out-of-range total (e.g. a near-int64-max
    // unit literal) is detected and deferred rather than silently wrapping to
    // a wrong (negative) millisecond value.
    var totalMicros = BigInt.zero;
    for (final arg in args) {
      if (arg is! NamedExpression) {
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message: 'Duration accepts only named unit arguments '
                '(days / hours / minutes / seconds / milliseconds / '
                'microseconds).',
            location: loc,
          ),
        );
        return '';
      }
      final unit = arg.name.label.name;
      final micros = unitMicros[unit];
      if (micros == null) {
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message: "Unsupported Duration unit '$unit'.",
            location: loc,
          ),
        );
        return '';
      }
      // The unified scalar boundary, so a const-object scalar field used as a
      // Duration unit folds consistently with emission (bypasses _translate).
      final folded = tryFoldScalarConstant(arg.expression);
      if (folded is! int) {
        issues.add(
          Issue(
            code: IssueCode.unresolvedIdentifier,
            message: "Duration '$unit' must be a const integer to lower to a "
                'milliseconds value.',
            location: loc,
          ),
        );
        return '';
      }
      totalMicros += BigInt.from(folded) * BigInt.from(micros);
    }
    final microsPerMilli = BigInt.from(Duration.microsecondsPerMillisecond);
    if (totalMicros % microsPerMilli != BigInt.zero) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'Sub-millisecond Duration values cannot be represented; the '
              'duration property is millisecond-granular.',
          location: loc,
        ),
      );
      return '';
    }
    final totalMillis = totalMicros ~/ microsPerMilli;
    // The emitted value is decoded as a 64-bit int; defer (don't wrap) a total
    // that does not fit.
    final maxInt = BigInt.parse('9223372036854775807');
    final minInt = BigInt.parse('-9223372036854775808');
    if (totalMillis < minInt || totalMillis > maxInt) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'Duration value is out of range; its millisecond total does '
              'not fit a 64-bit integer.',
          location: loc,
        ),
      );
      return '';
    }
    return '$totalMillis';
  }

  /// Records the diagnostic for a `Colors` / `Icons` / `CupertinoIcons`
  /// reference whose prefix is not the real `package:flutter` namespace (a
  /// customer lookalike or an unresolved prefix) and returns the empty-string
  /// sentinel. Deferring here is the translator-strict half of the
  /// classifier-broad / translator-strict pattern: the classifier may fold a
  /// customer scalar const into the composable set, but the translator refuses
  /// to lower a `Colors` / `Icons` reference that is not the framework's.
  String _deferFrameworkConstLookalike(
    PrefixedIdentifier expr,
    String prefix,
    String identifier,
    List<Issue> issues,
  ) {
    issues.add(
      Issue(
        code: IssueCode.unresolvedIdentifier,
        message: "'$prefix.$identifier' does not resolve to package:flutter's "
            '$prefix; a constant named $prefix that is not the framework one '
            'cannot be inlined here. Reference its value directly.',
        location: _locationOf(expr),
      ),
    );
    return '';
  }

  String _deferFrameworkCtorLookalike(
    InstanceCreationExpression expr,
    String typeName,
    List<Issue> issues,
  ) {
    issues.add(
      Issue(
        code: IssueCode.unresolvedIdentifier,
        message: "'${expr.toSource()}' does not resolve to package:flutter's "
            '$typeName; a constructor named $typeName that is not the '
            'framework one cannot be inlined here. Reference its value '
            'directly.',
        location: _locationOf(expr),
      ),
    );
    return '';
  }

  bool _isResolvedNonFrameworkCtor(InstanceCreationExpression expr) {
    final ctorClass = _classOfInstanceCreation(expr);
    return ctorClass != null && !_isFrameworkValueType(ctorClass);
  }

  /// Shared hand-authored value-type routing for the rows that are byte-
  /// identical across the constructor (`_instanceCreation`) and static-call
  /// (`_methodInvocation`) AST shapes. Both ladders normalize their shape to a
  /// `(type, variant)` descriptor and route here (via [_tryValueOrRecipe])
  /// after recipe dispatch, replacing the two hand-maintained type-name
  /// if-ladders with one table. Returns the emitted DSL fragment for a matched
  /// row, or
  /// `null` on a miss so the caller falls through to its shape-specific tail
  /// (the genuinely-divergent cases: the full ShapeBorder set + the
  /// unsupported-shape diagnostic on the constructor side; the
  /// LinearBorder/StarBorder factory + the unsupported-Border/Color-factory
  /// diagnostics on the static-call side).
  ///
  /// Two rows are SHAPE-GATED on [fromConstructor] because the original two
  /// ladders diverged for them and the divergence must be preserved
  /// byte-for-byte: `Duration` was lowered only on the constructor
  /// (`_instanceCreation`) shape, and `TextDecoration.combine` only on the
  /// static-call (`_methodInvocation`) shape. The cross-shape reachability is
  /// real (a standalone `TextDecoration.combine([...])` parses as an
  /// InstanceCreationExpression, NOT a MethodInvocation), so without the gate
  /// the constructor path would lower it where the original deferred it — an
  /// output change. The gate keeps both rows enumerated in this one table while
  /// reproducing the original per-shape behavior. (Lowering these on the other
  /// shape is a deliberate, separate feature-add, not part of this byte-stable
  /// normalization.)
  String? _tryValueType(
    String type,
    String? variant,
    NodeList<Expression> args,
    List<Issue> issues,
    String loc, {
    required bool fromConstructor,
  }) {
    switch (type) {
      case 'Locale':
        return _structured.locale(variant, args, issues, loc);
      case 'Paint':
        return variant == null ? '{}' : null;
      case 'Shadow':
        return variant == null ? _structured.shadow(args, issues, loc) : null;
      case 'FontFeature':
        return _structured.fontFeature(variant, args, issues, loc);
      case 'FontVariation':
        return variant == null
            ? _structured.fontVariation(args, issues, loc)
            : null;
      case 'Duration':
        // Constructor-shape only (see the `fromConstructor` note above).
        return fromConstructor && variant == null
            ? _duration(args, issues, loc)
            : null;
      case 'Border':
        if (variant == 'all') {
          return _structured.borderAll(args, issues, loc);
        }
        if (variant == null) {
          return _structured.borderDefault(args, issues, loc);
        }
        return null;
      case 'BorderSide':
        return variant == null
            ? _structured.borderSide(args, issues, loc)
            : null;
      case 'EdgeInsets':
        return variant == null
            ? null
            : _structured.edgeInsets(variant, args.toList(), issues, loc);
      case 'BorderRadius':
        return variant == null
            ? null
            : _structured.borderRadius(variant, args.toList(), issues, loc);
      case 'LinearGradient':
        return variant == null
            ? _structured.linearGradient(args, issues, loc)
            : null;
      case 'BoxShadow':
        return variant == null
            ? _structured.boxShadow(args, issues, loc)
            : null;
      case 'TextDecoration':
        // Static-call-shape only (see the `fromConstructor` note above).
        return !fromConstructor && variant == 'combine'
            ? _structured.textDecorationCombine(args, issues, loc)
            : null;
      default:
        return null;
    }
  }

  /// Routes one `(type, variant)` descriptor through the registered recipe
  /// table (Color / Offset / Alignment) first, then the shared hand-authored
  /// value-type table ([_tryValueType]). Returns the emitted DSL fragment on a
  /// hit, or `null` on a miss (no recipe and no table row) so the caller can
  /// try a second candidate descriptor or fall through to its shape tail.
  /// [fromConstructor] threads the caller's AST shape to the shape-gated table
  /// rows (see [_tryValueType]).
  String? _tryValueOrRecipe(
    String type,
    String? variant,
    NodeList<Expression> args,
    List<Issue> issues,
    String loc, {
    required bool fromConstructor,
  }) {
    final key = recipeKey(library: null, typeName: type, variant: variant);
    if (_recipeDispatcher.hasRecipe(key)) {
      final recipeHit =
          _recipeDispatcher.tryTranslate(key, args.toList(), issues, loc);
      if (recipeHit != null) return recipeHit;
    }
    return _tryValueType(
      type,
      variant,
      args,
      issues,
      loc,
      fromConstructor: fromConstructor,
    );
  }

  String _instanceCreation(
    InstanceCreationExpression expr,
    List<Issue> issues,
  ) {
    final typeName = expr.constructorName.type.name.lexeme;
    final constructorName = expr.constructorName.name?.name;
    // In analyzer 10+, `const SomeClass.namedFactory(...)` shifts the
    // class name onto `importPrefix` and lifts the factory name onto
    // `typeName`. Cache the prefix once for the dispatchers below.
    final prefix = expr.constructorName.type.importPrefix?.name.lexeme;

    final textRich = _tryTextRichInstanceCreation(expr, issues);
    if (textRich != null) return textRich;

    // #2 idiom auto-substitution: a `Text` wrapping an intl NumberFormat
    // formatting idiom rewrites to the equivalent RestagePrice /
    // RestageFormattedNumber catalog widget. Placed ahead of the
    // value-substitution gate below, which would otherwise route `Text`
    // straight to widget construction. Returns null when this is not the idiom.
    final substituted = _tryNumberFormatSubstitution(expr, issues);
    if (substituted != null) return substituted;

    // Value-substitution gate. The framework-value recognition below (the
    // recipe dispatch + the per-type value arms) is NAME-based. A resolved
    // class that is neither `dart:` nor `package:flutter/` is customer code: it
    // cannot be a framework value type, so route it straight to widget
    // construction — a custom `@RestageWidget` resolves there; a customer
    // look-alike of a value type (its own `EdgeInsets` / `Color` / …) defers
    // with an `unknownWidget` diagnostic — rather than lowering it as the
    // framework value (a value-wrong blob the type-aware floor cannot catch,
    // since any structurally-valid value passes). A null element (unresolved
    // synthetic input) keeps the name-based recognition; an
    // `InstanceCreationExpression` only parses when the analyzer resolved a
    // constructor, so production always takes the gated path.
    final ctorClass = _classOfInstanceCreation(expr);
    if (ctorClass != null && !_isFrameworkValueType(ctorClass)) {
      return _catalogWidgetConstruction(
        widgetName: typeName,
        flutterType: _flutterTypeOfInstanceCreation(expr),
        widgetClass: ctorClass,
        args: expr.argumentList.arguments,
        anchor: expr,
        issues: issues,
        constructorName: constructorName,
      );
    }

    // Value-type routing — the registered recipe table (Color / Offset /
    // Alignment) then the shared hand-authored table ([_tryValueType]), both
    // keyed on a `(type, variant)` descriptor. An InstanceCreation presents
    // that descriptor two ways: the type name carries the class with the named
    // constructor as the variant (`Color(...)`, `ui.Color(...)`,
    // `EdgeInsets.all(...)`, `ui.Locale(...)`), OR — the analyzer's
    // const-named-factory shift — the import-prefix slot carries the class and
    // the type name carries the factory (`const Color.fromARGB(...)`,
    // `const EdgeInsets.all(...)`). Try the type-name descriptor first so an
    // import-prefixed DEFAULT constructor (`ui.Locale('en')`, where `ui` is the
    // import alias) routes by its class name rather than being mis-read as
    // `(import-alias, class)`; then try the prefix descriptor for the
    // const-named-factory shift. `Duration` is reachable only through this
    // constructor shape.
    final args = expr.argumentList.arguments;
    final loc = _locationOf(expr);
    final byType = _tryValueOrRecipe(
      typeName,
      constructorName,
      args,
      issues,
      loc,
      fromConstructor: true,
    );
    if (byType != null) return byType;
    if (prefix != null && constructorName == null) {
      final byPrefix = _tryValueOrRecipe(
        prefix,
        typeName,
        args,
        issues,
        loc,
        fromConstructor: true,
      );
      if (byPrefix != null) return byPrefix;
    }

    // `Border` is a concrete `BoxBorder` and therefore a `ShapeBorder` subtype
    // in Flutter; its supported box-border constructors are handled above, so
    // any other `Border`/ShapeBorder factory falls to this generic path before
    // the unsupported-shape diagnostic.
    final shapeBorder = _structured.shapeBorder(
      prefix: prefix,
      typeName: typeName,
      constructorName: constructorName,
      args: expr.argumentList.arguments,
      issues: issues,
      loc: _locationOf(expr),
    );
    if (shapeBorder != null) return shapeBorder;
    if (_isShapeBorderClass(_classOfInstanceCreation(expr))) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'Unsupported ShapeBorder/OutlinedBorder value: '
              '${expr.toSource()}. Supported: RoundedRectangleBorder, '
              'RoundedSuperellipseBorder, CircleBorder, StadiumBorder, '
              'ContinuousRectangleBorder, BeveledRectangleBorder, '
              'LinearBorder, StarBorder, and StarBorder.polygon.',
          location: _locationOf(expr),
        ),
      );
      return '';
    }

    // `new Foo(...)` or resolved-library Foo(...) → catalog widget
    // construction. Pass the resolved class type when the analyzer
    // resolved it so the catalog lookup can pattern-match on the
    // canonical `flutterType` and not on the unqualified class name.
    return _catalogWidgetConstruction(
      widgetName: typeName,
      flutterType: _flutterTypeOfInstanceCreation(expr),
      widgetClass: _classOfInstanceCreation(expr),
      args: expr.argumentList.arguments,
      anchor: expr,
      issues: issues,
      constructorName: constructorName,
    );
  }

  /// #2 idiom auto-substitution — see [kSubstitutableNumberFormatCtors] and the
  /// announced-rewrite contract. Rewrites a
  /// `Text(NumberFormat.<ctor>(<const config>).format(<value>), <carry>)` idiom
  /// on the real `package:intl/` NumberFormat to the equivalent `RestagePrice` /
  /// `RestageFormattedNumber` catalog widget — provably equivalent (the
  /// substitute runs the SAME constructor with the SAME statically-extracted
  /// config) or it does not fire.
  ///
  /// Returns the emitted catalog-widget node on a fully-gated rewrite (adding
  /// the info-level [IssueCode.idiomAutoSubstituted] build notice); `''` (with
  /// a specific deferral) when [expr] IS the idiom but a gate fails; or `null`
  /// when [expr] is not this idiom (the caller continues normal translation).
  String? _tryNumberFormatSubstitution(
    InstanceCreationExpression expr,
    List<Issue> issues,
  ) {
    // G1 — the outer widget is the framework `Text` (default constructor),
    // RESOLVED. Unlike the read-only look-alike gates elsewhere (which tolerate
    // an unresolved reference as a synthetic-test affordance), this gate is the
    // SUBSTITUTION TARGET — the widget being replaced — so it requires a
    // resolved `package:flutter/` `Text`: a customer `Text` look-alike resolves
    // elsewhere and is rejected, and an unresolved `Text` (uncompilable source)
    // is never rewritten. The strong intl gate below would already block a
    // coherent build (intl resolved ⟹ Text resolved), but requiring resolution
    // here makes the no-bypass property explicit rather than inferred.
    if (expr.constructorName.type.name.lexeme != 'Text') return null;
    if (expr.constructorName.name != null) return null;
    final textClass = _classOfInstanceCreation(expr);
    if (textClass == null || !_isFrameworkValueType(textClass)) return null;

    final args = expr.argumentList.arguments;
    final positionals = args.where((a) => a is! NamedExpression).toList();
    if (positionals.isEmpty) return null;
    final first = positionals.first;
    if (first is! MethodInvocation) return null;

    // The strong element gate: the first positional is a real `package:intl/`
    // NumberFormat `.format()` call. `numberFormatAdoptTarget` returns null for
    // a customer look-alike, an unresolved reference, or a non-format call.
    final adoptTarget = numberFormatAdoptTarget(first);
    if (adoptTarget == null) return null;

    // From here the expression is provably `flutter.Text(intl.NumberFormat
    // .<ctor>(...).format(...), …)` — the recognizer OWNS the diagnostic. Any
    // gate failure below is a specific, named deferral, never a fall-through.
    // `defer` anchors every deferral on `expr` for the one adopt-target, so the
    // gates below read as `return defer('<why it did not fire>')`.
    final ctorCall = first.target! as InstanceCreationExpression;
    final ctorName = ctorCall.constructorName.name?.name;
    String defer(String reason) =>
        _deferSubstitution(expr, adoptTarget, issues, reason);

    if (positionals.length > 1) {
      return defer('the Text carries more than one positional argument');
    }

    // G2 — the constructor is auto-substitutable (the strict by-construction
    // subset). Recognised-but-not-substitutable ctors (e.g. simpleCurrency)
    // defer with the adopt-target named.
    if (!kSubstitutableNumberFormatCtors.contains(ctorName)) {
      return defer(
        'the NumberFormat.${ctorName ?? ''} constructor is recognised but not '
        'auto-adopted in this version',
      );
    }

    // G3 — complete static config extraction. Map every NumberFormat config
    // argument to a substitute-widget property; each must be a mappable param
    // AND a compile-time-constant literal. Anything else defers, naming it.
    final config = <String, Expression>{}; // widget prop name -> value expr.
    final ctorArgs = ctorCall.argumentList.arguments;
    switch (ctorName) {
      case 'currency':
        const paramToProp = {
          'locale': 'numberLocale',
          'symbol': 'symbol',
          'decimalDigits': 'decimalDigits',
        };
        for (final a in ctorArgs) {
          if (a is! NamedExpression) {
            return defer(
              'the NumberFormat.currency call has a positional argument this '
              'version cannot extract',
            );
          }
          final param = a.name.label.name;
          final widgetProp = paramToProp[param];
          if (widgetProp == null) {
            return defer(
              'the NumberFormat `$param:` argument has no faithful '
              '$adoptTarget equivalent',
            );
          }
          if (!_isConstFormatConfigLiteral(a.expression)) {
            return defer(
              'the NumberFormat `$param:` argument is not a compile-time '
              'constant; a dynamic format configuration is not adopted',
            );
          }
          config[widgetProp] = a.expression;
        }
      case 'decimalPattern':
        if (ctorArgs.length > 1) {
          return defer(
            'the NumberFormat.decimalPattern call has more arguments than this '
            'version can extract',
          );
        }
        if (ctorArgs.length == 1) {
          final a = ctorArgs.single;
          if (a is NamedExpression || !_isConstFormatConfigLiteral(a)) {
            return defer(
              'the NumberFormat.decimalPattern locale is not a compile-time '
              'constant; a dynamic format configuration is not adopted',
            );
          }
          config['numberLocale'] = a;
        }
      case null: // the unnamed NumberFormat(...) constructor.
        if (ctorArgs.isNotEmpty) {
          return defer(
            'the unnamed NumberFormat(...) constructor carries a pattern / '
            'locale this version cannot extract',
          );
        }
      default:
        // Unreachable — G2 admitted only the cases above; defensive defer.
        return defer('the NumberFormat.$ctorName constructor is not adopted');
    }

    // G4 — the `.format(<value>)` call takes exactly one positional value.
    final fmtArgs = first.argumentList.arguments;
    if (fmtArgs.length != 1 || fmtArgs.single is NamedExpression) {
      return defer(
        'the .format(...) call does not take exactly one positional value',
      );
    }
    final valueExpr = fmtArgs.single;

    // G4b — the value must render identically through the substitute's
    // `double` value slot. `NumberFormat.format` accepts `num`, so the original
    // idiom formats an `int` fine; the catalog slot decodes with
    // `source.v<double>`, which yields null for a runtime `int` (an empty
    // render). A numeric literal is double-coerced at emit and is safe; a
    // non-literal must be statically `double` — an `int` / `num` / dynamic /
    // unresolved value could carry an `int` at runtime and DEFERS.
    if (!_isDoubleCompatibleFormatValue(valueExpr)) {
      return defer(
        'the formatted value is not a numeric literal or a `double`-typed '
        'value; an int / num value can hold an integer at runtime, which the '
        'catalog widget would drop',
      );
    }

    // G5 — carry-all-or-defer: every Text named argument is in the shared
    // carry-set. Any other property (semanticsLabel, the widget-level
    // overflow / softWrap / locale, …) blocks the rewrite — a styled Text is
    // never silently reduced.
    final carried = <NamedExpression>[];
    for (final a in args.whereType<NamedExpression>()) {
      final name = a.name.label.name;
      if (name == 'key') continue;
      if (!kRestageFormattedTextProps.contains(name)) {
        return defer(
          'the Text `$name:` property is not reproduced by $adoptTarget (the '
          'rewrite never silently drops a property)',
        );
      }
      carried.add(a);
    }

    // All structural gates pass — resolve the substitute entry and lower every
    // value into a scratch issue list. Emit the node ONLY if every part lowers
    // cleanly; any lowering error defers the whole rewrite (never a partial /
    // wrong node), surfacing the underlying diagnostic.
    final candidates = findWidgetsByName(catalog, adoptTarget);
    if (candidates.isEmpty) {
      return defer('$adoptTarget is not present in the active catalog');
    }
    final entry = candidates.first;

    final scratch = <Issue>[];
    final emitted = <String>[];

    String? lowerSlot(String propName, Expression value) {
      final p = entry.properties.where((pr) => pr.name == propName).firstOrNull;
      if (p == null) return null; // caller defers — missing widget property.
      _validateThemeValueForSlot(value, p.type, scratch);
      return _translateSlotValue(value, p.type, scratch, property: p);
    }

    final loweredValue = lowerSlot('value', valueExpr);
    if (loweredValue == null) {
      return defer('$adoptTarget has no `value` property');
    }
    emitted.add('value: $loweredValue');

    for (final cfg in config.entries) {
      final lowered = lowerSlot(cfg.key, cfg.value);
      if (lowered == null) {
        return defer('$adoptTarget has no `${cfg.key}` property');
      }
      emitted.add('${cfg.key}: $lowered');
    }

    for (final a in carried) {
      final name = a.name.label.name;
      // `style` decomposes through the entry's native recipe (TextStyle ->
      // flat props), exactly as a hand-authored substitute would.
      final decomposed = _tryDecompose(entry, name, a.expression, scratch);
      if (decomposed != null) {
        emitted.addAll(decomposed);
        continue;
      }
      final lowered = lowerSlot(name, a.expression);
      if (lowered == null) {
        return defer('$adoptTarget has no `$name` property');
      }
      emitted.add('$name: $lowered');
    }

    if (scratch.isNotEmpty) {
      // A value / config / carried property could not lower — defer the whole
      // rewrite and surface the underlying diagnostic rather than emit a
      // partial node.
      issues.addAll(scratch);
      return '';
    }

    // The announced-rewrite build notice (normative): the rewrite is automatic
    // but never silent at build time — the author is told what was rewritten.
    issues.add(
      Issue(
        code: IssueCode.idiomAutoSubstituted,
        message: 'Auto-adopted the `$adoptTarget` catalog widget for a '
            'Text(NumberFormat.${ctorName ?? ''}(...).format(...)) number '
            'formatting idiom — the substitute runs the same formatting, so '
            'the rendered output is identical. The emitted blob references '
            '$adoptTarget, not Text.',
        location: _locationOf(expr),
      ),
    );

    return '${entry.name}(${emitted.join(', ')})';
  }

  /// Emits a specific deferral [Issue] for a recognised-but-not-substitutable
  /// number-formatting idiom and returns `''` (the deferral). The message names
  /// why the rewrite did not fire and points at the catalog widget to adopt.
  String _deferSubstitution(
    Expression anchor,
    String adoptTarget,
    List<Issue> issues,
    String reason,
  ) {
    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message: 'Could not auto-adopt the `$adoptTarget` catalog widget for '
            'this number-formatting idiom because $reason. '
            '${numberFormatDeferMessage(adoptTarget)}',
        location: _locationOf(anchor),
      ),
    );
    return '';
  }

  /// Whether [e] is a compile-time-constant literal acceptable as a static
  /// `NumberFormat` configuration argument: a non-interpolated string literal
  /// (locale / symbol) or an integer literal (decimalDigits). Conservative by
  /// design — a const variable or any computed expression defers, so the
  /// extracted configuration is always a literal the differential matrix can
  /// enumerate.
  bool _isConstFormatConfigLiteral(Expression e) =>
      e is SimpleStringLiteral || e is IntegerLiteral;

  String? _tryTextRichInstanceCreation(
    InstanceCreationExpression expr,
    List<Issue> issues,
  ) {
    final typeName = _instanceCreationTypeName(expr);
    final constructorName = _instanceCreationMemberName(expr);
    if (typeName != 'Text' || constructorName != 'rich') return null;

    final cls = _classOfInstanceCreation(expr);
    if (!_flutterOrUnresolved(cls)) {
      _addNonFlutterTextRichIssue(expr, issues);
      return '';
    }

    return _textRich(
      args: expr.argumentList.arguments,
      anchor: expr,
      flutterType: _flutterTypeOfClassOrNull(cls, constructorName: 'rich'),
      issues: issues,
    );
  }

  String? _tryTextRichMethodInvocation(
    MethodInvocation expr,
    List<Issue> issues,
  ) {
    final target = expr.target;
    if (target is! SimpleIdentifier ||
        target.name != 'Text' ||
        expr.methodName.name != 'rich') {
      return null;
    }

    final cls = _classOfMethodInvocation(expr) ??
        (target.element is ClassElement
            ? target.element! as ClassElement
            : null);
    final resolvedSomething =
        target.element != null || expr.methodName.element != null;
    if (cls == null && resolvedSomething) {
      _addNonFlutterTextRichIssue(expr, issues);
      return '';
    }
    if (!_flutterOrUnresolved(cls)) {
      _addNonFlutterTextRichIssue(expr, issues);
      return '';
    }

    return _textRich(
      args: expr.argumentList.arguments,
      anchor: expr,
      flutterType: _flutterTypeOfClassOrNull(cls, constructorName: 'rich'),
      issues: issues,
    );
  }

  String _textRich({
    required NodeList<Expression> args,
    required Expression anchor,
    required String? flutterType,
    required List<Issue> issues,
  }) {
    final entry = _textRichEntry(flutterType);
    if (entry == null) {
      issues.add(
        Issue(
          code: IssueCode.unknownWidget,
          message: "Widget 'Text.rich' is not a known catalog widget. Add a "
              'catalog entry with a PropertyType.inlineSpan textSpan slot '
              'before lowering Text.rich.',
          location: _locationOf(anchor),
        ),
      );
      return '';
    }

    final textSpanProp = entry.properties.firstWhereOrNull(
      (p) => p.name == 'textSpan' && p.type == PropertyType.inlineSpan,
    );
    if (textSpanProp == null) {
      issues.add(
        Issue(
          code: IssueCode.unknownProperty,
          message: "Catalog widget '${entry.name}' must declare a "
              "'textSpan' PropertyType.inlineSpan slot for Text.rich.",
          location: _locationOf(anchor),
        ),
      );
      return '';
    }

    final positionals = args.where((a) => a is! NamedExpression).toList();
    if (positionals.length != 1) {
      issues.add(
        Issue(
          code: IssueCode.unknownProperty,
          message: 'Text.rich requires exactly one positional TextSpan tree.',
          location: _locationOf(anchor),
        ),
      );
      return '';
    }

    final span = _textSpanMap(positionals.single, issues, depth: 0);
    if (span == null) return '';

    // This mirrors the catalog-widget named-arg loop, but DELIBERATELY
    // fails the whole emission (`return ''`) on the first unknown / unlowerable
    // property rather than skipping it like the catalog-widget path does — a
    // Text.rich must never emit a blob that dropped an authored property. Keep
    // this fail-fast policy if the loops are ever unified.
    final emitted = <String>['${textSpanProp.name}: $span'];
    for (final arg in args.whereType<NamedExpression>()) {
      final name = arg.name.label.name;
      if (name == 'key') continue;

      final before = issues.length;
      final decomposed = _tryDecompose(entry, name, arg.expression, issues);
      if (issues.length > before) return '';
      if (decomposed != null) {
        emitted.addAll(decomposed);
        continue;
      }

      final prop = entry.properties.firstWhereOrNull((p) => p.name == name);
      if (prop == null) {
        issues.add(
          Issue(
            code: IssueCode.unknownProperty,
            message: "Property '$name' is not declared on '${entry.name}'. "
                'Catalog properties: '
                '${entry.properties.map((p) => p.name).join(", ")}.',
            location: _locationOf(arg),
          ),
        );
        return '';
      }
      _validateThemeValueForSlot(arg.expression, prop.type, issues);
      final value = _translateSlotValue(
        arg.expression,
        prop.type,
        issues,
        property: prop,
      );
      if (value.isEmpty && issues.length > before) return '';
      emitted.add('$name: $value');
    }

    return '${entry.name}(${emitted.join(', ')})';
  }

  WidgetEntry? _textRichEntry(String? flutterType) {
    if (flutterType != null) {
      final resolved =
          catalog.widgets.firstWhereOrNull((w) => w.flutterType == flutterType);
      if (resolved != null) return resolved;
    }
    return catalog.widgets.firstWhereOrNull((w) => w.name == 'Text.rich') ??
        catalog.widgets
            .firstWhereOrNull((w) => w.flutterType.endsWith('#Text.rich'));
  }

  String? _textSpanMap(
    Expression expr,
    List<Issue> issues, {
    required int depth,
  }) {
    final stripped = _stripParens(expr);
    if (depth > kMaxInlineSpanDepth) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'TextSpan tree exceeds kMaxInlineSpanDepth '
              '($kMaxInlineSpanDepth). Split the rich text into shallower '
              'Text.rich nodes; codegen never emits a tree that relies on '
              'runtime depth truncation.',
          location: _locationOf(stripped),
        ),
      );
      return null;
    }
    if (stripped is ConditionalExpression) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'Whole TextSpan conditionals are not supported by this '
              'transpiler increment. Put the conditional on a carried span '
              'value, such as text: condition ? a : b.',
          location: _locationOf(stripped),
        ),
      );
      return null;
    }

    final spanArgs = _textSpanArguments(stripped, issues);
    if (spanArgs == null) return null;

    final parts = <String>[];
    for (final positional in spanArgs.where((a) => a is! NamedExpression)) {
      issues.add(
        Issue(
          code: IssueCode.unknownProperty,
          message: 'TextSpan positional arguments are not carried by the '
              'inlineSpan emitter. Use named text:, style:, and children: '
              'arguments only.',
          location: _locationOf(positional),
        ),
      );
      return null;
    }

    for (final arg in spanArgs.whereType<NamedExpression>()) {
      final name = arg.name.label.name;
      if (!_kCarriedTextSpanProps.contains(name)) {
        _addTextSpanUncarriedPropIssue(name, arg, issues);
        return null;
      }

      switch (name) {
        case 'text':
          if (arg.expression is NullLiteral) continue;
          final before = issues.length;
          final value = _translateSlotValue(
            arg.expression,
            PropertyType.string,
            issues,
          );
          if (value.isEmpty && issues.length > before) return null;
          parts.add('text: $value');
        case 'style':
          if (arg.expression is NullLiteral) continue;
          final style = _textSpanStyleMap(arg.expression, issues);
          if (style == null) return null;
          parts.add('style: $style');
        case 'children':
          if (arg.expression is NullLiteral) continue;
          final children = _textSpanChildren(arg.expression, issues, depth);
          if (children == null) return null;
          parts.add('children: $children');
      }
    }

    return '{ ${parts.join(', ')} }';
  }

  NodeList<Expression>? _textSpanArguments(
    Expression expr,
    List<Issue> issues,
  ) {
    if (expr is InstanceCreationExpression) {
      if (_instanceCreationTypeName(expr) != 'TextSpan' ||
          _instanceCreationMemberName(expr) != null) {
        _addTextSpanExpectedIssue(expr, issues);
        return null;
      }
      final cls = _classOfInstanceCreation(expr);
      if (!_flutterOrUnresolved(cls)) {
        _addNonFlutterTextSpanIssue(expr, issues);
        return null;
      }
      return expr.argumentList.arguments;
    }

    if (expr is MethodInvocation && expr.target == null) {
      if (expr.methodName.name != 'TextSpan') {
        _addTextSpanExpectedIssue(expr, issues);
        return null;
      }
      final cls = _classOfMethodInvocation(expr);
      if (cls == null && expr.methodName.element != null) {
        _addNonFlutterTextSpanIssue(expr, issues);
        return null;
      }
      if (!_flutterOrUnresolved(cls)) {
        _addNonFlutterTextSpanIssue(expr, issues);
        return null;
      }
      return expr.argumentList.arguments;
    }

    _addTextSpanExpectedIssue(expr, issues);
    return null;
  }

  String? _textSpanStyleMap(Expression expr, List<Issue> issues) {
    final textEntry = _textStyleCatalogEntry;
    if (textEntry == null) {
      issues.add(
        Issue(
          code: IssueCode.unknownProperty,
          message: "TextSpan.style requires the catalog's Text(style: "
              'TextStyle(...)) native decomposition metadata so nested style '
              'fields use the same encoding as flat Text styles.',
          location: _locationOf(expr),
        ),
      );
      return null;
    }

    final before = issues.length;
    final decomposed = _tryDecompose(textEntry, 'style', expr, issues);
    if (issues.length > before) return null;
    if (decomposed == null) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'TextSpan.style must be a TextStyle(...) value whose fields '
              'can be decomposed by the Text style recipe.',
          location: _locationOf(expr),
        ),
      );
      return null;
    }
    return '{ ${decomposed.join(', ')} }';
  }

  String? _textSpanChildren(
    Expression expr,
    List<Issue> issues,
    int depth,
  ) {
    final stripped = _stripParens(expr);
    if (stripped is! ListLiteral) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'TextSpan.children must be a static list of TextSpan nodes.',
          location: _locationOf(stripped),
        ),
      );
      return null;
    }

    final children = <String>[];
    for (final element in stripped.elements) {
      if (element is! Expression) {
        issues.add(
          Issue(
            code: IssueCode.unsupportedCollectionFlow,
            message: 'TextSpan.children does not support spread, '
                'collection-if, or collection-for. Use a static list of '
                'TextSpan nodes.',
            location: _locationOf(stripped),
          ),
        );
        return null;
      }
      final child = _textSpanMap(element, issues, depth: depth + 1);
      if (child == null) return null;
      children.add(child);
    }
    return '[${children.join(', ')}]';
  }

  void _addTextSpanUncarriedPropIssue(
    String name,
    NamedExpression arg,
    List<Issue> issues,
  ) {
    final knownDeferred = _kDeferredTextSpanProps.contains(name)
        ? ' This property is intentionally deferred in this increment.'
        : '';
    issues.add(
      Issue(
        code: IssueCode.unknownProperty,
        message: 'Text.rich inline-span emission carries only TextSpan '
            'text, style, and children. TextSpan.$name would be dropped, so '
            'the whole Text.rich is deferred.$knownDeferred',
        location: _locationOf(arg),
      ),
    );
  }

  void _addTextSpanExpectedIssue(Expression expr, List<Issue> issues) {
    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message: 'Text.rich requires its positional argument to be a '
            'TextSpan(...) tree.',
        location: _locationOf(expr),
      ),
    );
  }

  void _addNonFlutterTextRichIssue(Expression expr, List<Issue> issues) {
    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message: "'${expr.toSource()}' does not resolve to package:flutter's "
            'Text.rich. A customer class named Text is not emitted as the '
            'framework rich-text widget.',
        location: _locationOf(expr),
      ),
    );
  }

  void _addNonFlutterTextSpanIssue(Expression expr, List<Issue> issues) {
    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message: "'${expr.toSource()}' does not resolve to package:flutter's "
            'TextSpan. A customer class named TextSpan is not emitted as an '
            'inline-span map.',
        location: _locationOf(expr),
      ),
    );
  }

  bool _flutterOrUnresolved(Element? element) =>
      element == null || libraryIsFlutter(element);

  String? _flutterTypeOfClassOrNull(
    ClassElement? cls, {
    String? constructorName,
  }) =>
      cls == null
          ? null
          : _flutterTypeOfClass(cls, constructorName: constructorName);

  /// Whether the `.format(<value>)` argument is safe to lower into the
  /// substitute's `double`-typed value slot. A numeric literal (including a
  /// negated one) is double-coerced at emit and is always safe. A non-literal
  /// must be statically `double`: the substitute decodes its value slot with
  /// `source.v<double>`, which yields null for a runtime `int`, so an `int` /
  /// `num` / dynamic / unresolved value could render the empty string through
  /// the catalog widget where the original `NumberFormat.format(num)` would
  /// format it — a wrong output the gate refuses.
  bool _isDoubleCompatibleFormatValue(Expression valueExpr) {
    var e = valueExpr;
    if (e is PrefixExpression && e.operator.lexeme == '-') {
      e = e.operand;
    }
    if (e is IntegerLiteral || e is DoubleLiteral) return true;
    final type = valueExpr.staticType;
    return type != null && type.isDartCoreDouble;
  }

  String _methodInvocation(MethodInvocation expr, List<Issue> issues) {
    final target = expr.target;
    final method = expr.methodName.name;
    final args = expr.argumentList.arguments;

    // Named-intermediate inlining: a call whose method element the classifier
    // captured for THIS definition body is inlined to the helper's body —
    // element-resolved identity, never name (a customer / different-library
    // look-alike resolves to a different element, is not captured, and falls
    // through). Mirrors the classifier's `_resolveInlinableHelper`. Fires for
    // ANY target — a bare own/top-level call (`_helper()`) or a qualified
    // same-library static (`Helpers.row()`) — and is placed BEFORE the static
    // value-substitution gate below so a captured static inlines rather than
    // deferring as a widget construction.
    final helper = _walk.inlined.helpers[expr.methodName.element];
    if (helper != null) {
      return _inlineHelperBody(helper, expr, issues);
    }

    final textRich = _tryTextRichMethodInvocation(expr, issues);
    if (textRich != null) return textRich;

    // Number/currency formatting: a `NumberFormat.<ctor>(...).format(<value>)`
    // call on the real intl `NumberFormat` defers with a diagnostic that NAMES
    // the catalog widget to adopt (RestagePrice / RestageFormattedNumber).
    // Element-gated on `package:intl/` so a customer class named NumberFormat
    // is never named an intl adopt-target. The #2 auto-substitution recognizer
    // inserts ahead of this defer, for the statically-extractable shapes.
    final formatAdoptTarget = numberFormatAdoptTarget(expr);
    if (formatAdoptTarget != null) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: numberFormatDeferMessage(formatAdoptTarget),
          location: _locationOf(expr),
        ),
      );
      return '';
    }

    // Value-substitution gate — the static-call counterpart of
    // _instanceCreation's (see there for the rationale). A `Foo.method(...)`
    // whose target class resolves to a non-framework library is a customer
    // static-method look-alike (a real framework value construction parses as
    // an InstanceCreationExpression, handled there); route it to widget
    // construction (defer). A `target == null` bare call and an unresolved
    // target keep the name-based recognition (the synthetic-test affordance).
    if (target is SimpleIdentifier && !_frameworkOrUnresolved(target.element)) {
      return _catalogWidgetConstruction(
        widgetName: target.name,
        flutterType: _flutterTypeOfMethodInvocation(expr),
        widgetClass: _classOfMethodInvocation(expr),
        args: args,
        anchor: expr,
        issues: issues,
      );
    }

    // Value-type routing — the registered recipe table (Color / Offset) then
    // the shared hand-authored table ([_tryValueType]), keyed on a
    // `(type, variant)` descriptor (the same table the constructor path uses).
    // The static-call shape maps a bare call to `(method, null)` and a
    // `Class.method(...)` to `(Class, method)`. `TextDecoration.combine` is
    // reachable only through this static-call shape. A non-identifier target
    // (e.g. `a.b.method()`) can't be a value type and falls to the tail.
    if (target == null || target is SimpleIdentifier) {
      final type = target is SimpleIdentifier ? target.name : method;
      final variant = target is SimpleIdentifier ? method : null;
      final valueType = _tryValueOrRecipe(
        type,
        variant,
        args,
        issues,
        _locationOf(expr),
        fromConstructor: false,
      );
      if (valueType != null) return valueType;
    }

    // LinearBorder / StarBorder factory statics — the static-call counterpart
    // of the constructor path's ShapeBorder set (resolved shape borders parse
    // as InstanceCreationExpression; only these factory statics reach here).
    if (target is SimpleIdentifier &&
        (target.name == 'LinearBorder' || target.name == 'StarBorder')) {
      final shapeBorder = _structured.shapeBorder(
        prefix: target.name,
        typeName: method,
        constructorName: null,
        args: args,
        issues: issues,
        loc: _locationOf(expr),
      );
      if (shapeBorder != null) return shapeBorder;
    }

    // `Border.<factory>` reaching here is an unsupported Border factory —
    // `Border.all` and the default `Border(...)` are handled by the table.
    if (target is SimpleIdentifier && target.name == 'Border') {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'Unsupported Border factory: Border.$method. '
              'Supported: all, default Border(top:, right:, bottom:, left:).',
          location: _locationOf(expr),
        ),
      );
      return '[]';
    }

    // A `Color.<factory>` reaching here is an unsupported Color factory — the
    // supported forms (`Color(0xAARRGGBB)` / `Color.fromARGB` / `Color.fromRGBO`)
    // are handled by the recipe dispatch above, which always wins.
    if (target is SimpleIdentifier && target.name == 'Color') {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'Unsupported Color factory: Color.$method. '
              'Supported: Color(0xAARRGGBB), Color.fromARGB, Color.fromRGBO.',
          location: _locationOf(expr),
        ),
      );
      return '';
    }

    // Helper-call recognition: a free-function call with no target whose name
    // and declaring library are both registered in the helper table. This runs
    // BEFORE the catalog widget construction path so that recognized helpers
    // (paywallEvent / paywallPurchase / paywallPriceFor) are never accidentally
    // routed as widget lookups.
    if (target == null) {
      final element = expr.methodName.element;
      HelperDefinition? helper;
      if (element != null) {
        // Analyzer resolved the call to a library. Match strictly by
        // (name, libraryUri) — do NOT fall back to name-only here, because
        // a host-app function that happens to share a name with an SDK helper
        // but resolves to a different library must not be mis-translated.
        final libraryUri = element.library?.identifier ?? '';
        helper = helpers.find(method, libraryUri);
      } else {
        // Analyzer could not resolve the element (e.g. Flutter SDK unavailable
        // in the build_runner resolver context). Fall back to name-only as a
        // best-effort — authors who name a local function identically to an
        // SDK helper may see a false-positive, but that is the lesser evil.
        helper = helpers.findByNameOnly(method);
      }
      if (helper != null) {
        if (helper.name == 'onboardingEvent') {
          final helperArgs = _translateOnboardingEventArgs(expr, issues);
          if (helperArgs == null) return '';
          return _safeHelperTranslate(expr, helper, helperArgs, issues);
        }
        // A value-reference (`string`-category) helper interpolates its
        // argument into a reference PATH where a `switch` cannot syntactically
        // live, so a conditional argument is DISTRIBUTED over the call (the
        // switch-of-references the inverted idiom produces) rather than emitted
        // inside the path (which fails to parse — the malformed-DSL
        // bug). Event (`voidCallback`) helpers take the pass-through below: the
        // switch sits in a value position there and is already valid.
        if (helper.returnCategory == HelperReturnCategory.string) {
          final distributed =
              _tryDistributeConditionalValueHelper(expr, helper, issues);
          if (distributed != null) return distributed;
        }
        final positional = <String>[];
        final named = <String, String>{};
        for (final a in expr.argumentList.arguments) {
          if (a is NamedExpression) {
            named[a.name.label.name] =
                _translateHelperArgument(a.expression, issues);
          } else {
            positional.add(_translateHelperArgument(a, issues));
          }
        }
        return _safeHelperTranslate(
          expr,
          helper,
          HelperCallArgs(positional: positional, named: named),
          issues,
        );
      }
    }

    // Bare type call: `Foo(...)` with no target — routes to catalog
    // widget construction. The analyzer parses `Foo()` as a
    // MethodInvocation; if `Foo` resolved to a constructor element, we
    // can identify the class behind it for the canonical-type lookup.
    if (target == null) {
      return _catalogWidgetConstruction(
        widgetName: method,
        flutterType: _flutterTypeOfMethodInvocation(expr),
        widgetClass: _classOfMethodInvocation(expr),
        args: expr.argumentList.arguments,
        anchor: expr,
        issues: issues,
      );
    }

    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message: 'Unsupported method invocation: ${expr.toSource()}.',
        location: _locationOf(expr),
      ),
    );
    return '';
  }

  /// Recognises a chained theme read and returns the contract-path
  /// segments in source order. Accepts two source shapes:
  ///
  /// - `Theme.of(<ident>).<x>(.<y>)` → segments are the chained property
  ///   names, mapping to the contract path `colorScheme.*`,
  ///   `iconTheme.{color, size}`, etc.
  /// - `DefaultTextStyle.of(<ident>).style.<x>` → normalises the leading
  ///   `style` segment to `defaultTextStyle` to match the contract path
  ///   the SDK publishes (`data.theme.defaultTextStyle.<x>`).
  ///
  /// Returns `null` for any other shape, so the caller falls through to
  /// the generic dispatch. Binding-aware: the chain may pass through a bound
  /// `final` theme-local captured in the active [InlinedDefinitions]
  /// (`scheme.primary` where `final scheme = Theme.of(c).colorScheme;` is in
  /// scope), resolved element-keyed against `_walk.inlined.localBindings`.
  /// Delegates to the canonical [themeReadSegments] walk so the classifier
  /// recognizer, this lowerer, and the slot validator never drift.
  List<String>? _recognizeThemeRead(Expression expr) =>
      themeReadSegments(expr, bindings: _walk.inlined.localBindings);

  /// Lowers a recognised theme read [segments] to its `data.theme.<...>`
  /// reference. Validates the joined path against the published
  /// `data.theme.*` contract — an out-of-contract read would resolve to
  /// null at render time, so it surfaces as an authoring error instead.
  String _themeRead(
    List<String> segments,
    String location,
    List<Issue> issues,
  ) {
    final path = segments.join('.');
    if (!kThemeContractPaths.contains(path)) {
      issues.add(
        Issue(
          code: IssueCode.themeReadOutOfContract,
          message: "The theme read '$path' is not part of the published "
              "'data.theme.*' contract. Supported reads cover the "
              "'colorScheme' colour roles, 'iconTheme.{color, size}', "
              "and 'defaultTextStyle.{color, fontSize, fontWeight}'.",
          location: location,
        ),
      );
      return '';
    }
    return 'data.theme.$path';
  }

  String _translateHelperArgument(Expression expr, List<Issue> issues) {
    final descriptorId = _constDescriptorId(expr);
    if (descriptorId != null) return _stringLiteral(descriptorId);
    return _translate(expr, issues);
  }

  /// Runs [helper]'s pure translation under the structured-diagnostic guard:
  /// a throw from its per-call validation (an `ArgumentError` on a bad arg
  /// shape, a `StateError`, …) becomes an `unrecognizedMethodCall` issue
  /// naming the helper rather than crashing the build.
  String _safeHelperTranslate(
    MethodInvocation expr,
    HelperDefinition helper,
    HelperCallArgs helperArgs,
    List<Issue> issues,
  ) {
    try {
      return helper.translate(helperArgs);
    } on Object catch (e) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'Failed to translate ${helper.name}: $e',
          location: _locationOf(expr),
        ),
      );
      return '';
    }
  }

  /// Strips any parenthesis wrapping from [expr].
  Expression _stripParens(Expression expr) {
    var current = expr;
    while (current is ParenthesizedExpression) {
      current = current.expression;
    }
    return current;
  }

  /// Distributes a single conditional argument over a value-reference
  /// (`string`-category) helper call, lowering `helper(slot: cond ? a : b)` to
  /// `switch cond { true: helper(slot: a), false: helper(slot: b) }` — the
  /// switch-of-references the inverted idiom produces, which is valid DSL where
  /// the in-path form is not. Sound because these helpers are pure string
  /// translators (`f(cond?a:b) == cond?f(a):f(b)`). Returns null when no
  /// argument is a conditional (the caller takes the normal pass-through);
  /// emits a clean diagnostic and returns `''` when more than one argument is
  /// a conditional (ambiguous to distribute), never malformed output.
  String? _tryDistributeConditionalValueHelper(
    MethodInvocation expr,
    HelperDefinition helper,
    List<Issue> issues,
  ) {
    final args = expr.argumentList.arguments;
    int? condIndex;
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      final value = a is NamedExpression ? a.expression : a;
      if (_stripParens(value) is ConditionalExpression) {
        if (condIndex != null) {
          issues.add(
            Issue(
              code: IssueCode.unrecognizedMethodCall,
              message: "'${helper.name}' has more than one conditional "
                  'argument; this transpiler increment distributes only a '
                  'single conditional argument over a value helper. Use one '
                  'conditional argument, or the inverted form (a conditional '
                  'of helper calls).',
              location: _locationOf(expr),
            ),
          );
          return '';
        }
        condIndex = i;
      }
    }
    if (condIndex == null) return null;
    final condArg = args[condIndex];
    final slotExpr = condArg is NamedExpression ? condArg.expression : condArg;
    return _distributeValueHelper(expr, helper, condIndex, slotExpr, issues);
  }

  /// Recursively lowers [helper] applied with the argument at [condIndex] set
  /// to [slotExpr]: while [slotExpr] is a conditional, emit a `switch` over its
  /// condition whose branches re-apply the helper (so a nested two-axis
  /// conditional becomes a nested switch); the base case builds the argument
  /// maps — substituting [slotExpr] at [condIndex] — and translates the call.
  String _distributeValueHelper(
    MethodInvocation expr,
    HelperDefinition helper,
    int condIndex,
    Expression slotExpr,
    List<Issue> issues,
  ) {
    final stripped = _stripParens(slotExpr);
    if (stripped is ConditionalExpression) {
      return _conditionalSwitch(
        stripped,
        issues,
        (branch) =>
            _distributeValueHelper(expr, helper, condIndex, branch, issues),
      );
    }
    final positional = <String>[];
    final named = <String, String>{};
    final args = expr.argumentList.arguments;
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      final valueExpr =
          i == condIndex ? stripped : (a is NamedExpression ? a.expression : a);
      final translated = _translateHelperArgument(valueExpr, issues);
      if (a is NamedExpression) {
        named[a.name.label.name] = translated;
      } else {
        positional.add(translated);
      }
    }
    return _safeHelperTranslate(
      expr,
      helper,
      HelperCallArgs(positional: positional, named: named),
      issues,
    );
  }

  HelperCallArgs? _translateOnboardingEventArgs(
    MethodInvocation expr,
    List<Issue> issues,
  ) {
    final positional = <String>[];
    final named = <String, String>{};
    for (final arg in expr.argumentList.arguments) {
      if (arg is NamedExpression) {
        named[arg.name.label.name] =
            _translateHelperArgument(arg.expression, issues);
        continue;
      }
      if (positional.isEmpty) {
        final descriptorId = _onboardingEventDescriptorId(arg);
        if (descriptorId == null) {
          issues.add(
            Issue(
              code: IssueCode.unrecognizedMethodCall,
              message: 'Expected a static OnboardingEvent field reference; '
                  'got ${arg.toSource()}.',
              location: _locationOf(arg),
            ),
          );
          return null;
        }
        positional.add(_stringLiteral(descriptorId));
        continue;
      }
      // A scalar event value is wrapped under the reserved `value` key so the
      // event always carries a string-keyed args map: a bare scalar would be
      // coerced to an empty map at the runtime boundary (and a flow
      // `.capture()` reads the reserved `value` key). A map literal already
      // carries named fields, so it is emitted as-is.
      final translated = _translateHelperArgument(arg, issues);
      final isMapLiteral = arg is SetOrMapLiteral && arg.isMap;
      positional.add(
        isMapLiteral ? translated : '{ $kCapturedEventValueKey: $translated }',
      );
    }
    return HelperCallArgs(positional: positional, named: named);
  }

  String? _onboardingEventDescriptorId(Expression expr) {
    final field = _staticConstOnboardingEventField(expr);
    return field?.computeConstantValue()?.getField('id')?.toStringValue();
  }

  FieldElement? _staticConstOnboardingEventField(Expression expr) {
    Element? element;
    if (expr is SimpleIdentifier) {
      element = expr.element;
    } else if (expr is PrefixedIdentifier) {
      element = expr.identifier.element;
    } else if (expr is PropertyAccess) {
      element = expr.propertyName.element;
    }
    if (element is PropertyAccessorElement) {
      element = element.variable;
    }
    if (element is! FieldElement || !element.isStatic || !element.isConst) {
      return null;
    }
    final type = element.type;
    if (type is! InterfaceType ||
        type.element.name != 'OnboardingEvent' ||
        !libraryUriMatchesOrigin(
          type.element.library.identifier,
          _kRestageFlutterSdkLibraryOrigin,
        )) {
      return null;
    }
    return element;
  }

  String? _constDescriptorId(Expression expr) {
    Element? element;
    if (expr is SimpleIdentifier) {
      element = expr.element;
    } else if (expr is PrefixedIdentifier) {
      element = expr.identifier.element;
    } else if (expr is PropertyAccess) {
      element = expr.propertyName.element;
    }
    if (element is PropertyAccessorElement) {
      element = element.variable;
    }
    if (element is! FieldElement || !element.isConst) return null;
    return element.computeConstantValue()?.getField('id')?.toStringValue();
  }

  /// Implied-default property emissions for a catalog widget's named
  /// constructor that this transpiler increment lowers faithfully — the
  /// `Positioned.fill` form, whose four edges default to zero. Returns the
  /// per-edge default literals (already double-coerced for the `length`
  /// slots); the caller emits each one the author did not override. Returns
  /// `null` for any other named constructor, which the caller defers loud
  /// rather than silently emit a degraded base widget.
  ///
  /// `SizedBox.expand`/`.shrink`, `Positioned.directional`/`.fromRect`, and
  /// other named constructors are deliberately NOT lowered here: `.expand`'s
  /// implied `infinity` is a non-finite double (a separate loud catch), and
  /// the rest carry no real-paywall demand — they defer loud and can graduate
  /// to a faithful lowering later if demand appears.
  Map<String, String>? _namedConstructorImpliedDefaults(
    String widgetName,
    String constructorName,
  ) {
    if (widgetName == 'Positioned' && constructorName == 'fill') {
      return const {
        'left': '0.0',
        'top': '0.0',
        'right': '0.0',
        'bottom': '0.0',
      };
    }
    return null;
  }

  RecognisedModalSheet? _findSingleRootModalSheetTrigger(
    Expression expr,
    List<Issue> issues,
  ) {
    final scanner = _RootModalSheetTriggerScanner();
    expr.accept(scanner);
    if (scanner.resultDrop != null) {
      issues.add(_modalSheetUnsupportedIssue(scanner.resultDrop!, expr));
      return null;
    }
    if (scanner.recognised.isEmpty) return null;
    if (scanner.recognised.length > 1) {
      issues.add(
        _modalSheetUnsupportedIssue(
          'only one modal sheet trigger can be lowered in a paywall root',
          expr,
        ),
      );
      return null;
    }
    return scanner.recognised.single;
  }

  List<RecognisedNavigation> _findRootNavigationTriggers(
    Expression expr,
    List<Issue> issues, {
    required Element? buildContextParameter,
  }) {
    final scanner = _RootNavigationTriggerScanner(
      buildContextParameter: buildContextParameter,
    );
    expr.accept(scanner);
    if (scanner.resultDrop != null) {
      issues.add(_navigationUnsupportedIssue(scanner.resultDrop!, expr));
      return const [];
    }
    return scanner.recognised;
  }

  _NavigationEmitContext? _createNavigationContext({
    required String entryId,
    required Expression expr,
    required List<RecognisedNavigation> triggers,
    required List<Issue> issues,
    required Element? buildContextParameter,
  }) {
    final existingEventNames = _paywallEventNames(expr).toSet();
    if (triggers.isNotEmpty && !existingEventNames.contains('skip')) {
      issues.add(
        _navigationUnsupportedIssue(
          'a screen-navigation paywall lowers to a flow that needs a '
          'non-purchase dismiss to terminate; add a skip affordance '
          "(paywallEvent('skip')); purchase-based termination lands in a "
          'later increment',
          expr,
        ),
      );
      return null;
    }

    final entries = <_NavigationTriggerEntry>[];
    for (var i = 0; i < triggers.length; i++) {
      final event = _mintNavigationEvent(i, existingEventNames);
      existingEventNames.add(event);
      entries.add(_NavigationTriggerEntry(trigger: triggers[i], event: event));
    }
    return _NavigationEmitContext(
      entryId: entryId,
      entries: entries,
      buildContextParameter: buildContextParameter,
    );
  }

  Iterable<String> _paywallEventNames(Expression expr) {
    final scanner = _WidgetEventNameScanner(helpers);
    expr.accept(scanner);
    return scanner.names;
  }

  String _mintNavigationEvent(int index, Set<String> existingEventNames) {
    var candidateIndex = index;
    while (true) {
      final candidate = 'restageNav$candidateIndex';
      if (!existingEventNames.contains(candidate)) return candidate;
      candidateIndex++;
    }
  }

  bool _usesBuildContextParameter(SimpleIdentifier identifier) {
    final buildContextParameter = _currentNavigation?.buildContextParameter;
    final element = identifier.element;
    if (buildContextParameter == null || element == null) return true;
    return element == buildContextParameter;
  }

  String _mintModalSheetFlag(List<CustomWidgetStateField>? rootState) {
    final authorNames = {
      for (final field in rootState ?? const <CustomWidgetStateField>[])
        field.name,
    };
    var index = 0;
    while (true) {
      final candidate = '_restageSheet${index}Open';
      if (!authorNames.contains(candidate)) return candidate;
      index++;
    }
  }

  String _emitModalSheetRoot(
    _ModalSheetEmitContext context, {
    required String underlayDsl,
    required List<Issue> issues,
  }) {
    final sheetEntry = findWidgetsByName(catalog, 'RestageModalSheet')
        .firstWhereOrNull((entry) => entry.library == WidgetLibrary.material);
    if (sheetEntry == null) {
      issues.add(
        _modalSheetUnsupportedIssue(
          'the catalog does not contain RestageModalSheet',
          context.sheet.call,
        ),
      );
      return '';
    }
    // The per-function presentation is load-bearing: the emit loop only
    // serialises slots the loaded catalog hosts, so a catalog missing the
    // `presentation` property (a codegen / catalog version skew the
    // strict-drift gate is meant to prevent) would SILENTLY drop it and let
    // the sheet decode to the adaptive default — rendering the wrong
    // platform's sheet. Fail loudly instead of emitting an unpinned sheet.
    if (!sheetEntry.properties.any((p) => p.name == 'presentation')) {
      issues.add(
        _modalSheetUnsupportedIssue(
          'the catalog RestageModalSheet is missing the presentation slot the '
          'per-function lowering requires; regenerate the catalog',
          context.sheet.call,
        ),
      );
      return '';
    }

    final values = _modalSheetSlotValues(context, sheetEntry, issues);
    if (values == null) return '';
    values
      ..['open'] = 'state.${context.flagName}'
      ..['underlay'] = underlayDsl
      ..['onSheetDismissed'] = 'set state.${context.flagName} = false'
      // Pin the sheet library per source function (Material for
      // showModalBottomSheet, Cupertino for showCupertinoSheet) so the
      // server-delivered sheet matches Flutter on every platform. The widget
      // default is adaptive; the lowering overrides it.
      ..['presentation'] =
          '"${kModalSheetPresentation[context.sheet.function]!}"';

    final emitted = <String>[];
    for (final property in sheetEntry.properties) {
      final value = values[property.name];
      if (value != null) emitted.add('${property.name}: $value');
    }
    return 'RestageModalSheet(${emitted.join(', ')})';
  }

  Map<String, String>? _modalSheetSlotValues(
    _ModalSheetEmitContext context,
    WidgetEntry sheetEntry,
    List<Issue> issues,
  ) {
    final call = context.sheet.call;
    final dispositions =
        kModalSheetArgumentDispositions[context.sheet.function];
    if (dispositions == null) {
      issues.add(
        _modalSheetUnsupportedIssue(
          'the sheet function is not supported',
          call,
        ),
      );
      return null;
    }

    Expression? builderExpr;
    Expression? pageBuilderExpr;
    final mapped = <String, Expression>{};
    final emitted = <String, String>{};

    for (final arg in call.argumentList.arguments) {
      if (arg is! NamedExpression) {
        issues.add(
          _modalSheetUnsupportedIssue(
            'positional arguments have no declarative sheet equivalent',
            arg,
          ),
        );
        return null;
      }
      final name = arg.name.label.name;
      final disposition = dispositions[name];
      if (disposition == null) {
        issues.add(
          _modalSheetUnsupportedIssue(
            "the '$name' argument has no RestageModalSheet equivalent",
            arg,
          ),
        );
        return null;
      }
      switch (disposition) {
        case ModalSheetArgumentDisposition.drop:
          break;
        case ModalSheetArgumentDisposition.builder:
          builderExpr ??= arg.expression;
        case ModalSheetArgumentDisposition.pageBuilder:
          pageBuilderExpr ??= arg.expression;
        case ModalSheetArgumentDisposition.map:
          mapped[name] = arg.expression;
        case ModalSheetArgumentDisposition.animationStyle:
          final animation = _modalSheetAnimationStyleSlots(
            arg.expression,
            sheetEntry,
            issues,
          );
          if (animation == null) return null;
          emitted.addAll(animation);
        case ModalSheetArgumentDisposition.defer:
          issues.add(
            _modalSheetUnsupportedIssue(
              "the '$name' argument has no faithful declarative sheet slot",
              arg,
            ),
          );
          return null;
      }
    }

    final builder = builderExpr ?? pageBuilderExpr;
    if (builder == null) {
      issues.add(
        _modalSheetUnsupportedIssue(
          'a static builder is required',
          call,
        ),
      );
      return null;
    }
    final builderBody = recogniseStaticModalSheetBuilder(builder);
    switch (builderBody) {
      case ModalSheetBuilderRecognised(:final body):
        final before = issues.length;
        final saved = _walk;
        _walk = _walk.copyWith(modalSheetCloseFlag: context.flagName);
        try {
          final child = _translate(body, issues);
          if (child.isEmpty && issues.length > before) return null;
          emitted['child'] = child;
        } finally {
          _walk = saved;
        }
      case ModalSheetBuilderUnsupported(:final reason):
        issues.add(_modalSheetUnsupportedIssue(reason, builder));
        return null;
    }

    for (final property in sheetEntry.properties) {
      final expr = mapped[property.name];
      if (expr == null) continue;
      final value = _emitModalSheetSlot(
        sheetEntry,
        property.name,
        expr,
        issues,
      );
      if (value == null) return null;
      emitted[property.name] = value;
    }

    return emitted;
  }

  Map<String, String>? _modalSheetAnimationStyleSlots(
    Expression source,
    WidgetEntry sheetEntry,
    List<Issue> issues,
  ) {
    final expr = _stripParens(source);
    if (expr is! InstanceCreationExpression ||
        _instanceCreationTypeName(expr) != 'AnimationStyle' ||
        _instanceCreationMemberName(expr) != null ||
        !_flutterOrUnresolved(_classOfInstanceCreation(expr))) {
      issues.add(
        _modalSheetUnsupportedIssue(
          'sheetAnimationStyle must be a literal AnimationStyle(...)',
          source,
        ),
      );
      return null;
    }

    final emitted = <String, String>{};
    for (final arg in expr.argumentList.arguments) {
      if (arg is! NamedExpression) {
        issues.add(
          _modalSheetUnsupportedIssue(
            'AnimationStyle accepts only named fields in sheet lowering',
            arg,
          ),
        );
        return null;
      }
      final fieldName = arg.name.label.name;
      final slotName = switch (fieldName) {
        'duration' => 'enterDuration',
        'reverseDuration' => 'exitDuration',
        'curve' => 'enterCurve',
        'reverseCurve' => 'exitCurve',
        _ => null,
      };
      if (slotName == null) {
        issues.add(
          _modalSheetUnsupportedIssue(
            'AnimationStyle.$fieldName is not supported',
            arg,
          ),
        );
        return null;
      }
      final isCurve = fieldName == 'curve' || fieldName == 'reverseCurve';
      if (isCurve && _supportedCurveName(arg.expression) == null) {
        issues.add(
          _modalSheetUnsupportedIssue(
            '$fieldName must be a supported Curves.* value',
            arg.expression,
          ),
        );
        return null;
      }
      final value = _emitModalSheetSlot(
        sheetEntry,
        slotName,
        arg.expression,
        issues,
      );
      if (value == null) return null;
      emitted[slotName] = value;
    }
    return emitted;
  }

  String? _supportedCurveName(Expression source) {
    final expr = _stripParens(source);
    if (expr is PrefixedIdentifier && expr.prefix.name == 'Curves') {
      if (!_frameworkOrUnresolved(expr.prefix.element)) return null;
      final name = expr.identifier.name;
      return kSupportedCurveNames.contains(name) ? name : null;
    }
    return null;
  }

  String? _emitModalSheetSlot(
    WidgetEntry sheetEntry,
    String propName,
    Expression expr,
    List<Issue> issues,
  ) {
    final property = sheetEntry.properties
        .firstWhereOrNull((candidate) => candidate.name == propName);
    if (property == null) {
      issues.add(
        _modalSheetUnsupportedIssue(
          "the catalog RestageModalSheet has no '$propName' property",
          expr,
        ),
      );
      return null;
    }
    final before = issues.length;
    _validateThemeValueForSlot(expr, property.type, issues);
    final value = _translateSlotValue(
      expr,
      property.type,
      issues,
      property: property,
    );
    if (value.isEmpty && issues.length > before) return null;
    return value;
  }

  Issue _modalSheetUnsupportedIssue(String reason, AstNode anchor) {
    return Issue(
      code: IssueCode.modalSheetFormUnsupported,
      message: 'Modal sheet could not be lowered declaratively: $reason.',
      location: _locationOf(anchor),
    );
  }

  Issue _navigationUnsupportedIssue(String reason, AstNode anchor) {
    return Issue(
      code: IssueCode.navigationFormUnsupported,
      message: 'Screen navigation could not be lowered declaratively: $reason.',
      location: _locationOf(anchor),
    );
  }

  /// Lowers a vanilla-Flutter `PageView(...)` to the `RestagePager` catalog
  /// widget — the declarative paged surface. Carry-all-or-defer per argument:
  /// the mapped set (`children`, `scrollDirection`, `pageSnapping`,
  /// `onPageChanged`) maps by name onto RestagePager's properties; a
  /// `controller: PageController(initialPage:, viewportFraction:)` literal
  /// flattens those two fields onto RestagePager's direct properties; and `key`
  /// is dropped (the universal super-key convention). ANY other form — a named
  /// constructor (`.builder` / `.custom`), a positional argument, an argument
  /// with no RestagePager equivalent, a controller that is not a literal
  /// `PageController(...)` in the flatten set, or an absent / empty children
  /// list — defers the WHOLE widget loud (an `pageViewFormUnsupported` Issue
  /// naming the reason) rather than emit a paged surface that silently drops
  /// the unexpressed behaviour.
  ///
  /// Gated on the resolved `package:flutter` PageView identity: returns `null`
  /// (the caller continues to the `unknownWidget` path) for a customer
  /// look-alike, an unresolved construction, or a catalog without RestagePager.
  /// Otherwise returns the emitted `RestagePager(...)` DSL, or `''` after
  /// recording a deferral Issue.
  String? _pageViewAlias({
    required ClassElement? widgetClass,
    required String? constructorName,
    required NodeList<Expression> args,
    required Expression anchor,
    required List<Issue> issues,
  }) {
    // Strict identity: only the real `package:flutter` PageView aliases.
    if (!libraryIsFlutter(widgetClass)) return null;
    // The alias target must be present in the merged catalog; without it (a
    // catalog lacking restage.material) this is not aliasable here.
    final pager = findWidgetsByName(catalog, 'RestagePager').firstOrNull;
    if (pager == null) return null;

    final loc = _locationOf(anchor);
    void defer(String reason, {String? subject}) {
      issues.add(
        Issue(
          code: IssueCode.pageViewFormUnsupported,
          capabilityGapSubject: subject ?? 'widget:PageView',
          message: 'PageView could not be lowered to the declarative paged '
              'surface: $reason. Use a children-list PageView (optionally with '
              'a literal PageController(initialPage:, viewportFraction:)), or '
              'compose the paged surface directly.',
          location: loc,
        ),
      );
    }

    // `.builder` / `.custom` — a dynamic itemBuilder; children-list form only.
    if (constructorName != null) {
      defer(
        "the named constructor 'PageView.$constructorName' is not "
        'supported (children-list form only)',
        subject: 'constructor:PageView.$constructorName',
      );
      return '';
    }

    Expression? childrenExpr;
    Expression? scrollDirectionExpr;
    Expression? pageSnappingExpr;
    Expression? onPageChangedExpr;
    Expression? initialPageExpr; // from the PageController flatten
    Expression? viewportFractionExpr; // from the PageController flatten

    for (final arg in args) {
      if (arg is! NamedExpression) {
        defer('a positional argument has no declarative equivalent');
        return '';
      }
      final name = arg.name.label.name;
      if (name == 'key') continue; // the universal super.key convention
      switch (name) {
        case 'children':
          childrenExpr = arg.expression;
        case 'scrollDirection':
          scrollDirectionExpr = arg.expression;
        case 'pageSnapping':
          pageSnappingExpr = arg.expression;
        case 'onPageChanged':
          onPageChangedExpr = arg.expression;
        case 'controller':
          {
            final flat = _pageControllerFlatten(arg.expression);
            if (flat == null) {
              defer("the 'controller' argument must be a literal "
                  'PageController(initialPage:, viewportFraction:) with no '
                  'other arguments');
              return '';
            }
            initialPageExpr = flat.$1;
            viewportFractionExpr = flat.$2;
          }
        default:
          defer("the '$name' argument has no RestagePager equivalent");
          return '';
      }
    }

    // `children` is required and non-empty (RestagePager asserts non-empty).
    if (childrenExpr == null) {
      defer('a children list is required');
      return '';
    }
    if (childrenExpr is ListLiteral && childrenExpr.elements.isEmpty) {
      defer('the children list must be non-empty');
      return '';
    }

    // Translate each mapped value through the corresponding RestagePager slot;
    // a value that defers (empty DSL + a new issue) aborts the whole widget.
    // Properties are emitted in catalog order for an author-order-independent,
    // byte-stable blob.
    final emitted = <String>[];
    bool emit(String propName, Expression expr) {
      final p = pager.properties.firstWhereOrNull((pe) => pe.name == propName);
      if (p == null) {
        defer("the catalog RestagePager has no '$propName' property");
        return false;
      }
      final before = issues.length;
      _validateThemeValueForSlot(expr, p.type, issues);
      final value = _translateSlotValue(expr, p.type, issues, property: p);
      if (value.isEmpty && issues.length > before) return false;
      emitted.add('$propName: $value');
      return true;
    }

    if (!emit('children', childrenExpr)) return '';
    if (initialPageExpr != null && !emit('initialPage', initialPageExpr)) {
      return '';
    }
    if (viewportFractionExpr != null &&
        !emit('viewportFraction', viewportFractionExpr)) {
      return '';
    }
    if (scrollDirectionExpr != null &&
        !emit('scrollDirection', scrollDirectionExpr)) {
      return '';
    }
    if (pageSnappingExpr != null && !emit('pageSnapping', pageSnappingExpr)) {
      return '';
    }
    if (onPageChangedExpr != null &&
        !emit('onPageChanged', onPageChangedExpr)) {
      return '';
    }

    return 'RestagePager(${emitted.join(', ')})';
  }

  /// Recognises an inline literal `package:flutter` `PageController(...)` for
  /// the PageView alias's controller flatten. Returns the `initialPage` and
  /// `viewportFraction` value expressions (either may be `null` when the author
  /// omitted it — RestagePager's defaults equal PageController's), or `null`
  /// for any non-flattenable shape: a non-construction (a bound identifier, a
  /// factory call), a customer `PageController` look-alike, a named
  /// constructor, a positional argument, or any argument outside the flatten
  /// set (`keepPage` / `onAttach` / `onDetach` / …). A `null` return defers the
  /// whole PageView — complete-static-extraction-or-defer.
  (Expression?, Expression?)? _pageControllerFlatten(Expression expr) {
    if (expr is! InstanceCreationExpression) return null;
    if (!libraryIsFlutter(_classOfInstanceCreation(expr))) return null;
    if (expr.constructorName.name != null) return null; // a named constructor
    Expression? initialPage;
    Expression? viewportFraction;
    for (final arg in expr.argumentList.arguments) {
      if (arg is! NamedExpression) return null; // a positional argument
      switch (arg.name.label.name) {
        case 'initialPage':
          initialPage = arg.expression;
        case 'viewportFraction':
          viewportFraction = arg.expression;
        default:
          return null; // keepPage / onAttach / onDetach / …
      }
    }
    return (initialPage, viewportFraction);
  }

  /// Lowers a vanilla-Flutter `DraggableScrollableSheet(...)` to the
  /// `RestageDraggableSheet` catalog widget — the declarative draggable
  /// surface. A widget-identity alias (the RestagePager precedent). The detents
  /// map by name; the persistent surface owns its scroll controller internally,
  /// so the only byte-faithful builder is `(context, scrollController) =>
  /// SingleChildScrollView(controller: scrollController, child: content)` whose
  /// scroll view carries nothing beyond `key` / `controller` / `child` — the
  /// inner `content` lowers onto the `child` slot. Carry-all-or-defer: a named
  /// constructor, a positional argument, an argument with no faithful slot, an
  /// author-supplied controller, a non-empty `snapSizes`, a
  /// `shouldCloseOnMinExtent: true`, or any non-canonical builder defers the
  /// WHOLE widget loud rather than emit a surface that silently changes
  /// behaviour.
  ///
  /// Gated on the resolved `package:flutter` DraggableScrollableSheet identity:
  /// returns `null` (the caller continues to the `unknownWidget` path) for a
  /// customer look-alike, an unresolved construction, or a catalog without
  /// RestageDraggableSheet. Otherwise returns the emitted DSL, or `''` after
  /// recording a deferral Issue.
  String? _draggableScrollableSheetAlias({
    required ClassElement? widgetClass,
    required String? constructorName,
    required NodeList<Expression> args,
    required Expression anchor,
    required List<Issue> issues,
  }) {
    // Strict identity: only the real `package:flutter` DraggableScrollableSheet
    // aliases; a customer look-alike falls through to `unknownWidget`.
    if (!libraryIsFlutter(widgetClass)) return null;
    final sheet =
        findWidgetsByName(catalog, 'RestageDraggableSheet').firstOrNull;
    if (sheet == null) return null;

    final loc = _locationOf(anchor);
    void defer(
      String reason, {
      String subject = 'widget:DraggableScrollableSheet',
    }) {
      issues.add(
        Issue(
          code: IssueCode.draggableSheetFormUnsupported,
          capabilityGapSubject: subject,
          message: 'DraggableScrollableSheet could not be lowered to the '
              'declarative draggable surface: $reason.',
          location: loc,
        ),
      );
    }

    // Catalog-shape skew guard. The lowering drops the source controller (the
    // widget owns one internally) and threads the builder content onto the
    // `child` slot. If a future catalog change removed `child` or exposed a
    // real author-bindable `controller` slot, "drop the controller" would mean
    // something different — fail loud rather than silently change it.
    final hasChild = sheet.properties.any((p) => p.name == 'child');
    final hasControllerSlot =
        sheet.properties.any((p) => p.name == 'controller');
    if (!hasChild || hasControllerSlot) {
      defer(
        'the catalog RestageDraggableSheet shape changed (the child slot is '
        'missing or an author-bindable controller slot appeared); regenerate '
        'the catalog',
        subject: 'catalog:RestageDraggableSheet',
      );
      return '';
    }

    if (constructorName != null) {
      defer(
        "the named constructor 'DraggableScrollableSheet.$constructorName' is "
        'not supported',
        subject: 'constructor:DraggableScrollableSheet.$constructorName',
      );
      return '';
    }

    Expression? builderExpr;
    final mapped = <String, Expression>{};
    for (final arg in args) {
      if (arg is! NamedExpression) {
        defer('a positional argument has no declarative equivalent');
        return '';
      }
      final name = arg.name.label.name;
      final disposition = kDraggableSheetArgumentDispositions[name];
      if (disposition == null) {
        defer("the '$name' argument has no RestageDraggableSheet equivalent");
        return '';
      }
      switch (disposition) {
        case DraggableSheetArgumentDisposition.drop:
          break;
        case DraggableSheetArgumentDisposition.map:
          mapped[name] = arg.expression;
        case DraggableSheetArgumentDisposition.builder:
          builderExpr = arg.expression;
        case DraggableSheetArgumentDisposition.snapSizes:
          if (!_isAbsentOrEmptyList(arg.expression)) {
            defer(
              kDraggableSheetSnapSizesUnsupportedReason,
              subject: 'param:snapSizes',
            );
            return '';
          }
        case DraggableSheetArgumentDisposition.shouldCloseOnMinExtent:
          final value = _staticBoolLiteral(arg.expression);
          if (value == null) {
            defer('shouldCloseOnMinExtent must be a literal false to lower');
            return '';
          }
          if (value) {
            defer(kDraggableSheetShouldCloseOnMinExtentReason);
            return '';
          }
        case DraggableSheetArgumentDisposition.controller:
          defer(kDraggableSheetControllerUnsupportedReason);
          return '';
      }
    }

    if (builderExpr == null) {
      defer('a static builder is required');
      return '';
    }

    // Fail loud on a catalog skew. The emit loop below iterates the catalog
    // properties, so a mapped source argument whose slot is absent would be
    // SILENTLY dropped (the sheet would decode to the runtime default). A
    // missing slot is a codegen / catalog version skew the strict-drift gate is
    // meant to prevent; fail loudly (the modal-sheet presentation-slot guard
    // posture) rather than emit an unfaithful sheet.
    for (final name in mapped.keys) {
      if (!sheet.properties.any((p) => p.name == name)) {
        defer(
          "the catalog RestageDraggableSheet is missing the '$name' slot the "
          'lowering requires; regenerate the catalog',
          subject: 'catalog:RestageDraggableSheet',
        );
        return '';
      }
    }

    final Expression contentExpr;
    switch (recogniseDraggableSheetBuilder(builderExpr)) {
      case DraggableSheetNotRecognised():
        defer(kDraggableSheetBuilderUnsupportedReason);
        return '';
      case DraggableSheetDeferred(:final reason):
        defer(reason);
        return '';
      case DraggableSheetRecognised(:final content):
        contentExpr = content;
    }

    // Emit in catalog order for an author-order-independent, byte-stable blob.
    // `child` is the first property; a mapped slot value that defers (empty DSL
    // + a new issue) aborts the whole widget.
    final emitted = <String>[];
    for (final property in sheet.properties) {
      if (property.name == 'child') {
        final before = issues.length;
        final value = _translate(contentExpr, issues);
        if (value.isEmpty) {
          if (issues.length == before) {
            defer('the sheet child could not be lowered');
          }
          return '';
        }
        emitted.add('child: $value');
      } else if (mapped.containsKey(property.name)) {
        final expr = mapped[property.name]!;
        final before = issues.length;
        _validateThemeValueForSlot(expr, property.type, issues);
        final value = _translateSlotValue(
          expr,
          property.type,
          issues,
          property: property,
        );
        if (value.isEmpty && issues.length > before) return '';
        emitted.add('${property.name}: $value');
      }
    }

    return 'RestageDraggableSheet(${emitted.join(', ')})';
  }

  /// Lowers a vanilla-Flutter `RadioGroup(...)` / `DropdownButton(...)` to the
  /// compiled single-select catalog widget (`RestageRadioGroupString` /
  /// `RestageDropdownString`) — the declarative single-select surface. A
  /// widget-identity alias (the RestagePager precedent). The pure shape
  /// recognition lives in `single_select_recognition.dart`; this method owns
  /// the framework-identity gate, the catalog-presence gate, and the emission
  /// of the recognised `{items, selected, onChanged}` parts.
  ///
  /// Carry-all-or-defer: the recogniser defers the WHOLE widget loud (a
  /// `singleSelectFormUnsupported` Issue) on any unparseable shape — a dynamic
  /// / builder child, a non-carrier leaf, a non-literal-`Text` label, a missing
  /// `value`, a duplicate value, or an unrecognized argument — rather than emit
  /// a partial or wrong group.
  ///
  /// Gated on the resolved `package:flutter` identity: returns `null` (the
  /// caller continues to the `unknownWidget` path) for a customer look-alike,
  /// an unresolved construction, or a catalog without the target widget.
  /// Otherwise returns the emitted DSL, or `''` after recording a deferral.
  String? _singleSelectAlias({
    required String widgetName,
    required ClassElement? widgetClass,
    required String? constructorName,
    required Expression anchor,
    required List<Issue> issues,
  }) {
    // Strict identity: only the real `package:flutter` widgets alias; a
    // customer look-alike falls through to `unknownWidget`.
    if (!libraryIsFlutter(widgetClass)) return null;
    final isRadio = widgetName == 'RadioGroup';
    final targetName =
        isRadio ? 'RestageRadioGroupString' : 'RestageDropdownString';
    final target = findWidgetsByName(catalog, targetName).firstOrNull;
    if (target == null) return null;

    final loc = _locationOf(anchor);
    void defer(String reason) {
      issues.add(
        Issue(
          code: IssueCode.singleSelectFormUnsupported,
          capabilityGapSubject: 'widget:$widgetName',
          message: '$widgetName could not be lowered to the declarative '
              'single-select surface: $reason.',
          location: loc,
        ),
      );
    }

    // A named constructor (`.adaptive`, etc.) is not the carrier form.
    if (constructorName != null) {
      defer("the named constructor '$widgetName.$constructorName' is not "
          'supported (the unnamed constructor only)');
      return '';
    }

    // The recogniser reads the construction's `<T>` type argument (the
    // String-keyed gate) as well as its argument list, so it takes the whole
    // creation expression. The dispatch only reaches here for an
    // `InstanceCreationExpression` anchor.
    if (anchor is! InstanceCreationExpression) return null;
    final outcome =
        isRadio ? recogniseRadioGroup(anchor) : recogniseDropdown(anchor);
    switch (outcome) {
      case SingleSelectDeferred(:final reason):
        defer(reason);
        return '';
      case SingleSelectRecognised(:final recognised):
        return _emitSingleSelect(target, recognised, issues);
    }
  }

  /// Emits the catalog single-select construction from the recognised parts:
  /// the `items` option list (a list of `{value, label}` maps, each value and
  /// label translated through the string slot), the `selected` value, and the
  /// `onChanged` event. A value/label that defers (empty DSL + a new issue)
  /// aborts the whole widget.
  String _emitSingleSelect(
    WidgetEntry target,
    RecognisedSingleSelect recognised,
    List<Issue> issues,
  ) {
    PropertyEntry? prop(String name) =>
        target.properties.firstWhereOrNull((p) => p.name == name);

    // Translate one option value/label expression through the string slot.
    // Returns null (after recording an issue) when the value cannot lower.
    String? str(Expression expr) {
      final before = issues.length;
      final value = _translateSlotValue(expr, PropertyType.string, issues);
      if (value.isEmpty && issues.length > before) return null;
      return value;
    }

    // Re-check duplicate values on the EXACT emitted DSL, not the raw source.
    // The recogniser's duplicate check only sees raw string literals; two
    // values that emit the SAME DSL pass that check but the compiled widget
    // would silently de-dupe (drop) the second option. Two cases fold here:
    // a const-folded string pair (`const a='pro'; const b='pro';` → both emit
    // `"pro"`) AND two IDENTICAL runtime references (`value: planId` on two
    // options → both emit `args.planId`). Both are an exact-duplicate emitted
    // value, so the WHOLE single-select defers loud rather than ship a group
    // with a silently-dropped option. Only NON-identical runtime references
    // (`args.a` vs `args.b` — distinct DSL) are left to the runtime de-dupe.
    final seenValueDsl = <String>{};
    final optionDsls = <String>[];
    for (final option in recognised.options) {
      final value = str(option.value);
      if (value == null) return '';
      if (!seenValueDsl.add(value)) {
        issues.add(
          Issue(
            code: IssueCode.singleSelectFormUnsupported,
            capabilityGapSubject: 'widget:${target.name}',
            message: 'two options emit the same value ($value) — each option '
                'value must be unique, so the whole single-select defers '
                'rather than silently drop the duplicate option.',
            location: _locationOf(option.value),
          ),
        );
        return '';
      }
      final label = str(option.label);
      if (label == null) return '';
      optionDsls.add('{ value: $value, label: $label }');
    }

    final parts = <String>['items: [${optionDsls.join(', ')}]'];

    final selected = recognised.selected;
    if (selected != null && selected is! NullLiteral) {
      final value = str(selected);
      if (value == null) return '';
      parts.add('selected: $value');
    }

    final onChanged = recognised.onChanged;
    if (onChanged != null && onChanged is! NullLiteral) {
      final onChangedProp = prop('onChanged');
      if (onChangedProp == null) {
        issues.add(
          Issue(
            code: IssueCode.singleSelectFormUnsupported,
            capabilityGapSubject: 'catalog:${target.name}',
            message: 'the catalog ${target.name} has no onChanged property; '
                'regenerate the catalog',
            location: _locationOf(onChanged),
          ),
        );
        return '';
      }
      final before = issues.length;
      final value = _translateSlotValue(
        onChanged,
        PropertyType.event,
        issues,
        property: onChangedProp,
      );
      if (value.isEmpty && issues.length > before) return '';
      parts.add('onChanged: $value');
    }

    return '${target.name}(${parts.join(', ')})';
  }

  /// Lowers a vanilla-Flutter `ToggleButtons(...)` to the compiled
  /// `RestageToggleButtons` catalog widget — the declarative multi-toggle
  /// surface. A widget-identity alias (the RestagePager precedent). The pure
  /// shape recognition lives in `toggle_buttons_recognition.dart`; this method
  /// owns the framework-identity gate, the catalog-presence gate, and the
  /// emission of the recognised `{children, isSelected, onPressed}` parts.
  ///
  /// Carry-all-or-defer: the recogniser defers the WHOLE widget loud (a
  /// `toggleButtonsFormUnsupported` Issue) on any unparseable shape — a
  /// dynamic / builder `children` or `isSelected`, a spread / `if` / `for`
  /// element, a non-`bool`-literal flag, an empty set, a length mismatch
  /// between `children` and `isSelected`, or a positional / unrecognized
  /// argument — rather than emit a partial or misaligned set.
  ///
  /// Gated on the resolved `package:flutter` identity: returns `null` (the
  /// caller continues to the `unknownWidget` path) for a customer look-alike,
  /// an unresolved construction, or a catalog without RestageToggleButtons.
  /// Otherwise returns the emitted DSL, or `''` after recording a deferral.
  String? _toggleButtonsAlias({
    required ClassElement? widgetClass,
    required Expression anchor,
    required List<Issue> issues,
  }) {
    // Strict identity: only the real `package:flutter` widget aliases; a
    // customer look-alike falls through to `unknownWidget`.
    if (!libraryIsFlutter(widgetClass)) return null;
    final target =
        findWidgetsByName(catalog, 'RestageToggleButtons').firstOrNull;
    if (target == null) return null;

    final loc = _locationOf(anchor);
    void defer(String reason) {
      issues.add(
        Issue(
          code: IssueCode.toggleButtonsFormUnsupported,
          capabilityGapSubject: 'widget:ToggleButtons',
          message: 'ToggleButtons could not be lowered to the declarative '
              'multi-toggle surface: $reason.',
          location: loc,
        ),
      );
    }

    // The dispatch only reaches here for an `InstanceCreationExpression`
    // anchor; the recogniser reads its argument list.
    if (anchor is! InstanceCreationExpression) return null;
    final outcome = recogniseToggleButtons(anchor);
    switch (outcome) {
      case ToggleButtonsDeferred(:final reason):
        defer(reason);
        return '';
      case ToggleButtonsRecognised(:final recognised):
        return _emitToggleButtons(target, recognised, issues);
    }
  }

  /// Emits the catalog multi-toggle construction from the recognised parts: the
  /// `children` widget list, the `isSelected` boolean-literal list, and the
  /// optional `onPressed` event. Each slot is translated through its catalog
  /// `PropertyType` (`children` through the widget-list slot, `isSelected`
  /// through the `booleanList` slot, `onPressed` through the event slot); a
  /// value that defers (empty DSL + a new issue) aborts the whole widget.
  /// Properties are emitted in catalog order for an author-order-independent,
  /// byte-stable blob.
  String _emitToggleButtons(
    WidgetEntry target,
    RecognisedToggleButtons recognised,
    List<Issue> issues,
  ) {
    final emitted = <String>[];
    bool emit(String propName, Expression expr) {
      final p = target.properties.firstWhereOrNull((pe) => pe.name == propName);
      if (p == null) {
        issues.add(
          Issue(
            code: IssueCode.toggleButtonsFormUnsupported,
            capabilityGapSubject: 'catalog:${target.name}',
            message: 'the catalog ${target.name} has no $propName property; '
                'regenerate the catalog.',
            location: _locationOf(expr),
          ),
        );
        return false;
      }
      final before = issues.length;
      _validateThemeValueForSlot(expr, p.type, issues);
      final value = _translateSlotValue(expr, p.type, issues, property: p);
      if (value.isEmpty && issues.length > before) return false;
      emitted.add('$propName: $value');
      return true;
    }

    if (!emit('children', recognised.children)) return '';
    if (!emit('isSelected', recognised.isSelected)) return '';

    final onPressed = recognised.onPressed;
    if (onPressed != null && onPressed is! NullLiteral) {
      if (!emit('onPressed', onPressed)) return '';
    }

    return '${target.name}(${emitted.join(', ')})';
  }

  /// Lowers a vanilla-Flutter `SegmentedButton<String>(...)` to the compiled
  /// `RestageSegmentedButton` catalog widget (`RestageSegmentedButtonString`) —
  /// the declarative segmented-button surface. A widget-identity alias (the
  /// RestagePager precedent). The pure shape recognition lives in
  /// `segmented_button_recognition.dart`; this method owns the
  /// framework-identity gate, the catalog-presence gate, and the emission of
  /// the recognised `{items, selected, onChanged, …}` parts.
  ///
  /// Carry-all-or-defer: the recogniser defers the WHOLE widget loud (a
  /// `segmentedButtonFormUnsupported` Issue) on any unparseable shape — a
  /// non-`String` generic, a dynamic / builder / spread segments or selected,
  /// a non-`ButtonSegment` leaf, an icon-only / non-literal-`Text` label, a
  /// missing `value`, a behavioral carrier arg, a duplicate value, or an
  /// unrecognized argument — rather than emit a partial, reordered, or wrong
  /// set.
  ///
  /// Gated on the resolved `package:flutter` identity: returns `null` (the
  /// caller continues to the `unknownWidget` path) for a customer look-alike,
  /// an unresolved construction, or a catalog without the target widget.
  /// Otherwise returns the emitted DSL, or `''` after recording a deferral.
  String? _segmentedButtonAlias({
    required ClassElement? widgetClass,
    required Expression anchor,
    required List<Issue> issues,
  }) {
    // Strict identity: only the real `package:flutter` widget aliases; a
    // customer look-alike falls through to `unknownWidget`.
    if (!libraryIsFlutter(widgetClass)) return null;
    final target =
        findWidgetsByName(catalog, 'RestageSegmentedButtonString').firstOrNull;
    if (target == null) return null;

    final loc = _locationOf(anchor);
    void defer(String reason) {
      issues.add(
        Issue(
          code: IssueCode.segmentedButtonFormUnsupported,
          capabilityGapSubject: 'widget:SegmentedButton',
          message: 'SegmentedButton could not be lowered to the declarative '
              'segmented-button surface: $reason.',
          location: loc,
        ),
      );
    }

    // The dispatch only reaches here for an `InstanceCreationExpression`
    // anchor; the recogniser reads its `<T>` type argument and its argument
    // list.
    if (anchor is! InstanceCreationExpression) return null;
    final outcome = recogniseSegmentedButton(anchor);
    switch (outcome) {
      case SegmentedButtonDeferred(:final reason):
        defer(reason);
        return '';
      case SegmentedButtonRecognised(:final recognised):
        return _emitSegmentedButton(target, recognised, issues);
    }
  }

  /// Emits the catalog segmented-button construction from the recognised parts:
  /// the `items` option list (a list of `{value, label}` maps, each value and
  /// label translated through the string slot), the `selected` value list, the
  /// `onChanged` settled-selection event, and the declarative
  /// `multiSelectionEnabled` / `emptySelectionAllowed` bools. Properties are
  /// emitted in catalog order for an author-order-independent, byte-stable
  /// blob. A value/label that defers (empty DSL + a new issue) aborts the whole
  /// widget; a post-fold duplicate emitted value defers loud.
  String _emitSegmentedButton(
    WidgetEntry target,
    RecognisedSegmentedButton recognised,
    List<Issue> issues,
  ) {
    PropertyEntry? prop(String name) =>
        target.properties.firstWhereOrNull((p) => p.name == name);

    // Translate [expr] through [type]'s slot, returning the DSL — or `null`
    // (after the slot recorded an issue) when it cannot lower, so the caller
    // aborts the whole widget rather than emit a partial blob.
    String? slot(
      Expression expr,
      PropertyType type, {
      PropertyEntry? property,
    }) {
      final before = issues.length;
      final value = _translateSlotValue(expr, type, issues, property: property);
      if (value.isEmpty && issues.length > before) return null;
      return value;
    }

    // One value/label through the string slot.
    String? str(Expression expr) => slot(expr, PropertyType.string);

    // Re-check duplicate values on the EXACT emitted DSL, not the raw source —
    // the same post-fold guard the single-select uses: a const-folded string
    // pair or two IDENTICAL runtime references both emit the same value, which
    // the compiled widget would silently de-dupe (drop). Defer the WHOLE widget
    // rather than ship a set with a silently-dropped segment.
    final seenValueDsl = <String>{};
    final optionDsls = <String>[];
    for (final segment in recognised.segments) {
      final value = str(segment.value);
      if (value == null) return '';
      if (!seenValueDsl.add(value)) {
        issues.add(
          Issue(
            code: IssueCode.segmentedButtonFormUnsupported,
            capabilityGapSubject: 'widget:${target.name}',
            message: 'two segments emit the same value ($value) — each segment '
                'value must be unique, so the whole segmented button defers '
                'rather than silently drop the duplicate segment.',
            location: _locationOf(segment.value),
          ),
        );
        return '';
      }
      final label = str(segment.label);
      if (label == null) return '';
      optionDsls.add('{ value: $value, label: $label }');
    }

    final parts = <String>['items: [${optionDsls.join(', ')}]'];

    // `selected` is a plain string list of the selected values. Translate each
    // value through the string slot; a value that defers aborts the widget.
    if (recognised.selectedValues.isNotEmpty) {
      final selectedDsls = <String>[];
      for (final value in recognised.selectedValues) {
        final dsl = str(value);
        if (dsl == null) return '';
        selectedDsls.add(dsl);
      }
      parts.add('selected: [${selectedDsls.join(', ')}]');
    }

    final onSelectionChanged = recognised.onSelectionChanged;
    if (onSelectionChanged != null && onSelectionChanged is! NullLiteral) {
      final onChangedProp = prop('onChanged');
      if (onChangedProp == null) {
        issues.add(
          Issue(
            code: IssueCode.segmentedButtonFormUnsupported,
            capabilityGapSubject: 'catalog:${target.name}',
            message: 'the catalog ${target.name} has no onChanged property; '
                'regenerate the catalog',
            location: _locationOf(onSelectionChanged),
          ),
        );
        return '';
      }
      // The host idiom is `onSelectionChanged: (Set<String> s) => <body>`. The
      // blob carries the declarative `<body>` event (the host wires its real
      // `ValueChanged<Set<String>>` to it); the closure params are irrelevant
      // to the wire. Unwrap a single-expression closure body to its declarative
      // event before the event-slot translation — a host-imperative body
      // (an arbitrary call / a block) defers loud there, never silently drops.
      final value = slot(
        _eventBodyOf(onSelectionChanged),
        PropertyType.event,
        property: onChangedProp,
      );
      if (value == null) return '';
      parts.add('onChanged: $value');
    }

    // The declarative bools — emitted only when authored (the catalog defaults
    // them otherwise), each translated through its boolean slot. An authored
    // bool that cannot lower aborts the whole widget.
    for (final (name, expr) in <(String, Expression?)>[
      ('multiSelectionEnabled', recognised.multiSelectionEnabled),
      ('emptySelectionAllowed', recognised.emptySelectionAllowed),
    ]) {
      if (expr == null || expr is NullLiteral || prop(name) == null) continue;
      final value = slot(expr, PropertyType.boolean);
      if (value == null) return '';
      parts.add('$name: $value');
    }

    return '${target.name}(${parts.join(', ')})';
  }

  /// Unwraps a single-expression callback closure to its body expression so the
  /// declarative event lowers at the event slot. `(s) => paywallEvent('x')`
  /// yields `paywallEvent('x')`; a direct `paywallEvent('x')` (no closure)
  /// passes through unchanged. A block-bodied closure (`(s) { … }`) or any
  /// other expression is returned as-is — it is not a single declarative event
  /// expression, so the event-slot translation defers it loud rather than
  /// silently dropping the author's intent.
  Expression _eventBodyOf(Expression expr) {
    final stripped = _stripParens(expr);
    if (stripped is FunctionExpression) {
      final body = stripped.body;
      if (body is ExpressionFunctionBody) return body.expression;
    }
    return stripped;
  }

  /// Whether [expr] is an absent (`null`) or empty list literal — the forms a
  /// `snapSizes` argument may take and still lower (treated as no snap stops).
  bool _isAbsentOrEmptyList(Expression expr) {
    final stripped = _stripParens(expr);
    if (stripped is NullLiteral) return true;
    return stripped is ListLiteral && stripped.elements.isEmpty;
  }

  /// The static value of a boolean literal [expr], or `null` when it is not a
  /// literal (a non-literal bool cannot be proven `false`).
  bool? _staticBoolLiteral(Expression expr) {
    final stripped = _stripParens(expr);
    return stripped is BooleanLiteral ? stripped.value : null;
  }

  /// Translates a widget construction call — either `Foo(...)` or
  /// `new Foo(...)` — into a catalog-validated RFW DSL fragment.
  ///
  /// Positional arguments are mapped to declared properties in catalog order.
  /// Named arguments are matched by name. The `key:` argument is silently
  /// dropped (super.key convention; not a catalog property). Unknown widget
  /// names and unknown property names each emit a structured [Issue].
  ///
  /// Lookup order:
  /// 1. If [flutterType] resolved (the analyzer knew the canonical class),
  ///    match against [WidgetEntry.flutterType]. This is the catalog's
  ///    primary identity path — re-exports and aliasing of curated widgets
  ///    land on the same canonical identifier.
  /// 2. Fallback to name-based lookup via [findWidgetsByName] for cases
  ///    where the analyzer couldn't resolve the type (synthetic test
  ///    fixtures, build-time analysis errors). The merged catalog is
  ///    sorted by built-in priority (core > material > cupertino), so
  ///    taking the first match yields the same tie-break the reference
  ///    used.
  String _catalogWidgetConstruction({
    required String widgetName,
    required String? flutterType,
    required ClassElement? widgetClass,
    required NodeList<Expression> args,
    required Expression anchor,
    required List<Issue> issues,
    String? constructorName,
  }) {
    WidgetEntry? entry;
    // Whether the entry was resolved by an exact `flutterType` match that
    // INCLUDES the named constructor (e.g. `...#Card.filled` → the dedicated
    // `CardFilled` entry). A named constructor that did NOT match a dedicated
    // entry this way falls through to the base entry by name and must not
    // silently drop its implied semantics (see the named-constructor block
    // below).
    var matchedByFlutterType = false;
    if (flutterType != null) {
      for (final w in catalog.widgets) {
        if (w.flutterType == flutterType) {
          entry = w;
          matchedByFlutterType = true;
          break;
        }
      }
    }
    if (entry == null) {
      final candidates = findWidgetsByName(catalog, widgetName);
      entry = candidates.isEmpty ? null : candidates.first;
    }
    if (entry == null) {
      if (widgetClass != null) {
        final key = customWidgetKey(widgetClass);
        final classification = customWidgetClassifications[key];
        if (classification != null) {
          final inlined = _tryInlineCustomWidget(
            classification,
            key,
            args,
            anchor,
            issues,
          );
          if (inlined != null) return inlined;
          issues.add(_customWidgetIssue(classification, widgetName, anchor));
          return '';
        }
      }
      // PageView → RestagePager alias. A vanilla-Flutter `PageView(...)` is the
      // faithful Flutter spelling of the declarative paged surface; recognise
      // it and lower to the `RestagePager` catalog widget (carry-all-or-defer).
      // Placed AFTER the custom-widget classification check (a customer
      // `@RestageWidget` named `PageView` still inlines above) and gated on the
      // resolved `package:flutter` identity inside the alias — a customer
      // look-alike or an unresolved construction returns `null` and falls
      // through to the `unknownWidget` diagnostic below.
      if (widgetName == 'PageView') {
        final aliased = _pageViewAlias(
          widgetClass: widgetClass,
          constructorName: constructorName,
          args: args,
          anchor: anchor,
          issues: issues,
        );
        if (aliased != null) return aliased;
      }
      // DraggableScrollableSheet → RestageDraggableSheet alias. Same posture as
      // the PageView alias: a vanilla-Flutter draggable sheet is the faithful
      // spelling of the declarative draggable surface; recognise it and lower
      // (carry-all-or-defer). Gated on the resolved `package:flutter` identity
      // inside the alias — a customer look-alike or an unresolved construction
      // returns `null` and falls through below.
      if (widgetName == 'DraggableScrollableSheet') {
        final aliased = _draggableScrollableSheetAlias(
          widgetClass: widgetClass,
          constructorName: constructorName,
          args: args,
          anchor: anchor,
          issues: issues,
        );
        if (aliased != null) return aliased;
      }
      // RadioGroup / DropdownButton → the compiled single-select catalog
      // widgets. Same posture as the PageView / DraggableScrollableSheet
      // aliases: the vanilla-Flutter idiom is the faithful spelling of the
      // declarative single-select surface; recognise it and lower
      // (carry-all-or-defer). Gated on the resolved `package:flutter` identity
      // inside the alias — a customer look-alike or an unresolved construction
      // returns `null` and falls through below.
      if (widgetName == 'RadioGroup' || widgetName == 'DropdownButton') {
        final aliased = _singleSelectAlias(
          widgetName: widgetName,
          widgetClass: widgetClass,
          constructorName: constructorName,
          anchor: anchor,
          issues: issues,
        );
        if (aliased != null) return aliased;
      }
      // ToggleButtons → the compiled RestageToggleButtons catalog widget. Same
      // posture as the single-select aliases: the vanilla-Flutter multi-toggle
      // is the faithful spelling of the declarative multi-toggle surface;
      // recognise it and lower (carry-all-or-defer). Gated on the resolved
      // `package:flutter` identity inside the alias — a customer look-alike or
      // an unresolved construction returns `null` and falls through below.
      if (widgetName == 'ToggleButtons') {
        final aliased = _toggleButtonsAlias(
          widgetClass: widgetClass,
          anchor: anchor,
          issues: issues,
        );
        if (aliased != null) return aliased;
      }
      // SegmentedButton → the compiled RestageSegmentedButton catalog widget.
      // Same posture as the single-select / multi-toggle aliases: the
      // vanilla-Flutter segmented button is the faithful spelling of the
      // declarative segmented-button surface; recognise it and lower
      // (carry-all-or-defer). Gated on the resolved `package:flutter` identity
      // inside the alias — a customer look-alike or an unresolved construction
      // returns `null` and falls through below.
      if (widgetName == 'SegmentedButton') {
        final aliased = _segmentedButtonAlias(
          widgetClass: widgetClass,
          anchor: anchor,
          issues: issues,
        );
        if (aliased != null) return aliased;
      }
      issues.add(
        Issue(
          code: IssueCode.unknownWidget,
          capabilityGapSubject: 'widget:$widgetName',
          message: "Widget '$widgetName' is not a known catalog widget. If "
              'it is a custom widget, annotate its class with @RestageWidget '
              'so the transpiler can recognise it.',
          location: _locationOf(anchor),
        ),
      );
      return '';
    }

    final localIssueStart = issues.length;
    final emitted = <String>[];

    // Named-constructor handling. A named constructor that resolved to a
    // dedicated variant entry by exact `flutterType` (Card.filled → CardFilled)
    // is already the right entry — nothing to do. A named constructor that fell
    // through to the BASE entry by name would otherwise emit the base widget
    // and SILENTLY drop the constructor's implied semantics (the
    // `Positioned.fill` fill-drop). `Positioned.fill` is lowered faithfully by
    // injecting its implied zero edges (an explicit edge the author passed
    // wins); every other unmatched named constructor defers loud rather than
    // emit a degraded blob.
    if (constructorName != null && !matchedByFlutterType) {
      final implied = _namedConstructorImpliedDefaults(
        entry.name,
        constructorName,
      );
      if (implied == null) {
        issues.add(
          Issue(
            code: IssueCode.namedConstructorUnsupported,
            capabilityGapSubject: 'constructor:${entry.name}.$constructorName',
            message:
                "The named constructor '${entry.name}.$constructorName' is "
                'not supported by this transpiler increment — emitting the '
                'base widget would silently drop its implied semantics. '
                "Rewrite it using the unnamed '${entry.name}(...)' constructor "
                'with explicit properties so each value lowers faithfully.',
            location: _locationOf(anchor),
          ),
        );
        return '';
      }
      // Emit each implied default the author did not pass explicitly; the
      // author's explicit value (handled by the arg loops below) wins.
      final authorNamed = {
        for (final a in args.whereType<NamedExpression>()) a.name.label.name,
      };
      for (final e in implied.entries) {
        if (!authorNamed.contains(e.key)) {
          emitted.add('${e.key}: ${e.value}');
        }
      }
    }

    // Positional args map to the catalog's `positional: true` properties in
    // declaration order. Properties without `positional: true` accept named
    // args only; they would otherwise capture the first positional slot and
    // collide with their own named-arg form (e.g. Icon's `size` would absorb
    // the IconData positional and then duplicate when `size:` is also named).
    final positionals = args.where((a) => a is! NamedExpression).toList();
    final positionalProps =
        entry.properties.where((p) => p.positional).toList();
    for (var i = 0; i < positionals.length; i++) {
      if (i >= positionalProps.length) {
        issues.add(
          Issue(
            code: IssueCode.unknownProperty,
            message: 'Too many positional arguments for ${entry.name}.',
            location: _locationOf(anchor),
          ),
        );
        break;
      }
      final positionalProp = positionalProps[i];
      final propName = positionalProp.name;
      final before = issues.length;
      _validateThemeValueForSlot(positionals[i], positionalProp.type, issues);
      final value = _translateSlotValue(
        positionals[i],
        positionalProp.type,
        issues,
        property: positionalProp,
      );
      if (value.isEmpty && issues.length > before) return '';
      emitted.add('$propName: $value');
    }

    // Named args map by name; ignore `key:` (super.key convention).
    for (final a in args.whereType<NamedExpression>()) {
      final name = a.name.label.name;
      if (name == 'key') continue;

      // Structured-type decomposition. If this argument matches one of the
      // entry's native recipes, hoist mapped structured fields to flat
      // properties on the outer widget. Inner values route back through
      // `_translate`, so per-type value translators compose recursively.
      final decomposed = _tryDecompose(entry, name, a.expression, issues);
      if (decomposed != null) {
        emitted.addAll(decomposed);
        continue;
      }

      final prop = entry.properties.where((p) => p.name == name).firstOrNull;
      if (prop == null) {
        issues.add(
          Issue(
            code: IssueCode.unknownProperty,
            message: "Property '$name' is not declared on '${entry.name}'. "
                'Catalog properties: '
                '${entry.properties.map((p) => p.name).join(", ")}.',
            location: _locationOf(a),
          ),
        );
        continue;
      }
      final before = issues.length;
      _validateThemeValueForSlot(a.expression, prop.type, issues);
      final value = _translateSlotValue(
        a.expression,
        prop.type,
        issues,
        property: prop,
      );
      if (value.isEmpty && issues.length > before) return '';
      // An asymmetric `BorderRadius` value (a direct `borderRadius:` arg, e.g.
      // ClipRRect) fans out onto the per-corner slots instead of the uniform
      // one — never a single `borderRadius:` carrying the sentinel.
      final beforeSplice = issues.length;
      final corners =
          _spliceBorderRadiusCorners(entry, value, issues, _locationOf(a));
      if (corners != null) {
        if (issues.length > beforeSplice) return '';
        emitted.addAll(corners);
        continue;
      }
      emitted.add('$name: $value');
    }

    // Detect string interpolation sentinel in Text's text argument. A
    // multi-segment interpolation is definitionally equivalent to
    // `Text.rich(TextSpan(children: ...))`: Flutter renders the same text run,
    // and the TextRich catalog entry is the supported Restage surface for
    // inline spans. Never emit the old test-only `RichText(spans: ...)` shape.
    if (entry.name == 'Text') {
      final interpolation = _rewriteInterpolatedText(
        emitted,
        anchor,
        issues,
        localIssueStart,
      );
      if (interpolation != null) return interpolation;
    }

    return '${entry.name}(${emitted.join(', ')})';
  }

  String? _rewriteInterpolatedText(
    List<String> emitted,
    Expression anchor,
    List<Issue> issues,
    int localIssueStart,
  ) {
    for (var i = 0; i < emitted.length; i++) {
      final emission = emitted[i];
      if (!emission.startsWith('text: ') ||
          !emission.contains('__rfw_interp(')) {
        continue;
      }
      final match =
          RegExp(r'__rfw_interp\((.*)\)$', dotAll: true).firstMatch(emission);
      if (match == null) continue;

      if (issues
          .skip(localIssueStart)
          .any((issue) => !issue.code.isInformational)) {
        return '';
      }

      final raw = match.group(1)!;
      final parts = splitTopLevelCommas(raw);
      if (parts.length == 1 && !parts.first.trimLeft().startsWith('"')) {
        final rest = List<String>.from(emitted)..removeAt(i);
        final allArgs = ['text: ${parts.first}', ...rest];
        return 'Text(${allArgs.join(', ')})';
      }

      final textRich = _textRichEntry(null);
      if (textRich == null) {
        issues.add(
          Issue(
            code: IssueCode.unknownWidget,
            capabilityGapSubject: 'widget:TextRich',
            message: "Widget 'TextRich' is not a known catalog widget. Add "
                'the Text.rich catalog entry before lowering interpolated '
                'Text spans.',
            location: _locationOf(anchor),
          ),
        );
        return '';
      }
      final textSpanProp = textRich.properties.firstWhereOrNull(
        (p) => p.name == 'textSpan' && p.type == PropertyType.inlineSpan,
      );
      if (textSpanProp == null) {
        issues.add(
          Issue(
            code: IssueCode.unknownProperty,
            message: "Catalog widget '${textRich.name}' must declare a "
                "'textSpan' PropertyType.inlineSpan slot before lowering "
                'interpolated Text spans.',
            location: _locationOf(anchor),
          ),
        );
        return '';
      }

      final textRichProps = {for (final p in textRich.properties) p.name};
      final rest = List<String>.from(emitted)..removeAt(i);
      for (final carried in rest) {
        final propName = _emittedPropertyName(carried);
        if (propName == null) {
          issues.add(
            Issue(
              code: IssueCode.unknownProperty,
              message: 'Interpolated Text could not identify emitted '
                  'property fragment `$carried`; the whole interpolation is '
                  'deferred.',
              location: _locationOf(anchor),
            ),
          );
          return '';
        }
        if (!_kTextInterpolationTextRichCarryProps.contains(propName)) {
          issues.add(
            Issue(
              code: IssueCode.unsupportedHelperPosition,
              message: 'Text with multi-segment string interpolation can '
                  'lower to ${textRich.name} only when every authored Text '
                  'property is in the closed carry set. Text.$propName would '
                  'not be carried, so the whole interpolation is deferred.',
              location: _locationOf(anchor),
            ),
          );
          return '';
        }
        if (!textRichProps.contains(propName)) {
          issues.add(
            Issue(
              code: IssueCode.unknownProperty,
              message: "Catalog widget '${textRich.name}' does not declare "
                  "carried Text property '$propName'; the whole interpolation "
                  'is deferred.',
              location: _locationOf(anchor),
            ),
          );
          return '';
        }
      }

      final spans = parts.map((p) => '{ text: $p }').join(', ');
      final outerArgs = [
        '${textSpanProp.name}: { children: [$spans] }',
        ...rest,
      ];
      return '${textRich.name}(${outerArgs.join(', ')})';
    }
    return null;
  }

  String? _emittedPropertyName(String emitted) {
    final colon = emitted.indexOf(': ');
    if (colon <= 0) return null;
    return emitted.substring(0, colon);
  }

  /// Inlines [helper]'s body at a call site, returning the translated body
  /// DSL. The call's arguments are bound to the helper's parameters 1:1
  /// (translator-strict — the same [bindHelperArguments] the classifier gated
  /// on); a parameter reference in the body then translates as its bound
  /// argument in the caller's context, so theme reads, arg references, and
  /// composed widgets lower identically to a hand-inlined body. A binding that
  /// is not provably 1:1 is a diagnosed defer, never a guessed inline (this
  /// should not occur — the classifier defers it first — but the translator
  /// re-checks rather than trust the classifier on a value-correctness gate).
  String _inlineHelperBody(
    HelperDef helper,
    MethodInvocation call,
    List<Issue> issues,
  ) {
    final binding = bindHelperArguments(
      helper.params,
      call.argumentList.arguments.toList(),
    );
    if (binding == null) {
      issues.add(
        Issue(
          code: IssueCode.customWidgetInliningDeferred,
          capabilityGapSubject: 'helper:${call.methodName.name}',
          message: "The helper '${call.methodName.name}' cannot be inlined: "
              'its arguments do not bind one-to-one to its parameters.',
          location: _locationOf(call),
        ),
      );
      return '';
    }
    final saved = _walk;
    _walk = _walk.copyWith(
      paramBindings: {..._walk.paramBindings, ...binding},
    );
    try {
      return _translate(helper.body, issues);
    } finally {
      _walk = saved;
    }
  }

  /// Inlines a class-4a custom widget when it is inlinable in this codegen
  /// increment — registering its RFW remote-widget definition (translating
  /// the blueprint's `build()` expression) and returning the call-site
  /// reference. Returns `null` when [classification] is not an inlinable-now
  /// [ComposableWidget] — a `4b`, a deferred-mechanism, or an unclassifiable
  /// widget — so the caller emits the classified diagnostic instead.
  ///
  /// "Inlinable now" means every required inlining mechanism is one this
  /// increment emits — composition (always), constant-folding, theme-as-data,
  /// and declarative state.
  String? _tryInlineCustomWidget(
    WidgetClassification classification,
    String key,
    NodeList<Expression> args,
    Expression anchor,
    List<Issue> issues,
  ) {
    if (classification is! ComposableWidget) return null;
    final unmet =
        classification.requiredMechanisms.difference(_kImplementedMechanisms);
    if (unmet.isNotEmpty) return null;
    final blueprint = customWidgetBlueprints[key];
    final definitions = _currentWidgetDefinitions;
    final definitionStates = _currentWidgetDefinitionStates;
    final owners = _currentDefinitionOwners;
    if (blueprint == null ||
        definitions == null ||
        definitionStates == null ||
        owners == null) {
      return null;
    }
    final name = blueprint.rfwName;

    // Resolve the RFW widget name. The first widget to claim a name registers
    // its definition; a name a *different* classKey already claimed, or one
    // that shadows a catalog widget, would make a reference in the blob
    // ambiguous — diagnose it rather than emit.
    final claimedBy = owners[name];
    if (claimedBy == null) {
      if (name == paywallRootWidgetName) {
        issues.add(
          _nameCollisionIssue(key, name, 'the paywall root widget'),
        );
        return '';
      }
      if (catalog.widgets.any((w) => w.name == name)) {
        issues.add(_nameCollisionIssue(key, name, 'the catalog widget'));
        return '';
      }
      // Validate State field initialisers BEFORE claiming the name: if any
      // field has a non-foldable initialiser, the widget cannot be inlined,
      // and we don't want a stale `owners` entry to make a sibling reference
      // think it succeeded. The diagnostic is surfaced at the translator —
      // the classifier captures fields broadly and leaves the strict-shape
      // check for this site.
      final shapeIssue = _validateStateShape(blueprint, anchor);
      if (shapeIssue != null) {
        issues.add(shapeIssue);
        return '';
      }
      owners[name] = key;
      // Register the body once. Translating it re-enters this method for
      // every custom widget the body composes, so the closure is emitted
      // transitively. The classifier rejects composition cycles
      // (→ UnclassifiableWidget), so the closure is acyclic and terminates.
      final saved = _walk;
      // A stateful blueprint always carries a (possibly empty) state list.
      // Marking the walk stateful here drives `widget.<X>` → `args.X` and
      // bare `<X>` → `state.X` lowerings in the body translation; the
      // stateless case keeps the null marker so neither lowering fires.
      final stateFields = blueprint.state;
      _walk = _walk.copyWith(
        argNames: blueprint.params.map((p) => p.name).toSet(),
        params: {for (final p in blueprint.params) p.name: p},
        classKey: blueprint.classKey,
        validatedCoalesceParams: {},
        stateFields: stateFields == null
            ? null
            : {for (final field in stateFields) field.name: field},
        eventHandlers: blueprint.eventHandlers,
        rootStateContext: false,
        inlined: blueprint.inlined,
      );
      try {
        definitions[name] = _translate(blueprint.buildExpression, issues);
        if (stateFields != null && stateFields.isNotEmpty) {
          definitionStates[name] = {
            for (final field in stateFields)
              field.name: _stateInitialLiteral(field),
          };
        }
      } finally {
        _walk = saved;
      }
    } else if (claimedBy != key) {
      issues.add(
        _nameCollisionIssue(key, name, 'another custom widget ($claimedBy)'),
      );
      return '';
    }

    // The call-site arguments translate in the caller's context — restored
    // above after any definition-body translation.
    return '$name(${_customWidgetCallArgs(blueprint, args, issues)})';
  }

  /// Diagnostic for a custom widget [key] whose emitted RFW name [name]
  /// collides with [conflict] — two widgets sharing one name make a
  /// reference in the emitted blob ambiguous.
  Issue _nameCollisionIssue(String key, String name, String conflict) {
    return Issue(
      code: IssueCode.customWidgetNameCollision,
      message: "The custom widget '$key' cannot be inlined: its RFW widget "
          "name '$name' collides with $conflict. Rename one of the widget "
          'classes so every inlined widget has a unique name.',
      location: key,
    );
  }

  /// Emits the call-site argument list for a custom-widget reference. Each
  /// [CustomWidgetBlueprint.params] entry becomes one argument — the value
  /// supplied at the call site (a named argument by label, a positional
  /// argument by formal index), or the parameter's constructor default when
  /// the call site omits it. A numeric parameter's value is coerced to a
  /// double literal; the `key:` argument is dropped.
  ///
  /// Theme-read / slot-type compatibility is NOT validated here: a custom
  /// widget's parameters carry no catalog property types (only a numeric
  /// flag), so there is no slot type to validate against. In resolved
  /// authoring the parameter's own Dart type bounds what a call site can
  /// supply; validation against catalog slot types happens where the value
  /// reaches a catalog widget's property inside the definition body.
  String _customWidgetCallArgs(
    CustomWidgetBlueprint blueprint,
    NodeList<Expression> args,
    List<Issue> issues,
  ) {
    // Collect the call-site expressions by parameter name — a named argument
    // by its label, a positional argument by the formal at its index. An
    // argument matching no parameter is dropped untranslated; in resolved
    // authoring the Dart constructor signature already rejects it.
    final supplied = <String, Expression>{};
    var positionalIndex = 0;
    for (final arg in args) {
      if (arg is NamedExpression) {
        final argName = arg.name.label.name;
        if (argName == 'key') continue;
        supplied[argName] = arg.expression;
      } else {
        if (positionalIndex < blueprint.params.length) {
          supplied[blueprint.params[positionalIndex].name] = arg;
        }
        positionalIndex++;
      }
    }
    // Emit one argument per parameter per the null-coalescing completion
    // table (a property the blueprint marked coalesced is `completion-required`
    // — its lowered fallback is cached under the definition's classKey):
    //   supplied value (not explicit null)      → the value         (row 4)
    //   supplied explicit `null`, coalesced      → the fallback       (row 3)
    //   omitted, constructor default exists      → the default        (row 1)
    //   omitted, no default, coalesced           → the fallback       (row 2)
    //   omitted, no default, not coalesced       → unbound (args.<name> = null)
    final emitted = <String>[];
    final fallbacks = _completionFallbacks[blueprint.classKey] ?? const {};
    for (final param in blueprint.params) {
      final suppliedExpr = supplied[param.name];
      final fallback = fallbacks[param.name];
      if (suppliedExpr != null) {
        if (fallback != null && _isNullLiteral(suppliedExpr)) {
          // Row 3: explicit `null` fires the `??` → the fallback.
          emitted.add('${param.name}: ${_coerceParamValue(param, fallback)}');
        } else {
          final lowered = _translateParamValue(param, suppliedExpr, issues);
          if (fallback != null &&
              (_isRuntimeMissing(suppliedExpr) ||
                  _lowersToMissableRef(lowered))) {
            // Gate 3: a passed value that can be MISSING at runtime — a
            // nullable-typed expression, OR one that lowers to a
            // possibly-missing data reference (`data.products.*` priced-only,
            // `data.context.*` host-omittable) — would fall to the factory
            // default instead of the author's fallback (the body's `??` is
            // rewritten away). Diagnosed defer, never a silent miss.
            issues.add(
              Issue(
                code: IssueCode.customWidgetUnsupportedReducible,
                message: "The optional property '${param.name}' of "
                    "'${blueprint.rfwName}' is completed with a `?? fallback` "
                    'default, but the value passed here can be missing at '
                    'runtime, so that default would be lost. Pass a value that '
                    'is always present, or omit the property.',
                location: _locationOf(suppliedExpr),
              ),
            );
          } else {
            // Row 4: a passed value, unchanged.
            emitted.add('${param.name}: $lowered');
          }
        }
      } else if (param.defaultValue != null) {
        // Row 1: omitted + constructor default — the `??` never fires; the
        // existing default-completion path, unchanged.
        final defaultLiteral = _foldedLiteral(param.defaultValue!);
        emitted.add(
          '${param.name}: ${_coerceParamValue(param, defaultLiteral)}',
        );
      } else if (fallback != null) {
        // Row 2: omitted, no default — the fallback.
        emitted.add('${param.name}: ${_coerceParamValue(param, fallback)}');
      }
    }
    return emitted.join(', ');
  }

  /// Whether [expr] is the literal `null` (through any parenthesis wrapping) —
  /// the explicit-null call-site form that, for a coalesced property, fires the
  /// `??` and completes with the fallback (distinct from an omitted argument
  /// with a constructor default).
  bool _isNullLiteral(Expression expr) => _stripParens(expr) is NullLiteral;

  /// Whether the call-site value [expr] passed to a coalesced property can be
  /// missing at runtime — a statically nullable expression (not the literal
  /// `null`, handled separately). With the body's `??` rewritten to a bare
  /// `args.<name>` read, a runtime-null passed value would resolve to the
  /// factory default instead of the author's fallback, so it is gated as a
  /// diagnosed defer rather than completed.
  bool _isRuntimeMissing(Expression expr) {
    final type = expr.staticType;
    return type != null && type.nullabilitySuffix == NullabilitySuffix.question;
  }

  /// Whether [lowered] is an RFW reference into a namespace whose value can be
  /// MISSING at render time: `data.products.*` (the SDK populates only priced
  /// products) and `data.context.*` (host-supplied, omittable). `data.theme.*`
  /// is always published, so it is present. Gate 3 defers a
  /// non-nullable-typed passed value that lowers to one of these — completing
  /// it into a coalesced property would resolve to the factory default instead
  /// of the author's fallback when the reference is absent.
  bool _lowersToMissableRef(String lowered) =>
      lowered.startsWith('data.products.') ||
      lowered.startsWith('data.context.');

  /// Translates a call-site value bound to [param] with the parameter's
  /// numeric coercion applied through the branches of a conditional — the
  /// parameter-level analogue of [_translateSlotValue]: a bare integer in
  /// either branch of a ternary bound to a numeric parameter must be
  /// normalised per branch or the definition body's `source.v<double>`
  /// decode silently nulls it.
  String _translateParamValue(
    CustomWidgetParam param,
    Expression expr,
    List<Issue> issues,
  ) {
    // Unwrap parens before the conditional check so a parenthesized ternary
    // bound to a parameter still applies the per-branch numeric coercion
    // (mirrors the slot path via [_resolveBoundIdentifier]).
    final stripped = _stripParens(expr);
    if (stripped is ConditionalExpression) {
      return _conditionalSwitch(
        stripped,
        issues,
        (branch) => _translateParamValue(param, branch, issues),
      );
    }
    return _coerceParamValue(param, _translate(stripped, issues));
  }

  /// Coerces a numeric parameter's [value] to a double literal — so it
  /// survives an rfw `source.v<double>` decode in the definition body — and
  /// passes a non-numeric parameter's value through unchanged.
  String _coerceParamValue(CustomWidgetParam param, String value) =>
      param.isNumeric ? asDoubleLiteral(value) : value;

  /// Translates a scalar bound to a `double`-decoded structured field (a
  /// border width, an `Offset`/`BorderRadius`/`BoxShadow` extent, an
  /// `EdgeInsets` edge, a gradient stop, …), coercing to a double literal —
  /// and, crucially, coercing INSIDE each branch when the value is a
  /// conditional. A bare-int branch would otherwise survive
  /// [asDoubleLiteral]: the assembled `switch state.X { … }` string contains a
  /// `.` (from `state.X`), so [asDoubleLiteral]'s `contains('.')` fast-path
  /// returns it unchanged and the runtime `source.v<double>` decode silently
  /// nulls the bare int. This is the structured-value analogue of the
  /// catalog-slot per-branch coercion in [_translateSlotValue]; routing
  /// through [_conditionalSwitch] also composes with the integer-state N-arm
  /// switch (each arm is double-coerced). Byte-identical to
  /// `_translateDoubleScalar(expr, issues)` for a non-conditional value.
  String _translateDoubleScalar(Expression expr, List<Issue> issues) {
    final stripped = _stripParens(expr);
    if (stripped is ConditionalExpression) {
      return _conditionalSwitch(
        stripped,
        issues,
        (branch) => _translateDoubleScalar(branch, issues),
      );
    }
    return asDoubleLiteral(_translate(stripped, issues));
  }

  /// Renders a State field's initial value as a DSL literal for the emitted
  /// `widget X { name: <literal>, … }` state block. A numeric field is
  /// coerced to a double literal so the binary form decodes through
  /// `source.v<double>` consistently with constructor-arg coercion. The
  /// caller has already validated that [CustomWidgetStateField.initialValue]
  /// is non-null via [_validateStateShape] — a null reaching here would be
  /// an internal contract violation, so we throw rather than silently emit
  /// a `null` literal.
  String _stateInitialLiteral(CustomWidgetStateField field) {
    final value = field.initialValue;
    if (value == null) {
      throw StateError(
        'State field "${field.name}" reached emission with a null initial '
        'value; _validateStateShape should have surfaced this earlier.',
      );
    }
    final literal = _foldedLiteral(value);
    return field.isNumeric ? asDoubleLiteral(literal) : literal;
  }

  /// Validates a stateful blueprint's State shape against the strict emit-
  /// time invariants: every primitive field has a folded initial value, and
  /// every event-handler tear-off referenced in build() has a recognised
  /// setState verdict. Returns the first issue found, or `null` when the
  /// blueprint is emit-safe. The classifier captures fields and handlers
  /// broadly (intentionally permissive); this emit-time check is the
  /// guarantor that no widget with an unrepresentable construct lands in
  /// the inlinable set.
  ///
  /// The setState verdicts are also checked at translation time (via
  /// `_emitSetStateHandler`), but doing the field check here is cheap and
  /// keeps the abort symmetric: any state-shape failure aborts before the
  /// owners map records the widget.
  Issue? _validateStateShape(
    CustomWidgetBlueprint blueprint,
    Expression anchor,
  ) {
    final state = blueprint.state;
    if (state == null) return null;
    final className = blueprint.rfwName;
    for (final field in state) {
      if (field.initialValue == null) {
        return Issue(
          code: IssueCode.stateShapeUnsupported,
          message: 'State field "${field.name}" in "$className" has an '
              'initialiser this transpiler increment cannot yet fold to a '
              'literal. Use a const value like `${_dartTypeHint(field)} '
              '${field.name} = ${_dartDefaultHint(field)};`.',
          location: _locationOf(anchor),
        );
      }
    }
    // An unrecognised event-handler verdict means the classifier accepted
    // the widget as 4a (any primitive State field qualifies), but the
    // recogniser found a method body the translator cannot emit. Surface
    // the diagnostic before any body translation so the failure points at
    // the specific method shape rather than at a fallback identifier
    // error.
    for (final entry in blueprint.eventHandlers.entries) {
      final verdict = entry.value;
      if (verdict is SetStateUnrecognised) {
        return _setStateUnrecognisedIssue(entry.key, verdict.reason, anchor);
      }
    }
    return null;
  }

  /// Validates root-source State material before translating the root
  /// expression. Root state uses the same strict emit-time rules as custom
  /// widget state: every field must have a concrete initial literal and every
  /// referenced State method must have a recognised `setState` verdict.
  Issue? _validateRootStateShape(
    List<CustomWidgetStateField>? state,
    Map<String, RecognisedSetState> eventHandlers,
    Expression anchor,
  ) {
    if (state == null) return null;
    for (final field in state) {
      if (field.initialValue == null) {
        return Issue(
          code: IssueCode.stateShapeUnsupported,
          message: 'Root State field "${field.name}" has an initialiser this '
              'transpiler increment cannot fold to a literal. Use a const '
              'bool, num, String, or enum value.',
          location: _locationOf(anchor),
        );
      }
    }
    for (final entry in eventHandlers.entries) {
      final verdict = entry.value;
      if (verdict is SetStateUnrecognised) {
        return _setStateUnrecognisedIssue(entry.key, verdict.reason, anchor);
      }
    }
    return null;
  }

  /// Author-facing type hint for the `stateShapeUnsupported` diagnostic's
  /// remediation example. Numeric fields render as `double`, everything
  /// else as `bool` — the two most common shapes; the message wording
  /// elides the rarer int / String / enum forms to stay concise.
  String _dartTypeHint(CustomWidgetStateField field) =>
      field.isNumeric ? 'double' : 'bool';

  /// Author-facing default-value hint for the `stateShapeUnsupported`
  /// diagnostic — `0.0` for numeric, `false` for everything else.
  String _dartDefaultHint(CustomWidgetStateField field) =>
      field.isNumeric ? '0.0' : 'false';

  /// Emits a `set state.<field> = <value>` event handler from the
  /// classifier-captured [verdict] for the State method named [methodName].
  /// A [SetStateLiteral] emits a folded scalar; a [SetStateBoolFlip] emits
  /// the no-negation `switch state.<field> { true: false, false: true }`
  /// form RFW data accepts. A [SetStateUnrecognised] becomes a
  /// `stateShapeUnsupported` diagnostic and an empty fragment so the build
  /// surfaces the issue and abandons the inlined widget.
  String _emitSetStateHandler(
    RecognisedSetState verdict,
    String methodName,
    List<Issue> issues,
    AstNode anchor,
  ) {
    switch (verdict) {
      case SetStateLiteral(:final fieldName, :final value):
        final field = _walk.stateFields?[fieldName];
        final literal = _foldedLiteral(value);
        final coerced =
            field?.isNumeric == true ? asDoubleLiteral(literal) : literal;
        return 'set state.$fieldName = $coerced';
      case SetStateBoolFlip(:final fieldName):
        return 'set state.$fieldName = switch state.$fieldName '
            '{ true: false, false: true }';
      case SetStateUnrecognised(:final reason):
        issues.add(_setStateUnrecognisedIssue(methodName, reason, anchor));
        return '';
    }
  }

  /// Builds the `stateShapeUnsupported` issue surfaced when a State method
  /// referenced as an event handler does not match the recognised
  /// single-assignment setState shape. Shared between the emit-time hit
  /// (`_emitSetStateHandler`) and the upfront validation path
  /// (`_validateStateShape`) so the wording stays in one place.
  Issue _setStateUnrecognisedIssue(
    String methodName,
    String reason,
    AstNode anchor,
  ) {
    return Issue(
      code: IssueCode.stateShapeUnsupported,
      message: 'State method "$methodName" is referenced as an event '
          'handler but its body is not a recognised setState shape '
          '(a single `setState(() => <field> = <literal>);` or '
          '`setState(() => <field> = !<field>);`). Specifically: '
          '$reason.',
      location: _locationOf(anchor),
    );
  }

  /// Lowers a Dart ternary `<cond> ? <then> : <else>` to an RFW `switch`.
  /// A bool condition (`state.X` / `args.X` of bool type, or a folded
  /// `true`/`false`) becomes the 2-arm `switch <cond> { true: …, false: … }`;
  /// an integer-state equality chain becomes a native N-arm switch (see
  /// [_conditionalSwitch] / [_tryIntStateEqualitySwitch]). Any other condition
  /// (a `&&`, an unrecognised expression, a non-equality int comparison)
  /// defers loud rather than emitting a degraded blob.
  String _conditionalExpression(
    ConditionalExpression expr,
    List<Issue> issues,
  ) =>
      _conditionalSwitch(expr, issues, (branch) => _translate(branch, issues));

  /// The single emission site for the conditional → `switch` lowering;
  /// [branch] renders each arm so slot-typed values can apply per-branch
  /// coercion ([_translateSlotValue]) while generic translation uses plain
  /// [_translate].
  ///
  /// Two condition shapes lower: a bool reference becomes the 2-arm
  /// `switch <ref> { true: …, false: … }`; an integer-state equality chain
  /// (`<intStateField> == <intLiteral>` nested through the else) becomes a
  /// native N-arm `switch state.<field> { <k>: …, …, default: … }` keyed on
  /// the int field ([_tryIntStateEqualitySwitch]).
  String _conditionalSwitch(
    ConditionalExpression expr,
    List<Issue> issues,
    String Function(Expression) branch,
  ) {
    final intSwitch = _tryIntStateEqualitySwitch(expr, issues, branch);
    if (intSwitch != null) return intSwitch;
    final cond = _translate(expr.condition, issues);
    final thenDsl = branch(expr.thenExpression);
    final elseDsl = branch(expr.elseExpression);
    return 'switch $cond { true: $thenDsl, false: $elseDsl }';
  }

  /// Attempts to lower [expr] — a conditional whose condition is an
  /// integer-state equality — to a native N-arm `switch` keyed on the int
  /// field. Returns the switch DSL when the condition is the supported
  /// `<intStateField> == <intLiteral>` shape (flattening consecutive
  /// SAME-field arms; a different-field terminal else recurses to its own
  /// nested switch via [branch], so two fields can never be mis-flattened into
  /// one switch's arm set). Returns `''` after emitting an
  /// [IssueCode.intStateConditionUnsupported] diagnostic when the condition is
  /// a comparison INVOLVING an int state field but not that exact shape
  /// (`!=`/`<`/`>`, a non-literal RHS, the literal-on-the-left form). Returns
  /// `null` when the condition is not an int-state comparison at all, so the
  /// caller falls back to the bool path.
  String? _tryIntStateEqualitySwitch(
    ConditionalExpression expr,
    List<Issue> issues,
    String Function(Expression) branch,
  ) {
    final cond = _stripParens(expr.condition);
    final head = _intStateEquality(cond);
    if (head == null) {
      if (cond is BinaryExpression && _comparisonInvolvesIntStateField(cond)) {
        issues.add(
          Issue(
            code: IssueCode.intStateConditionUnsupported,
            message: 'Only `<intStateField> == <intLiteral>` equality '
                'comparisons on an integer state field lower to a switch in '
                'this transpiler increment (with the field on the left and an '
                'integer literal on the right). `!=`, `<`, `>`, a non-literal '
                'comparison, and the literal-on-the-left form are not yet '
                'supported — express the selection as an equality chain '
                '(`field == 0 ? … : field == 1 ? … : …`).',
            location: _locationOf(cond),
          ),
        );
        return '';
      }
      return null;
    }

    // Flatten consecutive SAME-field `== <intLiteral>` arms into one switch.
    final fieldName = head.field.name;
    final arms = <String>[];
    Expression? defaultBranch;
    ConditionalExpression? current = expr;
    while (current != null) {
      final match = _intStateEquality(_stripParens(current.condition));
      if (match == null || match.field.name != fieldName) {
        // The else chain reached a condition that is not `<sameField> ==
        // <intLiteral>` — this conditional (a different-field comparison, a
        // bool ref, …) is the default; [branch] lowers it normally, so a
        // different-field comparison recurses to its own nested switch.
        defaultBranch = current;
        break;
      }
      arms.add('${match.key}: ${branch(current.thenExpression)}');
      final elseExpr = _stripParens(current.elseExpression);
      if (elseExpr is ConditionalExpression) {
        current = elseExpr;
      } else {
        defaultBranch = current.elseExpression;
        current = null;
      }
    }
    final defaultDsl = branch(defaultBranch!);
    final armsDsl = arms.join(', ');
    return 'switch state.$fieldName { $armsDsl, default: $defaultDsl }';
  }

  /// The root integer State field [expr] (through parens) references, or
  /// `null` when it is not such a reference. An integer State field is the
  /// element-resolved root field (never a shadowing local) captured
  /// `isNumeric: false` (only `double`/`num` are numeric) with an `int`
  /// initial value — so it emits as a bare int and a switch keys on int
  /// literals. The single source of truth for "what counts as an int state
  /// field", shared by the equality decomposition and the near-miss check.
  CustomWidgetStateField? _intStateFieldOf(Expression expr) {
    final e = _stripParens(expr);
    if (e is! SimpleIdentifier) return null;
    if (e.element is LocalVariableElement) return null;
    final field = _walk.stateFields?[e.name];
    if (field == null || field.isNumeric || field.initialValue is! int) {
      return null;
    }
    return field;
  }

  /// The `(field, key)` of an `<intStateField> == <intLiteral>` comparison —
  /// the int State field on the left, an integer literal on the right — or
  /// `null` for any other shape.
  ({CustomWidgetStateField field, String key})? _intStateEquality(
    Expression cond,
  ) {
    if (cond is! BinaryExpression || cond.operator.lexeme != '==') return null;
    final field = _intStateFieldOf(cond.leftOperand);
    if (field == null) return null;
    final right = _stripParens(cond.rightOperand);
    if (right is! IntegerLiteral) return null;
    final value = right.value;
    if (value == null) return null;
    return (field: field, key: value.toString());
  }

  /// Whether [cond] is a comparison (`==`/`!=`/`<`/`>`/`<=`/`>=`) with an
  /// integer state field on either side — used to surface the named
  /// "equality-only this increment" defer for a near-miss instead of the
  /// generic unsupported-expression error.
  bool _comparisonInvolvesIntStateField(BinaryExpression cond) {
    const comparisonOps = {'==', '!=', '<', '>', '<=', '>='};
    if (!comparisonOps.contains(cond.operator.lexeme)) return false;
    return _intStateFieldOf(cond.leftOperand) != null ||
        _intStateFieldOf(cond.rightOperand) != null;
  }

  /// Translates a value bound to a slot of [type] with the slot's coercion
  /// applied through the branches of a conditional: each branch feeds the
  /// same slot, so a bare integer in either branch of a ternary bound to a
  /// `length` / `real` slot is normalised to a double literal exactly like
  /// a direct value — coercing the assembled `switch` string would miss
  /// the branch literals and the runtime decode would silently null them.
  /// Any other value translates and coerces as a unit.
  String _translateSlotValue(
    Expression expr,
    PropertyType type,
    List<Issue> issues, {
    PropertyEntry? property,
  }) {
    // Null-coalescing optional property — `<prop> ?? <fallback>`. Handled ahead
    // of the type-special dispatch so the slot value is `args.<prop>` without
    // the catalog coercion mangling the reference. The fallback was validated
    // against this slot in `_validateThemeValueForSlot` before the rewrite.
    final coalesce = _coalesceParamAt(expr);
    if (coalesce != null) {
      return _translateCoalesce(coalesce, issues);
    }
    // Resolve a named-intermediate binding (helper param / `final` local)
    // BEFORE the type-special dispatch below: the `alignmentXY` branch calls
    // `_structured.alignmentGeometry` directly rather than `_translate`,
    // so a bound reference used in such a slot would otherwise bypass the
    // resolve-through and over-claim. Inert outside inlining (both maps empty).
    final resolved = _resolveBoundIdentifier(expr);
    if (resolved is ConditionalExpression) {
      return _conditionalSwitch(
        resolved,
        issues,
        (branch) => _translateSlotValue(
          branch,
          type,
          issues,
          property: property,
        ),
      );
    }
    // A const-object field at a slot — resolve it BEFORE the type-special
    // dispatch below, because the `alignmentXY` / `enumValue` branches call
    // their shared emitters directly (not `_translate`, where the main
    // const-object hook lives). This mirrors that hook so the slot-specific
    // lowering applies to the FOLDED value, keeping the classifier (which tags
    // such a field foldable) and the translator from diverging: β re-dispatch
    // the bound initializer through this same slot path; α fold a scalar
    // (coerced to the slot); else loud-defer — never a bare field name.
    if (isConstObjectFieldAccess(resolved)) {
      final initializer = resolveConstObjectFieldInitializer(resolved);
      if (initializer != null) {
        return _translateSlotValue(
          initializer,
          type,
          issues,
          property: property,
        );
      }
      final scalar = tryScalarFoldConstObjectField(resolved);
      if (scalar != null) {
        return _coerceForPropertyType(type, _foldedLiteral(scalar));
      }
      issues.add(_constObjectFieldUnresolvedIssue(resolved));
      return '';
    }
    // A concrete-`Alignment` slot (`alignmentXY`) decodes a `{x, y}` map
    // (`RestageDecoders.alignmentXY`), so a Dart-source `Alignment.<member>`
    // / `Alignment(x, y)` must lower to that map HERE rather than fall
    // through to the generic enum-string path — which would emit a bare
    // member name the runtime decoder nulls (a silent drop to the default).
    // The shared, element-gated `_structured.alignmentGeometry` does the
    // lowering: it value-asserts the member coordinates, defers a resolved
    // customer `Alignment` look-alike with a diagnostic (never the substituted
    // value or a bare string), and diagnoses `AlignmentDirectional` /
    // unsupported members.
    if (type == PropertyType.alignmentXY) {
      return _structured.alignmentGeometry(resolved, issues, _locationOf(expr));
    }
    if (type == PropertyType.enumValue && property != null) {
      final enumValue = _enumValueSlot(resolved, property, issues);
      if (enumValue != null) return enumValue;
    }
    return _coerceForPropertyType(type, _translate(resolved, issues));
  }

  /// Slot-aware generic enum lowering. The context-free fallback at
  /// `_prefixedIdentifier` preserves unresolved synthetic expression tests, but
  /// a catalog `enumValue` slot has enough identity to be stricter: the member
  /// must resolve to the enum type the catalog names, and the emitted name must
  /// be present on that same resolved declaration. The generated decoder uses
  /// `ArgumentDecoders.enumValue<T>(T.values, ...)`, so the analyzer
  /// declaration is the same-build decoder vocabulary; OTA capability skew is
  /// a delivery-side floor, not a per-blob guess.
  String? _enumValueSlot(
    Expression expr,
    PropertyEntry property,
    List<Issue> issues,
  ) {
    if (property.valueShape is! EnumShape && property.enumType == null) {
      return null;
    }
    if (expr is! PrefixedIdentifier && expr is! PropertyAccess) return null;

    final memberName = _enumMemberName(expr);
    if (memberName == null) return null;

    final resolvedMember = _unwrapPropertyAccessor(_enumMemberElement(expr));
    final memberOwner = resolvedMember is FieldElement &&
            resolvedMember.isEnumConstant &&
            resolvedMember.enclosingElement is EnumElement
        ? resolvedMember.enclosingElement as EnumElement
        : null;

    final targetOwner = memberOwner ?? _enumTargetOwner(expr);
    if (targetOwner == null) {
      _addEnumSlotIssue(
        expr,
        property,
        issues,
        "Enum value '${expr.toSource()}' for slot '${property.name}' must "
        'resolve to ${_expectedEnumDescription(property)}.',
      );
      return '';
    }

    if (!_enumOwnerMatchesProperty(targetOwner, property)) {
      _addEnumSlotIssue(
        expr,
        property,
        issues,
        "Enum value '${expr.toSource()}' for slot '${property.name}' resolves "
        'to ${_enumDescription(targetOwner)}, but the slot expects '
        '${_expectedEnumDescription(property)}.',
      );
      return '';
    }

    final members = {
      for (final field in targetOwner.fields)
        if (field.isEnumConstant) field.name,
    };
    if (!members.contains(memberName)) {
      _addEnumSlotIssue(
        expr,
        property,
        issues,
        "Enum member '${expr.toSource()}' is not declared on "
        "${_enumDescription(targetOwner)} for slot '${property.name}'.",
      );
      return '';
    }

    return '"$memberName"';
  }

  void _addEnumSlotIssue(
    Expression expr,
    PropertyEntry property,
    List<Issue> issues,
    String message,
  ) {
    issues.add(
      Issue(
        code: IssueCode.unresolvedIdentifier,
        message: message,
        location: _locationOf(expr),
      ),
    );
  }

  Element? _unwrapPropertyAccessor(Element? element) =>
      element is PropertyAccessorElement ? element.variable : element;

  Element? _enumMemberElement(Expression expr) {
    if (expr is PrefixedIdentifier) return expr.identifier.element;
    if (expr is PropertyAccess) return expr.propertyName.element;
    return null;
  }

  String? _enumMemberName(Expression expr) {
    if (expr is PrefixedIdentifier) return expr.identifier.name;
    if (expr is PropertyAccess) return expr.propertyName.name;
    return null;
  }

  EnumElement? _enumTargetOwner(Expression expr) {
    Element? target;
    if (expr is PrefixedIdentifier) {
      target = expr.prefix.element;
    } else if (expr is PropertyAccess) {
      final receiver = expr.target;
      if (receiver is SimpleIdentifier) {
        target = receiver.element;
      } else if (receiver is PrefixedIdentifier) {
        target = receiver.identifier.element ?? receiver.prefix.element;
      } else if (receiver is PropertyAccess) {
        target = receiver.propertyName.element;
      }
    }
    final resolved = _unwrapPropertyAccessor(target);
    return resolved is EnumElement ? resolved : null;
  }

  bool _enumOwnerMatchesProperty(
    EnumElement owner,
    PropertyEntry property,
  ) {
    final expectedShape = property.valueShape;
    final actual = _dartTypeRefOfEnum(owner);
    if (expectedShape is EnumShape) return actual == expectedShape.enumRef;
    final enumType = property.enumType;
    return enumType != null && owner.name == enumType;
  }

  DartTypeRef _dartTypeRefOfEnum(EnumElement owner) {
    final libraryUri = owner.library.identifier;
    return DartTypeRef(libraryUri: libraryUri, symbolName: owner.name ?? '');
  }

  String _expectedEnumDescription(PropertyEntry property) {
    final shape = property.valueShape;
    if (shape is EnumShape) return _dartTypeRefDescription(shape.enumRef);
    return property.enumType ?? '<unknown enum>';
  }

  String _enumDescription(EnumElement owner) =>
      _dartTypeRefDescription(_dartTypeRefOfEnum(owner));

  String _dartTypeRefDescription(DartTypeRef ref) =>
      '${ref.libraryUri}#${ref.symbolName}';

  /// Resolves [expr] through parenthesis wrapping AND any active
  /// named-intermediate binding — a helper parameter or a leading `final`
  /// local resolved to its bound expression — so a slot path that does NOT
  /// route through [_translate] (e.g. the `alignmentXY` branch of
  /// [_translateSlotValue], which pattern-matches on the resolved expression's
  /// type) still sees the underlying value, not a bare reference or a
  /// parenthesis-wrapped form. Looping unwraps parens and follows a chain of
  /// bound locals together; returns [expr] unchanged when it is neither
  /// parenthesized nor a bound identifier — so outside an inline (both binding
  /// maps empty) it only strips parens.
  Expression _resolveBoundIdentifier(Expression expr) {
    var current = expr;
    while (true) {
      if (current is ParenthesizedExpression) {
        current = current.expression;
        continue;
      }
      if (current is SimpleIdentifier) {
        final bound = _walk.paramBindings[current.element] ??
            _walk.inlined.localBindings[current.element];
        if (bound == null) break;
        current = bound;
        continue;
      }
      break;
    }
    return current;
  }

  /// If [expr] is `<own coalesced property> ?? <fallback>` — a `??` whose left
  /// reads a property the blueprint marked coalesced — returns the property's
  /// `read` (lowered to `args.<name>`), its `name`, and the `fallback`
  /// expression. The blueprint's `coalesceFallback` marker is the
  /// translator-strict gate: only a property the classifier recognised as
  /// coalesced is rewritten. Returns null otherwise.
  ({String name, Expression read, Expression fallback})? _coalesceParamAt(
    Expression expr,
  ) {
    if (expr is! BinaryExpression || expr.operator.lexeme != '??') return null;
    final left = expr.leftOperand;
    final read = left is ParenthesizedExpression ? left.expression : left;
    String? name;
    if (read is SimpleIdentifier) {
      name = read.name;
    } else if (read is PrefixedIdentifier && read.prefix.name == 'widget') {
      name = read.identifier.name;
    }
    if (name == null) return null;
    if (_walk.params[name]?.coalesceFallback == null) return null;
    return (name: name, read: read, fallback: expr.rightOperand);
  }

  /// Lowers a recognised `<prop> ?? <fallback>` to `args.<prop>` and caches the
  /// fallback's lowered value (once per property, under the definition's
  /// classKey) for call-site completion. Gate 1 guarantees an identical
  /// fallback at every read of the property, so the first-seen lowering is the
  /// canonical one.
  String _translateCoalesce(
    ({String name, Expression read, Expression fallback}) coalesce,
    List<Issue> issues,
  ) {
    // The body rewrite (`prop ?? f` → `args.prop`) is sound only when `f` was
    // kind-validated against this slot. The catalog-slot + native-decompose
    // paths validate before translating (recording the property below); a `??`
    // reached through a hand-authored structured-value translator that calls
    // `_translate` directly was NOT validated — defer rather than hoist an
    // unchecked fallback.
    if (!_walk.validatedCoalesceParams.contains(coalesce.name)) {
      issues.add(
        Issue(
          code: IssueCode.customWidgetUnsupportedReducible,
          capabilityGapSubject: 'customWidgetPropertyFallback:${coalesce.name}',
          message: "The optional property '${coalesce.name}' is coalesced "
              '(`?? <fallback>`) in a value position this transpiler increment '
              'cannot validate the fallback against. Use the property in a '
              'catalog-widget slot, or set it via the constructor.',
          location: _locationOf(coalesce.read),
        ),
      );
      return '';
    }
    _completionFallbacks
        .putIfAbsent(_walk.classKey!, () => <String, String>{})
        .putIfAbsent(
          coalesce.name,
          () => _translate(coalesce.fallback, issues),
        );
    return _translate(coalesce.read, issues);
  }

  /// Builds the diagnostic for a recognised custom widget referenced in a
  /// paywall, from its [classification].
  Issue _customWidgetIssue(
    WidgetClassification classification,
    String widgetName,
    Expression anchor,
  ) {
    switch (classification) {
      case ComposableWidget():
        final mechanisms = classification.requiredMechanisms;
        final note = mechanisms.isEmpty
            ? ''
            : ' (needs ${mechanisms.map((m) => m.name).join(", ")})';
        return Issue(
          code: IssueCode.customWidgetInliningDeferred,
          capabilityGapSubject: 'customWidget:$widgetName',
          message: "The custom widget '$widgetName' is recognised as pure "
              'composition$note, but it needs an inlining mechanism this '
              'transpiler increment does not yet implement.',
          location: _locationOf(anchor),
        );
      case ImperativeWidget():
        // Disposition split: a genuine RFW boundary (dead end) reads
        // "cannot express"; an all-reducible-blocker widget reads "not
        // supported yet" so it isn't mis-sold as inherently imperative. Same
        // deferred blob behaviour either way; the code + verb carry the
        // distinction.
        if (classification.disposition == CustomWidgetDisposition.deadEnd) {
          final blocker = classification.blockers.firstWhere(
            (b) => b.disposition == CustomWidgetDisposition.deadEnd,
          );
          return Issue(
            code: IssueCode.customWidgetImperative,
            message: "The custom widget '$widgetName' cannot be transpiled "
                'into a paywall: its build() uses ${blocker.detail}, which the '
                'declarative paywall format cannot express '
                '(${blocker.kind.name}).',
            location: blocker.location,
          );
        }
        final blocker = classification.blockers.first;
        return Issue(
          code: IssueCode.customWidgetUnsupportedReducible,
          capabilityGapSubject: 'customWidget:$widgetName',
          message: "The custom widget '$widgetName' is not supported by this "
              'transpiler increment yet: its build() uses ${blocker.detail} '
              '(${blocker.kind.name}). It is not inherently imperative — a '
              'future catalog / recipe / state-authoring increment may make it '
              'expressible.',
          location: blocker.location,
        );
      case UnclassifiableWidget():
        return Issue(
          code: classification.diagnosticCode,
          capabilityGapSubject: 'customWidget:$widgetName',
          message: "The custom widget '$widgetName' is recognised but this "
              'transpiler increment does not yet classify it: '
              '${classification.reason}.',
          location: _locationOf(anchor),
        );
    }
  }

  /// Splits a comma-separated argument list at the top level only, respecting
  /// nested parentheses, brackets, and quoted strings. Used to decompose the
  /// `__rfw_interp(...)` sentinel without breaking on commas inside nested
  /// expressions or quoted strings.
  @visibleForTesting
  static List<String> splitTopLevelCommas(String input) {
    final out = <String>[];
    var depth = 0;
    var inString = false;
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      // Toggle string mode on a real string boundary.
      // Count consecutive backslashes immediately before this quote:
      // an odd count means the quote is escaped (`\"`); an even count
      // means it is a real boundary (`\\"` or just `"`).
      if (ch == '"') {
        var backslashes = 0;
        for (var j = i - 1; j >= 0 && input[j] == r'\'; j--) {
          backslashes++;
        }
        if (backslashes.isEven) {
          inString = !inString;
        }
      }
      if (!inString) {
        if (ch == '(' || ch == '[' || ch == '{') depth++;
        if (ch == ')' || ch == ']' || ch == '}') depth--;
        if (ch == ',' && depth == 0) {
          out.add(buffer.toString().trim());
          buffer.clear();
          continue;
        }
      }
      buffer.write(ch);
    }
    if (buffer.isNotEmpty) out.add(buffer.toString().trim());
    return out;
  }

  /// Whether [expr] is a framework-or-unresolved `BorderRadius.{only,vertical,
  /// horizontal,all}` construction (in either AST shape). The decompose
  /// interception gate (the `.circular` form is deliberately excluded so it
  /// keeps flowing the frozen construct-variant transform byte-identically).
  /// Name-based — `_translate` re-applies the value-substitution framework
  /// gate, so a resolved customer `BorderRadius` look-alike still defers there.
  bool _isAsymmetricBorderRadiusCtor(Expression expr) {
    final stripped = _stripParens(expr);
    final String className;
    final String? ctorName;
    if (stripped is InstanceCreationExpression) {
      className = _instanceCreationTypeName(stripped);
      ctorName = _instanceCreationMemberName(stripped);
    } else if (stripped is MethodInvocation) {
      final target = stripped.target;
      if (target is! SimpleIdentifier) return false;
      className = target.name;
      ctorName = stripped.methodName.name;
    } else {
      return false;
    }
    return className == 'BorderRadius' &&
        _kAsymmetricBorderRadiusCtors.contains(ctorName);
  }

  /// Fans a per-corner BorderRadius [value] out onto [entry]'s per-corner
  /// catalog slots. Returns `null` when [value] is not the per-corner sentinel
  /// (the caller emits it as the uniform slot value). On a hit, returns the
  /// `'<property>: <dsl>'` emissions for the corners the author set — only the
  /// SET corners; an omitted corner reconstructs to `Radius.zero`. The widget
  /// must declare all four per-corner slots (mirroring the reconstruction's
  /// all-four-or-none convention); if it does not, the asymmetric radius is not
  /// representable here, so a loud issue is added and `const []` returned — the
  /// sentinel never leaks into the emitted blob.
  List<String>? _spliceBorderRadiusCorners(
    WidgetEntry entry,
    String value,
    List<Issue> issues,
    String loc,
  ) {
    final isCleanSentinel =
        value.startsWith(_kBorderRadiusCornerSentinel) && value.endsWith(')');
    if (!isCleanSentinel) {
      // Close the class by construction: the sentinel is an internal marker
      // that must NEVER reach the blob. A value that CONTAINS it but isn't a
      // clean top-level sentinel means the asymmetric BorderRadius was wrapped
      // in another expression the splice can't fan out — e.g. a conditional on
      // a direct slot (`cond ? BorderRadius.only(..) : circular(..)`) lowers to
      // a `switch {.. <sentinel> ..}`. Defer the whole value loudly rather than
      // leak the sentinel; never a partial or wrong emit.
      if (value.contains(_kBorderRadiusCornerSentinel)) {
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message: 'An asymmetric BorderRadius cannot be combined with a '
                'conditional (or other expression) at this slot — it must be a '
                'direct BorderRadius.only/.vertical/.horizontal. Move the '
                'condition inside each corner radius value instead.',
            location: loc,
          ),
        );
        return const [];
      }
      return null;
    }
    // Membership keyed on the `borderRadiusCorner` synthetic + the property
    // name — the same discovery the reconstruction side uses (factory_emitter
    // `_borderRadiusCornersOf`), so the two halves can't drift apart.
    final hasAllCorners = _kBorderRadiusCornerProperty.values.every(
      (name) => entry.properties.any(
        (p) => p.name == name && p.synthetic == _kBorderRadiusCornerSynthetic,
      ),
    );
    if (!hasAllCorners) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'An asymmetric BorderRadius is not representable on '
              "'${entry.name}' (it has no per-corner radius slots). Use "
              'BorderRadius.circular(...) for a uniform radius.',
          location: loc,
        ),
      );
      return const [];
    }
    final inner = value.substring(
      _kBorderRadiusCornerSentinel.length,
      value.length - 1,
    );
    if (inner.trim().isEmpty) return const [];
    final out = <String>[];
    for (final part in splitTopLevelCommas(inner)) {
      final sep = part.indexOf(': ');
      final corner = sep < 0 ? part : part.substring(0, sep);
      final property = _kBorderRadiusCornerProperty[corner];
      if (sep < 0 || property == null) {
        // The sentinel is produced solely by our own recognition, so this is
        // unreachable in practice; guard rather than emit a malformed slot.
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message: 'Malformed BorderRadius per-corner value.',
            location: loc,
          ),
        );
        return const [];
      }
      out.add('$property: ${part.substring(sep + 2)}');
    }
    return out;
  }

  /// Coerces a translated literal to match the rfw runtime decoder for the
  /// catalog property type. Today the only coercion is `length` / `real` →
  /// double literal: rfw's `source.v<double>(...)` strict-casts and would
  /// silently null a bare integer like `24`, dropping the slot. Other slot
  /// types pass through unchanged.
  String _coerceForPropertyType(PropertyType type, String value) {
    switch (type) {
      case PropertyType.length:
      case PropertyType.real:
        return asDoubleLiteral(value);
      // Non-numeric / structured slots pass through unchanged. Listing
      // them out would add no information beyond `default:`, and the
      // double-coercion contract is naturally narrow.
      // ignore: no_default_cases
      default:
        return value;
    }
  }

  /// Validates a contract theme read supplied as the value of a slot of
  /// [type] — through any parenthesis wrapping and through both branches of
  /// a conditional (each branch feeds the same slot). Deliberately does not
  /// descend into nested constructions or collection literals: their values
  /// are validated at their own property sites. An out-of-contract read is
  /// not re-diagnosed here — the theme-read lowering already fails it closed
  /// with its own diagnostic.
  void _validateThemeValueForSlot(
    Expression source,
    PropertyType type,
    List<Issue> issues,
  ) {
    var current = source;
    while (current is ParenthesizedExpression) {
      current = current.expression;
    }
    if (current is ConditionalExpression) {
      _validateThemeValueForSlot(current.thenExpression, type, issues);
      _validateThemeValueForSlot(current.elseExpression, type, issues);
      return;
    }
    // Null-coalescing optional property — `<prop> ?? <fallback>`. The fallback
    // is hoisted to the call site for completion, so it never reaches a body
    // slot to be validated there; validate it against THIS slot's type here,
    // before the rewrite, exactly as if it were written directly.
    final coalesce = _coalesceParamAt(current);
    if (coalesce != null) {
      _validateThemeValueForSlot(coalesce.fallback, type, issues);
      // Record that this property's fallback was validated against a slot —
      // the body rewrite is sound only for validated coalesced reads (see
      // [_translateCoalesce]).
      _walk.validatedCoalesceParams.add(coalesce.name);
      return;
    }
    // Binding-aware: a `scheme.primary` fallback is a PrefixedIdentifier, not a
    // PropertyAccess — `_recognizeThemeRead` resolves it through the active
    // theme-local bindings, so a PropertyAccess-only guard would silently skip
    // it and bypass this kind check.
    final segments = _recognizeThemeRead(current);
    if (segments == null) return;
    final kind = kThemeContractPathKinds[segments.join('.')];
    if (kind == null) return;
    if (propertyTypeAcceptsThemeKind(type, kind)) return;
    issues.add(
      Issue(
        code: IssueCode.propertyValueTypeMismatch,
        message: "Theme value 'data.theme.${segments.join('.')}' cannot be "
            "assigned to a '${type.name}' property type at this site.",
        location: _locationOf(current),
      ),
    );
  }

  String _locationOf(AstNode node) {
    final path = _currentSourcePath ?? '<unknown>';
    final li = _currentLineInfo;
    if (li == null) {
      return '$path (offset ${node.offset})';
    }
    final loc = li.getLocation(node.offset);
    return '$path:${loc.lineNumber}:${loc.columnNumber}';
  }

  /// Returns the canonical `'<library URI>#<class name>[.<ctor name>]'` for
  /// the type being constructed in [expr], or `null` when the analyzer
  /// couldn't resolve it (typical for synthetic test inputs without imports).
  String? _flutterTypeOfInstanceCreation(InstanceCreationExpression expr) {
    final cls = _classOfInstanceCreation(expr);
    if (cls == null) return null;
    return _flutterTypeOfClass(
      cls,
      constructorName: expr.constructorName.name?.name,
    );
  }

  /// The resolved [ClassElement] behind an `InstanceCreationExpression`, or
  /// `null` when the analyzer could not resolve it.
  ClassElement? _classOfInstanceCreation(InstanceCreationExpression expr) {
    final element = expr.constructorName.type.element;
    return element is ClassElement ? element : null;
  }

  /// The resolved [ClassElement] behind a bare `Foo(...)` call, or `null`
  /// when the analyzer could not resolve it to a constructor.
  ClassElement? _classOfMethodInvocation(MethodInvocation expr) {
    final element = expr.methodName.element;
    if (element is! ConstructorElement) return null;
    final cls = element.enclosingElement;
    return cls is ClassElement ? cls : null;
  }

  /// Returns the canonical `'<library URI>#<class name>'` for the class
  /// behind a bare `Foo()` call, or `null` when unresolved.
  String? _flutterTypeOfMethodInvocation(MethodInvocation expr) {
    final cls = _classOfMethodInvocation(expr);
    return cls == null ? null : _flutterTypeOfClass(cls);
  }

  String? _flutterTypeOfClass(ClassElement cls, {String? constructorName}) {
    final libraryUri = cls.library.identifier;
    final className = cls.name;
    if (className == null || className.isEmpty) return null;
    final constructorSuffix = constructorName == null || constructorName.isEmpty
        ? ''
        : '.$constructorName';
    return '$libraryUri#$className$constructorSuffix';
  }

  /// Returns hoisted flat-property emissions when [expr] matches a native
  /// decomposition recipe for [entry]'s constructor argument [argName].
  List<String>? _tryDecompose(
    WidgetEntry entry,
    String argName,
    Expression expr,
    List<Issue> issues,
  ) {
    if (entry.decomposes.isEmpty) return null;

    final relevantRecipes =
        entry.decomposes.where((r) => r.targetArg == argName).toList();
    if (relevantRecipes.isEmpty) return null;
    final candidateRecipes =
        relevantRecipes.where((r) => r.construction != null).toList();
    if (candidateRecipes.length != relevantRecipes.length) {
      issues.add(
        Issue(
          code: IssueCode.unknownProperty,
          message: "Native decomposition for '${entry.name}.$argName' is "
              'missing native construction metadata.',
          location: _locationOf(expr),
        ),
      );
      return const [];
    }

    final index = _nativeCatalogIndex;
    for (final recipe in candidateRecipes) {
      final construction = recipe.construction!;

      final structured = index.structuredByRef(recipe.structuredRef);
      final variant = index.variantByRef(construction.variantRef);
      if (structured == null || variant == null) continue;

      final match = _matchNativeInvocation(
        expr,
        construction,
        owningWidget: entry,
        resultStructured: structured,
        variant: variant,
      );
      if (match == null) continue;

      final out = <String>[];
      final mappedFields = recipe.fieldMappings.map((m) => m.fieldRef).toSet();
      final mappedArguments = <String>{};
      for (final mapping in recipe.fieldMappings) {
        final sourceExpr = match.fieldExpressions[mapping.fieldRef];
        if (sourceExpr == null) continue;
        final destProp =
            index.widgetProperty(_widgetRef(entry), mapping.propertyRef);
        if (destProp == null) continue;
        // Validate against the destination slot BEFORE translating, so a
        // coalesced `??` fallback is recorded as validated before the body
        // rewrite (see [_translateCoalesce] / [_walk.validatedCoalesceParams]).
        _validateThemeValueForSlot(sourceExpr, destProp.type, issues);
        // Precise funnel: an asymmetric / `.all` `BorderRadius` hoisted through
        // the uniform `borderRadius` field cannot pass the frozen circular-only
        // construct-variant transform. Route those specific ctors through the
        // shared recognition + per-corner splice BEFORE the transform rejects
        // them; `.circular` still flows the existing transform byte-stably.
        if (destProp.synthetic == _kBorderRadiusCircularSynthetic &&
            _isAsymmetricBorderRadiusCtor(sourceExpr)) {
          final before = issues.length;
          final translated = _translate(sourceExpr, issues);
          final hadError =
              issues.skip(before).any((i) => !i.code.isInformational);
          if (translated.isEmpty || hadError) continue;
          final corners = _spliceBorderRadiusCorners(
            entry,
            translated,
            issues,
            _locationOf(sourceExpr),
          );
          if (corners != null) {
            out.addAll(corners);
          } else {
            // `.all(Radius.circular(..))` is the uniform form: emit the scalar
            // onto the uniform slot, exactly as the circular transform would.
            out.add(
              '${destProp.name}: '
              '${_coerceForPropertyType(destProp.type, translated)}',
            );
          }
          continue;
        }
        final translated = _decompositionValue(
          mapping.transform,
          sourceExpr,
          owningWidget: entry,
          destination: destProp,
          issues: issues,
        );
        if (translated == null) continue;
        final value = _coerceForPropertyType(destProp.type, translated);
        out.add('${destProp.name}: $value');
      }
      for (final mapping in recipe.parameterMappings) {
        final sourceExpr = match.parameterExpressions[mapping.parameterRef];
        if (sourceExpr == null) continue;
        final parameter = index.variantParameter(
          construction.variantRef,
          mapping.parameterRef,
        );
        if (parameter != null) {
          mappedArguments.add(_nativeParameterLabel(parameter));
        }
        final destProp =
            index.widgetProperty(_widgetRef(entry), mapping.propertyRef);
        if (destProp == null) continue;
        // Validate against the destination slot BEFORE translating, so a
        // coalesced `??` fallback is recorded as validated before the body
        // rewrite (see [_translateCoalesce] / [_walk.validatedCoalesceParams]).
        _validateThemeValueForSlot(sourceExpr, destProp.type, issues);
        final translated = _decompositionValue(
          mapping.transform,
          sourceExpr,
          owningWidget: entry,
          destination: destProp,
          issues: issues,
        );
        if (translated == null) continue;
        final value = _coerceForPropertyType(destProp.type, translated);
        out.add('${destProp.name}: $value');
      }

      for (final supplied in match.fieldExpressions.entries) {
        if (mappedFields.contains(supplied.key)) continue;
        final field = index.structuredField(recipe.structuredRef, supplied.key);
        final fieldName = field?.name ?? supplied.key.value;
        issues.add(
          Issue(
            code: IssueCode.unknownProperty,
            message: "Native decomposition field '$fieldName' on "
                "'${structured.name}' is not mapped to a flat property on "
                "'${entry.name}'.",
            location: _locationOf(supplied.value),
          ),
        );
      }

      for (final unmapped in match.unmappedArguments.entries) {
        if (mappedArguments.contains(unmapped.key)) continue;
        issues.add(
          Issue(
            code: IssueCode.unknownProperty,
            message: "Native decomposition argument '${unmapped.key}' on "
                "'${structured.name}' is not mapped to a structured field.",
            location: _locationOf(unmapped.value),
          ),
        );
      }

      return out;
    }
    return null;
  }

  String _nativeParameterLabel(FactoryParameter parameter) {
    switch (parameter.kind) {
      case FactoryParameterKind.named:
        return parameter.name ?? parameter.wireId.value;
      case FactoryParameterKind.positional:
        return '#${parameter.position ?? -1}';
    }
  }

  WireIdRef _widgetRef(WidgetEntry entry) =>
      WireIdRef(library: entry.library.namespace, wireId: entry.wireId);

  String? _decompositionValue(
    DecompositionValueTransform transform,
    Expression sourceExpr, {
    required WidgetEntry owningWidget,
    required PropertyEntry destination,
    required List<Issue> issues,
  }) {
    switch (transform) {
      case IdentityTransform():
      case CoerceScalarTransform():
        final before = issues.length;
        final translated = _translateSlotValue(
          sourceExpr,
          destination.type,
          issues,
          property: destination,
        );
        if (translated.isEmpty && issues.length > before) return null;
        return translated;
      case ProjectListTransform(:final itemTransform):
        if (itemTransform is IdentityTransform) {
          final before = issues.length;
          final translated = _translate(sourceExpr, issues);
          if (translated.isEmpty && issues.length > before) return null;
          return translated;
        }
        _unsupportedNativeTransform(
          'Only projectList(identity) is supported for ${destination.name}.',
          sourceExpr,
          issues,
        );
        return null;
      case ConstructVariantTransform():
        return _decompositionConstructVariant(
          transform,
          sourceExpr,
          owningWidget: owningWidget,
          destination: destination,
          issues: issues,
        );
    }
  }

  String? _decompositionConstructVariant(
    ConstructVariantTransform transform,
    Expression sourceExpr, {
    required WidgetEntry owningWidget,
    required PropertyEntry destination,
    required List<Issue> issues,
  }) {
    final resultRef = transform.resultStructuredRef;
    final invocation = transform.invocation;

    final index = _nativeCatalogIndex;
    final structured = index.structuredByRef(resultRef);
    final variant = index.variantByRef(invocation.variantRef);
    if (structured == null || variant == null) {
      _unsupportedNativeTransform(
        'constructVariant for ${destination.name} references unknown native '
        'metadata.',
        sourceExpr,
        issues,
      );
      return null;
    }

    final match = _matchNativeInvocation(
      sourceExpr,
      invocation,
      owningWidget: owningWidget,
      resultStructured: structured,
      variant: variant,
    );
    if (match == null) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'Native decomposition for ${destination.name} expected '
              "a '${structured.name}' value constructed through the catalog "
              'variant ${invocation.variantRef.wireId.value}.',
          location: _locationOf(sourceExpr),
        ),
      );
      return null;
    }

    if (transform.argumentBindings.isEmpty) {
      _unsupportedNativeTransform(
        'constructVariant for ${destination.name} has no argument bindings.',
        sourceExpr,
        issues,
      );
      return null;
    }

    String? value;
    for (final binding in transform.argumentBindings) {
      final boundValue = _decompositionBindingValue(
        binding,
        match,
        owningWidget: owningWidget,
        destination: destination,
        sourceExpr: sourceExpr,
        issues: issues,
      );
      if (boundValue == null) continue;
      if (value != null) {
        _unsupportedNativeTransform(
          'constructVariant for ${destination.name} produced multiple '
          'values.',
          sourceExpr,
          issues,
        );
        return null;
      }
      value = boundValue;
    }
    return value;
  }

  String? _decompositionBindingValue(
    TransformArgumentBinding binding,
    _NativeInvocationMatch match, {
    required WidgetEntry owningWidget,
    required PropertyEntry destination,
    required Expression sourceExpr,
    required List<Issue> issues,
  }) {
    switch (binding) {
      case PropertyValueArgumentBinding():
        final expr = match.parameterExpressions[binding.parameterRef];
        if (expr == null) {
          return _missingNativeBindingValue(
            binding,
            destination: destination,
            sourceExpr: sourceExpr,
            issues: issues,
          );
        }
        if (expr is NullLiteral) {
          return _nullNativeBindingValue(
            binding,
            destination: destination,
            sourceExpr: expr,
            issues: issues,
          );
        }
        // The bound argument becomes the destination property's value
        // directly, so a theme read here is validated — and the value
        // coerced — against the destination slot's type.
        _validateThemeValueForSlot(expr, destination.type, issues);
        return _translateSlotValue(
          expr,
          destination.type,
          issues,
          property: destination,
        );
      case LiteralArgumentBinding(:final literal):
        final literalValue = _literalNativeBindingValue(literal);
        if (literalValue == null) {
          _unsupportedNativeTransform(
            'Unsupported literal native decomposition binding for '
            '${destination.name}.',
            sourceExpr,
            issues,
          );
        }
        return literalValue;
      case NestedTransformArgumentBinding(:final nestedTransform):
        final expr = match.parameterExpressions[binding.parameterRef];
        if (expr == null) {
          return _missingNativeBindingValue(
            binding,
            destination: destination,
            sourceExpr: sourceExpr,
            issues: issues,
          );
        }
        if (expr is NullLiteral) {
          return _nullNativeBindingValue(
            binding,
            destination: destination,
            sourceExpr: expr,
            issues: issues,
          );
        }
        return _decompositionValue(
          nestedTransform,
          expr,
          owningWidget: owningWidget,
          destination: destination,
          issues: issues,
        );
    }
  }

  String? _missingNativeBindingValue(
    TransformArgumentBinding binding, {
    required PropertyEntry destination,
    required Expression sourceExpr,
    required List<Issue> issues,
  }) {
    switch (binding.missingPolicy) {
      case TransformMissingPolicy.nullResult:
      case TransformMissingPolicy.omitArgument:
      case TransformMissingPolicy.useDefault:
        return null;
      case TransformMissingPolicy.error:
        issues.add(
          Issue(
            code: IssueCode.unknownProperty,
            message: 'Native decomposition for ${destination.name} is missing '
                'required argument ${binding.parameterRef.value}.',
            location: _locationOf(sourceExpr),
          ),
        );
        return null;
    }
  }

  String? _nullNativeBindingValue(
    TransformArgumentBinding binding, {
    required PropertyEntry destination,
    required Expression sourceExpr,
    required List<Issue> issues,
  }) {
    switch (binding.nullPolicy) {
      case TransformNullPolicy.nullResult:
      case TransformNullPolicy.omitArgument:
        return null;
      case TransformNullPolicy.emitNull:
        return 'null';
      case TransformNullPolicy.error:
        issues.add(
          Issue(
            code: IssueCode.unknownProperty,
            message: 'Native decomposition for ${destination.name} does not '
                'allow null for argument ${binding.parameterRef.value}.',
            location: _locationOf(sourceExpr),
          ),
        );
        return null;
    }
  }

  String? _literalNativeBindingValue(Object? value) {
    if (value == null) return 'null';
    if (value is String) return _stringLiteral(value);
    if (value is num || value is bool) return value.toString();
    return null;
  }

  void _unsupportedNativeTransform(
    String message,
    Expression sourceExpr,
    List<Issue> issues,
  ) {
    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message: message,
        location: _locationOf(sourceExpr),
      ),
    );
  }

  _NativeInvocationMatch? _matchNativeInvocation(
    Expression expr,
    FactoryInvocation invocation, {
    required WidgetEntry owningWidget,
    required StructuredEntry resultStructured,
    required FactoryVariant variant,
  }) {
    final receiver = _nativeCatalogIndex.receiverDartType(
      invocation.receiver,
      owningWidget: owningWidget,
      resultStructured: resultStructured,
    );
    final expectedMember = _factoryInvocationMember(invocation, variant);

    if (expr is InstanceCreationExpression) {
      if (variant is! ConstructorVariant) return null;
      final actualType = _dartTypeRefOfInstanceCreation(expr);
      final fallbackTypeName = _instanceCreationTypeName(expr);
      if (!_matchesDartType(receiver, actualType, fallbackTypeName)) {
        return null;
      }
      if (!_matchesMember(
        _instanceCreationMemberName(expr),
        expectedMember,
      )) {
        return null;
      }
      return _bindNativeInvocationArguments(
        variant,
        expr.argumentList.arguments,
      );
    }

    if (expr is MethodInvocation) {
      if (expr.target == null) {
        if (variant is! ConstructorVariant) return null;
        if (!_matchesDartType(receiver, null, expr.methodName.name)) {
          return null;
        }
        if (!_matchesMember(null, expectedMember)) return null;
        return _bindNativeInvocationArguments(
          variant,
          expr.argumentList.arguments,
        );
      }

      if (variant is! ConstructorVariant && variant is! StaticMethodVariant) {
        return null;
      }
      final actualType = _dartTypeRefOfInvocationTarget(expr);
      final fallbackTypeName = _staticTargetName(expr.target);
      if (!_matchesDartType(receiver, actualType, fallbackTypeName)) {
        return null;
      }
      if (!_matchesMember(expr.methodName.name, expectedMember)) return null;
      return _bindNativeInvocationArguments(
        variant,
        expr.argumentList.arguments,
      );
    }

    return null;
  }

  String? _factoryInvocationMember(
    FactoryInvocation invocation,
    FactoryVariant variant,
  ) {
    if (invocation.memberName != null) return invocation.memberName;
    return switch (variant) {
      ConstructorVariant(:final namedConstructor) => namedConstructor,
      StaticMethodVariant(:final staticAccessor) => staticAccessor,
      StaticGetterVariant(:final staticAccessor) => staticAccessor,
      ConstValueVariant(:final staticAccessor) => staticAccessor,
    };
  }

  _NativeInvocationMatch _bindNativeInvocationArguments(
    FactoryVariant variant,
    NodeList<Expression> args,
  ) {
    final parameterExpressions = <WireId, Expression>{};
    final fieldExpressions = <WireId, Expression>{};
    final unmappedArguments = <String, Expression>{};
    final parameters = factoryVariantCallableFields(variant).parameters;

    var positionalIndex = 0;
    for (final arg in args) {
      if (arg is NamedExpression) {
        final name = arg.name.label.name;
        final parameter = parameters.firstWhereOrNull(
          (p) => p.kind == FactoryParameterKind.named && p.name == name,
        );
        if (parameter == null) {
          unmappedArguments[name] = arg.expression;
          continue;
        }
        final mapped = _bindNativeParameter(
          variant,
          parameter,
          arg.expression,
          parameterExpressions,
          fieldExpressions,
        );
        if (!mapped) unmappedArguments[name] = arg.expression;
      } else {
        final position = positionalIndex;
        final parameter = parameters.firstWhereOrNull(
          (p) =>
              p.kind == FactoryParameterKind.positional &&
              p.position == positionalIndex,
        );
        positionalIndex++;
        if (parameter == null) {
          unmappedArguments['#$position'] = arg;
          continue;
        }
        final mapped = _bindNativeParameter(
          variant,
          parameter,
          arg,
          parameterExpressions,
          fieldExpressions,
        );
        if (!mapped) unmappedArguments['#$position'] = arg;
      }
    }

    return _NativeInvocationMatch(
      parameterExpressions: parameterExpressions,
      fieldExpressions: fieldExpressions,
      unmappedArguments: unmappedArguments,
    );
  }

  bool _bindNativeParameter(
    FactoryVariant variant,
    FactoryParameter parameter,
    Expression expr,
    Map<WireId, Expression> parameterExpressions,
    Map<WireId, Expression> fieldExpressions,
  ) {
    parameterExpressions[parameter.wireId] = expr;
    final mappingKey = _nativeArgMappingKey(parameter);
    if (mappingKey == null) return false;
    final argMappings = factoryVariantCallableFields(variant).argMappings;
    final mapping = argMappings[mappingKey];
    if (mapping == null) return false;
    var mapped = false;
    for (final fieldRef in mapping.targetFields) {
      fieldExpressions[fieldRef] = expr;
      mapped = true;
    }
    return mapped;
  }

  String? _nativeArgMappingKey(FactoryParameter parameter) {
    switch (parameter.kind) {
      case FactoryParameterKind.named:
        return parameter.name;
      case FactoryParameterKind.positional:
        return parameter.name ?? '';
    }
  }

  bool _matchesMember(String? actual, String? expected) =>
      (actual ?? '') == (expected ?? '');

  bool _matchesDartType(
    DartTypeRef expected,
    DartTypeRef? actual,
    String? fallbackName,
  ) {
    if (actual != null) return actual == expected;
    // Name-only fallback: used solely when the analyzer could not resolve the
    // receiver to an element (unresolved / synthetic inputs). For resolved
    // inputs the element-qualified [actual] comparison above is authoritative;
    // this branch only compares the bare symbol name.
    return fallbackName == expected.symbolName;
  }

  DartTypeRef? _dartTypeRefOfInstanceCreation(
    InstanceCreationExpression expr,
  ) {
    final cls = _classOfInstanceCreation(expr);
    return cls == null ? null : _dartTypeRefOfClass(cls);
  }

  DartTypeRef? _dartTypeRefOfInvocationTarget(MethodInvocation expr) {
    final element = expr.methodName.element;
    Element? enclosing;
    if (element is MethodElement) {
      enclosing = element.enclosingElement;
    } else if (element is ConstructorElement) {
      enclosing = element.enclosingElement;
    }
    if (enclosing is ClassElement) return _dartTypeRefOfClass(enclosing);

    final target = expr.target;
    if (target is SimpleIdentifier && target.element is ClassElement) {
      return _dartTypeRefOfClass(target.element! as ClassElement);
    }
    return null;
  }

  DartTypeRef? _dartTypeRefOfClass(ClassElement cls) {
    final className = cls.name;
    if (className == null || className.isEmpty) return null;
    return DartTypeRef(
      libraryUri: cls.library.identifier,
      symbolName: className,
    );
  }

  String _instanceCreationTypeName(InstanceCreationExpression expr) {
    final prefix = expr.constructorName.type.importPrefix?.name.lexeme;
    if (prefix != null && expr.constructorName.name == null) {
      return prefix;
    }
    return expr.constructorName.type.name.lexeme;
  }

  String? _instanceCreationMemberName(InstanceCreationExpression expr) {
    final prefix = expr.constructorName.type.importPrefix?.name.lexeme;
    if (prefix != null && expr.constructorName.name == null) {
      return expr.constructorName.type.name.lexeme;
    }
    return expr.constructorName.name?.name;
  }

  String? _staticTargetName(Expression? target) {
    if (target is SimpleIdentifier) return target.name;
    if (target is PrefixedIdentifier) return target.identifier.name;
    if (target is PropertyAccess) return target.propertyName.name;
    return null;
  }

  bool _isShapeBorderClass(ClassElement? cls) {
    if (cls == null) return false;
    bool isShapeName(String? name) =>
        name == 'ShapeBorder' || name == 'OutlinedBorder';
    if (isShapeName(cls.name)) return true;
    return cls.allSupertypes.any((type) => isShapeName(type.element.name));
  }
}

final class _NativeInvocationMatch {
  const _NativeInvocationMatch({
    required this.parameterExpressions,
    required this.fieldExpressions,
    required this.unmappedArguments,
  });

  final Map<WireId, Expression> parameterExpressions;
  final Map<WireId, Expression> fieldExpressions;
  final Map<String, Expression> unmappedArguments;
}

final class _ModalSheetEmitContext {
  const _ModalSheetEmitContext({required this.sheet, required this.flagName});

  final RecognisedModalSheet sheet;
  final String flagName;
}

final class _NavigationEmitContext {
  const _NavigationEmitContext({
    required this.entryId,
    required this.entries,
    required this.buildContextParameter,
  });

  final String entryId;
  final List<_NavigationTriggerEntry> entries;
  final Element? buildContextParameter;

  bool get hasTransitions => entries.isNotEmpty;

  String? eventFor(RecognisedNavigation navigation) {
    for (final entry in entries) {
      if (identical(entry.trigger.pushCall, navigation.pushCall)) {
        return entry.event;
      }
    }
    return null;
  }

  NavigationLowering toLowering() => NavigationLowering(
        entryId: entryId,
        transitions: [
          for (final entry in entries)
            NavigationTransition(
              event: entry.event,
              pushedId: entry.trigger.paywallSourceId,
            ),
        ],
        terminatingEvent: 'skip',
      );
}

final class _NavigationTriggerEntry {
  const _NavigationTriggerEntry({required this.trigger, required this.event});

  final RecognisedNavigation trigger;
  final String event;
}

final class _RootNavigationTriggerScanner extends RecursiveAstVisitor<void> {
  _RootNavigationTriggerScanner({required this.buildContextParameter});

  final Element? buildContextParameter;
  final List<RecognisedNavigation> recognised = [];
  String? resultDrop;

  @override
  void visitFunctionExpression(FunctionExpression node) {
    switch (recogniseNavigatorPopBack(node)) {
      case NavigatorPopBackRecognised() || NavigatorPopResultUnsupported():
        super.visitFunctionExpression(node);
        return;
      case NavigatorPopNotRecognised():
        break;
    }

    final outcome = recogniseNavigationTrigger(node);
    if (!_isNavigationTriggerSlot(node)) {
      switch (outcome) {
        case NavigationRecognised():
          resultDrop ??= kNavigationTriggerSlotUnsupportedReason;
        case NavigationResultDropped(:final reason) ||
              NavigationFormUnsupported(:final reason):
          resultDrop ??= reason;
        case NavigationNotRecognised():
          break;
      }
      super.visitFunctionExpression(node);
      return;
    }

    switch (outcome) {
      case NavigationRecognised(:final navigation):
        if (_usesBuildContextParameter(navigation)) {
          recognised.add(navigation);
        } else {
          resultDrop ??= kNavigationContextUnsupportedReason;
        }
      case NavigationResultDropped(:final reason) ||
            NavigationFormUnsupported(:final reason):
        resultDrop ??= reason;
      case NavigationNotRecognised():
        break;
    }
    super.visitFunctionExpression(node);
  }

  bool _isNavigationTriggerSlot(FunctionExpression node) {
    final parent = node.parent;
    if (parent is! NamedExpression) return false;
    return isNavigationTriggerSlotName(parent.name.label.name);
  }

  bool _usesBuildContextParameter(RecognisedNavigation navigation) {
    final identifier = _navigationContextIdentifier(navigation.pushCall);
    final element = identifier?.element;
    if (buildContextParameter == null || element == null) return true;
    return element == buildContextParameter;
  }

  SimpleIdentifier? _navigationContextIdentifier(MethodInvocation pushCall) {
    final target = pushCall.realTarget;
    if (target is MethodInvocation && target.methodName.name == 'of') {
      final args = target.argumentList.arguments;
      if (args.length != 1) return null;
      final arg = args.single;
      if (arg is NamedExpression) return null;
      return arg is SimpleIdentifier ? arg : null;
    }
    final args = pushCall.argumentList.arguments;
    if (args.isEmpty) return null;
    final first = args.first;
    if (first is NamedExpression) return null;
    return first is SimpleIdentifier ? first : null;
  }
}

final class _WidgetEventNameScanner extends RecursiveAstVisitor<void> {
  _WidgetEventNameScanner(this.helpers);

  final HelperRegistry helpers;
  final List<String> names = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = _paywallEventName(node);
    if (name != null) names.add(name);
    super.visitMethodInvocation(node);
  }

  String? _paywallEventName(MethodInvocation node) {
    if (node.realTarget != null || node.methodName.name != 'paywallEvent') {
      return null;
    }
    final helper = _helperFor(node);
    if (helper?.name != 'paywallEvent') return null;
    final args = node.argumentList.arguments;
    if (args.isEmpty || args.first is NamedExpression) return null;
    final first = _stripParens(args.first);
    // Use the unified scalar boundary so an authored event name carried by a
    // const-object scalar field (`paywallEvent(_skin.nav)`) is collected here
    // exactly as emission folds it — otherwise the synthetic navigation-event
    // minter, blind to it, could reuse an authored name and collide.
    final folded = tryFoldScalarConstant(first);
    return folded is String ? folded : null;
  }

  HelperDefinition? _helperFor(MethodInvocation node) {
    final element = node.methodName.element;
    if (element != null) {
      final libraryUri = element.library?.identifier ?? '';
      return helpers.find(node.methodName.name, libraryUri);
    }
    return helpers.findByNameOnly(node.methodName.name);
  }

  Expression _stripParens(Expression expr) {
    var current = expr;
    while (current is ParenthesizedExpression) {
      current = current.expression;
    }
    return current;
  }
}

final class _RootModalSheetTriggerScanner extends RecursiveAstVisitor<void> {
  final List<RecognisedModalSheet> recognised = [];
  String? resultDrop;

  @override
  void visitFunctionExpression(FunctionExpression node) {
    final outcome = recogniseModalSheetTrigger(node);
    if (!_isModalTriggerSlot(node)) {
      switch (outcome) {
        case ModalSheetRecognised():
          resultDrop ??= kModalSheetTriggerSlotUnsupportedReason;
        case ModalSheetResultDropped(:final reason):
          resultDrop ??= reason;
        case ModalSheetNotRecognised():
          break;
      }
      super.visitFunctionExpression(node);
      return;
    }
    switch (outcome) {
      case ModalSheetRecognised(:final sheet):
        recognised.add(sheet);
      case ModalSheetResultDropped(:final reason):
        resultDrop ??= reason;
      case ModalSheetNotRecognised():
        break;
    }
    super.visitFunctionExpression(node);
  }

  bool _isModalTriggerSlot(FunctionExpression node) {
    final parent = node.parent;
    if (parent is! NamedExpression) return false;
    return isModalSheetTriggerSlotName(parent.name.label.name);
  }
}

// ---------------------------------------------------------------------------
// Internal helpers for string-interpolation decomposition.
// ---------------------------------------------------------------------------

enum _InterpKind { literal, dataRef }

final class _InterpSegment {
  _InterpSegment.literal(this.text) : kind = _InterpKind.literal;
  _InterpSegment.dataRef(this.text) : kind = _InterpKind.dataRef;
  final _InterpKind kind;
  final String text;
}

// ---------------------------------------------------------------------------

/// Subset of Flutter's Colors constants resolved at codegen time. Authors
/// who reference any name not in this table get an unresolvedIdentifier
/// issue with the supported list.
const Map<String, String> _kMaterialColors = {
  'red': '0xFFF44336',
  'pink': '0xFFE91E63',
  'purple': '0xFF9C27B0',
  'blue': '0xFF2196F3',
  'green': '0xFF4CAF50',
  'yellow': '0xFFFFEB3B',
  'orange': '0xFFFF9800',
  'grey': '0xFF9E9E9E',
  'black': '0xFF000000',
  'white': '0xFFFFFFFF',
  'transparent': '0x00000000',
};

/// Whether a slot of catalog property [type] accepts a theme-contract value
/// of [kind] — the compatibility axis between the published `data.theme.*`
/// value kinds and the catalog's slot types. Exhaustive over [PropertyType]
/// so a new slot type forces an explicit decision here; the conservative
/// answer for a new type is `false` (the build fails closed rather than
/// shipping a value the slot's decoder would silently null).
bool propertyTypeAcceptsThemeKind(
  PropertyType type,
  ThemeContractValueKind kind,
) =>
    switch (type) {
      PropertyType.color => kind == ThemeContractValueKind.color,
      PropertyType.length ||
      PropertyType.real =>
        kind == ThemeContractValueKind.size,
      PropertyType.fontWeight => kind == ThemeContractValueKind.fontWeight,
      PropertyType.widget ||
      PropertyType.widgetList ||
      PropertyType.edgeInsets ||
      PropertyType.alignment ||
      PropertyType.alignmentXY ||
      PropertyType.offset ||
      PropertyType.duration ||
      PropertyType.curve ||
      PropertyType.boolean ||
      PropertyType.integer ||
      PropertyType.string ||
      PropertyType.stringList ||
      PropertyType.booleanList ||
      PropertyType.event ||
      PropertyType.dataReference ||
      PropertyType.enumValue ||
      PropertyType.gradient ||
      PropertyType.border ||
      PropertyType.boxShadowList ||
      PropertyType.locale ||
      PropertyType.paint ||
      PropertyType.shadowList ||
      PropertyType.fontFeatureList ||
      PropertyType.fontVariationList ||
      PropertyType.textDecoration ||
      PropertyType.shapeBorder ||
      PropertyType.structured ||
      PropertyType.inlineSpan ||
      PropertyType.decorationImage ||
      PropertyType.selectionOptionList ||
      PropertyType.unknown =>
        false,
    };

/// Sentinel for [_WalkContext.copyWith] that distinguishes "argument omitted"
/// (keep the current value) from "argument explicitly null" (set to null) for
/// the nullable walk-scoped fields.
const Object _kWalkUnset = _WalkUnset();

class _WalkUnset {
  const _WalkUnset();
}

/// The walk-scoped translation state — the eleven fields saved → mutated →
/// restored around custom-widget definition-body and helper-inline translation.
///
/// Bundled into one immutable value object so a push/pop is a single
/// whole-object swap — `final saved = _walk; _walk = saved.copyWith(<subset>);`
/// then `finally { _walk = saved; }` — rather than eleven hand-mirrored field
/// saves. Fields are shared by
/// reference across [copyWith] (none of the ten non-`validatedCoalesceParams`
/// fields is ever mutated through the live object — they are only reassigned),
/// so a child scope that does not touch a field keeps the parent's reference.
///
/// [validatedCoalesceParams] is the one field mutated in place (`.add`). Its
/// reset sites pass a fresh mutable set, and the initial state allocates one,
/// so a child scope's additions land in the child's set and the whole-object
/// restore discards them — while an addition made at a scope that did not reset
/// it mutates the shared set and survives the restore (the saved context holds
/// the same reference). This reproduces the pre-bundle behaviour exactly.
final class _WalkContext {
  const _WalkContext({
    required this.argNames,
    required this.stateFields,
    required this.eventHandlers,
    required this.rootStateContext,
    required this.inlined,
    required this.params,
    required this.classKey,
    required this.paramBindings,
    required this.modalSheet,
    required this.modalSheetCloseFlag,
    required this.validatedCoalesceParams,
  });

  /// The initial root state — matches the pre-bundle field defaults. Not
  /// `const` because [validatedCoalesceParams] must be a fresh mutable set
  /// (it is mutated in place via `.add`).
  _WalkContext.initial()
      : argNames = const {},
        stateFields = null,
        eventHandlers = const {},
        rootStateContext = false,
        inlined = const InlinedDefinitions.empty(),
        params = const {},
        classKey = null,
        paramBindings = const {},
        modalSheet = null,
        modalSheetCloseFlag = null,
        validatedCoalesceParams = {};

  /// The constructor-parameter names of the custom-widget definition body
  /// currently being translated — empty while translating the root paywall.
  /// A bare identifier in this set lowers to an `args.` reference; a
  /// `widget.<X>` PrefixedIdentifier lowers to `args.X` when X is in this set
  /// AND the definition is stateful (i.e. `stateFields` is non-null) — a
  /// stateless widget's `build()` resolves constructor params as bare
  /// identifiers, never via `widget.`.
  final Set<String> argNames;

  /// The State fields of the stateful custom-widget definition body currently
  /// being translated — null while translating a stateless definition body or
  /// the root paywall, a name-keyed map inside one. A bare identifier whose
  /// name is a key in this map lowers to a `state.<name>` reference; the
  /// null-vs-empty distinction also gates the `widget.<X>` → `args.X` lowering
  /// (a stateless walk never carries `widget.`). The value carries `isNumeric`
  /// so a numeric setState RHS gets the same double-coercion as the initial
  /// state value.
  final Map<String, CustomWidgetStateField>? stateFields;

  /// The State event handlers of the stateful custom-widget definition body
  /// currently being translated — empty outside a stateful walk, an
  /// unmodifiable name → verdict map inside one. A bare identifier in this map
  /// lowers to a `set state.<field> = …` event handler emitted from the
  /// classifier-captured verdict (a literal-RHS assignment, a same-field bool
  /// flip, or — when the verdict is `SetStateUnrecognised` — a diagnostic the
  /// translator surfaces in lieu of an emit).
  final Map<String, RecognisedSetState> eventHandlers;

  /// True only while translating a root source's State.build() expression.
  /// This distinguishes root state from a stateful custom-widget definition:
  /// both lower bare State fields to `state.X`, but only custom widgets have
  /// constructor args that can be read as `widget.X` → `args.X`.
  final bool rootStateContext;

  /// The named intermediates (own helper methods, and later local bindings) of
  /// the custom-widget definition body currently being translated — empty
  /// while translating the root paywall or a definition with no inlinable
  /// intermediate. A bare `_helper(...)` call whose method element is a key in
  /// `InlinedDefinitions.helpers` is inlined to its body (element-resolved
  /// identity, never name-matched). Saved/restored around each definition-body
  /// translation, mirroring `argNames`.
  final InlinedDefinitions inlined;

  /// The constructor parameters (by name) of the custom-widget definition body
  /// currently being translated — empty while translating the root paywall.
  /// Used to recognise a `<param> ?? <fallback>` coalesce at a typed slot.
  /// Saved/restored around each definition-body translation.
  final Map<String, CustomWidgetParam> params;

  /// The classKey of the custom-widget definition body currently being
  /// translated — the key under which its coalesce-fallback completions are
  /// cached. Null while translating the root paywall.
  final String? classKey;

  /// Active helper-parameter bindings (param element → bound argument
  /// expression) while inlining a parameterized helper body. A bare identifier
  /// resolving (by element) to a bound parameter is translated as its argument
  /// in the caller's context — the inlined composition. Pushed/restored around
  /// each helper-body inline, element-keyed so nested helpers don't collide.
  final Map<Element, Expression> paramBindings;

  /// Active root-level modal-sheet lowering, when the root paywall contains
  /// exactly one supported show*Sheet trigger. The context lets the event-slot
  /// translator rewrite that source closure to a set-state handler, and lets
  /// sheet content rewrite the exact Navigator.pop(context) close form.
  final _ModalSheetEmitContext? modalSheet;

  /// Set only while translating the modal sheet builder subtree. This prevents
  /// an unrelated Navigator.pop(context) in the underlay from being treated as
  /// a sheet-close control.
  final String? modalSheetCloseFlag;

  /// Coalesced property names whose fallback was kind-validated against its
  /// slot (by `_validateThemeValueForSlot`) BEFORE the body rewrite. The
  /// rewrite is only sound when the fallback was validated, so
  /// `_translateCoalesce` defers a `??` reached through a path that did not
  /// validate it. Reset per definition body; the one field mutated in place
  /// (via `.add`).
  final Set<String> validatedCoalesceParams;

  /// Returns a copy with the named fields replaced. Omitted fields keep their
  /// current value (shared by reference). The four nullable fields use the
  /// [_kWalkUnset] sentinel so a caller can set them to null.
  _WalkContext copyWith({
    Set<String>? argNames,
    Object? stateFields = _kWalkUnset,
    Map<String, RecognisedSetState>? eventHandlers,
    bool? rootStateContext,
    InlinedDefinitions? inlined,
    Map<String, CustomWidgetParam>? params,
    Object? classKey = _kWalkUnset,
    Map<Element, Expression>? paramBindings,
    Object? modalSheet = _kWalkUnset,
    Object? modalSheetCloseFlag = _kWalkUnset,
    Set<String>? validatedCoalesceParams,
  }) {
    return _WalkContext(
      argNames: argNames ?? this.argNames,
      stateFields: identical(stateFields, _kWalkUnset)
          ? this.stateFields
          : stateFields as Map<String, CustomWidgetStateField>?,
      eventHandlers: eventHandlers ?? this.eventHandlers,
      rootStateContext: rootStateContext ?? this.rootStateContext,
      inlined: inlined ?? this.inlined,
      params: params ?? this.params,
      classKey: identical(classKey, _kWalkUnset)
          ? this.classKey
          : classKey as String?,
      paramBindings: paramBindings ?? this.paramBindings,
      modalSheet: identical(modalSheet, _kWalkUnset)
          ? this.modalSheet
          : modalSheet as _ModalSheetEmitContext?,
      modalSheetCloseFlag: identical(modalSheetCloseFlag, _kWalkUnset)
          ? this.modalSheetCloseFlag
          : modalSheetCloseFlag as String?,
      validatedCoalesceParams:
          validatedCoalesceParams ?? this.validatedCoalesceParams,
    );
  }
}
