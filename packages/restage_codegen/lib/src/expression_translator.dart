import 'package:restage_codegen/src/surface_publication/recorded_layouts.dart';
import 'package:restage_compiler_core/src/rfw_scalar_callback_contract.dart'
    show eventNativeType;
import 'package:restage_codegen/src/scalar_callback_lowering.dart';
import 'package:restage_codegen/src/grid_value_recipes.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/widget_builder_lowering.dart';
import 'package:restage_codegen/src/widget_collection_lowering.dart';
import 'dart:collection';
import 'dart:convert' show jsonEncode, utf8;
import 'dart:math' as math;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart' show TokenType;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/callback_shape.dart';
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/collection_unroll.dart';
import 'package:restage_codegen/src/commerce_authoring.dart';
import 'package:restage_codegen/src/const_folding.dart';
import 'package:restage_codegen/src/const_value_literal.dart';
import 'package:restage_codegen/src/custom_structured_admissibility.dart'
    show reasonClause;
import 'package:restage_codegen/src/custom_structured_value_emitter.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/dart_import_planner.dart';
import 'package:restage_codegen/src/device_recognition.dart';
import 'package:restage_codegen/src/draggable_sheet_recognition.dart';
import 'package:restage_codegen/src/dsl_parse_diagnostic.dart';
import 'package:restage_codegen/src/dsl_emission.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/factory_variant_fields.dart';
import 'package:restage_codegen/src/framework_const_values.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/hoisting.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_codegen/src/islands/islands.dart';
import 'package:restage_codegen/src/islands/opt_outs.dart';
import 'package:restage_codegen/src/surface_publication/app_widget_events.dart'
    show inlineEventIssue, surfaceEventConstant;
import 'package:restage_codegen/src/surface_publication/app_widget_mount_install.dart'
    show spellBesideClass;
import 'package:restage_codegen/src/surface_publication/split_widgets.dart'
    show
        SplitWidgetDefinitions,
        kPlacementNameArgument,
        kPlacementItemsArgument,
        declaresGeneratedPart,
        splitAppName;
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/installed_native_call.dart';
import 'package:restage_codegen/src/installed_native_provenance.dart'
    show installedNativeConstantValue;
import 'package:restage_codegen/src/intl_format_recognition.dart';
import 'package:restage_codegen/src/lowering_targets.dart';
import 'package:restage_codegen/src/measurement/measurement_event_occurrence.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_codegen/src/modal_sheet_recognition.dart';
import 'package:restage_codegen/src/native_binding_routes.dart';
import 'package:restage_codegen/src/runtime_realization.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:restage_codegen/src/navigation_recognition.dart';
import 'package:restage_codegen/src/number_format_recognition.dart';
import 'package:restage_codegen/src/optional_native_value_emitter.dart';
import 'package:restage_codegen/src/optional_native_values.dart';
import 'package:restage_codegen/src/owning_library_namespace.dart';
import 'package:restage_codegen/src/paywall_completion.dart';
import 'package:restage_codegen/src/preferred_heights.dart';
import 'package:restage_codegen/src/recipe_dispatcher.dart';
import 'package:restage_codegen/src/rfw_constructor_presence_protocol.dart';
import 'package:restage_codegen/src/rfw_emitter.dart';
import 'package:restage_codegen/src/segmented_button_recognition.dart';
import 'package:restage_codegen/src/setstate_recognition.dart';
import 'package:restage_codegen/src/shader_mask_recognition.dart';
import 'package:restage_codegen/src/single_select_recognition.dart';
import 'package:restage_codegen/src/islands/context_reach.dart'
    show isFlutterFrameworkType;
import 'package:restage_codegen/src/source_state.dart' show ContentFreeBuilders;
import 'package:restage_codegen/src/structured_value_emitter.dart';
import 'package:restage_codegen/src/surface_publication/generated_handle_names.dart'
    show generatedSurfaceName;
import 'package:restage_codegen/src/surface_vocabulary.dart';
import 'package:restage_codegen/src/synthetic_property.dart';
import 'package:restage_codegen/src/theme_recognition.dart';
import 'package:restage_codegen/src/text_span_recognizer.dart';
import 'package:restage_codegen/src/toggle_buttons_recognition.dart';
import 'package:restage_codegen/src/translator_recipe.dart';
import 'package:restage_codegen/src/type_inference.dart';
import 'package:restage_codegen/src/widget_catalog/translator_tables.g.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        BuilderResult,
        WidgetVocabulary,
        islandLibraryNamespace,
        NativeBindingContract,
        kNativeVoidCallbackType,
        kTextSpanRecognizerDetailCallbacks,
        SurfaceScreenHostDataNativeBindingShapeV1,
        builderContextValueType,
        colorValueType,
        ValueNode,
        ValueOperation,
        ValueType,
        DeviceContractValueKind,
        ThemeContractValueKind,
        kCapturedEventValueKey,
        kDeviceContractPathKinds,
        kDeviceContractPaths,
        kIconThemeDataFallbackKey,
        kIconThemeDataLerpKey,
        kMaxInlineSpanDepth,
        kMaxStructuredCopyWithLayers,
        kReservedCommerceEventNames,
        kRestageFormattedTextProps,
        kStructuredCopyWithKey,
        kSupportedCurveNames,
        kThemeContractPathKinds,
        kThemeContractPaths,
        kThemeContractTextThemeFieldKinds,
        kThemeContractTextThemeStyles;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show
        kHostListItemPositionKey,
        kLocalValueSetEventName,
        kMeasurementPublicationTapEventNameV1;
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart'
    show
        RecordAdmitted,
        RecordExcluded,
        classifyRecordType,
        dartCoreMapType,
        resolveValueShape;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const String _kSelectionOptionLibraryOrigin =
    'package:restage_core/src/runtime/decoders.dart';
const Set<String> _kTranslatedTypedListFrameworkItems = {
  'AssetImage',
  'Border',
  'BorderRadius',
  'BorderRadiusDirectional',
  'EdgeInsetsDirectional',
  'BorderSide',
  'BoxShadow',
  'DecorationImage',
  'FontFeature',
  'FontVariation',
  'LinearGradient',
  'Locale',
  'NetworkImage',
  'Paint',
  'RadialGradient',
  'Shadow',
  'Size',
  'SweepGradient',
  'TextDecoration',
  'TextStyle',
};
const Set<String> _kScreenEventHelperNames = {'surfaceEvent'};
const Set<String> _kRfwLoopReservedWords = {
  'args',
  'data',
  'event',
  'false',
  'set',
  'state',
  'true',
};

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

const String _kBorderRadiusCornerSentinel = kBorderRadiusCornerSentinel;

const String _kInputDecorationText = 'inputDecorationText';
const String _kInputDecorationPrefixIcon = 'inputDecorationPrefixIcon';
const String _kInputDecorationPrefixIconFontFamily =
    'inputDecorationPrefixIconFontFamily';
const String _kInputDecorationPrefixIconMatchTextDirection =
    'inputDecorationPrefixIconMatchTextDirection';
const String _kInputBorderSynthetic = 'inputBorder';
const String _kTextInputTypeSynthetic = 'textInputType';
const String _kScrollNotificationDepthSynthetic = 'scrollNotificationDepth';
const String _kScrollNotificationLibrary =
    'package:flutter/src/widgets/scroll_notification.dart';

/// The `synthetic` strategy of the codepoint property an icon slot carries.
const String _kIconDataSynthetic = 'iconData';

/// The `synthetic` strategy of the font-family property that travels beside
/// a codepoint.
const String _kIconFontFamilySynthetic = 'iconFontFamily';

/// The `synthetic` strategy of the mirroring property that travels beside a
/// codepoint, selecting the glyph that flips in a right-to-left locale.
const String _kIconMatchTextDirectionSynthetic = 'iconMatchTextDirection';

/// The icon font family a codepoint belongs to when the wire names none.
const String _kDefaultIconFontFamily = 'MaterialIcons';

/// Corner name (as the sentinel emits) → the per-corner catalog property name.
/// Mirrors the reconstruction side's `borderRadius<Corner>` convention; the
/// recognition stays widget-agnostic (it emits the bare corner name).
const Map<String, String> _kBorderRadiusCornerProperty = {
  'topLeft': 'borderRadiusTopLeft',
  'topRight': 'borderRadiusTopRight',
  'bottomLeft': 'borderRadiusBottomLeft',
  'bottomRight': 'borderRadiusBottomRight',
  'topStart': 'borderRadiusTopStart',
  'topEnd': 'borderRadiusTopEnd',
  'bottomStart': 'borderRadiusBottomStart',
  'bottomEnd': 'borderRadiusBottomEnd',
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
    Set<String> referencedCustomLibraries = const {},
    Iterable<IconDataReference> iconReferences = const [],
    Iterable<fmt.RfwCatalogConstructorProvenance> rfwCatalogConstructorOrigins =
        const [],
    Map<String, Object> localSeeds = const {},
    this.usesLocalValues = false,
    this.emitsInteractionItems = false,
    this.completesSurface = false,
    Iterable<DslEmissionSource> emissionSources = const [],
    Iterable<HoistedValue> hoisted = const [],
    Iterable<PropertyInducingElement> firedEvents = const [],
    Iterable<ClassElement> placedCustomWidgets = const [],
    Iterable<AstNode> placedCustomWidgetSites = const [],
    Iterable<Island> islands = const [],
    this.split,
    Set<Element> blocked = const {},
  }) : issues = List.unmodifiable(issues),
       blocked = Set.unmodifiable(blocked),
       emissionSources = List.unmodifiable(emissionSources),
       hoisted = List.unmodifiable(hoisted),
       firedEvents = List.unmodifiable(firedEvents),
       placedCustomWidgets = Set.unmodifiable(placedCustomWidgets),
       placedCustomWidgetSites = List.unmodifiable(placedCustomWidgetSites),
       islands = List.unmodifiable(islands),
       localSeeds = Map.unmodifiable(localSeeds),
       iconReferences = List.unmodifiable(iconReferences),
       widgetDefinitions = Map.unmodifiable(widgetDefinitions),
       widgetDefinitionStates = Map.unmodifiable(widgetDefinitionStates),
       rootWidgetState = Map.unmodifiable(rootWidgetState),
       referencedCustomLibraries = Set.unmodifiable(referencedCustomLibraries),
       rfwCatalogConstructorOrigins = List.unmodifiable(
         rfwCatalogConstructorOrigins,
       );

  /// The DSL fragment, e.g. `"42"` or `'event "name" {}'`. Empty string if
  /// translation failed and one or more [issues] were collected.
  final String dsl;

  /// Surface declarations the mount could not see where an island failed.
  final Set<Element> blocked;

  /// Issues collected during this translation (unmodifiable).
  final List<Issue> issues;

  /// The source expression behind each emitted fragment, for naming the
  /// construct when the emitted text fails to parse.
  final List<DslEmissionSource> emissionSources;

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

  /// Namespaces of the CUSTOM catalog libraries this translation references (a
  /// widget resolved to a non-built-in catalog entry, not inlined). The emitter
  /// imports each so the reference resolves at runtime. Empty when the surface
  /// references only built-in and inlined widgets.
  final Set<String> referencedCustomLibraries;

  /// The compile-time icons this translation resolved, ordered by font family
  /// and then code point, each carrying every `IconData` field so generated
  /// code rebuilds the value exactly.
  final List<IconDataReference> iconReferences;

  /// Typed catalog origins for RFW calls emitted during this translation.
  final List<fmt.RfwCatalogConstructorProvenance> rfwCatalogConstructorOrigins;

  /// Initial screen-local values, keyed by the value's name. Empty when the
  /// surface writes no local value.
  final Map<String, Object> localSeeds;

  /// Whether a value callback writes a screen-local value.
  final bool usesLocalValues;

  /// Whether any measured tap carries an item identity.
  final bool emitsInteractionItems;

  /// Whether the paywall declares events that complete it.
  final bool completesSurface;

  /// Values the generated mount computes, ordered by key.
  final List<HoistedValue> hoisted;

  /// The `SurfaceEvent` constants the build fires, in the order it fires
  /// them; a screen's contract includes the ones it doesn't declare.
  final List<PropertyInducingElement> firedEvents;

  /// The custom widgets the build places by their catalog entries rather
  /// than inlining them.
  final Set<ClassElement> placedCustomWidgets;

  /// The constructions that place those widgets by catalog entry.
  final List<AstNode> placedCustomWidgetSites;

  /// Widget expressions that render from the app, ordered by ID.
  final List<Island> islands;

  /// Where [value] is first read: the innermost emission that reads it.
  String? locationOf(HoistedValue value) {
    final read = RegExp(
      '(?<![A-Za-z0-9_])${RegExp.escape(value.key)}(?![A-Za-z0-9_])',
    );
    return emissionSources
        .firstWhereOrNull((source) => read.hasMatch(source.dsl))
        ?.location;
  }

  /// How the mount takes over the surface's shell and `State`, if it does.
  final MountSplit? split;

  /// The validation registry for this translation's installed declarations.
  Map<String, ValueOperation> get valueOperations =>
      installedNativeCallOperations(hoisted);

  /// Whether the surface needs the client floor for these features.
  bool get requiresSurfaceFeatureFloor =>
      usesLocalValues || emitsInteractionItems || completesSurface;

  /// Creates the closed typed input used to resolve emitted RFW calls.
  fmt.RfwCatalogOccurrenceResolutionInput rfwCatalogOccurrenceResolutionInput({
    required String artifactProvenance,
    required String sourceLibraryIdentity,
    required String sourceDeclarationIdentity,
    required Iterable<String> renderEntryNames,
  }) {
    final roots = renderEntryNames.toSet();
    final catalogOriginsByName =
        <String, fmt.RfwCatalogConstructorProvenance>{};
    for (final origin in rfwCatalogConstructorOrigins) {
      final previous = catalogOriginsByName.putIfAbsent(
        origin.constructorName,
        () => origin,
      );
      if (!previous.matches(origin)) {
        throw StateError(
          'One emitted RFW constructor spelling has conflicting catalog '
          'origins',
        );
      }
    }
    // A definition inlined without a catalog entry is an ordinary local.
    final generatedLocalSymbols = [
      for (final name in widgetDefinitions.keys)
        fmt.RfwCatalogLocalSymbol(
          name: name,
          generatedCatalogOrigin: catalogOriginsByName[name],
        ),
    ];
    return fmt.RfwCatalogOccurrenceResolutionInput(
      artifactProvenance: artifactProvenance,
      sourceLibraryIdentity: sourceLibraryIdentity,
      sourceDeclarationIdentity: sourceDeclarationIdentity,
      renderEntryNames: roots,
      catalogConstructors: rfwCatalogConstructorOrigins,
      localSymbols: [
        for (final name in roots) fmt.RfwCatalogLocalSymbol(name: name),
        ...generatedLocalSymbols,
      ],
    );
  }
}

/// Private build artifact describing a lowered paywall-root navigation flow.
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

  /// Stable JSON representation for the private `.navplan` sidecar.
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

typedef _CustomWidgetEmissionIdentity = ({
  String classKey,
  String remoteLibrary,
});

typedef _CustomWidgetFactoryRoute = ({
  String widgetName,
  String reason,
});

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
    this.splitWidgetDefinitions = const {},
    this.canonicalPaywallIdFor,
    this.measurementRouteEmissionPlan,
  }) : _isFrameworkValueType = isFrameworkValueTypeLibrary;

  /// Test-only override of the framework-value-type predicate the
  /// value-substitution gate keys on. Production is strict-by-default
  /// ([isFrameworkValueTypeLibrary] — `dart:` / `package:flutter/`), and that
  /// deferral of a resolved custom look-alike is proven through the
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
    this.splitWidgetDefinitions = const {},
    this.canonicalPaywallIdFor,
    this.measurementRouteEmissionPlan,
  }) : _isFrameworkValueType = frameworkLibraryPredicate;

  /// Resolves canonical pushed-paywall identities from the package roster.
  ///
  /// The normal translator leaves this null because only the aggregate package
  /// compiler owns canonical source identity. Legacy `@PaywallSource`
  /// navigation still resolves through its compatibility annotation field.
  final CanonicalPaywallIdFor? canonicalPaywallIdFor;

  /// Exact analyzer-expression bindings for transient Measurement route
  /// markers. The package publication compiler resolves those markers to the
  /// final carrier before hashing the emitted artifact.
  final MeasurementRouteEmissionPlan? measurementRouteEmissionPlan;

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
    translate: (expr, issues) =>
        _translateSlotValue(expr, PropertyType.unknown, issues),
    translateSlotValue: _translateSlotValue,
    translateSlotElement: _translateSlotElement,
    translateTypedListTerminal: _translateTypedListTerminal,
    translateDoubleScalar: _translateDoubleScalar,
    translateDoubleElement: _translateDoubleElement,
    resolveDoubleListSource: _resolveDoubleListSource,
    translateDoubleLiteral: _translateDoubleLiteral,
    stripParens: _stripParens,
    stringLiteral: _stringLiteral,
    frameworkOrUnresolved: _frameworkOrUnresolved,
    resolveBoundIdentifier: _resolveBoundIdentifier,
    collectionSemanticProbe: _collectionSemanticProbe,
    isResolvedNonFrameworkCtor: _isResolvedNonFrameworkCtor,
    deferFrameworkConstLookalike: _deferFrameworkConstLookalike,
    deferFrameworkCtorLookalike: _deferFrameworkCtorLookalike,
    locationOf: _locationOf,
  );

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
    InliningMechanism.conditionalElement,
  };

  static const Set<String> _kCarriedTextSpanProps = {
    'text',
    'style',
    'children',
    'recognizer',
  };

  static const Set<String> _kDeferredTextSpanProps = {
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

  late final Set<String> _admittedHelperPackages = artifactHelperPackages(
    catalog,
  );

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

  /// Emission blueprints for the inlineable custom widgets referenced this
  /// build pass, keyed by `'<library URI>#<ClassName>'` ([customWidgetKey]).
  /// The translator inlines an inlinable-now widget from its blueprint —
  /// emitting an RFW remote-widget definition — rather than deferring it.
  final Map<String, CustomWidgetBlueprint> customWidgetBlueprints;

  /// The delivered declarations of each split custom widget, by class key:
  /// its own definition and the definitions and states it inlines.
  final Map<String, SplitWidgetDefinitions> splitWidgetDefinitions;

  /// Walk-scoped state replaced atomically around nested translations.
  _WalkContext _walk = _WalkContext.initial();

  /// Mount-computed values of the current translation, when it has a mount.
  _HoistSession? _hoist;

  // Whether build locals resolve to what they hold, while delivering.
  bool _seesThroughPreludes = false;

  /// Islands of the current translation, when it has a mount.
  _IslandSession? _islands;

  Map<Element, HelperDef> _collectionHelpers = const {};
  late CollectionSemanticTraversalSession _collectionSession =
      CollectionSemanticTraversalSession(admitsPlacedReuse: _routedPerSpot);

  /// Const declarations under translation.
  final Set<Element> _constDeclarationsInFlight = <Element>{};

  // Per-call location context, set at the start of each [translate] call.
  String? _currentSourcePath;
  LineInfo? _currentLineInfo;
  AstNode? _currentSourceUnit;

  // Per-call accumulator for the custom-widget definitions emitted while
  // translating (rfwName → body DSL), set at the start of each [translate]
  // call and surfaced on the result. Null outside a translate() call.
  Map<String, String>? _currentWidgetDefinitions;

  // Per definitions map: each custom widget whose build returns one of its own
  // widget parameters, by RFW name, and that parameter. It inlines as the
  // argument, as Flutter renders it, with no declaration.
  final Expando<Map<String, String>> _passThroughs = Expando();

  // Per-call accumulator for the stateful-definition initial-state maps
  // emitted while translating (rfwName → field-name → literal-DSL). Null
  // outside a translate() call.
  Map<String, Map<String, String>>? _currentWidgetDefinitionStates;

  // Owner of each emitted RFW widget name this call (rfwName → classKey) —
  // bookkeeping that detects two custom widgets claiming one name. Null
  // outside a translate() call.
  Map<String, String>? _currentDefinitionOwners;

  // Namespaces of the custom catalog libraries referenced (not inlined) in the
  // current translate() call — the emitter imports each. Null outside a call.
  Set<String>? _currentReferencedCustomLibraries;

  // The icons resolved in the current translate() call, so the generated
  // surface reference can rebuild them. Null outside a call.
  IconReferenceCollector? _currentIconReferences;

  // Typed catalog selections for RFW constructors emitted during one
  // translation. The aggregate compiler reuses these selections to bind the
  // parsed calls without resolving their names again.
  Map<String, fmt.RfwCatalogConstructorProvenance>?
  _currentRfwCatalogConstructorOrigins;

  Set<_CustomWidgetEmissionIdentity>? _currentCustomWidgetInlineClaims;
  Set<_CustomWidgetEmissionIdentity>? _currentCustomWidgetReferences;
  Map<_CustomWidgetEmissionIdentity, _CustomWidgetFactoryRoute>?
  _currentCustomWidgetFactoryRoutes;
  Map<_CustomWidgetEmissionIdentity, _CustomWidgetFactoryRoute>
  _forcedCustomWidgetFactoryRoutes = const {};

  // Closure-wrapped event notices, reported only when the translation succeeds.
  List<Issue>? _currentEventClosureNotices;

  // The `SurfaceEvent` constants the current translation lowers.
  Set<PropertyInducingElement>? _currentFiredEvents;

  // Refusals only the measured pass raises; an inlined body keeps them.
  final Set<Issue> _measuredRefusals = Set.identity();

  Issue _measuredRefusal(Issue issue) {
    _measuredRefusals.add(issue);
    return issue;
  }

  // The custom widgets the current translation places by catalog entry.
  Set<ClassElement>? _currentPlacedCustomWidgets;

  // The constructions that place them.
  List<AstNode>? _currentPlacedCustomWidgetSites;

  // Whether this translation attached an item to a measured tap.
  bool _currentEmitsInteractionItems = false;

  // Root State fields written by value callbacks; read as `data.local.*`.
  Set<String> _currentLocalFields = const {};

  /// Fragments recorded during the current translation.
  List<DslEmissionSource>? _emissionSources;

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

  // The measured callback slot whose value is being translated.
  MeasurementEventOccurrence? _measuredEventOccurrence;

  // The font family the icon at the codepoint slot being translated belongs
  // to, when it is not the Material default. Set by `_resolveIconCodepoint`
  // and taken by the enclosing constructor emission.
  String? _resolvedIconFontFamily;

  // Whether that same icon mirrors under a right-to-left directionality, which
  // is what tells the two glyphs of a shared codepoint apart.
  bool _resolvedIconMatchTextDirection = false;

  /// Table-driven dispatcher. A registered recipe short-circuits the
  /// hand-authored per-type dispatch; an unregistered call falls through.
  late final RecipeDispatcher _recipeDispatcher = RecipeDispatcher(
    recipes: kTranslatorRecipes,
    translate: (expr, issues) =>
        _translateSlotValue(expr, PropertyType.unknown, issues),
    translateDouble: _translateDoubleScalar,
    translateDoubleElement: _translateDoubleElement,
    resolveDoubleListSource: _resolveDoubleListSource,
    resolveTypedListExpression: _resolveBoundIdentifier,
    collectionSemanticProbe: _collectionSemanticProbe,
    locationOf: _locationOf,
    translateSlot: _translateSlotValue,
    translateSlotElement: _translateSlotElement,
    translateTypedListTerminal: _translateTypedListTerminal,
    // Inject the (forTesting-aware) framework-value-type predicate so the
    // member-table nested-value gate defers a resolved custom look-alike
    // consistently with the hand-authored helpers.
    isFrameworkLibrary: _isFrameworkValueType,
  );

  /// Native catalog lookups are needed only for structured decomposition.
  /// Keep construction lazy so translator tests with synthetic catalog
  /// fragments do not pay native validation unless they exercise recipes.
  late final NativeCatalogIndex _nativeCatalogIndex = NativeCatalogIndex(
    catalog,
  );

  /// Custom structured types keyed by resolved Dart type, derived directly
  /// from the merged catalog's `structuredTypes` (a plain source-type parse —
  /// NOT the native-validated [_nativeCatalogIndex], which rejects a catalog
  /// carrying unallocated sentinel wire IDs). The encode recognition only needs
  /// the entry's fields, so this avoids paying native validation on every
  /// non-framework construction — and reads the SAME `StructuredEntry` the
  /// decoder does, so encode↔decode key symmetry stays by construction.
  late final Map<DartTypeRef, StructuredEntry> _customStructuredByDartType = {
    for (final structured in catalog.structuredTypes)
      if (dartTypeRefFromSourceType(structured.sourceType) case final ref?)
        ref: structured,
  };

  /// Emits the RFW DSL map for a custom STRUCTURED VALUE authored in a
  /// paywall body — the ENCODE side of the custom-structured render path.
  /// `late final` so the injected method tear-offs bind to a fully-constructed
  /// `this`.
  late final CustomStructuredValueEmitter _customStructuredValue =
      CustomStructuredValueEmitter(
        structuredValueFor: (expr) {
          final ref = _dartTypeRefOfInstanceCreation(expr);
          return ref == null ? null : _customStructuredByDartType[ref];
        },
        dispatch: _recipeDispatcher.emit,
        locationOf: _locationOf,
      );

  /// Translates a single Dart [expr] into a DSL fragment.
  ///
  /// [sourcePath] and [lineInfo] improve issue location strings from byte
  /// offsets to `file:line:column`. Both default to null (offset-only
  /// fallback). [rootInlined] carries the root `build()` prelude's `final`
  /// locals and the helpers its calls inline.
  TranslationResult translate(
    Expression expr, {
    String? sourcePath,
    LineInfo? lineInfo,
    String? entryId,
    List<CustomWidgetStateField>? rootState,
    List<RootContextParam> rootParams = const [],
    Map<String, RecognisedSetState> rootEventHandlers = const {},
    Element? buildContextParameter,
    bool flowScreenContext = false,
    InlinedDefinitions rootInlined = const InlinedDefinitions.empty(),
    bool hoistInMount = false,
    bool islands = true,
    ClassElement? liftedState,
    List<FormalParameterElement> rootBuildArguments = const [],
    ContentFreeBuilders contentFree = ContentFreeBuilders.none,
    String? surfaceId,
  }) {
    final first = _translateArtifact(
      expr,
      sourcePath: sourcePath,
      lineInfo: lineInfo,
      entryId: entryId,
      rootState: rootState,
      rootParams: rootParams,
      rootEventHandlers: rootEventHandlers,
      buildContextParameter: buildContextParameter,
      flowScreenContext: flowScreenContext,
      rootInlined: rootInlined,
      hoistInMount: hoistInMount,
      islands: islands,
      liftedState: liftedState,
      rootBuildArguments: rootBuildArguments,
      contentFree: contentFree,
      surfaceId: surfaceId ?? entryId,
      forcedCustomWidgetFactoryRoutes: const {},
    );
    final mixed = first.inlineClaims.intersection(first.references);
    if (mixed.isEmpty) return first.result;
    return _translateArtifact(
      expr,
      sourcePath: sourcePath,
      lineInfo: lineInfo,
      entryId: entryId,
      rootState: rootState,
      rootParams: rootParams,
      rootEventHandlers: rootEventHandlers,
      buildContextParameter: buildContextParameter,
      flowScreenContext: flowScreenContext,
      rootInlined: rootInlined,
      hoistInMount: hoistInMount,
      islands: islands,
      liftedState: liftedState,
      rootBuildArguments: rootBuildArguments,
      contentFree: contentFree,
      surfaceId: surfaceId ?? entryId,
      forcedCustomWidgetFactoryRoutes: Map.unmodifiable({
        for (final identity in mixed) identity: first.factoryRoutes[identity],
      }),
    ).result;
  }

  ({
    TranslationResult result,
    Set<_CustomWidgetEmissionIdentity> inlineClaims,
    Set<_CustomWidgetEmissionIdentity> references,
    Map<_CustomWidgetEmissionIdentity, _CustomWidgetFactoryRoute> factoryRoutes,
  })
  _translateArtifact(
    Expression expr, {
    required String? sourcePath,
    required LineInfo? lineInfo,
    required String? entryId,
    required List<CustomWidgetStateField>? rootState,
    required List<RootContextParam> rootParams,
    required Map<String, RecognisedSetState> rootEventHandlers,
    required Element? buildContextParameter,
    required bool flowScreenContext,
    required InlinedDefinitions rootInlined,
    required bool hoistInMount,
    required bool islands,
    required ClassElement? liftedState,
    required List<FormalParameterElement> rootBuildArguments,
    required ContentFreeBuilders contentFree,
    required String? surfaceId,
    required Map<_CustomWidgetEmissionIdentity, _CustomWidgetFactoryRoute>
    forcedCustomWidgetFactoryRoutes,
  }) {
    final saved = _walk;
    _builderScopeCounter = 0;
    _keptClosures.clear();
    final savedHoist = _hoist;
    final hoistLibrary = switch (expr.root) {
      CompilationUnit(:final declaredFragment?) => declaredFragment.element,
      _ => null,
    };
    _hoist = hoistInMount && hoistLibrary != null
        ? _HoistSession(
            HoistAnalyzer(
              namespace: OwningLibraryNamespace(hoistLibrary),
              rootContext: buildContextParameter,
              isStateWidget: _isStateWidgetGetter,
              rootParamFor: _rootParamForElement,
              // While probing, a local the mount holds is read through its
              // initializer, so what it depends on is seen.
              isMountScope: (element) =>
                  (_islands?.inMountScope(element) ?? false) &&
                  !(_islands!.probing &&
                      _walk.inlined.localBindings.containsKey(element)),
              mountNameOf: (element) =>
                  _islands?.mountNames.containsKey(element.baseElement) ?? false
                  ? '\u0000${_islands!.heldSlot(element.baseElement)}\u0000'
                  : null,
              recordedLocalOf: (element) {
                if (element is FormalParameterElement && !_recordingSlot) {
                  return null;
                }
                final body = _islands?.buildBody;
                final offset = element.firstFragment.offset;
                return body != null &&
                        element.firstFragment.libraryFragment?.source ==
                            (body.root as CompilationUnit)
                                .declaredFragment
                                ?.source &&
                        offset >= body.offset &&
                        offset < body.end
                    ? heldLocalSlot(element.name ?? '', inner: true)
                    : null;
              },
              isSurfaceMember: (element) =>
                  _islands?.isSurfaceMember(element) ?? false,
              forwardsWidget: () => _islands?.liftedState != null,
              thisFor: (type) => _islands?.thisFor(type),
              thisOutOfReach: (type) =>
                  (_islands?.probing ?? false) &&
                  type?.element == _islands?.liftedState,
              isDeclaredCallable: (reference) =>
                  _borrowedNativeRoot(
                        _resolveBoundIdentifier(_stripParens(reference)),
                      )?.type
                      is FunctionType,
              bindingFor: (element) =>
                  _walk.paramBindings[element] ??
                  _walk.inlined.localBindings[element],
              buildArgumentFor: (element) => rootBuildArguments
                  .where(
                    (argument) =>
                        identical(argument.baseElement, element.baseElement),
                  )
                  .firstOrNull
                  ?.name,
              itemLoopFor: (element) {
                for (final loop in _walk.runtimeLoops.reversed) {
                  if (!loop.binds(element)) continue;
                  return loop.items ??
                      (loop.shape is HostDataObjectShape
                          ? loop.root?.name
                          : null);
                }
                return null;
              },
              keepsItemNames: (item) =>
                  _hoist?.values[item]?.kind == HoistValueKind.items,
              outerItem: (item) => _hoist?.values[item]?.item,
            ),
          )
        : null;
    _hoist?.onAdd = _recordValueSite;
    _hoist?.occurrence = _keyedByOccurrence;
    final hoist = _hoist;
    final savedIslands = _islands;
    final islandPackage = hoistLibrary?.uri.pathSegments.firstOrNull;
    final islandNamespace = islandPackage == null
        ? null
        : islandLibraryNamespace(islandPackage);
    final islandNamespaceTaken =
        islandNamespace != null &&
        !(catalog.libraries[WidgetLibrary.custom(islandNamespace)]?.islands ??
            true);
    _islands =
        islands &&
            hoist != null &&
            islandNamespace != null &&
            !islandNamespaceTaken
        ? _IslandSession(
            islandNamespace,
            hoistLibrary!,
            liftedState,
            islandSurface(expr, id: surfaceId),
            contentFree: contentFree,
            designOwnsState: rootState != null && liftedState != null,
            stateless: liftedState == null
                ? switch (expr
                      .thisOrAncestorOfType<ClassDeclaration>()
                      ?.declaredFragment
                      ?.element) {
                    final ClassElement owner
                        when stateWidgetOf(owner) == null =>
                      owner,
                    _ => null,
                  }
                : null,
          )
        : null;
    final islandSession = _islands;
    final savedNavigation = _currentNavigation;
    final savedFlowScreenContext = _flowScreenContext;
    final savedSuppressed = _currentTranslationSuppressed;
    final savedCollectionHelpers = _collectionHelpers;
    final savedCollectionSession = _collectionSession;
    final savedForcedCustomWidgetFactoryRoutes =
        _forcedCustomWidgetFactoryRoutes;
    _currentSourcePath = sourcePath;
    _currentLineInfo = lineInfo;
    _currentSourceUnit = expr.root;
    final savedLocalFields = _currentLocalFields;
    final localFields = rootState == null
        ? const <String>{}
        : _localValueFields(
            expr,
            rootInlined,
            {for (final field in rootState) field.name},
          );
    _currentLocalFields = localFields;
    _walk = _walk.copyWith(
      argNames: const {},
      stateFields: rootState == null
          ? null
          : {
              for (final field in rootState)
                if (!localFields.contains(field.name)) field.name: field,
            },
      rootParams: {for (final p in rootParams) p.name: p},
      eventHandlers: rootEventHandlers,
      rootStateContext: rootState != null,
      // The root walk's prelude locals; a definition body substitutes its own.
      inlined: rootInlined,
      measurementScope: measurementRouteEmissionPlan?.rootScope,
      measurementWidget: null,
      measurementWidgetList: null,
    );
    _collectionHelpers = _collectionHelperDefinitions(expr);
    _collectionSession = CollectionSemanticTraversalSession(
      admitsPlacedReuse: _routedPerSpot,
    );
    _currentNavigation = null;
    _flowScreenContext = flowScreenContext;
    _currentTranslationSuppressed = false;
    final issues = <Issue>[
      if (islands && islandNamespaceTaken)
        islandNamespaceTakenIssue(islandNamespace),
    ];
    final emissionSources = <DslEmissionSource>[];
    final savedEmissionSources = _emissionSources;
    _emissionSources = emissionSources;
    final widgetDefinitions = <String, String>{};
    final widgetDefinitionStates = <String, Map<String, String>>{};
    final rootWidgetState = <String, String>{};
    final localSeeds = <String, Object>{};
    final definitionOwners = <String, String>{};
    final referencedCustomLibraries = <String>{};
    final iconReferences = IconReferenceCollector();
    final rfwCatalogConstructorOrigins =
        <String, fmt.RfwCatalogConstructorProvenance>{};
    final customWidgetInlineClaims = <_CustomWidgetEmissionIdentity>{};
    final customWidgetReferences = <_CustomWidgetEmissionIdentity>{};
    final customWidgetFactoryRoutes =
        <_CustomWidgetEmissionIdentity, _CustomWidgetFactoryRoute>{};
    _currentWidgetDefinitions = widgetDefinitions;
    _currentWidgetDefinitionStates = widgetDefinitionStates;
    _currentDefinitionOwners = definitionOwners;
    _currentReferencedCustomLibraries = referencedCustomLibraries;
    _currentIconReferences = iconReferences;
    _currentRfwCatalogConstructorOrigins = rfwCatalogConstructorOrigins;
    _currentCustomWidgetInlineClaims = customWidgetInlineClaims;
    _currentCustomWidgetReferences = customWidgetReferences;
    _currentCustomWidgetFactoryRoutes = customWidgetFactoryRoutes;
    _forcedCustomWidgetFactoryRoutes = forcedCustomWidgetFactoryRoutes;
    final savedEventClosureNotices = _currentEventClosureNotices;
    final eventClosureNotices = <Issue>[];
    _currentEventClosureNotices = eventClosureNotices;
    final savedFiredEvents = _currentFiredEvents;
    final firedEvents = <PropertyInducingElement>{};
    _currentFiredEvents = firedEvents;
    final savedPlaced = _currentPlacedCustomWidgets;
    final placed = <ClassElement>{};
    _currentPlacedCustomWidgets = placed;
    final savedPlacedSites = _currentPlacedCustomWidgetSites;
    final placedSites = <AstNode>[];
    _currentPlacedCustomWidgetSites = placedSites;
    final savedEmitsInteractionItems = _currentEmitsInteractionItems;
    _currentEmitsInteractionItems = false;
    var emitsInteractionItems = false;
    var dsl = '';
    var suppressed = false;
    NavigationLowering? navigationLowering;
    try {
      // The mount keeps the root shell; the rest is the design.
      final design = islandSession == null
          ? expr
          : _splitRoot(expr, islandSession, liftedState);
      if (islandSession?.problem case final problem?) issues.add(problem);
      // Under a split, a root sheet or navigation that cannot lower leaves
      // its closures to the mount as actions. A refused sheet also leaves
      // navigation to the app; failing navigation keeps the sheet. Without a
      // split, either refusal fails the build.
      final split = islandSession != null;
      bool refuses(List<Issue> found) =>
          found.any((issue) => !issue.code.isBuildNotice);
      final sheetIssues = <Issue>[];
      final modalSheet = _findSingleRootModalSheetTrigger(design, sheetIssues);
      final navigationIssues = <Issue>[];
      bool clean() =>
          issues.isEmpty && navigationIssues.isEmpty && sheetIssues.isEmpty;
      final navigationTriggers = entryId == null || !clean()
          ? const <RecognisedNavigation>[]
          : _findRootNavigationTriggers(
              design,
              navigationIssues,
              buildContextParameter: buildContextParameter,
            );
      var navigationContext = clean() && entryId != null
          ? _createNavigationContext(
              entryId: entryId,
              expr: design,
              triggers: navigationTriggers,
              issues: navigationIssues,
              buildContextParameter: buildContextParameter,
            )
          : null;
      if (split && refuses(navigationIssues)) navigationContext = null;
      for (final found in [sheetIssues, navigationIssues]) {
        if (!split || !refuses(found)) issues.addAll(found);
      }
      final rootShapeIssue = issues.isEmpty
          ? _validateRootStateShape(rootState, rootEventHandlers, expr)
          : null;
      if (rootShapeIssue != null) issues.add(rootShapeIssue);
      if (issues.isEmpty) {
        if (rootState != null) {
          rootWidgetState.addAll({
            for (final field in rootState)
              if (!localFields.contains(field.name))
                field.name: _stateInitialLiteral(field),
          });
          _collectLocalSeeds(
            rootState,
            rootEventHandlers,
            localFields,
            localSeeds,
            issues,
            expr,
          );
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
        if (_branches(issues) case final branches?) {
          dsl = branches;
        } else if (_admitOrdinaryLeaf(design, issues)) {
          dsl = _translate(design, issues);
        }
        final context = _walk.modalSheet;
        if (context != null && issues.isEmpty) {
          dsl = _emitModalSheetRoot(
            context,
            underlayDsl: dsl,
            issues: issues,
          );
        }
        if (context != null && issues.isNotEmpty) dsl = '';
        // The plan holds only transitions whose event the design fires.
        if (navigationContext != null && navigationContext.hasTransitions) {
          navigationLowering = navigationContext.toLowering(
            emitted: [dsl, ...widgetDefinitions.values],
          );
        }
        if (navigationContext != null &&
            (issues.any((issue) => !issue.code.isBuildNotice) ||
                _currentTranslationSuppressed)) {
          dsl = '';
          navigationLowering = null;
        }
      }
    } finally {
      _walk = saved;
      _collectionHelpers = savedCollectionHelpers;
      _collectionSession = savedCollectionSession;
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
      _currentReferencedCustomLibraries = null;
      _currentIconReferences = null;
      _currentRfwCatalogConstructorOrigins = null;
      _currentCustomWidgetInlineClaims = null;
      _currentCustomWidgetReferences = null;
      _currentCustomWidgetFactoryRoutes = null;
      _forcedCustomWidgetFactoryRoutes = savedForcedCustomWidgetFactoryRoutes;
      _currentEventClosureNotices = savedEventClosureNotices;
      // A nested translation's events are the enclosing build's too.
      _currentFiredEvents = savedFiredEvents?..addAll(firedEvents);
      _currentPlacedCustomWidgets = savedPlaced?..addAll(placed);
      _currentPlacedCustomWidgetSites = savedPlacedSites?..addAll(placedSites);
      emitsInteractionItems = _currentEmitsInteractionItems;
      _currentEmitsInteractionItems = savedEmitsInteractionItems;
      _currentLocalFields = savedLocalFields;
      _emissionSources = savedEmissionSources;
      // Clear the per-call source context so it never lingers past this call —
      // a helper invoked directly (not through `translate`) would otherwise
      // read a stale source path / line info from a previous translation.
      _currentSourcePath = null;
      _currentLineInfo = null;
      _currentSourceUnit = null;
      _hoist = savedHoist;
      _islands = savedIslands;
    }
    // Island tokens need the surface's whole island set.
    if (islandSession != null) {
      assignIslandTokens(islandSession.islands.values);
      for (final island in islandSession.islands.values) {
        final entry = islandWidgetEntry(island);
        rfwCatalogConstructorOrigins[entry.name] =
            fmt.RfwCatalogConstructorProvenance(
              constructorName: entry.name,
              catalogLibraryNamespace: entry.library.namespace,
              catalogWidgetWireId: entry.wireId,
            );
      }
    }
    if (dsl.isNotEmpty &&
        !suppressed &&
        !issues.any((issue) => !issue.code.isBuildNotice)) {
      issues.addAll(_customWidgetFactoryNotices(customWidgetFactoryRoutes));
      final seen = <String>{};
      issues.addAll(
        eventClosureNotices.where((notice) => seen.add(notice.buildNoticeKey)),
      );
    }
    final recordedSplit = _recorded(
      islandSession?.split,
      islandSession,
      hoist,
      // A pushed screen needs the recorded copy only where a mount can carry
      // it; without the generated part the surface compiles as it did.
      navigates:
          navigationLowering != null &&
          hoistLibrary != null &&
          declaresGeneratedPart(hoistLibrary),
    );
    if (islandSession != null) issues.addAll(islandSession.recordIssues);
    return (
      result: TranslationResult(
        dsl: dsl,
        issues: issues,
        navigation: navigationLowering,
        suppressed: suppressed,
        widgetDefinitions: widgetDefinitions,
        widgetDefinitionStates: widgetDefinitionStates,
        rootWidgetState: rootWidgetState,
        referencedCustomLibraries: referencedCustomLibraries,
        iconReferences: iconReferences.references,
        emitsInteractionItems: emitsInteractionItems,
        completesSurface: _declaresCompletion(expr),
        emissionSources: emissionSources,
        hoisted: hoist == null
            ? const []
            : ([
                for (final value in hoist.values.values)
                  // A value only a slot records is the slot's own, never
                  // the mount's.
                  if (!_slotOnly(hoist, value.key))
                    switch (hoist.records
                        .where((record) => record.key == value.key)
                        .firstOrNull) {
                      final record? when value.location == null => value.at(
                        _locationOf(record.site),
                      ),
                      _ => value,
                    },
              ]..sort((left, right) => left.key.compareTo(right.key))),
        split: recordedSplit,
        firedEvents: {...firedEvents, ...?islandSession?.firedEvents},
        placedCustomWidgets: placed,
        placedCustomWidgetSites: placedSites,
        blocked: islandSession?.blocked ?? const {},
        islands: islandSession == null
            ? const []
            : (islandSession.islands.values.toList()
                ..sort((left, right) => left.id.compareTo(right.id))),
        localSeeds: localSeeds,
        usesLocalValues: localFields.isNotEmpty,
        rfwCatalogConstructorOrigins:
            rfwCatalogConstructorOrigins.values.toList()..sort(
              (left, right) =>
                  left.constructorName.compareTo(right.constructorName),
            ),
      ),
      inlineClaims: Set.unmodifiable(customWidgetInlineClaims),
      references: Set.unmodifiable(customWidgetReferences),
      factoryRoutes: Map.unmodifiable(customWidgetFactoryRoutes),
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
  /// required mechanism, a non-foldable State shape, or an unrecognised body
  /// expression —
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
  /// emitted DSL and the post-emit `validateModelAgainstCatalog` schema walk
  /// (see `codegen_builder`). So a body that translates issue-free but whose
  /// emitted DSL would fail one of those would still count confirmed here.
  /// The metric is therefore a (safe-direction) **over-confirming upper
  /// bound** — it never under-counts inlinable; the residual is narrow and
  /// closes once the measurement is run against the full real-catalog emit.
  ///
  /// Private to the coverage-measurement tooling (the harness + the
  /// standalone CLI). Callers map the result to an `EmitOutcome`.
  TranslationResult attemptInlineEmit(
    WidgetClassification classification,
    CustomWidgetBlueprint blueprint, {
    List<RootContextParam> rootParams = const [],
  }) {
    final savedCollectionSession = _collectionSession;
    _collectionSession = CollectionSemanticTraversalSession(
      admitsPlacedReuse: _routedPerSpot,
    );
    try {
      return _attemptInlineEmit(
        classification,
        blueprint,
        rootParams: rootParams,
      );
    } finally {
      _collectionSession = savedCollectionSession;
    }
  }

  TranslationResult _attemptInlineEmit(
    WidgetClassification classification,
    CustomWidgetBlueprint blueprint, {
    required List<RootContextParam> rootParams,
  }) {
    _currentSourcePath = null;
    _currentLineInfo = null;
    _currentSourceUnit = null;
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

    // The same name the production inline path emits under.
    final name = _definitionName(blueprint);

    // State-shape validation (non-foldable initialiser / unrecognised
    // setState body) — surfaced before body translation, as the inline path
    // does.
    final shapeIssue = _validateStateShape(
      blueprint,
      blueprint.buildExpression,
    );
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
      argNames: {for (final p in blueprint.params) p.readName: p.name},
      params: {for (final p in blueprint.params) p.name: p},
      // Custom-widget definitions cannot read root host data.
      rootParams: const {},
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
      if (_admitOrdinaryLeaf(blueprint.buildExpression, issues)) {
        definitions[name] = _translate(blueprint.buildExpression, issues);
      }
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
    final site = _valueSite;
    _valueSite = expr;
    try {
      return _translateAt(expr, issues);
    } finally {
      _valueSite = site;
    }
  }

  String _translateAt(Expression expr, List<Issue> issues) {
    if (_islands?.stubs.contains(expr) ?? false) return 'SizedBox()';
    final dsl =
        _islandAttempt(expr, issues) ??
        (_activeWidgetBuilder == null
            ? _hoisted(
                expr,
                issues,
                (scratch) => _translateExpression(expr, scratch),
              )
            : null) ??
        _translateExpression(expr, issues);
    _recordEmission(expr, dsl);
    _noteParamPlacement(dsl, expr);
    return dsl;
  }

  /// Translates a widget expression of a mounted surface, or emits it as an
  /// island when it does not lower; `null` when [expr] is no candidate.
  String? _islandAttempt(Expression expr, List<Issue> issues) {
    final session = _islands;
    final node = _stripParens(expr);
    if (session == null ||
        (node is! InstanceCreationExpression && node is! MethodInvocation) ||
        classifyHoistType(node.staticType) is! HoistIsWidget) {
      return null;
    }
    if (_hoist!.speculating ||
        _activeWidgetBuilder != null ||
        _walk.classKey != null) {
      // No island forms here, so a widget kept as the app builds it is
      // refused, never lowered; the refusal also ends a speculation.
      if (optOutOf(node, _locationOf(node)) case final kept?) {
        issues.add(optOutUnkept(node, kept.location, null));
        return '';
      }
      return null;
    }
    if (!session.attempting.add(node)) return null;
    try {
      // A widget the developer keeps as the app builds it is an island.
      if (optOutOf(node, _locationOf(node)) case final kept?) {
        if (_emitIsland(node, [kept], issues) case final island?) {
          return island;
        }
        issues.add(
          optOutUnkept(
            node,
            kept.location,
            session.blockedBy.remove(node)?.name,
          ),
        );
        return '';
      }
      // A helper that reads an argument that runs code more than once
      // renders in the app as written, so the argument runs once.
      if (_repeatsCode(node)) {
        if (_emitIsland(node, const [], issues) case final island?) {
          return island;
        }
      }
      final attempt = _attempt(node);
      if (attempt.lowers) {
        issues.addAll(attempt.issues);
        return attempt.dsl;
      }
      // Only a node that needs app code renders from the app.
      final island =
          attempt.issues.every(
            (issue) => issue.code.isBuildNotice || issue.code.needsAppCode,
          )
          ? _emitIsland(node, attempt.issues, issues)
          : null;
      if (island != null) return island;
      issues.addAll(switch (session.blockedBy.remove(node)) {
        final blocked? => _surfaceOnlyIssues(node, blocked, attempt.issues),
        null => attempt.issues,
      });
      return '';
    } finally {
      session.attempting.remove(node);
    }
  }

  // [issues] with a generic first refusal replaced by the surface value [node]
  // needs; a refusal that names its own cause stays.
  List<Issue> _surfaceOnlyIssues(
    Expression node,
    HoistNeedsSurfaceValue blocked,
    List<Issue> issues,
  ) {
    final first = issues.indexWhere((issue) => !issue.code.isBuildNotice);
    // A custom widget's gap is replaced too: an app widget that doesn't lower
    // is an island, so the surface value is why it didn't form.
    if (first < 0 ||
        !const {
          IssueCode.unknownWidget,
          IssueCode.unrecognizedMethodCall,
          IssueCode.customWidgetInliningDeferred,
          IssueCode.customWidgetImperative,
          IssueCode.customWidgetUnsupportedReducible,
          IssueCode.customWidgetUnclassified,
        }.contains(issues[first].code)) {
      return issues;
    }
    final screen = _islands!.surface.screen;
    final place = '`${readableSource(node.toSource())}` (${_locationOf(node)})';
    final message = _declaredByIfCase(node, blocked)
        ? "$place: Restage can't use `${blocked.name}` because an `if case` "
              'pattern declares it. Try testing the value with `!= null` and '
              'using it with `!` instead.'
        : '$place: uses `${blocked.name}`, which only exists inside '
              "`$screen`. Try passing it in through the screen's constructor.";
    return [
      ...issues.take(first),
      // The message names its place, so the issue names the declaration.
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message: message,
        location: _declarationOf(node),
      ),
      ...issues.skip(first + 1),
    ];
  }

  // Whether the surface-only name [blocked] reads is a variable an `if case`
  // pattern declares.
  static bool _declaredByIfCase(AstNode node, HoistNeedsSurfaceValue blocked) {
    final elements = {
      if (blocked.node case SimpleIdentifier(:final element?))
        element.baseElement,
      for (final element in blocked.elements)
        if (element.name == blocked.name) element.baseElement,
    };
    if (elements.isEmpty) return false;
    var found = false;
    node.root.accept(
      _PatternVariables((pattern) {
        if (!elements.contains(pattern.declaredFragment?.element.baseElement)) {
          return;
        }
        final clause = pattern.thisOrAncestorOfType<CaseClause>();
        found =
            found ||
            clause?.parent is IfStatement ||
            clause?.parent is IfElement;
      }),
    );
    return found;
  }

  /// Emits [node] as an island: widget arguments that lower become slots and
  /// literal ones properties. `null` when the mount cannot evaluate the rest.
  ///
  /// With [shared], [node] is the initializer of a local the mount computes
  /// once, and the island is that local's placement at [shared].
  String? _emitIsland(
    Expression node,
    List<Issue> failure,
    List<Issue> issues, {
    SimpleIdentifier? shared,
  }) {
    // A reserved event stays refused when the widget that fires it renders
    // from the app.
    final reserved = _reservedEventIssues(node);
    if (reserved.isNotEmpty) {
      issues.addAll(reserved);
      return '';
    }
    final session = _islands!;
    final restore = _checkpoint();
    // The ordinal is the order the surface uses its islands, an enclosing
    // island before those nested in it.
    final scope = _walk.islandScope.join('>');
    final widget = islandWidgetType(node);
    final key = '$scope/$widget';
    final peers = [
      for (final entry in session.order)
        if (entry.key == key) entry.node,
    ];
    final ordinal = switch (peers.indexWhere((peer) => identical(peer, node))) {
      -1 => peers.length,
      final index => index,
    };
    if (ordinal == peers.length) session.order.add((key: key, node: node));
    final slots = <IslandSlot>[];
    final properties = <IslandProperty>[];
    final holes = <AstNode, String>{};
    final compiled = <IslandCompiledArgument>[];
    final kept = <Issue>[];
    final arguments = node is InstanceCreationExpression && shared == null
        ? node.argumentList.arguments
        : const <Argument>[];
    // Slots are children of the island's own measured occurrence.
    final walk = _walk;
    final widgetClass = node is InstanceCreationExpression
        ? node.constructorName.type.element
        : null;
    if (_walk.measurementScope case final scope?
        when widgetClass is InterfaceElement) {
      _walk = _walk.copyWith(
        measurementScope: null,
        measurementWidget: scope.widget(widgetClass),
        measurementWidgetList: null,
      );
    }
    // A helper call or a local the mount computes once keeps its arguments.
    final frozen = switch (node) {
      InstanceCreationExpression(:final argumentList) when shared != null => (
        argumentList.arguments,
        IslandCompiledReason.sharedLocal,
        shared.name,
      ),
      MethodInvocation(:final argumentList) => (
        argumentList.arguments,
        IslandCompiledReason.helperCall,
        null,
      ),
      _ => null,
    };
    if (frozen case (final frozen, final reason, final detail)) {
      for (final argument in frozen) {
        final name = _islandArgumentLabel(argument);
        if (name == 'key') continue;
        compiled.add(IslandCompiledArgument(name, reason, detail: detail));
      }
    }
    for (final argument in arguments) {
      final value = argument.argumentExpression;
      final parameter = argument.correspondingParameter;
      // A positional argument takes its parameter's public name.
      final name = switch (argument) {
        NamedArgument(:final name) => name.lexeme,
        _ => islandArgumentName(parameter),
      };
      if (name == null) {
        compiled.add(
          IslandCompiledArgument(
            _islandArgumentLabel(argument),
            parameter?.name == '_'
                ? IslandCompiledReason.wildcard
                : IslandCompiledReason.unresolved,
          ),
        );
        continue;
      }
      void keep(IslandCompiledReason reason, {String? detail}) {
        if (name == 'key') return;
        compiled.add(IslandCompiledArgument(name, reason, detail: detail));
      }

      // The first refusal of a nested translation, which says why.
      String? refusal(List<Issue> scratch) => scratch
          .where((issue) => !issue.code.isBuildNotice)
          .firstOrNull
          ?.message;

      // An app builder whose body lowers stays in the island; its body is
      // delivered as a slot.
      if (_stripParens(value) case final FunctionExpression callback) {
        final builder = AppValueSlot.of(callback);
        if (builder == null) {
          keep(
            islandTypeReason(callback.staticType) ??
                IslandCompiledReason.callback,
          );
          continue;
        }
        final undo = _checkpoint();
        final misses = _hoist!.closureMisses.length;
        final scratch = <Issue>[];
        // The slot runs its own closure, recording what its body reads.
        _keptClosures.add(callback);
        final dsl = _translateWidgetBuilder(
          callback,
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: name,
            type: PropertyType.widgetBuilder,
            description: '',
            builderContract: builder.contract,
          ),
          scratch,
        );
        if (dsl.isEmpty ||
            scratch.any((issue) => !issue.code.isBuildNotice) ||
            _hoist!.closureMisses.length != misses) {
          _keptClosures.remove(callback);
          undo();
          keep(
            IslandCompiledReason.builderBody,
            detail: refusal(scratch),
          );
          continue;
        }
        kept.addAll(scratch);
        holes[value] = islandHole(name);
        slots.add(
          IslandSlot(
            name,
            list: false,
            dsl: dsl,
            node: value,
            builder: builder,
          ),
        );
        continue;
      }
      final type = parameter?.type ?? value.staticType;
      final list = _isWidgetListType(type);
      final slot = list || classifyHoistType(type) is HoistIsWidget;
      final literal = _isLiteralArgument(value);
      final propertyShape = slot || !literal ? null : islandPropertyShape(type);
      final propertyType = propertyShape?.propertyType;
      final fallback = switch (propertyType == null
          ? null
          : _hoist!.analyzer.analyze(value)) {
        final HoistEvaluable evaluable => evaluable,
        _ => null,
      };
      if (!slot && fallback == null) {
        // Whether a design can carry the type comes before how it's written.
        final source = readableSource(value.toSource());
        switch (islandTypeReason(type)) {
          case final reason?:
            keep(reason, detail: type == null ? null : islandTypeName(type));
          case null when !literal:
            keep(IslandCompiledReason.notLiteral, detail: source);
          case null:
            keep(IslandCompiledReason.notEvaluable, detail: source);
        }
        continue;
      }
      final undo = _checkpoint();
      final scratch = <Issue>[];
      final dsl = _translateSlotValue(
        value,
        propertyType ?? (list ? PropertyType.widgetList : PropertyType.widget),
        scratch,
        sourceParameter: propertyType == null
            ? argument.correspondingParameter
            : null,
      );
      if (dsl.isEmpty || scratch.any((issue) => !issue.code.isBuildNotice)) {
        undo();
        keep(
          propertyType == null
              ? IslandCompiledReason.slotContent
              : IslandCompiledReason.notEvaluable,
          detail: propertyType == null
              ? refusal(scratch)
              : readableSource(value.toSource()),
        );
        continue;
      }
      kept.addAll(scratch);
      holes[value] = islandHole(name);
      if (propertyType == null) {
        slots.add(IslandSlot(name, list: list, dsl: dsl, node: value));
      } else {
        // A preview runs without the app's build, so it copies the value as
        // written only when it reads nothing the build declares.
        properties.add(
          IslandProperty(
            name,
            argument: argument,
            shape: propertyShape!,
            dsl: dsl,
            fallback: fallback!.template,
            closed: !_needsMount(value, const {}),
            nullable: type?.nullabilitySuffix == NullabilitySuffix.question,
          ),
        );
      }
    }
    _walk = walk;
    final analysis = _hoist!.analyzer.analyze(shared ?? node, holes: holes);
    if (analysis is! HoistEvaluable) {
      if (analysis case final HoistNeedsSurfaceValue blocked) {
        session.blocked.addAll(blocked.elements);
        session.blockedBy[node] = blocked;
      }
      restore();
      return null;
    }
    // The island takes its position in every loop around it, so each
    // iteration keeps its own element, and binds the items it reads.
    final loops = _walk.runtimeLoops;
    final reads = <int>{
      for (
        String? item = analysis.item;
        item != null;
        item = _hoist!.values[item]?.item
      )
        loops.lastIndexWhere((loop) => loop.item == item),
    };
    if (reads.contains(-1) || loops.any((loop) => !_keysItems(loop))) {
      restore();
      return null;
    }
    issues.addAll(kept);
    final identity = islandIdentity(session.surface, scope, widget, ordinal);
    final island = Island(
      id: identity.id,
      name: identity.name,
      widget: widget,
      screen: session.surface.screen,
      scope: scope,
      location: _locationOf(node),
      reason: failure.where((issue) => !issue.code.isBuildNotice).firstOrNull,
      slots: slots,
      properties: properties,
      compiled: compiled,
      template: analysis.template,
      library: session.namespace,
      node: node,
      items: [for (final loop in loops) loop.item!],
      reads: reads,
      placements: [
        // Exclusive placements share the island; the fallback keys each.
        ...?session.islands[identity.id]?.placements,
        (at: shared ?? node, through: [..._localReads]),
      ],
      preview: _islandPreview(shared ?? node, holes),
    );
    if (session.islands[identity.id] case final prior?
        when prior.implementation != island.implementation ||
            !identical(prior.node, node)) {
      issues.add(islandNameConflictIssue(widget, _locationOf(node)));
      restore();
      return null;
    }
    session.islands[identity.id] = island;
    final placement = _placementOf(shared ?? node);
    // A value placed at spots the build's copy can't mark keeps no identity.
    if (placement.spots.firstWhereOrNull((read) => _spotForm(read) == null)
        case final read?) {
      issues.add(
        Issue(
          code: IssueCode.islandSpotsIndistinct,
          message:
              '`$widget` (${_locationOf(node)}) is placed in more than one '
              'spot through `${read.toSource()}`, and Restage can\'t tell '
              'those spots apart here, so its State resets when a new design '
              'is shown. Try giving each spot its own value.',
          location: _locationOf(node),
        ),
      );
    }
    _recordsWithoutDesignState(
      shared ?? node,
      holes: {for (final MapEntry(:key, :value) in holes.entries) key: value},
      kind: _Recorded.widget,
    );
    session.recordIslands.add((
      name: identity.name,
      node: shared ?? node,
      shared: shared != null,
      placement: placement,
      holes: {
        for (final MapEntry(:key, :value) in holes.entries)
          key: (
            marker: value.replaceAllMapped(
              islandHolePattern,
              (m) => '\u0002${identity.name}|${m[1]}\u0002',
            ),
            property: properties.any((p) => islandHole(p.name) == value),
          ),
      },
      calls: [..._callSites],
      items: loops.isEmpty ? null : loops.last.item,
    ));
    _currentReferencedCustomLibraries?.add(session.namespace);
    return '${identity.name}(${[
      for (final property in properties) '${_rfwMapKey(property.name)}: ${property.dsl}',
      for (final slot in slots) '${_rfwMapKey(slot.name)}: ${slot.dsl}',
      if (loops.isNotEmpty) '$kPlacementItemsArgument: [${[
          for (final loop in loops) '${loop.identifier}'
                '${_rfwPathPart(_hoist!.add(itemIndexValue(loop.item!, label: _itemIndexLabel(loop))).key)}',
        ].join(', ')}]',
    ].join(', ')})';
  }

  // How many times the local or parameter [read] names is read where it is
  // declared.
  int _readsOf(SimpleIdentifier read) {
    final element = read.element;
    final offset = element?.firstFragment.offset;
    if (element == null || offset == null) return 0;
    return _readCounts[element] ??= () {
      // The function that declares it: its body holds a local, its
      // parameter list a parameter.
      final scope = read.thisOrAncestorMatching<AstNode>(
        (node) =>
            node is FunctionBody &&
            node.parent != null &&
            node.parent!.offset <= offset &&
            offset < node.parent!.end,
      );
      if (scope == null) return 0;
      var count = 0;
      scope.accept(
        _IdentifierVisitor((identifier) {
          if (identifier.element?.baseElement == element.baseElement &&
              !identifier.inDeclarationContext()) {
            count++;
          }
        }),
      );
      return count;
    }();
  }

  final _readCounts = Map<Element, int>.identity();

  // How the build's copy marks [read] without changing what its value is
  // used as: `spot` for a widget, `spotEach` for widgets spread or passed
  // as a list. Null where a marked value wouldn't type, so its placements
  // keep no identity.
  String? _spotForm(SimpleIdentifier read) {
    final library = switch (read.root) {
      CompilationUnit(:final declaredFragment?) => declaredFragment.element,
      _ => null,
    };
    final type = read.staticType;
    if (library == null || type is! InterfaceType) return null;
    InterfaceType? widgetOf(InterfaceType type) =>
        [
          type,
          ...type.allSupertypes,
        ].firstWhereOrNull(
          (t) =>
              isFlutterFrameworkType(t.element, 'Widget') &&
              t.element.name == 'Widget',
        );
    final iterable =
        type.allSupertypes.firstWhereOrNull(
          (t) => t.isDartCoreIterable,
        ) ??
        (type.isDartCoreIterable ? type : null);
    final element = iterable?.typeArguments.singleOrNull;
    final widget = element is InterfaceType
        ? widgetOf(element)
        : widgetOf(type);
    if (widget == null) return null;
    final marked = iterable == null
        ? widget
        : library.typeProvider.listType(widget);
    final context = switch (read.parent) {
      SpreadElement(:final parent) => switch (parent) {
        TypedLiteral(:final staticType?) => staticType,
        _ => null,
      },
      _ => _contextTypeOf(read),
    };
    if (context == null) return null;
    final fits = read.parent is SpreadElement
        ? context is InterfaceType &&
              library.typeSystem.isAssignableTo(
                marked,
                library.typeProvider.iterableType(
                  context.typeArguments.firstOrNull ?? widget,
                ),
              )
        : library.typeSystem.isAssignableTo(marked, context);
    if (!fits) return null;
    return iterable == null ? 'spot' : 'spotEach';
  }

  // The type the code around [expression] expects of it, if it says one.
  DartType? _contextTypeOf(Expression expression) {
    final parent = expression.parent;
    return switch (parent) {
      ParenthesizedExpression() => _contextTypeOf(parent),
      ConditionalExpression(:final condition)
          when !identical(condition, expression) =>
        _contextTypeOf(parent),
      NamedArgument() => expression.correspondingParameter?.type,
      ArgumentList() => expression.correspondingParameter?.type,
      ListLiteral(:final staticType?) => switch (staticType) {
        InterfaceType(:final typeArguments) => typeArguments.singleOrNull,
        _ => null,
      },
      ExpressionFunctionBody() => _returnTypeOf(parent),
      ReturnStatement() => switch (parent
          .thisOrAncestorOfType<FunctionBody>()) {
        final body? => _returnTypeOf(body),
        null => null,
      },
      _ => null,
    };
  }

  DartType? _returnTypeOf(FunctionBody body) => switch (body.parent) {
    FunctionExpression(:final declaredFragment?) =>
      declaredFragment.element.returnType,
    MethodDeclaration(:final declaredFragment?) =>
      declaredFragment.element.returnType,
    _ => null,
  };

  // The build locals being translated through, outermost first.
  final _localReads = <({SimpleIdentifier read, Expression initializer})>[];

  // Every read a widget value is translated through, outermost first: a
  // build local, a const local or a helper parameter, with what it stands
  // for (`null` for a const local's own initializer).
  final _placementReads = <({SimpleIdentifier read, Expression? bound})>[];

  // Where the app places the widget [node] builds: the outermost read its
  // value flows through unchanged, and the [spots], outermost first, of the
  // reads that place a value holding it, which tell its placements apart.
  ({AstNode at, List<SimpleIdentifier> spots}) _placementOf(AstNode node) {
    AstNode at = node;
    final spots = <SimpleIdentifier>[];
    for (final (:read, :bound) in _placementReads.reversed) {
      final same = bound == null
          ? switch (_stripParensNode(at).parent) {
              final VariableDeclaration declaration =>
                declaration.declaredFragment?.element == read.element,
              _ => false,
            }
          : identical(_stripParensNode(bound), _stripParensNode(at));
      if (spots.isEmpty && same) {
        at = read;
      } else if (_readsOf(read) > 1) {
        // A value read once is placed once: its own key tells it apart.
        spots.insert(0, read);
      }
    }
    return (at: at, spots: spots);
  }

  AstNode _stripParensNode(AstNode node) =>
      node is Expression ? _stripParens(node) : node;

  // The expression being translated, where a value hoisted now is read.
  AstNode? _valueSite;

  // Whether a value an app builder's body records is being translated; such
  // a value may read the builder's own parameters.
  bool _recordingSlot = false;

  // The inlined helper calls being translated through, outermost first.
  final _callSites = <AstNode>[];

  // [value] under its occurrence's key: the first occurrence of a text keeps
  // its key, and each other one gets its own.
  HoistedValue _keyedByOccurrence(HoistedValue value) {
    final hoist = _hoist!;
    final node = value.site ?? _valueSite;
    // Repeats of a read that runs no code, of a binding the mount borrows,
    // or of a loop's items are one value.
    if (_islands == null ||
        node == null ||
        hoist.exposing ||
        value.kind == HoistValueKind.items ||
        value.kind == HoistValueKind.itemIndex ||
        value.kind == HoistValueKind.nativeBinding && !value.computed ||
        !_evaluatesCode(node) && !_readsReassigned(node)) {
      return value;
    }
    final id =
        '${value.key}|${occurrenceOf(node, _callSites)}|'
        '${[for (final step in _unrolled) step.ordinal].join('.')}';
    final key = hoist.occurrenceKeys[id] ??= switch (hoist.occurrenceCounts
        .update(value.key, (count) => count + 1, ifAbsent: () => 0)) {
      0 => value.key,
      final count => '${value.key}_$count',
    };
    return key == value.key ? value : value.withKey(key);
  }

  // Whether [node] reads a local the build assigns after declaring it.
  bool _readsReassigned(AstNode node) {
    var found = false;
    node.accept(
      _ElementReferenceVisitor.at(
        (element) =>
            element is LocalVariableElement &&
            !element.isFinal &&
            !element.isConst,
        (_) => found = true,
      ),
    );
    return found;
  }

  void _recordValueSite(HoistedValue value) {
    final site = _valueSite;
    if (_islands == null) return;
    final at =
        value.site ?? (site == null ? null : _recordSite(site, value) ?? site);
    // A binding the mount borrows is provided whatever the design shows.
    if (at != null &&
        !(value.kind == HoistValueKind.nativeBinding && !value.computed)) {
      _recordsWithoutDesignState(at, label: value.label);
    }
    if (at != null) {
      _hoist!.records.add((
        key: value.key,
        site: at,
        calls: [..._callSites],
        unrolled: [..._unrolled],
        slot: _recordingSlot,
      ));
      // A value a widget closure records exists only when that closure runs:
      // a kept builder's or an island slot's. A binding the mount borrows
      // isn't recorded, so the delivered design reads it anywhere.
      if (!_recordingSlot &&
          !(value.kind == HoistValueKind.nativeBinding && !value.computed) &&
          !_hoist!.exposing &&
          !_recordedEarly(at, _callSites) &&
          [at, ..._callSites].any((node) => _unrunClosure(node) != null)) {
        _hoist!.closureMisses.add(at);
      }
    }
  }

  // The widget-building closure around [node] that the design path doesn't
  // run, or `null`.
  FunctionExpression? _unrunClosure(AstNode node) {
    for (
      AstNode? cursor = node.parent;
      cursor != null && cursor is! MethodDeclaration;
      cursor = cursor.parent
    ) {
      if (cursor is! FunctionExpression) continue;
      if (cursor.parent is FunctionDeclaration) return null;
      final type = cursor.staticType;
      if (type is FunctionType &&
          classifyHoistType(type.returnType) is HoistIsWidget &&
          !_keptClosures.contains(cursor)) {
        return cursor;
      }
    }
    return null;
  }

  // Whether the value at [at], in a widget closure the design path doesn't
  // run, reads only what the build has before that closure and runs no code,
  // so the mount records it where the design is built.
  bool _recordedEarly(AstNode at, List<AstNode> calls) {
    if (calls.isNotEmpty || _evaluatesCode(at) || _readsReassigned(at)) {
      return false;
    }
    FunctionExpression? outermost;
    for (AstNode? node = at; node != null; node = node.parent) {
      if (node is FunctionExpression && _unrunClosure(node.body) == node) {
        outermost = node;
      }
    }
    final closure = outermost;
    if (closure == null) return false;
    var local = false;
    at.accept(
      _ElementReferenceVisitor.at((element) {
        final offset = element?.firstFragment.offset ?? -1;
        return (element is LocalVariableElement ||
                element is FormalParameterElement) &&
            offset >= closure.offset &&
            offset < closure.end;
      }, (_) => local = true),
    );
    return !local;
  }

  // The kept builders' closures, which run before the design is built.
  final Set<FunctionExpression> _keptClosures = HashSet.identity();

  static bool _isBool(AstNode node) => switch (node) {
    Expression(staticType: final DartType type) =>
      type.isDartCoreBool &&
          type.nullabilitySuffix != NullabilitySuffix.question,
    _ => false,
  };

  // The node in [site] the app computes [value] at: the outermost one the
  // mount writes as the value's own template.
  AstNode? _recordSite(AstNode site, HoistedValue value) {
    final hoist = _hoist!;
    final nodes = <Expression>[];
    site.accept(_Expressions(nodes));
    for (final node in nodes) {
      final analysis = hoist.analyzer.analyze(node);
      if (analysis is HoistEvaluable && analysis.template == value.template) {
        return node;
      }
    }
    return null;
  }

  // The const local reads being translated in their own scope.
  final _constReads = <SimpleIdentifier>{};

  /// [translate] of the [initializer] that [read] stands for; each placement
  /// of a local that can render beside another is its own island scope. A
  /// local the mount computes once is placed as an island that reads it.
  String _throughLocal(
    SimpleIdentifier read,
    Expression initializer,
    List<Issue> issues,
    String Function() translate,
  ) {
    // A helper the collection resolver inlined binds its parameters here.
    if (read.element is FormalParameterElement) {
      return _throughParameter(read, initializer, translate);
    }
    final saved = _walk;
    _walk = _walk.copyWith(
      islandScope: [
        ..._walk.islandScope,
        ..._placementStep(
          read,
          initializer.thisOrAncestorOfType<FunctionBody>() ?? read.root,
        ),
      ],
    );
    try {
      if (_islands?.sharedLocals.contains(read.element?.baseElement) ?? false) {
        return _emitIsland(initializer, const [], issues, shared: read) ??
            translate();
      }
      _localReads.add((read: read, initializer: initializer));
      _placementReads.add((read: read, bound: initializer));
      try {
        return translate();
      } finally {
        _localReads.removeLast();
        _placementReads.removeLast();
      }
    } finally {
      _walk = saved;
    }
  }

  /// [translate] of the argument [read] stands for; each placement of a
  /// parameter that can render beside another is its own island scope when
  /// the argument runs no code, so it is the same value in each. A call
  /// whose argument runs code and is read more than once is an island.
  String _throughParameter(
    SimpleIdentifier read,
    Expression argument,
    String Function() translate,
  ) {
    final body = _declaringBody(read);
    _placementReads.add((read: read, bound: argument));
    try {
      if (body == null || _evaluatesCode(argument)) return translate();
      return _inScope(_placementStep(read, body), translate);
    } finally {
      _placementReads.removeLast();
    }
  }

  // Whether [node] is a call of a helper that reads an argument that runs
  // code more than once, where the surface has islands.
  bool _repeatsCode(AstNode node) =>
      _islands != null &&
      node is MethodInvocation &&
      _repeatedArguments(node).isNotEmpty;

  // The arguments of [call] that run code and that its helper reads more
  // than once, or in a loop, closure or call.
  List<Expression> _repeatedArguments(MethodInvocation call) {
    final helper = _walk.inlined.helpers[call.methodName.element];
    final body =
        helper?.functionBody ??
        helper?.body.thisOrAncestorOfType<FunctionBody>();
    final binding = helper == null
        ? null
        : bindHelperArguments(
            helper.params,
            call.argumentList.arguments.toList(),
          );
    if (body == null || binding == null) return const [];
    return [
      for (final MapEntry(key: parameter, value: argument) in binding.entries)
        if (_evaluatesCode(argument) && _readRepeatedly(parameter, body))
          argument,
    ];
  }

  // Whether [body] reads [parameter] more than once, or in a loop, closure
  // or call, which may run it more than once.
  static bool _readRepeatedly(Element parameter, FunctionBody body) {
    final reads = <SimpleIdentifier>[];
    body.accept(
      _ElementReferenceVisitor.at(
        (element) => element?.baseElement == parameter.baseElement,
        reads.add,
      ),
    );
    return reads.length > 1 ||
        reads.any(
          (read) =>
              read.thisOrAncestorMatching(
                    (node) =>
                        identical(node, body) ||
                        node is ForElement ||
                        node is ForStatement ||
                        node is FunctionExpression ||
                        node is ArgumentList &&
                            node.parent is! InstanceCreationExpression,
                  )
                  is! FunctionBody,
        );
  }

  // [translate] with [steps] added to the island scope.
  String _inScope(List<String> steps, String Function() translate) {
    if (steps.isEmpty) return translate();
    final saved = _walk;
    _walk = _walk.copyWith(islandScope: [..._walk.islandScope, ...steps]);
    try {
      return translate();
    } finally {
      _walk = saved;
    }
  }

  // The scope step of a read of a const widget local, which each placement
  // gets as a final local's does; none for anything else.
  static List<String> _constPlacementStep(SimpleIdentifier read) {
    final element = read.element;
    if (element is! LocalVariableElement ||
        !element.isConst ||
        classifyHoistType(element.type) is! HoistIsWidget) {
      return const [];
    }
    final offset = element.firstFragment.nameOffset ?? -1;
    for (AstNode? node = read; node != null; node = node.parent) {
      if (node is FunctionBody && node.offset <= offset && offset < node.end) {
        return _placementStep(read, node);
      }
    }
    return const [];
  }

  // [read]'s scope step among the placements of its variable in [scope]:
  // none when every placement is one identity.
  static List<String> _placementStep(SimpleIdentifier read, AstNode scope) {
    final element = read.element;
    if (element == null) return const [];
    final placements = _placements(scope, element);
    final ordinal = placements.ordinals[read];
    return ordinal == null || placements.count < 2
        ? const []
        : ['${read.name}$ordinal'];
  }

  /// Each placement of [element] under [scope], numbered by identity: reads
  /// that can render together differ, reads in exclusive branches share one.
  /// A read that is the target of an access does not place it.
  static ({Map<SimpleIdentifier, int> ordinals, int count}) _placements(
    AstNode scope,
    Element element,
  ) {
    final ordinals = Map<SimpleIdentifier, int>.identity();
    int number(AstNode node, int next) {
      if (node is SimpleIdentifier) {
        if (node.element?.baseElement == element.baseElement &&
            !_isAccessTarget(node)) {
          ordinals[node] = next++;
        }
        return next;
      }
      final (Iterable<AstNode> head, List<AstNode> arms) = switch (node) {
        ConditionalExpression() => (
          [node.condition],
          [node.thenExpression, node.elseExpression],
        ),
        IfElement(:final elseElement?) => (
          [node.expression, if (node.caseClause case final clause?) clause],
          [node.thenElement, elseElement],
        ),
        IfStatement(:final elseStatement?) => (
          [node.expression, if (node.caseClause case final clause?) clause],
          [node.thenStatement, elseStatement],
        ),
        SwitchExpression() => ([node.expression], node.cases),
        SwitchStatement() => ([node.expression], node.members),
        _ => (node.childEntities.whereType<AstNode>(), const <AstNode>[]),
      };
      for (final child in head) {
        next = number(child, next);
      }
      var end = next;
      for (final arm in arms) {
        end = math.max(end, number(arm, next));
      }
      return end;
    }

    return (ordinals: ordinals, count: number(scope, 0));
  }

  static bool _isAccessTarget(SimpleIdentifier node) {
    final parent = node.parent;
    return parent is PrefixedIdentifier && identical(parent.prefix, node) ||
        parent is PropertyAccess && identical(parent.target, node) ||
        parent is MethodInvocation && identical(parent.target, node);
  }

  // The function body that declares the parameter [read] reads.
  static FunctionBody? _declaringBody(SimpleIdentifier read) {
    final element = read.element?.baseElement;
    for (AstNode? node = read; node != null; node = node.parent) {
      if (node is! FunctionBody) continue;
      final parameters = switch (node.parent) {
        FunctionExpression(:final parameters) ||
        MethodDeclaration(:final parameters) => parameters,
        _ => null,
      };
      if (parameters?.parameters.any(
            (parameter) =>
                parameter.declaredFragment?.element.baseElement == element,
          ) ??
          false) {
        return node;
      }
    }
    return null;
  }

  // Whether evaluating [node] runs code: a call other than an inlined
  // helper's, or a constructor that is not const. Closures run later and do
  // not count.
  bool _evaluatesCode(AstNode node, {bool appCode = false}) {
    final visitor = _EvaluatesCode(
      (element) => _walk.inlined.helpers[element],
      appCode: appCode,
    );
    node.accept(visitor);
    return visitor.found;
  }

  // An argument as the build report names it: its name, its parameter's, or
  // its place among the positional arguments.
  static String _islandArgumentLabel(Argument argument) => switch (argument) {
    NamedArgument(:final name) => name.lexeme,
    _ =>
      islandArgumentName(argument.correspondingParameter) ??
          switch (argument.parent) {
            final ArgumentList list =>
              'argument ${[
                    for (final other in list.arguments)
                      if (other is! NamedArgument) other,
                  ].indexOf(argument) + 1}',
            _ => 'an argument',
          },
  };

  /// [node]'s template without its mount: an argument that needs the mount
  /// is left out when optional and does nothing when it is a void callback.
  /// `null` when anything else needs the mount.
  String? _islandPreview(Expression node, Map<AstNode, String> holes) {
    final edits = {...holes};
    final arguments = switch (node) {
      InstanceCreationExpression(:final argumentList) ||
      MethodInvocation(:final argumentList) => argumentList.arguments,
      _ => const <Argument>[],
    };
    for (final argument in arguments) {
      final value = argument.argumentExpression;
      if (holes.containsKey(value) || !_needsMount(value, const {})) continue;
      final parameter = argument.correspondingParameter;
      final type = parameter?.type;
      if (type is FunctionType &&
          type.returnType is VoidType &&
          type.formalParameters.every((p) => p.isRequiredPositional)) {
        edits[value] =
            '(${[
              for (var index = 1; index <= type.formalParameters.length; index++) '_' * index,
            ].join(', ')}) {}';
      } else if (argument is NamedArgument &&
          parameter != null &&
          !parameter.isRequired) {
        edits[value] = _kDropped;
      } else {
        return null;
      }
    }
    if (_needsMount(node, edits.keys.toSet())) return null;
    final analysis = _hoist!.analyzer.analyze(node, holes: edits);
    if (analysis is! HoistEvaluable || analysis.item != null) return null;
    return analysis.template.replaceAll(
      RegExp(
        r'[A-Za-z_$][A-Za-z0-9_$]*\s*:\s*'
        '$_kDropped'
        r'\s*,?',
      ),
      '',
    );
  }

  static const _kDropped = '\u0004';

  /// Whether [node], outside [skipped], reads anything only the mount has:
  /// the surface's members or `this`, or a variable declared around it.
  bool _needsMount(AstNode node, Set<AstNode> skipped) {
    final root = _hoist?.analyzer.rootContext?.baseElement;
    var needs = false;
    node.accept(
      _MountReads(skipped, (identifier) {
        final element = identifier.element;
        final base = element?.baseElement;
        if (base == null || identical(base, root)) return;
        if (base is LocalVariableElement || base is FormalParameterElement) {
          final offset = base.firstFragment.nameOffset ?? -1;
          if (offset < node.offset || offset >= node.end) needs = true;
        } else if (isInstanceMember(base) &&
            !(identifier.parent is PropertyAccess &&
                (identifier.parent! as PropertyAccess).propertyName ==
                    identifier) &&
            !(identifier.parent is PrefixedIdentifier &&
                (identifier.parent! as PrefixedIdentifier).identifier ==
                    identifier) &&
            !(identifier.parent is MethodInvocation &&
                identical(
                  (identifier.parent! as MethodInvocation).methodName,
                  identifier,
                ) &&
                (identifier.parent! as MethodInvocation).target != null)) {
          needs = true;
        }
      }, onThis: () => needs = true),
    );
    return needs;
  }

  /// Finds the root shell of [root] and returns the design root under it.
  ///
  /// The shell is the chain of single-child wrappers and builders from the
  /// root down to the last one that does not lower. The mount writes it, and
  /// the design as its fallback, as the surface wrote them.
  Expression _splitRoot(
    Expression root,
    _IslandSession session,
    ClassElement? liftedState,
  ) {
    if (_reservedName(root) case final issue?) session.problem ??= issue;
    _keepPreludes(session, root);
    final state = liftedState == null
        ? null
        : _liftedState(root, liftedState, session);
    if (liftedState != null && state == null) return root;
    final returns = _walk.inlined.returns;
    session.returns = returns;
    session.buildBody = root.thisOrAncestorOfType<FunctionBody>();
    session.rootWalk = _walk;
    // A build that returns a switch takes its cases as several returns.
    if (_stripParens(root) case final SwitchExpression switched
        when returns.length < 2) {
      session.arms = switched.cases;
    }
    final branches = _branchExpressions();
    if (branches.length > 1) {
      // The design is whichever return the build took.
      session.split = MountSplit(
        kept: const [],
        // A switch's design root is its last case, as a build's is its last
        // return.
        designRoot: returns.length > 1 ? root : branches.last,
        designExpression: root,
        shell: const [],
        state: state,
      );
      return root;
    }
    final chain = _rootChain(root);
    // The copy runs the shell as the app wrote it, so the whole shell stays
    // above the design; a lifted State can also keep the design alone.
    final whole = [for (var index = 0; index <= chain.end; index++) index];
    for (final kept in [
      if (whole.isNotEmpty) whole,
      const <int>[],
    ]) {
      if (_splitAt(root, chain, kept, state, session) case final split?) {
        session.split = split;
        return _stripParens(split.designRoot);
      }
    }
    if (state == null) return root;
    // The State moves into the mount whole; the recorded copy writes its
    // build as the app wrote it.
    session.split = MountSplit(
      kept: const [],
      designRoot: root,
      shell: const [],
      state: state,
    );
    return root;
  }

  /// A build with several returns as a switch on which one its mount took,
  /// each return delivered as its own branch; `null` for one return.
  String? _branches(List<Issue> issues) {
    final branches = _branchExpressions();
    final library = _hoist?.analyzer.namespace.library;
    if (branches.length < 2 || _islands == null || library == null) {
      return null;
    }
    // Which arm the mount takes must not depend on State the design keeps.
    for (final expression in branches) {
      _recordsWithoutDesignState(
        expression,
        label: '${_islands!.surface.screen}.build',
        kind: _Recorded.branch,
        conditionsOnly: true,
      );
    }
    final type = library.typeProvider.intType;
    final branch = _hoist!.add(
      HoistEvaluable(
        label: 'which return ${_islands!.surface.screen}.build takes',
        template: _kBranch,
      ).value(classifyHoistType(type) as HoistCrosses, type),
    );
    bool throws(Expression e) => _stripParens(e) is ThrowExpression;
    final session = _islands!;
    final translated = _armChecked(
      issues,
      () => {
        for (final (index, expression) in branches.indexed)
          if (!throws(expression))
            expression: _inArm(
              session,
              index,
              () => _inBuildBranch(index, () => _translate(expression, issues)),
            ),
      },
    );
    return 'switch ${_hoistedRead(branch)} {${[
      for (final (index, expression) in branches.indexed) '${index == branches.length - 1 ? 'default' : index}: '
            // A branch that throws never renders: the build throws there.
            '${translated[expression] ?? translated.values.first}',
    ].join(', ')}}';
  }

  /// What the build returns on each path, when the mount takes it.
  List<Expression> _branchExpressions() {
    final returns = _walk.inlined.returns;
    if (returns.length > 1) {
      return buildBranches(returns.last.expression!, returns);
    }
    final switched = _islands?.arms.firstOrNull?.parent;
    return switched is SwitchExpression
        ? buildBranches(switched, returns)
        : const [];
  }

  static const _kBranch = 'restageBranch';

  /// Makes each build local that calls code a mount prelude, run once in
  /// order. Delivered content sees through it to what it holds; the mount's
  /// own code reads it by name, and one nothing reads still runs.
  void _keepPreludes(_IslandSession session, Expression root) {
    if (_walk.inlined.statements.isNotEmpty) {
      _keepStatements(session);
      return;
    }
    final preludes = _walk.inlined.localBindings.entries.toList()
      ..sort(
        (left, right) => (left.key.firstFragment.nameOffset ?? 0).compareTo(
          right.key.firstFragment.nameOffset ?? 0,
        ),
      );
    for (final MapEntry(key: local, value: initializer) in preludes) {
      // A widget the build places is design; one it reads is a value, and so
      // is one that runs code and renders in several places at once.
      final shared =
          local is VariableElement &&
          classifyHoistType(local.type) is HoistIsWidget &&
          _evaluatesCode(initializer);
      if (!(shared &&
              _placedRepeatedly(
                local,
                initializer.thisOrAncestorOfType<FunctionBody>(),
              )) &&
          _onlyPlaced(local, [root, ..._walk.inlined.localBindings.values])) {
        continue;
      }
      // Only code the build calls needs to run once; data stays delivered.
      final calls = _Invocations();
      initializer.accept(calls);
      if (!calls.found) continue;
      final analysis = _hoist!.analyzer.analyze(initializer);
      if (analysis is! HoistEvaluable || analysis.item != null) continue;
      session.scope.add(local.baseElement);
      session.preludeLocals.add(local.baseElement);
      if (shared) session.sharedLocals.add(local.baseElement);
    }
  }

  // Whether [local], declared by [initializer], can render in more than one
  // place at once: placed beside itself, in a loop, closure or call, or
  // inside a local that can.
  bool _placedRepeatedly(
    Element local,
    AstNode? scope, [
    Set<Element> visiting = const {},
  ]) {
    if (scope == null) return true;
    final placements = _placements(scope, local);
    if (placements.count > 1) return true;
    for (final read in placements.ordinals.keys) {
      for (
        AstNode? node = read.parent;
        node != null && !identical(node, scope);
        node = node.parent
      ) {
        if (node is ForElement ||
            node is ForStatement ||
            node is FunctionExpression ||
            node is ArgumentList &&
                node.parent is! InstanceCreationExpression) {
          return true;
        }
        if (node is VariableDeclaration) {
          final outer = node.declaredFragment?.element;
          final held = outer == null
              ? null
              : _walk.inlined.localBindings[outer];
          if (held != null &&
              !visiting.contains(outer!.baseElement) &&
              _placedRepeatedly(
                outer,
                held.thisOrAncestorOfType<FunctionBody>(),
                {...visiting, local.baseElement},
              )) {
            return true;
          }
          break;
        }
      }
    }
    return false;
  }

  // Whether every read of the widget-typed [local] in [scopes] places it.
  bool _onlyPlaced(Element local, List<Expression> scopes) {
    if (classifyHoistType(local is VariableElement ? local.type : null)
            is! HoistIsWidget &&
        !_isWidgetListType(local is VariableElement ? local.type : null)) {
      return false;
    }
    var read = false;
    for (final scope in scopes) {
      scope.accept(
        _ElementReferenceVisitor.at(
          (element) => element?.baseElement == local.baseElement,
          (node) {
            final parent = node.parent;
            if (parent is PrefixedIdentifier &&
                    identical(parent.prefix, node) ||
                parent is PropertyAccess && identical(parent.target, node) ||
                parent is MethodInvocation && identical(parent.target, node)) {
              read = true;
            }
          },
        ),
      );
    }
    return !read;
  }

  /// Runs a build's statements in the mount as written. With several
  /// returns, each return records which it is and leaves the statements, and
  /// the build's locals are declared ahead of them so the mount can read them.
  void _keepStatements(_IslandSession session) {
    final body = _walk.inlined;
    final multiple = body.returns.length > 1;
    // With several returns, a local a block, a loop, an if-case pattern or a
    // for-each loop declares is read past where it is declared, so its values
    // key by the local, as the build's own locals do.
    final ahead = multiple ? _aheadDeclarations(body.statements) : null;
    if (ahead != null) {
      final inner = [
        for (final (statement, _) in ahead.locals)
          for (final variable in statement.variables.variables)
            if (variable.declaredFragment?.element case final element?)
              element.baseElement,
        for (final (_, pattern) in ahead.patterns)
          if (pattern.declaredFragment?.element case final element?)
            element.baseElement,
        for (final (_, pattern) in ahead.destructured)
          if (pattern.declaredFragment?.element case final element?)
            element.baseElement,
        for (final (_, element) in ahead.loopVariables) element.baseElement,
        for (final (_, element) in ahead.caught) element.baseElement,
      ];
      session.innerLocals.addAll(inner);
      _nameHeldLocals(session, [
        // The build's own locals first, so each keeps its plain name.
        for (final statement in body.statements)
          if (statement is VariableDeclarationStatement)
            for (final variable in statement.variables.variables)
              if (variable.declaredFragment?.element case final element?)
                element.baseElement,
        ...inner,
      ]);
      session.scope.addAll(inner);
    }
    for (final statement in [
      ...body.statements,
      for (final (statement, _)
          in ahead?.locals ?? const <(VariableDeclarationStatement, bool)>[])
        statement,
    ]) {
      if (statement is! VariableDeclarationStatement) continue;
      for (final variable in statement.variables.variables) {
        final element = variable.declaredFragment?.element;
        if (element == null) continue;
        session.scope.add(element.baseElement);
        if (multiple) {
          session.mountNames.putIfAbsent(
            element.baseElement,
            () => element.name!,
          );
        }
      }
    }
  }

  // The refusal for a name the build declares or reads that starts with the
  // prefix Restage keeps for the code it generates.
  Issue? _reservedName(Expression root) {
    final build = root.thisOrAncestorMatching(
      (node) => node is MethodDeclaration || node is FunctionDeclaration,
    );
    if (build == null) return null;
    Issue? found;
    build.accept(
      _Names((name, node) {
        if (found != null || !name.startsWith('_restage')) return;
        found = Issue(
          code: IssueCode.unresolvedIdentifier,
          message:
              '`$name` (${_locationOf(node)}): Restage reserves names that '
              'start with `_restage` for the code it generates. Try a name that '
              "doesn't start with `_restage`.",
          location: _declarationOf(node),
        );
      }),
    );
    return found;
  }

  // Whether [body] assigns or steps any of [elements].
  static bool _writesAny(AstNode body, Set<Element> elements) {
    var writes = false;
    body.accept(
      _Writes(
        (element) => writes = writes || elements.contains(element?.baseElement),
      ),
    );
    return writes;
  }

  // The declarations among [statements] the mount declares ahead: locals of
  // nested blocks and loop bodies, with whether a loop repeats them; if-case
  // pattern variables; and for-each loop variables.
  static _AheadDeclarations _aheadDeclarations(List<Statement> statements) {
    final ahead = (
      locals: <(VariableDeclarationStatement, bool)>[],
      patterns: <(Statement, DeclaredVariablePattern)>[],
      destructured:
          <(PatternVariableDeclarationStatement, DeclaredVariablePattern)>[],
      loopVariables: <(ForStatement, Element)>[],
      caught: <(CatchClause, Element)>[],
    );
    void walk(
      Statement? statement, {
      required bool nested,
      required bool repeats,
    }) {
      switch (statement) {
        case VariableDeclarationStatement() when nested:
          ahead.locals.add((statement, repeats));
        case PatternVariableDeclarationStatement(:final declaration):
          declaration.pattern.accept(
            _PatternVariables(
              (pattern) => ahead.destructured.add((statement, pattern)),
            ),
          );
        case Block(:final statements):
          for (final inner in statements) {
            walk(inner, nested: true, repeats: repeats);
          }
        case IfStatement(
          :final caseClause,
          :final thenStatement,
          :final elseStatement,
        ):
          caseClause?.guardedPattern.pattern.accept(
            _PatternVariables(
              (pattern) => ahead.patterns.add((statement, pattern)),
            ),
          );
          walk(thenStatement, nested: true, repeats: repeats);
          walk(elseStatement, nested: true, repeats: repeats);
        case ForStatement(:final forLoopParts, :final body):
          switch (forLoopParts) {
            case ForEachPartsWithDeclaration(:final loopVariable):
              if (loopVariable.declaredFragment?.element case final element?) {
                ahead.loopVariables.add((statement, element));
              }
            case ForEachPartsWithPattern(:final pattern):
              pattern.accept(
                _PatternVariables((variable) {
                  if (variable.declaredFragment?.element case final element?) {
                    ahead.loopVariables.add((statement, element));
                  }
                }),
              );
            // A classic loop's variables are held unless its body writes
            // them, where the held copy would not follow.
            case ForPartsWithDeclarations(:final variables):
              final elements = [
                for (final variable in variables.variables)
                  if (variable.declaredFragment?.element case final element?)
                    element,
              ];
              if (!_writesAny(body, elements.toSet())) {
                for (final element in elements) {
                  ahead.loopVariables.add((statement, element));
                }
              }
            default:
          }
          walk(body, nested: true, repeats: true);
        case TryStatement(
          :final body,
          :final catchClauses,
          :final finallyBlock,
        ):
          walk(body, nested: true, repeats: repeats);
          for (final clause in catchClauses) {
            for (final parameter in [
              clause.exceptionParameter,
              clause.stackTraceParameter,
            ]) {
              if (parameter?.declaredFragment?.element case final element?) {
                ahead.caught.add((clause, element));
              }
            }
            walk(clause.body, nested: true, repeats: repeats);
          }
          walk(finallyBlock, nested: true, repeats: repeats);
        case WhileStatement(:final body) || DoStatement(:final body):
          walk(body, nested: true, repeats: true);
        case SwitchStatement(:final members):
          for (final member in members) {
            if (member case SwitchPatternCase(:final guardedPattern)) {
              guardedPattern.pattern.accept(
                _PatternVariables(
                  (pattern) => ahead.patterns.add((statement, pattern)),
                ),
              );
            }
            for (final inner in member.statements) {
              walk(inner, nested: true, repeats: repeats);
            }
          }
        default:
      }
    }

    for (final statement in statements) {
      walk(statement, nested: false, repeats: false);
    }
    return ahead;
  }

  // Names each local the mount declares ahead after its source name, with a
  // number where an earlier one has the same name; the mount writes it under
  // a prefix only Restage uses.
  static void _nameHeldLocals(_IslandSession session, List<Element> locals) {
    final used = {...session.mountNames.values};
    for (final local in locals) {
      final name = local.name!;
      var spelled = name;
      for (var n = 2; used.contains(spelled); n++) {
        spelled = '$name$n';
      }
      used.add(spelled);
      session.mountNames[local] = spelled;
    }
  }

  void _statementProblem(
    _IslandSession session,
    Statement statement, [
    HoistAnalysis? analysis,
  ]) {
    final owner = session.liftedState?.name ?? session.surface.screen;
    final blocker = _blocker(analysis);
    final String cause;
    final String fix;
    if (blocker.unnamed case final unnamed?) {
      cause =
          " It uses `$unnamed`, which ${_screenFile(statement)} doesn't "
          'import.';
      fix = 'Try importing the library that declares it.';
    } else {
      final verb = blocker.calls ? 'calls' : 'reads';
      cause = blocker.read == null ? '' : ' It $verb `${blocker.read}`.';
      fix = 'Try moving the statement into a method of `$owner`.';
    }
    session.problem ??= Issue(
      code: IssueCode.buildMethodTooComplex,
      message:
          "Restage can't copy the statement at ${_locationOf(statement)} "
          'into the generated `${_mountName(session.surface.screen)}`.$cause '
          '$fix',
      // The message names its place, so the issue names the declaration.
      location: _declarationOf(statement),
    );
  }

  /// What stopped [analysis] from copying: the read it could not reach, as
  /// written and where, or the name its library does not import.
  ({String? read, String? location, bool calls, String? unnamed}) _blocker(
    HoistAnalysis? analysis,
  ) {
    if (analysis is HoistUnwritable && analysis.unnamed != null) {
      return (
        read: null,
        location: null,
        calls: false,
        unnamed: analysis.unnamed,
      );
    }
    final node = switch (analysis) {
      HoistNeedsSurfaceValue(:final node) ||
      HoistUnwritable(:final node) => node,
      _ => null,
    };
    if (node == null) {
      return (read: null, location: null, calls: false, unnamed: null);
    }
    final read = _accessThrough(node);
    if (read is MethodInvocation) {
      return (
        read: readableSource(
          [
            if (read.target case final target?) _writtenSource(target),
            read.methodName.name,
          ].join('.'),
        ),
        location: _locationOf(read),
        calls: true,
        unnamed: null,
      );
    }
    if (read.parent case FunctionExpressionInvocation(
      :final function,
    ) when identical(function, read)) {
      return (
        read: readableSource(_writtenSource(read)),
        location: _locationOf(read),
        calls: true,
        unnamed: null,
      );
    }
    return (
      read: readableSource(_writtenSource(read)),
      location: _locationOf(read),
      calls: false,
      unnamed: null,
    );
  }

  // The member access or call a bare name is part of, such as `super.title`
  // for `super` or `debugPrint(...)` for `debugPrint`; [node] otherwise.
  static AstNode _accessThrough(AstNode node) {
    if (node is! SimpleIdentifier &&
        node is! ThisExpression &&
        node is! SuperExpression) {
      return node;
    }
    final parent = node.parent;
    if (parent is PropertyAccess && identical(parent.target, node) ||
        parent is MethodInvocation &&
            (identical(parent.target, node) ||
                parent.target == null && identical(parent.methodName, node)) ||
        parent is PrefixedIdentifier && identical(parent.prefix, node)) {
      return parent!;
    }
    return node;
  }

  // The file the generated surface is written beside, as a path.
  String _screenFile(AstNode node) {
    final unit = _currentSourceUnit ?? node.root;
    return unit is CompilationUnit ? _unitPath(unit, unit) : 'this file';
  }

  // [node] as its file spells it.
  static String _writtenSource(AstNode node) {
    final unit = node.root;
    final text = unit is CompilationUnit
        ? unit.declaredFragment?.source.contents.data
        : null;
    return text == null
        ? node.toSource()
        : text.substring(node.offset, node.end);
  }

  // How a loop's item position reads to a developer: `index of p in plans`.
  String _itemIndexLabel(_RuntimeLoopBinding loop) {
    final items = _hoist!.values[loop.item!];
    final item = items?.pattern ?? loop.identifier;
    return 'index of $item in ${items?.label ?? loop.item!}';
  }

  /// The generated mount class's name for the screen class [screen].
  static String _mountName(String screen) =>
      generatedSurfaceName(screen, fallback: 'SurfaceScreen');

  // [split] with the copied build that records each published value where
  // the app computes it, when every value has such a place.
  MountSplit? _recorded(
    MountSplit? split,
    _IslandSession? session,
    _HoistSession? hoist, {
    bool navigates = false,
  }) {
    if (session == null || hoist == null) return split;
    // With nothing to record, no shell to keep, no statement to run and no
    // screen it pushes, the fallback is the surface itself.
    if (!navigates &&
        session.designMiss == null &&
        hoist.values.isEmpty &&
        session.islands.isEmpty &&
        session.recordPlacements.isEmpty &&
        (split == null || split.kept.isEmpty && split.state == null) &&
        switch (session.buildBody) {
          BlockFunctionBody(block: Block(:final statements)) =>
            !statements.take(statements.length - 1).any(_RunsAppCode.inside),
          _ => true,
        }) {
      return null;
    }
    final root =
        split?.designRoot ??
        session.returns.firstOrNull?.expression ??
        switch (session.buildBody) {
          ExpressionFunctionBody(:final expression) => expression,
          BlockFunctionBody(
            block: Block(
              statements: [..., ReturnStatement(:final expression?)],
            ),
          ) =>
            expression,
          _ => null,
        };
    if (root == null) {
      session.recordProblem ??= Issue(
        code: IssueCode.buildMethodTooComplex,
        message:
            "Restage can't generate `${_mountName(session.surface.screen)}`. "
            'Please report this as a Restage bug.',
        location: session.buildBody == null
            ? session.surface.screen
            : _declarationOf(session.buildBody!),
      );
      return split;
    }
    final outer = (_walk, _islands, _hoist);
    _walk = session.rootWalk ?? _walk;
    _islands = session;
    _hoist = hoist;
    final String? source;
    try {
      session.recording = true;
      source = _recordedBuild(session, hoist, root);
    } finally {
      session.recording = false;
      _walk = outer.$1;
      _islands = outer.$2;
      _hoist = outer.$3;
    }
    final base =
        split ??
        MountSplit(
          kept: const [],
          designRoot: root,
          shell: const [],
        );
    if (source == null) {
      return base.withRecorded(null, null, session.recordProblem);
    }
    return base.withRecorded(source, session.recordedFacts);
  }

  // The build as the app wrote it, each published value recorded where it
  // is computed; `null` when a value has no such place.
  String? _recordedBuild(
    _IslandSession session,
    _HoistSession hoist,
    Expression root,
  ) {
    if (session.designMiss case final miss?) {
      session.recordProblem ??= miss;
      return null;
    }
    final body = session.buildBody;
    if (body == null) {
      session.recordProblem ??= Issue(
        code: IssueCode.buildMethodTooComplex,
        message:
            "Restage can't generate `${_mountName(session.surface.screen)}`. "
            'Please report this as a Restage bug.',
        location: session.surface.screen,
      );
      return null;
    }
    const recorder = '_restageRecording';
    // Where a value is recorded: the mount's recording, or a slot's own.
    const into = '\u0006';
    String? giveUp(String why, {AstNode? at, HoistAnalysis? analysis}) {
      // A State member the copy can't read asks for the State to be lifted.
      if (analysis case HoistNeedsSurfaceValue(:final elements)) {
        session.blocked.addAll(elements);
      }
      final stopped =
          at ??
          switch (analysis) {
            HoistNeedsSurfaceValue(:final node) ||
            HoistUnwritable(:final node) => node,
            _ => null,
          };
      final statement = stopped?.thisOrAncestorOfType<Statement>();
      if (analysis != null && statement != null) {
        final previous = session.problem;
        session.problem = null;
        _statementProblem(session, statement, analysis);
        session.recordProblem ??= session.problem;
        session.problem = previous;
      }
      session.recordProblem ??= Issue(
        code: IssueCode.buildMethodTooComplex,
        message:
            "Restage can't generate `${_mountName(session.surface.screen)}`"
            "${stopped == null ? '' : ' at ${_locationOf(stopped)}'}. "
            'Please report this as a Restage bug.',
        location: _declarationOf(stopped ?? body),
      );
      return null;
    }

    if (hoist.closureMisses.firstOrNull case final missed?) {
      return giveUp('closure', at: missed);
    }
    String chainKey(List<AstNode> calls) =>
        calls.map(identityHashCode).join(',');
    final around =
        <String, Map<AstNode, List<({String before, String after})>>>{};
    final chains = <String, List<AstNode>>{'': const []};
    AstNode? declarationOf(AstNode call) {
      final owner = hoist.helperBodies[call]
          ?.thisOrAncestorOfType<FunctionBody>()
          ?.parent;
      return owner is FunctionExpression ? owner.parent : owner;
    }

    bool within(AstNode node, AstNode? scope) =>
        scope != null &&
        identical(node.root, scope.root) &&
        node.offset >= scope.offset &&
        node.end <= scope.end;
    AstNode? misplaced;
    // The node is written in the innermost function of the calls it was
    // reached through that contains it.
    List<AstNode> callsOf(List<AstNode> through, AstNode node) {
      for (var n = through.length; n > 0; n--) {
        if (within(node, declarationOf(through[n - 1]))) {
          return through.sublist(0, n);
        }
      }
      return const [];
    }

    // What the recorded build writes, for the layouts it publishes.
    final sites = <RecordedSite>[];
    final recordedReturns = <RecordedReturn>[];
    void site(
      RecordedSiteKind kind,
      String key,
      List<AstNode> through,
      AstNode node,
    ) => sites.add(
      RecordedSite(
        kind: kind,
        key: key,
        node: node,
        calls: callsOf(through, node),
      ),
    );

    void at(List<AstNode> through, AstNode node, String before, String after) {
      final calls = callsOf(through, node);
      if (calls.isEmpty && !within(node, body)) {
        misplaced ??= node;
        return;
      }
      for (var n = 1; n <= calls.length; n++) {
        final prefix = calls.sublist(0, n);
        chains[chainKey(prefix)] = prefix;
      }
      ((around[chainKey(calls)] ??= Map.identity())[node] ??= []).add((
        before: before,
        after: after,
      ));
    }

    String literal(String text) => "'$text'";
    String? outerOf(HoistedValue value) => value.item;
    final indexKeys = <String, List<String>>{};
    for (final value in hoist.values.values) {
      if (value.kind == HoistValueKind.itemIndex && value.item != null) {
        (indexKeys[value.item!] ??= []).add(value.key);
      }
    }
    String itemsCall(String key, String? outer) =>
        '$into.items(${literal(key)}, ';
    String itemsEnd(String key, String? outer) =>
        '${outer == null && indexKeys[key] == null ? '' : ', ${outer == null ? 'null' : literal(outer)}'}'
        '${indexKeys[key] == null ? '' : ', [${indexKeys[key]!.map(literal).join(', ')}]'})';
    final wrappedLoops = Set<AstNode>.identity();
    final early = <({String key, AstNode site})>[];
    // A site in a loop the design unrolls records, on each iteration, the
    // key of that iteration's value.
    final loopIds = <ForElement, int>{};
    final unrolledKeys = <String, Map<String, String>>{};
    for (final record in hoist.records) {
      if (record.unrolled.isEmpty) continue;
      for (final step in record.unrolled) {
        loopIds.putIfAbsent(step.loop, () => loopIds.length);
      }
      (unrolledKeys[occurrenceOf(record.site, record.calls)] ??= {})[[
            for (final step in record.unrolled) step.ordinal,
          ].join('.')] =
          record.key;
    }
    final wrappedUnrolled = Set<ForElement>.identity();
    final writtenUnrolled = <String>{};
    // The key [record] is recorded under, or `null` when its site already
    // records for every iteration.
    String? keyOf(
      ({
        String key,
        AstNode site,
        List<AstNode> calls,
        List<({ForElement loop, int ordinal})> unrolled,
        bool slot,
      })
      record,
    ) {
      if (record.unrolled.isEmpty) return literal(record.key);
      final group = occurrenceOf(record.site, record.calls);
      if (!writtenUnrolled.add(group)) return null;
      for (final step in record.unrolled) {
        if (!wrappedUnrolled.add(step.loop)) continue;
        final parts = step.loop.forLoopParts;
        if (parts is ForEachParts) {
          at(
            record.calls,
            parts.iterable,
            '$recorder.unrolled(${loopIds[step.loop]}, ',
            ')',
          );
        }
      }
      final keys = unrolledKeys[group]!;
      return '$recorder.unrolledKey(const {${[
        for (final MapEntry(:key, :value) in keys.entries) '${literal(key)}: ${literal(value)}',
      ].join(', ')}}, const [${[
        for (final step in record.unrolled) loopIds[step.loop],
      ].join(', ')}])';
    }

    // The loop over the screen input [outer] around [site] walks its items
    // into the recording, so what is recorded per item lands in one.
    void walkRootLoop(String outer, List<AstNode> calls, AstNode site) {
      for (
        AstNode? node = site.parent;
        node != null && !identical(node, body);
        node = node.parent
      ) {
        final parts = switch (node) {
          ForElement(:final forLoopParts) => forLoopParts,
          ForStatement(:final forLoopParts) => forLoopParts,
          _ => null,
        };
        if (parts is! ForEachParts) continue;
        final iterable = parts.iterable.toSource();
        if (iterable != outer &&
            iterable != 'widget.$outer' &&
            iterable != 'this.$outer') {
          continue;
        }
        if (wrappedLoops.add(parts.iterable)) {
          at(
            calls,
            parts.iterable,
            itemsCall(outer, null),
            itemsEnd(outer, null),
          );
        }
        break;
      }
    }

    for (final value in hoist.values.values) {
      if (value.mountSource((name) => name) == _kBranch) continue;
      if (value.kind == HoistValueKind.itemIndex) continue;

      if (value.kind == HoistValueKind.nativeBinding && !value.computed) {
        continue;
      }
      final records = [
        for (final record in hoist.records)
          if (record.key == value.key) record,
      ];
      if (hoist.exposes.any((expose) => expose.key == value.key)) continue;
      if (records.isEmpty)
        return giveUp('no site ${value.key} ${value.label} ${value.kind}');
      final placed = Set<AstNode>.identity();
      for (final record in records) {
        if (!placed.add(record.site)) continue;
        site(
          switch (value.kind) {
            HoistValueKind.items => RecordedSiteKind.items,
            HoistValueKind.nativeBinding => RecordedSiteKind.native,
            _ => RecordedSiteKind.value,
          },
          value.key,
          record.calls,
          record.site,
        );
        final outer = outerOf(value);
        switch (value.kind) {
          case HoistValueKind.items:
            wrappedLoops.add(record.site);
            at(
              record.calls,
              record.site,
              itemsCall(value.key, outer),
              itemsEnd(value.key, outer),
            );
          case HoistValueKind.textScaler:
            at(
              record.calls,
              record.site,
              '$recorder.scaler(${literal(value.key)}, ',
              ')',
            );
          case HoistValueKind.nativeBinding:
            final contract = value.nativeContract!;
            final nativeKey = keyOf(record);
            if (nativeKey == null) continue;
            at(
              record.calls,
              record.site,
              '$recorder.native($nativeKey, ',
              '${outer == null ? '' : ', items: ${literal(outer)}'}, '
                  'type: ${literal(contract.type)}, '
                  'nullable: ${contract.nullable})',
            );
          default:
            final tail = outer == null ? '' : ', ${literal(outer)}';
            if (outer == null && _recordedEarly(record.site, record.calls)) {
              early.add((key: value.key, site: record.site));
              continue;
            }
            final key = keyOf(record);
            if (key == null) continue;
            // A condition is recorded in the branch it takes, so it keeps
            // promoting what the branches read.
            switch (record.site.parent) {
              case IfElement(
                    :final expression,
                    :final thenElement,
                    :final elseElement,
                  )
                  when identical(expression, record.site) &&
                      record.site.parent!.thisOrAncestorMatching(
                            (node) =>
                                node is! CollectionElement ||
                                node is Expression,
                          )
                          is ListLiteral:
                at(
                  record.calls,
                  thenElement,
                  '...$into.mark($key, true, [',
                  ']$tail)${elseElement == null ? ' else ...$into.mark($key, false, const []$tail)' : ''}',
                );
                if (elseElement != null) {
                  at(
                    record.calls,
                    elseElement,
                    '...$into.mark($key, false, [',
                    ']$tail)',
                  );
                }
              case ConditionalExpression(
                    :final condition,
                    :final thenExpression,
                    :final elseExpression,
                  )
                  when identical(condition, record.site):
                at(
                  record.calls,
                  thenExpression,
                  '$into.taken($key, true, ',
                  '$tail)',
                );
                at(
                  record.calls,
                  elseExpression,
                  '$into.taken($key, false, ',
                  '$tail)',
                );
              case IfStatement(
                    :final expression,
                    :final thenStatement,
                    :final elseStatement,
                    caseClause: null,
                  )
                  when identical(expression, record.site):
                at(
                  record.calls,
                  thenStatement,
                  '{ $into.value($key, true$tail); ',
                  ' }${elseStatement == null ? ' else { $into.value($key, false$tail); }' : ''}',
                );
                if (elseStatement != null) {
                  at(
                    record.calls,
                    elseStatement,
                    '{ $into.value($key, false$tail); ',
                    ' }',
                  );
                }
              // A condition is recorded beside it with boolean literals, so
              // flow analysis still promotes through it.
              case _ when _isBool(record.site):
                at(
                  record.calls,
                  record.site,
                  '((',
                  ' || ($into.value($key, false$tail) && false)) && '
                      '($into.value($key, true$tail) || true))',
                );
              default:
                at(record.calls, record.site, '$into.value($key, ', '$tail)');
            }
        }
        // A value per item of a screen input is recorded into the item the
        // loop over that input walks.
        if (outer != null && hoist.values[outer] == null) {
          walkRootLoop(outer, record.calls, record.site);
        }
      }
    }
    // A kept builder publishes its parameters when it runs.
    final exposed = <FunctionExpression, List<String>>{};
    for (final expose in hoist.exposes) {
      if (!hoist.values.containsKey(expose.key)) continue;
      (exposed[expose.builder] ??= []).add(
        '${literal(expose.key)}: ${expose.source}',
      );
    }
    // Each run of a kept builder starts from what was recorded before it, so
    // a run never reads what an earlier run recorded.
    const allCalls = <AstNode>[];
    for (final (index, builder) in session.keptBuilders.indexed) {
      final entries = exposed[builder] ?? const <String>[];
      final values = entries.isEmpty
          ? 'const {}'
          : '{${entries.toSet().join(', ')}}';
      switch (builder.body) {
        case ExpressionFunctionBody(:final expression):
          at(
            allCalls,
            expression,
            '($recorder..frame($index)).exposing($values, ',
            ')',
          );
        case BlockFunctionBody(block: Block(statements: [final first, ...])):
          at(
            allCalls,
            first,
            '$recorder.frame($index); $recorder.exposing($values, null); ',
            '',
          );
        default:
          return giveUp('builder body');
      }
    }
    // Each return builds the design from what the build returns, recording
    // which return it was once it returns.
    final branch = hoist.values.values
        .where((value) => value.mountSource((name) => name) == _kBranch)
        .firstOrNull;
    final branches = switch (_branchExpressions()) {
      final cases when cases.length > 1 => cases,
      _ => [root],
    };
    // Values a closure the design doesn't run reads from before it are
    // recorded as the design is built.
    final earlyTexts = <String>[];
    for (final record in early) {
      final analysis = hoist.analyzer.analyze(record.site, scope: body);
      if (analysis is! HoistEvaluable) {
        return giveUp('early', analysis: analysis);
      }
      earlyTexts.add('${literal(record.key)}: ${analysis.template}');
    }
    final earlyBefore = earlyTexts.isEmpty
        ? ''
        : '$into.exposing({${earlyTexts.toSet().join(', ')}}, ';
    final earlyAfter = earlyTexts.isEmpty ? '' : ')';
    for (final (index, expression) in branches.indexed) {
      if (branch != null) {
        recordedReturns.add(
          RecordedReturn(key: branch.key, index: index, node: expression),
        );
      }
      for (final record in early) {
        site(RecordedSiteKind.value, record.key, const [], expression);
      }
      at(
        const [],
        expression,
        '_restageDesign(${branch == null ? '' : '$into.branch(${literal(branch.key)}, $index, '}$earlyBefore',
        '$earlyAfter${branch == null ? ')' : '))'}',
      );
    }
    // A route or dialog the build pushes shows its content inside the
    // surface's event scopes.
    for (final content in routeContents(body)) {
      at(const [], content, '$recorder.route(', ')');
    }
    final analyzer = hoist.analyzer;
    final islandNames = {
      for (final island in session.islands.values) island.name,
    };
    late final String? Function(
      AstNode node,
      AstNode scope,
      List<AstNode> calls,
    )
    renderNode;
    // An app builder's body, run where Flutter calls the builder: it records
    // into its own recording and renders the delivered body with it.
    String? slotBody(
      FunctionExpression callback,
      AstNode scope,
      List<AstNode> through,
    ) {
      final calls = callsOf(through, callback);
      final key = chainKey(calls);
      final base = around[key];
      final local = <AstNode, List<({String before, String after})>>{
        ...?base,
      };
      bool inside(AstNode node) =>
          node.offset >= callback.offset && node.end <= callback.end;
      for (final MapEntry(key: node, value: texts) in local.entries.toList()) {
        if (!inside(node)) continue;
        local[node] = [
          for (final text in texts)
            (
              before: text.before.replaceAll(into, kSlotRecordingName),
              after: text.after.replaceAll(into, kSlotRecordingName),
            ),
        ];
      }
      final returns = <ReturnStatement>[];
      final body = callback.body;
      body.accept(_OwnReturns(body, returns));
      final rendered = switch (body) {
        ExpressionFunctionBody(:final expression) => expression,
        BlockFunctionBody(:final block) => block,
        _ => null,
      };
      if (rendered == null) return null;
      for (final target in [
        if (body is ExpressionFunctionBody) body.expression,
        for (final r in returns)
          if (r.expression case final value?) value,
      ]) {
        local[target] = [
          (before: '$kSlotRenderName(', after: ')'),
          ...?local[target],
        ];
      }
      around[key] = local;
      try {
        final text = renderNode(rendered, scope, calls);
        if (text == null) return null;
        return body is ExpressionFunctionBody
            ? 'return $text;'
            : text.trim().substring(1, text.trim().length - 1);
      } finally {
        if (base == null) {
          around.remove(key);
        } else {
          around[key] = base;
        }
      }
    }

    final islandsPlaced = <(String, AstNode)>{};
    // Each island whose arguments the build evaluates once, by its node.
    // Each call site of a helper is its own island.
    final once =
        <
          String,
          ({
            AstNode node,
            List<AstNode> calls,
            List<Expression> arguments,
            Map<AstNode, String> shared,
            List<AstNode> slots,
            String? Function(List<String> written, String widget) text,
          })
        >{};
    // An app widget the design builds is placed as it does, keyed as the
    // design keys it; a split one through its wrapper.
    for (final placed in session.recordPlacements) {
      if (placed.items case final items? when hoist.values[items] == null) {
        walkRootLoop(items, placed.calls, placed.node);
      }
      // Unwrapped, the mount install refuses the surface.
      if (placed.place == null) continue;
      at(
        placed.calls,
        placed.node,
        '$recorder.island(${literal(placed.name)}, ',
        ', place: ${placed.place}'
            '${placed.items == null ? '' : ', items: ${literal(placed.items!)}'})',
      );
    }
    final spotsMarked = <String>{};
    final spotIds = Map<AstNode, int>.identity();
    int spotId(AstNode read) => spotIds[read] ??= spotIds.length;
    for (final island in session.recordIslands) {
      final placed = island.placement.at;
      if (!islandNames.contains(island.name) ||
          !islandsPlaced.add((island.name, placed))) {
        continue;
      }
      // An island inside a value reads place is keyed at the spot they name;
      // each read is marked once.
      final spots = island.placement.spots;
      for (final read in spots) {
        final form = _spotForm(read);
        if (form != null &&
            spotsMarked.add(occurrenceOf(read, callsOf(island.calls, read)))) {
          at(island.calls, read, '$recorder.$form(${spotId(read)}, ', ')');
        }
      }
      final placedAt = spots.isEmpty
          ? ''
          : ', spots: [${spots.map(spotId).join(', ')}]';
      site(
        RecordedSiteKind.island,
        WidgetVocabulary.qualifiedName(
          session.islands.values
              .firstWhere((entry) => entry.name == island.name)
              .library,
          island.name,
        ),
        island.calls,
        placed,
      );
      if (island.items case final items? when hoist.values[items] == null) {
        walkRootLoop(items, island.calls, placed);
      }
      final items = island.items == null
          ? ''
          : ', items: ${literal(island.items!)}';
      if (island.shared || island.holes.isEmpty) {
        at(
          island.calls,
          placed,
          '$recorder.island(${literal(island.name)}, ',
          '$items$placedAt)',
        );
        continue;
      }
      // An island with design content evaluates its arguments once, in
      // source order: the build's widget and the design's builder share them.
      final scope = island.node.thisOrAncestorOfType<FunctionBody>()?.parent;
      final scopeNode =
          scope is FunctionExpression && scope.parent is FunctionDeclaration
          ? scope.parent!
          : scope is MethodDeclaration
          ? scope
          : body;
      final arguments = switch (island.node) {
        InstanceCreationExpression(:final argumentList) ||
        MethodInvocation(:final argumentList) => <Expression>[
          // Only an argument that runs app code is shared; evaluating any
          // other twice changes nothing.
          for (final argument in argumentList.arguments)
            if (_stripParens(argument.argumentExpression)
                    is! FunctionExpression &&
                _evaluatesCode(argument.argumentExpression, appCode: true))
              argument.argumentExpression,
        ],
        _ => null,
      };
      if (arguments == null) return giveUp('island', at: island.node);
      // The record spells each argument's inferred type, so it infers as it
      // does at its parameter.
      final namespace = analyzer.namespace;
      final widgetType = switch ((island.node as Expression).staticType) {
        final InterfaceType type =>
          [type, ...type.allSupertypes]
              .where(
                (t) =>
                    t.element.name == 'Widget' &&
                    isFlutterFrameworkType(t.element, 'Widget'),
              )
              .firstOrNull,
        _ => null,
      };
      final types = [
        for (final argument in arguments)
          argument.staticType == null
              ? null
              : namespace.typeCode(argument.staticType!),
        widgetType == null ? null : namespace.typeCode(widgetType),
      ];
      if (arguments.isNotEmpty && types.contains(null)) {
        return giveUp('island', at: island.node);
      }
      final typed =
          '<(${[
            for (final type in types.take(arguments.length)) '$type, ',
          ].join()}), ${types.last}>';
      final shared = <AstNode, String>{
        for (final (index, argument) in arguments.indexed)
          argument: '_restageArgs.\$${index + 1}',
      };
      final holes = <AstNode, String>{...shared};
      for (final MapEntry(key: argument, value: hole) in island.holes.entries) {
        holes[argument] = hole.property
            ? '(${hole.marker} ?? ${shared[argument] ?? switch (analyzer.analyze(argument, scope: scopeNode)) {
                    HoistEvaluable(:final template) => template,
                    _ => 'null',
                  }})'
            : hole.marker;
      }
      // Each app builder slot runs a copy of the app's own body.
      final slotTexts = <String, String? Function()>{};
      for (final slot
          in session.islands.values
              .firstWhere((entry) => entry.name == island.name)
              .slots) {
        final builder = slot.builder;
        final callback = slot.node is Expression
            ? _stripParens(slot.node as Expression)
            : slot.node;
        if (builder == null || callback is! FunctionExpression) continue;
        final token = '\u0008${slotTexts.length}\u0008';
        holes[slot.node] = token;
        slotTexts[token] = () {
          final body = slotBody(callback, scopeNode, island.calls);
          return body == null
              ? null
              : builder.callback(
                  AppValueSlot.bindingName(slot.name),
                  sdk: kSdkPrefixMarker,
                  names: AppValueSlot.parameterNames(callback),
                  body: body,
                );
        };
      }
      final built = analyzer.analyze(
        island.node,
        holes: holes,
        scope: scopeNode,
      );
      if (built is! HoistEvaluable) return giveUp('island', analysis: built);
      final builders = {
        for (final slot
            in session.islands.values
                .firstWhere((entry) => entry.name == island.name)
                .slots)
          if (slot.builder case final builder?) slot.name: builder,
      };
      final build = builders.isEmpty
          ? built.template
          : AppValueSlot.owning(
              built.template,
              builders,
              source: '_restageSource',
              context: '_restageContext',
              sdk: kSdkPrefixMarker,
            );
      // A constant runs no code: its placement carries the delivered build.
      if (island.node case final Expression node when node.inConstantContext) {
        if (slotTexts.isNotEmpty || builders.isNotEmpty) {
          return giveUp('island', at: island.node);
        }
        at(
          island.calls,
          placed,
          '$recorder.island(${literal(island.name)}, ',
          '$items$placedAt, build: (_restageContext, _restageSource) => '
              '$build)',
        );
        continue;
      }
      // The app's own builder roots at the binding owner the delivered one
      // roots at, so the island keeps its element across a flip.
      final onceCalls = callsOf(island.calls, island.node);
      once[occurrenceOf(island.node, onceCalls)] = (
        node: island.node,
        calls: onceCalls,
        slots: [
          for (final slot
              in session.islands.values
                  .firstWhere((entry) => entry.name == island.name)
                  .slots)
            if (slot.builder != null) slot.node,
        ],
        arguments: arguments,
        shared: shared,
        text: (List<String> written, String widget) {
          final owned = builders.isEmpty
              ? widget
              : '${kSdkPrefixMarker}RestageBuilderBinding.retain(const [], '
                    'child: $widget)';
          final recorded =
              '$recorder.built($owned, '
              '(_restageContext, _restageSource) => $build)';
          var text = written.isEmpty
              ? recorded
              : '${kSdkPrefixMarker}restageOnce$typed(('
                    '${written.map((text) => '$text, ').join()}), '
                    '(_restageArgs) => $recorded)';
          for (final MapEntry(key: token, value: slot) in slotTexts.entries) {
            final callback = slot();
            if (callback == null) return null;
            text = text.replaceAll(token, callback);
          }
          return text;
        },
      );
      at(
        island.calls,
        placed,
        '$recorder.island(${literal(island.name)}, ',
        '$items$placedAt)',
      );
    }
    // [node] in the scope [scope], with each helper call that leads to a
    // recorded value written as its own recorded body.
    String? render(
      AstNode node,
      AstNode scope,
      List<AstNode> calls, {
      bool island = false,
    }) {
      final holes = <AstNode, String>{};
      // The island's own widget reads each shared argument from the once.
      if (island) holes.addAll(once[occurrenceOf(node, calls)]!.shared);
      for (final chain in chains.values) {
        if (chain.length != calls.length + 1) continue;
        if (chainKey(chain.sublist(0, calls.length)) != chainKey(calls)) {
          continue;
        }
        final call = chain.last;
        // Only the calls inside [node] are written here.
        if (call.offset < node.offset || call.end > node.end) continue;
        if (call is! MethodInvocation)
          return giveUp('call ${call.runtimeType}');
        final owner = hoist.helperBodies[call]
            ?.thisOrAncestorOfType<FunctionBody>()
            ?.parent;
        final declaration = owner is FunctionExpression ? owner.parent : owner;
        final (parameters, functionBody) = switch (declaration) {
          FunctionDeclaration(:final functionExpression) => (
            functionExpression.parameters,
            functionExpression.body,
          ),
          MethodDeclaration(:final parameters, body: final b) => (
            parameters,
            b,
          ),
          _ => (null, null),
        };
        if (declaration == null || parameters == null || functionBody == null) {
          return giveUp('no declaration $call');
        }
        final whole = render(declaration, declaration, chain);
        final arguments = render(call.argumentList, scope, calls);
        if (whole == null || arguments == null)
          return giveUp('helper render $call');
        final contents = declaration.root is CompilationUnit
            ? (declaration.root as CompilationUnit)
                  .declaredFragment
                  ?.source
                  .contents
                  .data
            : null;
        if (contents == null) return null;
        final head = contents.substring(declaration.offset, parameters.offset);
        if (!whole.startsWith(head)) return giveUp('head');
        var function = whole.substring(head.length).trimRight();
        if (functionBody is ExpressionFunctionBody && function.endsWith(';')) {
          function = function.substring(0, function.length - 1);
        }
        holes[call] = '($function)$arguments';
      }
      for (final shared in once.values) {
        final island = shared.node;
        if (identical(island, node) ||
            island.offset < node.offset ||
            island.end > node.end ||
            chainKey(shared.calls) != chainKey(calls)) {
          continue;
        }
        final written = [
          for (final argument in shared.arguments)
            render(argument, scope, calls),
        ];
        final widget = render(island, scope, calls, island: true);
        if (written.contains(null) || widget == null) return null;
        final text = shared.text(written.cast<String>(), widget);
        if (text == null) return null;
        holes[island] = text;
      }
      // An event the build fires dispatches through its own mount.
      final events = _EventHelperCalls();
      node.accept(events);
      final buildContext = _hoist?.analyzer.rootContext?.baseElement;
      for (final call in events.calls) {
        if (holes.keys.any(
          (hole) =>
              !identical(hole, node) &&
              hole.offset <= call.offset &&
              hole.end >= call.end,
        )) {
          continue;
        }
        if (call.argumentList.arguments.firstOrNull?.argumentExpression
            case final event?) {
          if (surfaceEventConstant(event) case final field?) {
            session.firedEvents.add(field);
          }
        }
        if (inlineEventIssue(call) case final issue?) {
          session.recordIssues.add(issue);
        }
        // A reserved event stays refused when the mount fires it.
        final reserved = _reservedEventIssues(call);
        if (reserved.isNotEmpty) {
          session.recordIssues.addAll(reserved);
          continue;
        }
        // Any other receiver runs as written: the SDK resolves the mount's
        // own context, under any name, to the surface it shows.
        final receiver = call.realTarget;
        if (buildContext != null &&
            !(receiver is SimpleIdentifier &&
                receiver.element?.baseElement == buildContext)) {
          continue;
        }
        final arguments = render(call.argumentList, scope, calls);
        if (arguments == null) return giveUp('event $call');
        holes[call] =
            '$recorder.surfaceEvent'
            '${call.typeArguments?.toSource() ?? ''}$arguments';
      }
      final aroundHere = around[chainKey(calls)] ?? const {};
      final analysis = analyzer.analyze(
        node,
        holes: holes,
        // The island's own record is written around its once, and its
        // app builder slots record where the design renders them.
        around: island
            ? (Map<AstNode, List<({String before, String after})>>.identity()
                ..addAll(aroundHere)
                ..remove(node)
                ..removeWhere(
                  (at, _) => once[occurrenceOf(node, calls)]!.slots.any(
                    (slot) => at.offset >= slot.offset && at.end <= slot.end,
                  ),
                ))
            : aroundHere,
        scope: scope,
      );
      return analysis is HoistEvaluable
          ? analysis.template
          : giveUp('render ${analysis.runtimeType}', analysis: analysis);
    }

    renderNode = render;
    if (misplaced case final node?) {
      return giveUp('outside', at: node);
    }
    final written = render(body, body, const [])?.replaceAll(into, recorder);
    if (written == null) return null;
    session.recordedFacts = RecordedBuild(
      body: body,
      sites: sites,
      returns: recordedReturns,
      splits: {
        for (final placed in session.recordPlacements)
          if (placed.split) placed.widget,
      },
      placesAppWidgets: session.recordPlacements.isNotEmpty,
      locate: _locationOf,
    );
    if (body is ExpressionFunctionBody) {
      return '() ${written.trimRight().replaceFirst(RegExp(r';$'), '')}';
    }
    return '() $written';
  }

  MountSplit? _splitAt(
    Expression root,
    _RootChain chain,
    List<int> kept,
    LiftedState? state,
    _IslandSession session,
  ) {
    // A builder's parameters and locals keep their names in the mount.
    final steps = [for (final index in kept) chain.steps[index]];
    final scope = {
      for (final step in steps) ...{...step.scope, ...step.bindings.keys},
    };
    final walk = _walk;
    session.scope.addAll(scope);
    _walk = _walk.copyWith(
      inlined: InlinedDefinitions(
        localBindings: {
          ..._walk.inlined.localBindings,
          for (final step in steps) ...step.bindings,
        },
        helpers: _walk.inlined.helpers,
      ),
    );
    final bottom = kept.isEmpty ? root : chain.steps[kept.last].next;
    final shellPairs = [
      for (final index in kept)
        (node: chain.nodes[index] as Expression, next: chain.steps[index].next),
    ];
    if (shellPairs.isEmpty && state == null) {
      session.scope.removeAll(scope);
      _walk = walk;
      return null;
    }
    // The recorded copy writes the shell and the design as the app wrote
    // them.
    for (final pair in shellPairs) {
      _recordsWithoutDesignState(
        pair.node,
        label: islandWidgetType(pair.node),
        holes: {pair.next: '_'},
        kind: _Recorded.wrapper,
      );
    }
    {
      for (final index in kept) {
        if (chain.steps[index].builder case final builder?) {
          _keptClosures.add(builder);
          session.keptBuilders.add(builder);
          _exposeBuilderState(builder, _locationOf(chain.nodes[index]));
        }
      }
      return MountSplit(
        kept: shellPairs,
        designRoot: bottom,
        shell: [
          for (final pair in shellPairs)
            (
              widget: islandWidgetType(pair.node),
              location: _locationOf(pair.node),
              reason:
                  pair.next.parent is FunctionBody ||
                      pair.next.parent is ReturnStatement
                  ? MountReason.builder
                  : MountReason.notDelivered,
            ),
        ],
        state: state,
      );
    }
  }

  /// Publishes every public field of [builder]'s parameters, and each
  /// parameter itself, that crosses as data, so any design can read them.
  void _exposeBuilderState(FunctionExpression builder, String location) {
    void expose(String source, DartType? type) {
      final verdict = classifyHoistType(type);
      if (verdict is! HoistCrosses ||
          verdict.kind == HoistValueKind.textScaler ||
          type == null) {
        return;
      }
      _hoist!.exposing = true;
      final value = _hoist!.add(
        HoistEvaluable(label: source, template: source).value(verdict, type),
      );
      _hoist!.exposing = false;
      _hoist!.exposes.add((key: value.key, source: source, builder: builder));
      _emissionSources?.add(
        DslEmissionSource(
          dsl: 'data.context.${value.key}',
          location: location,
          construct: source,
        ),
      );
    }

    for (final parameter
        in builder.parameters?.parameters ?? const <FormalParameter>[]) {
      final element = parameter.declaredFragment?.element;
      final name = element?.name;
      final type = element?.type;
      if (name == null || type is! InterfaceType) continue;
      expose(name, type);
      for (final owner in [type, ...type.allSupertypes]) {
        if (owner.element.library.isInSdk) continue;
        for (final field in owner.element.fields) {
          if (field.isStatic || !field.isPublic || !field.isOriginDeclaration) {
            continue;
          }
          final getter = type.lookUpGetter(field.name!, type.element.library);
          expose('$name.${field.name}', getter?.returnType);
        }
      }
    }
  }

  /// The single-child wrappers and builders from [root] down, and the index
  /// of the last one that does not lower.
  _RootChain _rootChain(Expression root) {
    final nodes = <InstanceCreationExpression>[];
    final steps = <_ShellStep>[];
    final lowers = <bool>[];
    var end = -1;
    var cursor = _stripParens(root);
    while (cursor is InstanceCreationExpression) {
      final step = _shellStep(cursor);
      if (step == null) break;
      nodes.add(cursor);
      steps.add(step);
      // A builder's body lowers with it or not at all, so a builder that
      // lowers ends the chain.
      final builder = step.builder != null;
      final attempt = _attempt(
        cursor,
        stub: builder ? null : step.next,
        probe: true,
      );
      // Only a node that needs app code stays in the mount.
      lowers.add(
        attempt.lowers ||
            !attempt.issues.every(
              (issue) => issue.code.isBuildNotice || issue.code.needsAppCode,
            ),
      );
      if (!lowers.last) {
        end = nodes.length - 1;
      } else if (builder) {
        break;
      }
      cursor = _stripParens(step.next);
    }
    return (nodes: nodes, steps: steps, lowers: lowers, end: end);
  }

  /// The surface's `State` as the mount declares it: its class header and
  /// members, with the mount's name in place of the surface's. `null`, with
  /// the reason recorded, when it cannot move.
  LiftedState? _liftedState(
    Expression root,
    ClassElement liftedState,
    _IslandSession session,
  ) {
    final unit = root.root as CompilationUnit;
    final source = unit.declaredFragment?.source.contents.data;
    final declaration = unit.declarations
        .whereType<ClassDeclaration>()
        .firstWhereOrNull((d) => d.declaredFragment?.element == liftedState);
    final surface = stateWidgetOf(liftedState);
    if (source == null || declaration == null || surface == null) return null;
    final members = [
      for (final member in declaration.body.members)
        if (!(member is MethodDeclaration && member.name.lexeme == 'build'))
          member,
    ];
    // The mount's State is not the app's, so its `super` is another object.
    final build = declaration.body.members
        .whereType<MethodDeclaration>()
        .firstWhereOrNull((member) => member.name.lexeme == 'build');
    final supers = <SuperExpression>[];
    build?.body.accept(_Supers(supers));
    if (supers.firstOrNull case final read?) {
      final use = switch (read.parent) {
        PropertyAccess() || MethodInvocation() => read.parent!,
        _ => read,
      };
      final calls = use is MethodInvocation;
      session.problem = Issue(
        code: IssueCode.stateShapeUnsupported,
        message:
            "`${liftedState.name}` can't be used in the generated "
            '`${_mountName(surface.name ?? '')}` because its build '
            '${calls ? 'calls' : 'reads'} `${readableSource(use.toSource())}` '
            '(${_locationOf(use)}). Try '
            '${calls ? 'calling it' : 'reading the value'} through a member '
            'of `${liftedState.name}`.',
        location: _locationOf(use),
      );
      return null;
    }
    final base = declaration.extendsClause?.superclass;
    if (base != null && !_baseTakesMount(base, surface)) {
      session.problem = Issue(
        code: IssueCode.stateShapeUnsupported,
        message:
            "`${liftedState.name}` can't be used in the generated "
            '`${_mountName(surface.name ?? '')}`. Its base class '
            '`${base.name.lexeme}` only accepts `${surface.name}` as its '
            'widget. Try loosening the bound on '
            "`${base.name.lexeme}`'s type parameter.",
        location: _locationOf(declaration),
      );
      return null;
    }
    // The header's and parameters' references to the surface's type name the
    // mount instead; constructions and other uses stay. `widget` reads an
    // instance of the surface the mount keeps current.
    String rewrite(AstNode node, {required bool header}) {
      final edits = <(int, int, String)>[];
      node.accept(_TypeReferences(surface, edits, header: header));
      node.accept(
        _ElementReferenceVisitor.at(
          _isStateWidgetGetter,
          (at) => edits.add((at.offset, at.end, kStateWidgetSlot)),
        ),
      );
      var text = source.substring(node.offset, node.end);
      edits.sort((left, right) => right.$1.compareTo(left.$1));
      for (final (start, end, replacement) in edits) {
        text = text.replaceRange(
          start - node.offset,
          end - node.offset,
          replacement,
        );
      }
      return text;
    }

    // The surface's didUpdateWidget runs from the mount's, given the
    // previous surface instance and the mount's old widget for `super`.
    String update(MethodDeclaration method) {
      final parameter = method.parameters?.parameters.singleOrNull;
      final name = parameter?.name?.lexeme ?? 'oldWidget';
      final body = method.body;
      final edits = <(int, int, String)>[];
      body.accept(
        _ElementReferenceVisitor.at(
          _isStateWidgetGetter,
          (at) => edits.add((at.offset, at.end, kStateWidgetSlot)),
        ),
      );
      body.accept(_SuperUpdates(edits));
      var text = source.substring(body.offset, body.end);
      edits.sort((left, right) => right.$1.compareTo(left.$1));
      for (final (start, end, replacement) in edits) {
        text = text.replaceRange(
          start - body.offset,
          end - body.offset,
          replacement,
        );
      }
      return 'void $kStateUpdateSlot(${surface.name} $name, '
          '$kMountNameMarker _restageOldWidget) $text';
    }

    return LiftedState(
      name: liftedState.name ?? '',
      location: _locationOf(declaration),
      header: [
        declaration.extendsClause,
        declaration.withClause,
        declaration.implementsClause,
      ].nonNulls.map((clause) => rewrite(clause, header: true)).join(' '),
      members: [
        for (final member in members)
          member is MethodDeclaration &&
                  member.name.lexeme == 'didUpdateWidget' &&
                  !member.isStatic
              ? update(member)
              : rewrite(member, header: false),
      ],
      updates: members.any(
        (member) =>
            member is MethodDeclaration &&
            member.name.lexeme == 'didUpdateWidget' &&
            !member.isStatic,
      ),
      customBase:
          base != null &&
          !(base.element?.name == 'State' &&
              base.element?.library?.identifier ==
                  'package:flutter/src/widgets/framework.dart'),
    );
  }

  // Whether the State base [base] can take the mount in place of [surface]:
  // Flutter's own `State`, or a base whose parameters the surface fills are
  // bounded by a type the mount, which extends the surface's own base, is.
  static bool _baseTakesMount(NamedType base, ClassElement surface) {
    final element = base.element;
    if (element is! InterfaceElement) return false;
    if (element.name == 'State' &&
        element.library.identifier ==
            'package:flutter/src/widgets/framework.dart') {
      return true;
    }
    final mount = surface.supertype;
    final arguments = base.typeArguments?.arguments ?? const <TypeAnnotation>[];
    if (mount == null ||
        !arguments.any((argument) => argument.type?.element == surface)) {
      return false;
    }
    for (final (index, argument) in arguments.indexed) {
      if (argument.type?.element != surface ||
          index >= element.typeParameters.length) {
        continue;
      }
      final bound = element.typeParameters[index].bound;
      if (bound is InterfaceType &&
          bound.element != mount.element &&
          !mount.allSupertypes.any((type) => type.element == bound.element)) {
        return false;
      }
    }
    return true;
  }

  /// The argument for [node]'s one widget or builder argument, when the call
  /// passes exactly one.
  _ShellStep? _shellStep(InstanceCreationExpression node) {
    bool isWidget(DartType? type) => classifyHoistType(type) is HoistIsWidget;
    final passed = [
      for (final argument in node.argumentList.arguments)
        if (_stripParens(
              argument is NamedArgument
                  ? argument.argumentExpression
                  : argument as Expression,
            )
            case final value
            when isWidget(value.staticType) ||
                _isWidgetListType(value.staticType) ||
                value is FunctionExpression &&
                    isWidget(value.declaredFragment?.element.returnType))
          value,
    ];
    if (passed.length != 1 || _isWidgetListType(passed.single.staticType)) {
      return null;
    }
    final argument = node.argumentList.arguments.firstWhere(
      (argument) => identical(
        _stripParens(
          argument is NamedArgument
              ? argument.argumentExpression
              : argument as Expression,
        ),
        passed.single,
      ),
    );
    final value = argument is NamedArgument
        ? argument.argumentExpression
        : argument as Expression;
    final builder = _stripParens(value);
    if (builder is! FunctionExpression) {
      return (next: value, builder: null, bindings: const {}, scope: const {});
    }
    // Only a builder that runs once per build of its widget joins the shell.
    final widget = node.constructorName.type.element;
    if (widget is! InterfaceElement ||
        !_islands!.contentFree.contains(
          widget,
          argument.correspondingParameter?.name ?? '',
        )) {
      return null;
    }
    final body = extractInlinableBuildBody(builder.body);
    if (body == null) return null;
    return (
      next: body.expression,
      builder: builder,
      bindings: body.localBindings,
      scope: {
        for (final parameter
            in builder.parameters?.parameters ?? const <FormalParameter>[])
          if (parameter.declaredFragment?.element case final element?) element,
      },
    );
  }

  /// Translates [node] against a checkpoint and rolls back when it does not
  /// lower or when it is a [probe]; [stub] stands for any delivered widget.
  ({String dsl, List<Issue> issues, bool lowers}) _attempt(
    Expression node, {
    Expression? stub,
    bool probe = false,
  }) {
    final stubs = _islands!.stubs;
    final misses = _hoist?.closureMisses.length ?? 0;
    final restore = _checkpoint();
    final scratch = <Issue>[];
    var dsl = '';
    if (stub != null) stubs.add(stub);
    try {
      if (!probe || _admitOrdinaryLeaf(node, scratch)) {
        dsl = _translateExpression(node, scratch);
      }
    } finally {
      if (stub != null) stubs.remove(stub);
    }
    final lowers =
        !scratch.any((issue) => !issue.code.isBuildNotice) &&
        (_hoist?.closureMisses.length ?? 0) == misses;
    if (probe || !lowers) restore();
    return (dsl: dsl, issues: scratch, lowers: lowers);
  }

  bool _isWidgetListType(DartType? type) =>
      type is InterfaceType &&
      (type.isDartCoreList || type.isDartCoreIterable) &&
      classifyHoistType(type.typeArguments.single) is HoistIsWidget;

  bool _isLiteralArgument(Expression value) {
    final stripped = _stripParens(value);
    return stripped is Literal ||
        stripped is InstanceCreationExpression && stripped.isConst ||
        tryFoldConstant(stripped) != null;
  }

  /// Captures the per-translation accumulators; the returned function puts
  /// them back, undoing a failed attempt.
  void Function() _checkpoint() {
    void Function() map<K, V>(Map<K, V>? target) {
      if (target == null) return () {};
      final copy = Map.of(target);
      return () => target
        ..clear()
        ..addAll(copy);
    }

    void Function() set<T>(Set<T>? target) {
      if (target == null) return () {};
      final copy = Set.of(target);
      return () => target
        ..clear()
        ..addAll(copy);
    }

    void Function() list<T>(List<T>? target) {
      if (target == null) return () {};
      final length = target.length;
      return () => target.length = length;
    }

    final restores = [
      map(_currentWidgetDefinitions),
      map(_currentWidgetDefinitionStates),
      map(_currentDefinitionOwners),
      set(_currentReferencedCustomLibraries),
      map(_currentRfwCatalogConstructorOrigins),
      set(_currentCustomWidgetInlineClaims),
      set(_currentCustomWidgetReferences),
      map(_currentCustomWidgetFactoryRoutes),
      list(_currentEventClosureNotices),
      list(_emissionSources),
      map(_hoist?.values),
      map(_hoist?.occurrenceKeys),
      map(_hoist?.occurrenceCounts),
      list(_hoist?.records),
      list(_hoist?.exposes),
      list(_hoist?.closureMisses),
      set(_keptClosures),
      list(_islands?.recordIslands),
      list(_islands?.recordPlacements),
      map(_islands?.islands),
      list(_islands?.order),
      _nestedMap(_paramPlacementCounts, (copies) => {...copies}),
      _nestedMap(_paramPlacements, (placed) => placed),
    ];
    final session = _collectionSession.copy();
    final islands = _islands;
    final designMiss = islands?.designMiss;
    final walk = _walk;
    final interactionItems = _currentEmitsInteractionItems;
    final suppressed = _currentTranslationSuppressed;
    final builderScopes = _builderScopeCounter;
    return () {
      _builderScopeCounter = builderScopes;
      for (final restore in restores) {
        restore();
      }
      _collectionSession = session;
      islands?.designMiss = designMiss;
      _walk = walk;
      _currentEmitsInteractionItems = interactionItems;
      _currentTranslationSuppressed = suppressed;
    };
  }

  // Restores [target], a map of maps, to its current contents.
  static void Function() _nestedMap<V>(
    Map<String, Map<String, V>> target,
    V Function(V value) copyValue,
  ) {
    final copy = {
      for (final MapEntry(:key, :value) in target.entries)
        key: {
          for (final inner in value.entries) inner.key: copyValue(inner.value),
        },
    };
    return () => target
      ..clear()
      ..addAll(copy);
  }

  /// The translation of [expr], reading a mount-computed value in place of
  /// an app-only expression; `null` when [expr] is not hoisted.
  String? _hoisted(
    Expression expr,
    List<Issue> issues,
    String Function(List<Issue> scratch) translate,
  ) {
    final hoist = _hoist;
    if (hoist == null || hoist.speculating) return null;
    final stripped = _stripParens(expr);
    if (hoist.inParts.contains(stripped)) return null;
    // A string or collection whose parts the payload cannot read crosses
    // whole.
    if (stripped is Literal &&
        stripped is! StringInterpolation &&
        stripped is! AdjacentStrings &&
        stripped is! TypedLiteral) {
      return null;
    }
    if (containsInstalledIntlTranslation(
      stripped,
      helpers: _walk.inlined.helpers,
    ))
      return null;
    final verdict = classifyHoistType(stripped.staticType);
    if (verdict is! HoistCrosses) return null;
    if (verdict.kind == HoistValueKind.color) {
      final source = _rootColorSource(stripped);
      final borrowed = _nativeBindingRead(source, type: 'flutter.Color');
      if (borrowed != null) return borrowed;
      if (_installedColorExpression(source) case final installed?) {
        try {
          final native = _tryNativeCallValue(
            installed,
            issues,
            type: 'flutter.Color',
          );
          if (native != null) return native;
        } on BuilderLoweringException catch (error) {
          issues.add(
            Issue(
              code: IssueCode.propertyValueTypeMismatch,
              message: error.reason,
              location: _locationOf(error.node),
            ),
          );
          return '';
        }
      }
    }
    final analysis = hoist.analyzer.analyze(stripped);
    if (analysis is! HoistEvaluable) return null;
    // A value that depends on design state is left for the design to lower.
    if (_designStateRead(stripped) != null) return null;
    if (verdict.kind == HoistValueKind.textScaler) {
      final native = _nativeBindingRead(stripped, type: 'flutter.TextScaler');
      if (native != null) return native;
    }
    // Per-item native objects need an explicit item scope before they can cross.
    if (verdict.kind == HoistValueKind.textScaler && analysis.item != null) {
      return null;
    }
    if (verdict.kind == HoistValueKind.scalar &&
        _readsKeyboardOrAccessibility(stripped)) {
      return _hoistedRead(
        hoist.add(
          analysis.value(verdict, stripped.staticType!, expression: stripped),
        ),
      );
    }
    // Copy stays in the payload around the parts the mount computes.
    if ((stripped is StringInterpolation || stripped is AdjacentStrings) &&
        hoist.inParts.add(stripped)) {
      final restore = _checkpoint();
      final parts = <Issue>[];
      try {
        final dsl = translate(parts);
        if (!parts.any((issue) => !issue.code.isBuildNotice)) {
          issues.addAll(parts);
          return dsl;
        }
      } finally {
        hoist.inParts.remove(stripped);
      }
      restore();
    }
    final scratch = <Issue>[];
    final String dsl;
    final restore = _checkpoint();
    hoist.speculating = true;
    final seesThrough = _seesThroughPreludes;
    _seesThroughPreludes = true;
    try {
      dsl = translate(scratch);
    } finally {
      hoist.speculating = false;
      _seesThroughPreludes = seesThrough;
    }
    if (!scratch.any((issue) => !issue.code.isBuildNotice)) {
      issues.addAll(scratch);
      return dsl;
    }
    restore();
    // A Color crosses as the native object; ARGB would drop its subtype.
    if (verdict.kind == HoistValueKind.color) {
      if (isInstalledNativeConstant(stripped)) {
        try {
          final native = _tryNativeCallValue(
            stripped,
            issues,
            type: 'flutter.Color',
          );
          if (native != null) return native;
        } on BuilderLoweringException catch (error) {
          issues.add(
            Issue(
              code: IssueCode.propertyValueTypeMismatch,
              message: error.reason,
              location: _locationOf(error.node),
            ),
          );
          return '';
        }
      }
      final native = _nativeBindingRead(
        stripped,
        type: 'flutter.Color',
        computed: true,
      );
      if (native != null) return native;
      issues.addAll(scratch);
      return '';
    }
    return _hoistedRead(
      hoist.add(
        analysis.value(
          verdict,
          stripped.staticType!,
          expression: stripped,
        ),
      ),
    );
  }

  bool _readsKeyboardOrAccessibility(AstNode node, [Set<AstNode>? visited]) {
    final seen = visited ?? Set<AstNode>.identity();
    if (!seen.add(node)) return false;
    if (node is Expression) {
      final resolved = _resolveBoundIdentifier(node);
      if (!identical(resolved, node)) {
        return _readsKeyboardOrAccessibility(resolved, seen);
      }
      if (_kKeyboardAndAccessibilityPaths.contains(
        _recognizeDeviceRead(node)?.path,
      )) {
        return true;
      }
      if (node is MethodInvocation) {
        final helper = _walk.inlined.helpers[node.methodName.element];
        if (helper != null) {
          // Check caller arguments before binding the body. A negative visit
          // can then be reused when that body is reached through another call.
          for (final argument in node.argumentList.arguments) {
            final expression = argument is NamedArgument
                ? argument.argumentExpression
                : argument as Expression;
            if (_readsKeyboardOrAccessibility(expression, seen)) return true;
          }
          return _inHelperBody(
            helper,
            node,
            <Issue>[],
            (body) => _readsKeyboardOrAccessibility(body, seen),
            refused: false,
          );
        }
      }
    }
    return node.childEntities.whereType<AstNode>().any(
      (child) => _readsKeyboardOrAccessibility(child, seen),
    );
  }

  RootContextParam? _borrowedNativeRoot(Expression expression) {
    final root = _rootParamRead(_stripParens(expression));
    final field = root?.field;
    if (field == null ||
        !field.isFinal ||
        field.isLate ||
        !field.isOriginDeclaration ||
        field.isAbstract ||
        field.isExternal)
      return null;
    return root;
  }

  bool _isInertNativeSelection(Expression expression) => isInertNativeSelection(
    expression,
    isBorrowedRead: (value) => _borrowedNativeRoot(value) != null,
  );

  /// Binds an exact constructor input, or with [computed] a value the mount
  /// evaluates; expressions with invocation timing stay local.
  String? _nativeBindingRead(
    Expression expression, {
    required String type,
    bool computed = false,
    bool construct = false,
  }) {
    if (_ownParamArg(expression) case final arg?) return arg;
    final hoist = _hoist;
    if (hoist == null || hoist.speculating) return null;
    final expr = _resolveBoundIdentifier(_stripParens(expression));
    final root = _borrowedNativeRoot(expr);
    if (root == null &&
        (!computed ||
            !construct &&
                (_InstalledNativeConstruction(
                  _resolveBoundIdentifier,
                )..visit(expr)).found))
      return null;
    final analysis = hoist.analyzer.analyze(expr);
    // A computed value read per list item binds once per item.
    if (analysis is! HoistEvaluable || (analysis.item != null && !computed)) {
      return null;
    }
    final valueType = root?.type ?? expr.staticType!;
    final contract = NativeBindingContract(
      type: type,
      nullable: valueType.nullabilitySuffix == NullabilitySuffix.question,
    );
    return _hoistedRead(
      hoist.add(
        analysis.value(
          HoistCrosses(
            HoistValueKind.nativeBinding,
            SurfaceScreenHostDataNativeBindingShapeV1(contract),
          ),
          valueType,
          expression: expr,
          nativeContract: contract,
          computed: root == null,
          location: _locationOf(expr),
        ),
      ),
    );
  }

  // The native binding contract values of [type] cross as, if any.
  static String? _nativeContractOf(DartType? type) {
    if (type is! InterfaceType) return null;
    for (final candidate in [type, ...type.allSupertypes]) {
      final element = candidate.element;
      if (nativeBindingRoute('${element.library.identifier}#${element.name}')
          case final route?) {
        return route.contractType;
      }
    }
    return null;
  }

  // A custom widget definition's read of its own parameter, as `args`: a
  // native value it was given crosses on as the same value.
  String? _ownParamArg(Expression expression) {
    if (_walk.classKey == null) return null;
    final (name, element) = switch (_stripParens(expression)) {
      SimpleIdentifier(:final name, :final element) => (name, element),
      PrefixedIdentifier(
        prefix: SimpleIdentifier(name: 'widget'),
        :final identifier,
      )
          when _walk.stateFields != null =>
        (identifier.name, identifier.element),
      _ => (null, null),
    };
    final variable = element is PropertyAccessorElement
        ? element.variable
        : element;
    final argName = name == null ? null : _walk.argNames[name];
    if (argName == null) return null;
    // Only a read of the parameter's own field is the parameter.
    final field = _walk.params[argName]?.sourceField;
    if (field == null || variable?.baseElement != field.baseElement) {
      return null;
    }
    return 'args${_rfwPathPart(argName)}';
  }

  PropertyEntry? _nativeKeyProperty(WidgetEntry entry) =>
      entry.properties.firstWhereOrNull((property) {
        if (property.name != 'key' || property.type != PropertyType.structured)
          return false;
        final shape = property.valueShape;
        final ref =
            property.structuredRef ??
            (shape is StructuredShape ? shape.structuredRef : null);
        final structured = ref == null
            ? null
            : _nativeCatalogIndex.structuredByRef(ref);
        return structured != null &&
            nativeBindingRoute(structured.sourceType)?.contractType ==
                'flutter.Key';
      });

  // A key a lowering can't carry is an issue, never dropped: in a mount the
  // widget then renders from the app with its key; without one it's refused.
  void _keyNotKept(Expression expression, List<Issue> issues) {
    // A builder's own program carries the key of the widget it returns.
    if (_activeWidgetBuilder != null) return;
    final mount = _generatedMountName(expression);
    issues.add(
      Issue(
        code: IssueCode.propertyValueTypeMismatch,
        message:
            '`${readableSource(_writtenSource(expression))}` '
            "(${_locationOf(expression)}): Restage keeps a widget's key only "
            "through the screen's generated widget, and this build doesn't "
            'use one. Try showing the screen through $mount, or removing the '
            'key.',
        location: _locationOf(expression),
      ),
    );
  }

  // The generated widget of the screen [expression] is in, as a message
  // names it.
  String _generatedMountName(Expression expression) {
    final declaration = expression.thisOrAncestorOfType<ClassDeclaration>();
    final element = declaration?.declaredFragment?.element;
    final screen = stateWidgetOf(element)?.name ?? element?.name;
    return screen == null
        ? 'its generated widget'
        : '`${generatedSurfaceName(screen, fallback: 'SurfaceScreen')}`';
  }

  String? _catalogNativeKey(
    WidgetEntry entry,
    Expression expression,
    List<Issue> issues,
  ) {
    final property = _nativeKeyProperty(entry);
    final resolved = _resolveBoundIdentifier(expression);
    // In a mount, a global key keeps its holder in the app, and a key that
    // compares by value and has no compiled constant is computed there.
    String? carried() {
      if (_islands == null ||
          property == null ||
          _activeWidgetBuilder != null ||
          runtimeRealizationFor(entry) != null ||
          !_comparesByValue(resolved)) {
        return null;
      }
      // The mount reads a build's constant local through its initializer.
      final read = _nativeBindingRead(
        _constantLocalValue(resolved) ?? expression,
        type: 'flutter.Key',
        computed: true,
        construct: true,
      );
      return read == null
          ? null
          : RfwConstructorPresenceEncoder.encode(property, read);
    }

    if (_islands != null) {
      if (_globalKeyIssue(expression) case final issue?) {
        issues.add(issue);
        return null;
      }
      // A constant has a compiled key; any other key the mount computes.
      if (!_isConstantKey(resolved)) {
        if (carried() case final key?) return key;
      }
    }
    final isNull =
        resolved is NullLiteral ||
        installedNativeConstantValue(resolved)?.isNull == true;
    final legacy = isNull || isLegacyScalarWidgetKey(resolved);
    if (runtimeRealizationFor(entry) != null && !legacy) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message:
              'A native key requires the original ${entry.name} owner; its guarded runtime replacement cannot retain that owner.',
          location: _locationOf(expression),
        ),
      );
      return null;
    }
    if (property == null && !legacy) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message:
              'A native key requires the original widget constructor key slot in the catalog.',
          location: _locationOf(expression),
        ),
      );
      return null;
    }
    if (isNull) {
      return property != null &&
              RfwConstructorPresenceProtocol.appliesTo(property)
          ? RfwConstructorPresenceEncoder.encode(property, 'null')
          : null;
    }
    final before = issues.length;
    final reference = _nativeKeyReference(expression, issues);
    if (reference == null && issues.length == before) {
      if (carried() case final key?) return key;
    }
    // In a mount a key the design can't carry is an issue, so the widget
    // takes a path that keeps it; it is never left out. A builder's own
    // program carries the key of the widget it returns.
    if (reference == null &&
        issues.length == before &&
        _activeWidgetBuilder == null &&
        (!legacy ||
            _islands != null ||
            property != null &&
                RfwConstructorPresenceProtocol.appliesTo(property))) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message:
              'This key requires an installed native Key binding; omitting it cannot preserve its owner or constructor default.',
          location: _locationOf(expression),
        ),
      );
    }
    if (reference == null && issues.length == before) {
      _keyNotKept(expression, issues);
      return null;
    }
    return reference == null || property == null
        ? reference
        : RfwConstructorPresenceEncoder.encode(property, reference);
  }

  // A global key in a mount: the app keeps the widget that holds it.
  Issue? _globalKeyIssue(Expression expression) {
    final type = _stripParens(expression).staticType;
    return type is InterfaceType &&
            [type, ...type.allSupertypes].any(
              (t) =>
                  t.element.name == 'GlobalKey' &&
                  t.element.library.identifier ==
                      'package:flutter/src/widgets/framework.dart',
            )
        ? Issue(
            code: IssueCode.propertyValueTypeMismatch,
            message: 'A global key needs the widget that holds it.',
            location: _locationOf(expression),
          )
        : null;
  }

  // Whether [expression], read through build locals, is a local key equal to
  // any key built from equal arguments: a constant with its own `==`, a key
  // whose `==` compares values, or a `ValueKey` over a type that does.
  bool _comparesByValue(Expression expression) {
    final seesThrough = _seesThroughPreludes;
    _seesThroughPreludes = true;
    try {
      expression = _stripParens(_resolveBoundIdentifier(expression));
    } finally {
      _seesThroughPreludes = seesThrough;
    }
    // A constant compares as the key it builds, such as `Key('…')`.
    final type =
        installedNativeConstantValue(expression)?.type ?? expression.staticType;
    if (type is! InterfaceType || !_isFlutterKey(type, 'LocalKey')) {
      return false;
    }
    final equals = type.lookUpMethod(
      '==',
      type.element.library,
      concrete: true,
    );
    if (equals == null ||
        equals.enclosingElement?.library?.isDartCore != false) {
      return false;
    }
    if (_isConstantKey(expression)) return true;
    if (equals.enclosingElement case final InterfaceElement owner
        when _isFlutterKey(owner.thisType, 'ValueKey')) {
      final value = type.asInstanceOf(owner)?.typeArguments.single;
      return value != null && _comparesValues(value);
    }
    return expression is InstanceCreationExpression &&
        (_islands?.contentFree.equalsByValue(type.element) ?? false);
  }

  // The initializer of the `const` local [expression] reads, if it reads one.
  static Expression? _constantLocalValue(Expression expression) {
    final element = expression is SimpleIdentifier ? expression.element : null;
    if (element is! LocalVariableElement || !element.isConst) return null;
    Expression? value;
    expression.thisOrAncestorOfType<FunctionBody>()?.accept(
      _DeclarationOf(element, (declaration) => value = declaration.initializer),
    );
    return value;
  }

  // Whether [expression] is a constant creation or reads a constant.
  static bool _isConstantKey(Expression expression) {
    final element = switch (expression) {
      Identifier(:final element) => element,
      PropertyAccess(:final propertyName) => propertyName.element,
      _ => null,
    };
    return expression is InstanceCreationExpression && expression.isConst ||
        element is PropertyAccessorElement && element.variable.isConst ||
        element is VariableElement && element.isConst;
  }

  // Whether [type] is Flutter's key class [name] or extends it.
  static bool _isFlutterKey(InterfaceType type, String name) =>
      [type, ...type.allSupertypes].any(
        (t) =>
            t.element.name == name &&
            t.element.library.identifier ==
                'package:flutter/src/foundation/key.dart',
      );

  // Whether values of [type] are equal when their contents are: core scalars,
  // enums, and classes with a constant constructor and their own `==`.
  static bool _comparesValues(DartType type) {
    if (type is! InterfaceType) return false;
    final element = type.element;
    if (element.library.isDartCore) {
      return const {
        'String',
        'int',
        'double',
        'num',
        'bool',
      }.contains(element.name);
    }
    if (element is EnumElement) return true;
    final equals = type.lookUpMethod('==', element.library, concrete: true);
    return equals != null &&
        equals.enclosingElement?.library?.isDartCore == false &&
        element.constructors.any((constructor) => constructor.isConst);
  }

  String? _nativeKeyReference(Expression expression, List<Issue> issues) {
    if (_islands != null) {
      if (_globalKeyIssue(expression) case final issue?) {
        issues.add(issue);
        return null;
      }
    }
    final active = _activeWidgetBuilder;
    if (active != null && active.hasNativeKeyValue(expression)) {
      return active.value(expression);
    }
    final borrowed = _nativeBindingRead(expression, type: 'flutter.Key');
    if (borrowed != null) return borrowed;
    final resolved = _resolveBoundIdentifier(_stripParens(expression));
    final hoist = _hoist;
    if (hoist != null &&
        !hoist.speculating &&
        installedNativeConstantType(resolved) == 'flutter.Key') {
      try {
        return _hoistedRead(
          hoist.add(
            installedNativeConstant(
              resolved,
              type: 'flutter.Key',
              emissionLibrary: hoist.analyzer.namespace.library,
              location: _locationOf(resolved),
            ),
          ),
        );
      } on BuilderLoweringException catch (error) {
        issues.add(
          Issue(
            code: IssueCode.propertyValueTypeMismatch,
            message: error.toString(),
            location: _locationOf(error.node),
          ),
        );
        return null;
      }
    }
    final constant = installedNativeConstantValue(resolved);
    // A ValueKey, written out or read from a constant declaration.
    final valueKeyType = switch (constant?.type ?? resolved.staticType) {
      final InterfaceType type => type.element,
      _ => null,
    };
    final scalarValueKey =
        valueKeyType?.name == 'ValueKey' &&
        valueKeyType?.library.identifier ==
            'package:flutter/src/foundation/key.dart' &&
        (resolved is InstanceCreationExpression || constant != null);
    if (constant != null && !constant.isNull && !scalarValueKey) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message: 'This constant Key family has no installed native route.',
          location: _locationOf(expression),
        ),
      );
      return null;
    }
    if (installedNativeConstructorType(resolved) != 'flutter.Key') return null;
    issues.add(
      Issue(
        code: IssueCode.propertyValueTypeMismatch,
        message:
            'A fresh native key requires an explicit callback or helper prelude initializer.',
        location: _locationOf(expression),
      ),
    );
    return null;
  }

  /// The payload's read of a mount-computed [value].
  String _hoistedRead(HoistedValue value) {
    final item = value.item;
    if (item == null) return 'data.context${_rfwPathPart(value.key)}';
    final loop = _walk.runtimeLoops.lastWhere((loop) => loop.item == item);
    return '${loop.identifier}${_rfwPathPart(value.key)}';
  }

  void _recordEmission(Expression expr, String dsl) {
    final sources = _emissionSources;
    if (sources == null || dsl.isEmpty || expr is ParenthesizedExpression) {
      return;
    }
    sources.add(
      DslEmissionSource(
        dsl: dsl,
        location: _locationOf(expr),
        construct: quoteConstruct(expr.toSource()),
      ),
    );
  }

  bool _containsIntlFormatting(Expression expression) =>
      containsIntlFormatting(expression, helpers: _walk.inlined.helpers);

  Map<String, ValueOperation> get _installedValueOperations =>
      installedNativeCallOperations(_hoist?.values.values ?? const []);

  int _lowerNativeCall(
    Expression value,
    BuilderExpressionLowering lowering, {
    required ValueType resultType,
    Map<Expression, String?> constantStrings = const {},
  }) {
    while (value is ParenthesizedExpression) {
      value = value.expression;
    }
    final active = _activeWidgetBuilder;
    if (value is! FunctionExpression &&
        (active == null || active.isProjectingBody) &&
        !_isInertNativeSelection(value)) {
      throw BuilderLoweringException(
        value,
        'Native evaluation requires an explicit callback or helper prelude initializer',
      );
    }
    final hoist = _hoist;
    if (hoist == null || hoist.speculating) {
      throw BuilderLoweringException(
        value,
        'Native calls require an installed source declaration',
      );
    }
    return lowering.lowerInstalledNativeCall(
      value,
      resultType: resultType,
      constantStrings: constantStrings,
      isBorrowedCallable: (reference) {
        final expr = _resolveBoundIdentifier(_stripParens(reference));
        // A split action's callback arrives as an input.
        if (_splittingAction && _widgetField(expr)?.type is FunctionType) {
          return true;
        }
        final root = _borrowedNativeRoot(expr);
        if (root?.type is! FunctionType) return false;
        final analysis = hoist.analyzer.analyze(expr);
        return analysis is HoistEvaluable && analysis.item == null;
      },
      emissionLibrary: hoist.analyzer.namespace.library,
      borrow: (identifier) {
        final root = _rootParamRead(identifier);
        if (root == null) return null;
        final String nominalType;
        try {
          nominalType = installedNativeTypeId(root.type);
        } on ArgumentError {
          throw BuilderLoweringException(
            identifier,
            'The native input type cannot be declared in this frame',
          );
        }
        final type = ValueType.native(
          nominalType,
          nullable: root.type.nullabilitySuffix == NullabilitySuffix.question,
        );
        final dsl = _nativeBindingRead(identifier, type: type.nativeType!);
        if (dsl == null) return null;
        final name = 'c${lowering.captureTypes.length}';
        lowering.captureTypes[name] = type;
        lowering.captureDsl[name] = dsl;
        return InstalledNativeInput(
          lowering.add(ValueNode('capture', type, name: name)),
          type,
        );
      },
      inputOf: _splittingAction
          ? (expression) => _actionInput(expression, lowering)
          : null,
      install: (plan) => hoist.add(plan.bindingAt(_locationOf(value))),
    );
  }

  // Whether an action is lowered as the app's callback, with arguments the
  // payload evaluates.
  bool _splittingAction = false;

  // Why the action being split can't take an argument, when that ends it.
  ({AstNode node, String problem, String fix})? _splitRefusal;

  /// Notes that the mount would depend on design state through [node], so the
  /// design can't keep its State. The first note is the one reported.
  void _designMiss(AstNode node, String problem, String fix) {
    final session = _islands;
    if (session == null || !session.designOwnsState || session.recording) {
      return;
    }
    session.designMiss ??= Issue(
      code: IssueCode.stateKeptInApp,
      message:
          "`${session.liftedState!.name}` stays in your app's code, so a "
          "published design can't change it: $problem. Try $fix.",
      location: _locationOf(node),
    );
  }

  // The State member the design owns that [node] reads, directly or through a
  // helper parameter, a build local or `this`; null when it reads none.
  Element? _designStateRead(
    AstNode node, {
    Map<AstNode, String> holes = const {},
  }) {
    final session = _islands;
    final hoist = _hoist;
    if (session == null ||
        hoist == null ||
        !session.designOwnsState ||
        session.recording) {
      return null;
    }
    session.probing = true;
    final HoistAnalysis analysis;
    try {
      analysis = hoist.analyzer.analyze(node, holes: holes);
    } finally {
      session.probing = false;
    }
    if (analysis is! HoistNeedsSurfaceValue) return null;
    return analysis.elements.firstWhereOrNull(
      (element) =>
          session.isDesignStateMember(element) ||
          element == session.liftedState,
    );
  }

  /// Enforces that what the mount records at [node] doesn't depend on design
  /// state: neither [node] nor a condition that decides whether it runs reads
  /// a member the design owns.
  void _recordsWithoutDesignState(
    AstNode node, {
    String? label,
    Map<AstNode, String> holes = const {},
    _Recorded kind = _Recorded.value,
    bool conditionsOnly = false,
  }) {
    final session = _islands;
    if (session == null || !session.designOwnsState || session.recording) {
      return;
    }
    final shown = label ?? readableSource(_writtenSource(node));
    void underCondition(Expression condition, Element member) {
      final written = readableSource(_writtenSource(condition));
      final reads = written == member.name
          ? ''
          : ', which reads `${member.name}`';
      if (kind == _Recorded.branch) {
        _designMiss(
          condition,
          '`$shown` picks the widget it returns with `$written`$reads, so '
              "your app's own copy of `${member.name}` picks it",
          'choosing between the widgets with a conditional expression, as in '
              "`annualSelected ? const Text('Annual') : const Text('Monthly')`",
        );
        return;
      }
      _designMiss(
        node,
        '`$shown` is computed by your app under `$written`'
            '${written == member.name ? '' : ', which reads `${member.name}`'}'
            ', so your app computes only the value its own copy of '
            '`${member.name}` picks',
        'showing each value in its own widget and hiding the other one, as '
            'in `Offstage(offstage: !annualSelected, child: Text(annual))`',
      );
    }

    if (conditionsOnly) {
      // Only what decides whether [node] runs is checked.
    } else if (_designStateRead(node, holes: holes) case final member?) {
      // A condition inside the value is reported as the condition it is.
      final condition = switch (node) {
        final Expression value => switch (_stripParens(value)) {
          ConditionalExpression(:final condition) => condition,
          SwitchExpression(:final expression) => expression,
          _ => null,
        },
        _ => null,
      };
      if (condition != null && _designStateRead(condition) == member) {
        underCondition(condition, member);
        return;
      }
      final name = member.name;
      final (problem, fix) = switch ((member, kind, node)) {
        (ClassElement(), _, _) => (
          '`$shown` runs in your app and uses `this`, the State the design '
              'keeps',
          'passing the State fields it needs instead of the State, as in '
              '`describe(annualSelected)`',
        ),
        (_, _Recorded.wrapper, _) => (
          '`$shown` wraps the design in your app\'s code and reads `$name`',
          'moving that read below the wrapper, into the widgets the design '
              'shows',
        ),
        (_, _Recorded.widget, _) => (
          '`$shown` is a widget your app builds, and it reads `$name`',
          'promoting it with `restage widget promote ${_locationOf(node)}` '
              'so the design builds it',
        ),
        (FieldElement(isOriginDeclaration: false), _, _) => (
          '`$name` is a getter your app computes from the State the design '
              'keeps, and `$shown` reads it',
          'reading the State fields it computes from in the design, or '
              'passing the value in as a widget field',
        ),
        (MethodElement(), _, _) => (
          '`$shown` runs in your app and calls `$name` of the State the '
              'design keeps',
          'passing `$name` straight to the widget that fires it, as in '
              '`onTap: $name`, or moving its work into a callback your widget '
              'takes',
        ),
        (_, _, FunctionExpression()) => (
          '`$shown` runs in your app and reads `$name`, which belongs to the '
              'State the design keeps',
          'reading `$name` in the callback\'s arguments rather than through '
              'a build local or helper, as in '
              '`() => widget.onDone?.call($name)`',
        ),
        _ => (
          '`$shown` is computed by your app from `$name`, which belongs to '
              'the State the design keeps',
          'reading `$name` only in the widgets the design shows and in '
              'setState handlers, or passing the value in as a widget field',
        ),
      };
      _designMiss(node, problem, fix);
      return;
    }
    for (final start in [node, ..._callSites.reversed]) {
      for (
        AstNode child = start, parent = start.parent!;
        parent is! MethodDeclaration &&
            parent is! FunctionDeclaration &&
            parent is! CompilationUnit;
        child = parent, parent = parent.parent!
      ) {
        final conditions = switch (parent) {
          ConditionalExpression(:final condition) when child != condition => [
            condition,
          ],
          IfElement(:final expression) when child != expression => [
            expression,
          ],
          IfStatement(:final expression) when child != expression => [
            expression,
          ],
          SwitchExpression(:final expression) when child != expression => [
            expression,
          ],
          SwitchStatement(:final expression) when child != expression => [
            expression,
          ],
          // An arm runs only when no earlier guard took the switch.
          SwitchExpressionCase(parent: SwitchExpression(:final cases))
              when child != parent.guardedPattern =>
            [
              for (final arm in cases.take(cases.indexOf(parent) + 1))
                ?arm.guardedPattern.whenClause?.expression,
            ],
          BinaryExpression(:final leftOperand, :final operator)
              when child != leftOperand &&
                  const {'&&', '||', '??'}.contains(operator.lexeme) =>
            [leftOperand],
          _ => const <Expression>[],
        };
        for (final condition in conditions) {
          if (_designStateRead(condition) case final member?) {
            underCondition(condition, member);
            return;
          }
        }
      }
    }
  }

  // How to declare a State field of [type] so the design can pass it, or null
  // when it already can.
  static String? _fieldTypeFix(String source, DartType? type) => switch (type) {
    InterfaceType(element: EnumElement()) =>
      'declaring `$source` as a `String` that holds the value\'s name',
    final InterfaceType type
        when type.nullabilitySuffix == NullabilitySuffix.question =>
      'declaring `$source` as a non-null `${type.element.name}` with a '
          'starting value',
    InterfaceType(element: ClassElement(name: 'num')) =>
      'declaring `$source` as a `double` or an `int`',
    _ => null,
  };

  // An input of a split action: the borrowed callback, or an argument that
  // reads design state, evaluated by the payload at tap time.
  InstalledNativeInput? _actionInput(
    Expression expression,
    BuilderExpressionLowering lowering,
  ) {
    // A widget field arrives as the mount's own value.
    if (_widgetField(expression) case final root?) {
      return _widgetFieldCapture(root, lowering, expression: expression);
    }
    if (!_readsDesignState(expression)) return null;
    final type = switch (expression.staticType) {
      final InterfaceType type
          when type.nullabilitySuffix == NullabilitySuffix.none &&
              type.element.library.isDartCore =>
        switch (type.element.name) {
          'bool' => ValueType.boolean,
          'int' => ValueType.integer,
          'double' => ValueType.real,
          'String' => ValueType.string,
          _ => null,
        },
      _ => null,
    };
    if (type == null && expression.parent is ArgumentList) {
      final source = readableSource(expression.toSource());
      _splitRefusal ??= (
        node: expression,
        problem:
            '`$source` is a `${expression.staticType}`, and a value the design '
            'passes to a callback is a non-null bool, int, double or String',
        fix:
            _fieldTypeFix(source, expression.staticType) ??
            'passing a bool, int, double or String State field instead',
      );
      return null;
    }
    if (type == null) return null;
    // A whole capture is the design's own value; anything the mount would
    // compute for it is left behind, and its parts arrive as inputs instead.
    final hoist = _hoist!;
    final restore = _checkpoint();
    final blocked = Set.of(_islands?.blocked ?? const <Element>{});
    final scratch = <Issue>[];
    hoist.speculating = true;
    final String dsl;
    try {
      dsl = _translate(expression, scratch);
    } finally {
      hoist.speculating = false;
    }
    if (dsl.isEmpty ||
        scratch.any((issue) => !issue.code.isBuildNotice) ||
        !_captureKeepsType(dsl, type)) {
      restore();
      _islands?.blocked
        ?..clear()
        ..addAll(blocked);
      return null;
    }
    return _actionCapture(lowering, type, dsl);
  }

  // [root] read from the mount as a native capture, or null when its type
  // has no stable name.
  InstalledNativeInput? _widgetFieldCapture(
    RootContextParam root,
    BuilderExpressionLowering lowering, {
    required Expression expression,
  }) {
    final String nominal;
    try {
      nominal = installedNativeTypeId(root.type);
    } on ArgumentError {
      _splitRefusal ??= (
        node: expression,
        problem:
            '`widget.${root.name}` has the type `${root.type}`, which a '
            'published design has no name for',
        fix: switch (root.type) {
          final FunctionType type
              when type.formalParameters.any((p) => p.type is RecordType) =>
            'taking each value as its own parameter instead of a record',
          FunctionType() =>
            'declaring its parameter and result types, as in '
                '`final void Function(String plan)? ${root.name};`',
          _ => 'declaring the field with a class type',
        },
      );
      return null;
    }
    final type = ValueType.native(
      nominal,
      nullable: root.type.nullabilitySuffix == NullabilitySuffix.question,
    );
    final dsl = expression is PrefixedIdentifier
        ? _nativeBindingRead(expression, type: nominal)
        : _rootBindingRead(root, expression, type: nominal);
    if (dsl == null) return null;
    return _actionCapture(lowering, type, dsl);
  }

  // The mount's binding of [root], as `widget.<root>` at [site] would read it.
  String? _rootBindingRead(
    RootContextParam root,
    AstNode site, {
    required String type,
  }) {
    final hoist = _hoist;
    if (hoist == null || hoist.speculating) return null;
    final contract = NativeBindingContract(
      type: type,
      nullable: root.type.nullabilitySuffix == NullabilitySuffix.question,
    );
    return _hoistedRead(
      hoist.add(
        HoistEvaluable(
          label: 'widget.${root.name}',
          template: '\u0000${root.name}\u0000',
          node: site,
        ).value(
          HoistCrosses(
            HoistValueKind.nativeBinding,
            SurfaceScreenHostDataNativeBindingShapeV1(contract),
          ),
          root.type,
          nativeContract: contract,
          location: _locationOf(site),
        ),
      ),
    );
  }

  // The final widget field [expression] reads as `widget.<field>`.
  RootContextParam? _widgetField(Expression expression) {
    if (expression is PrefixedIdentifier) {
      return _borrowedNativeRoot(expression);
    }
    if (expression case PropertyAccess(
      target: SimpleIdentifier target,
      :final propertyName,
    ) when _walk.rootStateContext && _isInheritedStateWidgetReceiver(target)) {
      final root = _rootParamForElement(propertyName.element);
      final field = root?.field;
      if (field != null &&
          field.isFinal &&
          !field.isLate &&
          field.isOriginDeclaration &&
          !field.isAbstract &&
          !field.isExternal) {
        return root;
      }
    }
    return null;
  }

  // The payload types a state read by the value it is seeded with, which the
  // design writes as a double for a double or num field.
  bool _captureKeepsType(String dsl, ValueType type) {
    final read = RegExp(r'^state\.([A-Za-z_$][A-Za-z0-9_$]*)$').firstMatch(dsl);
    if (read == null) {
      // An int literal in a double value is seeded as an int.
      return type.kind != 'double' && !dsl.startsWith('data.local.');
    }
    final field = _walk.stateFields?[read.group(1)];
    final seed = field?.initialValue;
    return switch (type.kind) {
      'bool' => seed is bool,
      'int' => seed is int && !field!.isNumeric,
      'double' => seed is num && field!.isNumeric,
      'String' => seed is String,
      _ => false,
    };
  }

  InstalledNativeInput _actionCapture(
    BuilderExpressionLowering lowering,
    ValueType type,
    String dsl,
  ) {
    final name = 'c${lowering.captureTypes.length}';
    lowering.captureTypes[name] = type;
    lowering.captureDsl[name] = dsl;
    return InstalledNativeInput(
      lowering.add(ValueNode('capture', type, name: name)),
      type,
    );
  }

  static bool _isSelector(SimpleIdentifier identifier) =>
      switch (identifier.parent) {
        PrefixedIdentifier(identifier: final selector) => identical(
          selector,
          identifier,
        ),
        PropertyAccess(:final propertyName, :final target) =>
          identical(propertyName, identifier) && target is! ThisExpression,
        MethodInvocation(:final methodName, :final target) =>
          identical(methodName, identifier) && target != null,
        _ => false,
      };

  // Whether [expression] is `() => callback(...)` over design state, where
  // the callback is a field of the widget.
  bool _splitsAction(Expression expression) {
    if (expression is! FunctionExpression ||
        expression.parameters?.parameters.isNotEmpty != false) {
      return false;
    }
    final call = switch (expression.body) {
      ExpressionFunctionBody(:final expression) => expression,
      BlockFunctionBody(
        block: Block(statements: [ExpressionStatement(:final expression)]),
      ) =>
        expression,
      _ => null,
    };
    if (call == null || !_readsDesignState(call)) return false;
    final callee = switch (call) {
      MethodInvocation(
        methodName: SimpleIdentifier(name: 'call'),
        :final target?,
      ) =>
        target,
      FunctionExpressionInvocation(:final function) => function,
      _ => null,
    };
    final root = switch (callee) {
      PostfixExpression(:final operand) => operand,
      final Expression callee => callee,
      null => null,
    };
    return root is Expression && _widgetField(root)?.type is FunctionType;
  }

  // Whether [node] reads a State field the design owns.
  bool _readsDesignState(AstNode node) {
    final fields = _walk.stateFields;
    if (fields == null || !_walk.rootStateContext) return false;
    var reads = false;
    node.accept(
      _IdentifierVisitor((identifier) {
        final element = identifier.element;
        if (element is PropertyAccessorElement &&
            !element.isStatic &&
            element.variable is FieldElement &&
            !identifier.inSetterContext() &&
            !_isSelector(identifier) &&
            (fields.containsKey(identifier.name) ||
                _currentLocalFields.contains(identifier.name))) {
          reads = true;
        }
      }),
    );
    return reads;
  }

  String? _tryNativeCallValue(
    Expression expression,
    List<Issue> issues, {
    required String type,
  }) {
    if (_hoist == null || _hoist!.speculating) return null;
    while (expression is ParenthesizedExpression) {
      expression = expression.expression;
    }
    final active = _activeWidgetBuilder;
    if (isInstalledNativeConstant(expression)) {
      final value = _hoist!.add(
        installedNativeConstant(
          expression,
          type: type,
          emissionLibrary: _hoist!.analyzer.namespace.library,
          location: _locationOf(expression),
        ),
      );
      final reference = _hoistedRead(value);
      if (active == null) return reference;
      return active.nativeValue(expression, (_, lowering) {
        final name = 'c${lowering.captureTypes.length}';
        final shape = ValueType.native(
          type,
          nullable: value.nativeContract!.nullable,
        );
        lowering.captureTypes[name] = shape;
        lowering.captureDsl[name] = reference;
        return lowering.add(ValueNode('capture', shape, name: name));
      });
    }
    if (active != null) {
      return active.nativeValue(
        expression,
        (value, lowering) => _lowerNativeCall(
          value,
          lowering,
          resultType: ValueType.native(
            type,
            nullable:
                value.staticType?.nullabilitySuffix ==
                NullabilitySuffix.question,
          ),
        ),
      );
    }
    if (expression is! FunctionExpression &&
        !_isInertNativeSelection(expression)) {
      throw BuilderLoweringException(
        expression,
        'Native evaluation requires an explicit callback or helper prelude initializer',
      );
    }
    // Root native inputs retain only proven borrowed constructor fields.
    final values = BuilderExpressionLowering(
      operations: _installedValueOperations,
      capture: (value) => _translate(value, issues),
    );
    final root = _lowerNativeCall(
      expression,
      values,
      resultType: ValueType.native(
        type,
        nullable:
            expression.staticType?.nullabilitySuffix ==
            NullabilitySuffix.question,
      ),
    );
    return _encodeScalarValueProgram(values, root);
  }

  int? _lowerInstalledValue(
    Expression value,
    BuilderExpressionLowering lowering,
  ) {
    if (isInstalledIntlTranslation(value)) {
      return _lowerNativeCall(value, lowering, resultType: ValueType.string);
    }
    final optional = optionalNativeInitializerType(value);
    if (optional != null && value is SimpleIdentifier) {
      final node = lowering.bindings[value.element];
      if (node != null) {
        final type = lowering.nodes[node].type;
        if (type.kind == 'native' && type.nativeType == optional) return node;
        throw BuilderLoweringException(
          value,
          'A native SVG alias requires its original installed value',
        );
      }
    }
    final native = optional ?? installedNativeConstructorType(value);
    if (native != null) {
      return _lowerNativeCall(
        value,
        lowering,
        resultType: ValueType.native(
          native,
          nullable:
              value.staticType?.nullabilitySuffix ==
                  NullabilitySuffix.question ||
              value.staticType?.isDartCoreNull == true,
        ),
      );
    }
    return lowerIntlValue(value, lowering, resolve: _resolveBoundIdentifier);
  }

  void _checkValueProgramBinding(Expression value, Expression bound) {
    if (isNativeIntlFormatterType(value.staticType) ||
        _containsIntlFormatting(bound)) {
      throw BuilderLoweringException(
        value,
        'A captured formatter requires a native prelude binding',
      );
    }
  }

  String? _tryIntlFormattingValue(Expression expression, List<Issue> issues) {
    final resolved = _resolveBoundIdentifier(expression);
    if (resolved.staticType?.isDartCoreString != true ||
        !_containsIntlFormatting(resolved))
      return null;
    return _tryScalarValueProgram(expression, issues);
  }

  String? _tryScalarValueProgram(
    Expression expression,
    List<Issue> issues, {
    bool asDouble = false,
    WidgetBuilderLowering? parentBuilder,
  }) {
    final resolved = _resolveBoundIdentifier(expression);
    final type = resolved.staticType;
    if (type == null ||
        !(type.isDartCoreString ||
            type.isDartCoreBool ||
            type.isDartCoreInt ||
            type.isDartCoreDouble ||
            type.isDartCoreNum))
      return null;
    if (!identical(resolved, expression) &&
        expression is SimpleIdentifier &&
        _walk.inlined.localBindings.containsKey(expression.element)) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message:
              'An eagerly computed local requires a native prelude binding',
          location: _locationOf(expression),
        ),
      );
      return '';
    }
    late final BuilderExpressionLowering values;
    values = BuilderExpressionLowering(
      operations: _installedValueOperations,
      parent: parentBuilder?.expressions,
      capture: (value) {
        if (parentBuilder != null &&
            (values.referencesOuter(value) ||
                _slotFrames.contains(parentBuilder))) {
          return parentBuilder.captureValue(value);
        }
        final saved = _activeWidgetBuilder;
        if (parentBuilder != null) _activeWidgetBuilder = null;
        try {
          return _translate(value, issues);
        } finally {
          _activeWidgetBuilder = saved;
        }
      },
      extension: (value, lowering) {
        if (value is SimpleIdentifier &&
            !lowering.bindings.containsKey(value.element)) {
          final bound = _resolveBoundIdentifier(value);
          if (!identical(bound, value)) {
            _checkValueProgramBinding(value, bound);
            return lowering.lower(bound);
          }
        }
        final root = _rootParamAccess(value);
        if (root != null && root.shape != null && !root.isRefused) {
          final name = 'c${lowering.captureTypes.length}';
          final type = valueTypeFor(value.staticType, value);
          lowering.captureTypes[name] = type;
          lowering.captureDsl[name] = _translate(value, issues);
          return lowering.add(ValueNode('capture', type, name: name));
        }
        if (value is MethodInvocation) {
          final helper =
              _walk.inlined.helpers[value.methodName.element] ??
              pureBuilderHelperFor(value, value.methodName.element);
          if (helper != null) {
            return lowering.lowerHelper(helper, value);
          }
        }
        return _lowerInstalledValue(value, lowering);
      },
    );
    try {
      var root = values.lower(resolved);
      // Ordinary values use the rendered constructor's context; authored context
      // reads require mount hoisting or a native callback's lexical binding.
      if (values.parameters.keys.any(
        (name) =>
            name != 'context:device:defaultTargetPlatform' &&
            builderContextValueType(name) != null,
      )) {
        throw BuilderLoweringException(
          expression,
          'An ambient context read requires an admitted native context binding',
        );
      }
      if (asDouble && values.nodes[root].type.kind == 'int') {
        root = values.add(
          ValueNode('toDouble', ValueType.real, inputs: [root]),
        );
      }
      return _encodeScalarValueProgram(values, root);
    } on BuilderLoweringException catch (error) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: error.reason,
          location: _locationOf(error.node),
        ),
      );
      return '';
    } on FormatException catch (error) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: error.message,
          location: _locationOf(expression),
        ),
      );
      return '';
    }
  }

  String _encodeScalarValueProgram(BuilderExpressionLowering values, int root) {
    final program = values.program(root);
    program.validate(operations: _installedValueOperations);
    return '$_kValueProgram${_stringLiteral(program.encode())}, captures: {'
        '${values.captureDsl.entries.map((e) => '${e.key}: ${e.value}').join(', ')} } }';
  }

  WidgetBuilderLowering? _activeWidgetBuilder;
  bool _inSpanCollection = false;
  bool _inSpanRecognizerCallback = false;

  String _spanCollectionBuilderValue(
    Expression expression,
    List<Issue> issues, {
    bool asDouble = false,
  }) {
    final resolved = _resolveBoundIdentifier(expression);
    final reference = _runtimeLoopReference(resolved);
    if (reference != null &&
        !reference.isRefused &&
        !(asDouble && resolved.staticType?.isDartCoreInt == true)) {
      return reference.dsl(_rfwPathPart);
    }
    var usesLoop = false;
    for (final loop in _walk.runtimeLoops) {
      resolved.accept(
        _ElementReferenceVisitor(loop.element, () => usesLoop = true),
      );
    }
    if (!usesLoop)
      return _activeWidgetBuilder!.value(expression, asDouble: asDouble);
    if (_inSpanRecognizerCallback) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message:
              'A computed loop event argument requires an installed native callback binding.',
          location: _locationOf(expression),
        ),
      );
      return '';
    }
    return _tryScalarValueProgram(
          expression,
          issues,
          asDouble: asDouble,
          parentBuilder: _activeWidgetBuilder,
        ) ??
        '';
  }

  bool _customNativeValueBoundary = false;

  T _withinNativeValueBoundary<T>(bool custom, T Function() translate) {
    final previous = _customNativeValueBoundary;
    _customNativeValueBoundary = custom;
    try {
      return translate();
    } finally {
      _customNativeValueBoundary = previous;
    }
  }

  int _builderScopeCounter = 0;
  final Set<HelperDef> _activeBuilderHelpers = {};
  int _nativePhysicsDepth = 0;

  String _translateScalarCallback(
    Expression expression,
    ScalarCallbackContract contract,
    List<Issue> issues,
  ) {
    if (contract.parameters.singleOrNull == ScalarCallbackParameter.valueKey &&
        contract.nullableResult) {
      final borrowed = _nativeBindingRead(
        expression,
        type: 'flutter.ChildIndexGetter',
      );
      if (borrowed != null) {
        return _nativeKeyIndexReference(
          borrowed,
          nullable:
              expression.staticType?.nullabilitySuffix ==
              NullabilitySuffix.question,
        );
      }
    }
    final scalarIssues = <Issue>[];
    final scalar = _translatePureScalarCallback(
      expression,
      contract,
      scalarIssues,
    );
    if (scalarIssues.isEmpty) return scalar;
    final resolved = _resolveBoundIdentifier(expression);
    if (contract.parameters.singleOrNull == ScalarCallbackParameter.valueKey &&
        contract.nullableResult &&
        resolved is FunctionExpression) {
      try {
        final native = _tryNativeCallValue(
          resolved,
          issues,
          type: 'flutter.ChildIndexGetter',
        );
        if (native != null)
          return _activeWidgetBuilder == null
              ? '{nativeKeyIndex: $native}'
              : _nativeKeyIndexReference(native);
      } on BuilderLoweringException catch (error) {
        issues.add(
          Issue(
            code: IssueCode.propertyValueTypeMismatch,
            message: error.toString(),
            location: _locationOf(error.node),
          ),
        );
        return '';
      }
    }
    issues.addAll(scalarIssues);
    return '';
  }

  String _nativeKeyIndexReference(String reference, {bool nullable = false}) {
    final values = BuilderExpressionLowering(
      operations: _installedValueOperations,
      capture: (_) => reference,
    );
    final type = ValueType.native(
      'flutter.ChildIndexGetter',
      nullable: nullable,
    );
    values.captureTypes['c0'] = type;
    values.captureDsl['c0'] = reference;
    final root = values.add(ValueNode('capture', type, name: 'c0'));
    return '{nativeKeyIndex: ${_encodeScalarValueProgram(values, root)}}';
  }

  String _translatePureScalarCallback(
    Expression expression,
    ScalarCallbackContract contract,
    List<Issue> issues,
  ) {
    final callback = _resolveBoundIdentifier(expression);
    final definition = callback is SimpleIdentifier
        ? pureBuilderCallbackFor(callback, callback.element)
        : null;
    final helper = callback is SimpleIdentifier
        ? _walk.inlined.helpers[callback.element] ??
              pureBuilderHelperFor(callback, callback.element)
        : null;
    if (callback is! FunctionExpression &&
        definition == null &&
        helper == null) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message: 'A scalar callback requires an analyzed pure closure.',
          location: _locationOf(expression),
        ),
      );
      return '';
    }
    final previous = _activeWidgetBuilder;
    late final ScalarCallbackLowering lowering;
    try {
      lowering = ScalarCallbackLowering(
        parent: previous?.expressions,
        operations: _installedValueOperations,
        valueExtension: _lowerInstalledValue,
        capture: (value) {
          final outer =
              lowering.expressions.referencesOuter(value) ||
              _slotFrames.contains(previous);
          _activeWidgetBuilder = outer ? previous : null;
          try {
            return outer && previous != null
                ? previous.captureValue(value)
                : _translate(_resolveBoundIdentifier(value), issues);
          } finally {
            _activeWidgetBuilder = previous;
          }
        },
        resolve: _resolveBoundIdentifier,
        contract: contract,
        helperFor: (call) =>
            _walk.inlined.helpers[call.methodName.element] ??
            pureBuilderHelperFor(call, call.methodName.element),
      );
      return definition != null
          ? lowering.lowerBody(definition.body, definition.parameters)
          : callback is FunctionExpression
          ? lowering.lower(callback)
          : lowering.lowerDefinition(helper!);
    } on BuilderLoweringException catch (error) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message: error.toString(),
          location: _locationOf(error.node),
        ),
      );
      return '';
    } on FormatException catch (error) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message: error.message,
          location: _locationOf(expression),
        ),
      );
      return '';
    } finally {
      _activeWidgetBuilder = previous;
    }
  }

  HelperDef? _admittedBuilderHelper(
    MethodInvocation call, {
    bool allowDynamicReturn = false,
  }) =>
      isArtifactHelperInvocation(
        call,
        admittedHelperPackages: _admittedHelperPackages,
        allowDynamicReturn: allowDynamicReturn,
      )
      ? _walk.inlined.helpers[call.methodName.element] ??
            pureBuilderHelperFor(call, call.methodName.element)
      : null;

  String _translateWidgetBuilder(
    Expression expression,
    PropertyEntry property,
    List<Issue> issues,
  ) {
    final resolved = _resolveBoundIdentifier(expression);
    final contract = property.builderContract;
    final definition = resolved is SimpleIdentifier
        ? (_walk.inlined.helpers[resolved.element] ??
              pureBuilderHelperFor(resolved, resolved.element))
        : null;
    final callback = resolved is SimpleIdentifier
        ? pureBuilderCallbackFor(resolved, resolved.element)
        : null;
    if (resolved is NullLiteral && property.constructorNullable) return 'null';
    if ((resolved is! FunctionExpression &&
            definition == null &&
            callback == null) ||
        contract == null) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message: 'A widget builder requires an analyzed pure closure.',
          location: _locationOf(expression),
        ),
      );
      return '';
    }
    final previous = _activeWidgetBuilder;
    late final WidgetBuilderLowering current;
    late final BuilderExpressionLowering values;
    values = BuilderExpressionLowering(
      operations: _installedValueOperations,
      parent: previous?.expressions,
      extension: (value, lowering) {
        if (value is SimpleIdentifier &&
            !lowering.bindings.containsKey(value.element)) {
          final resolved = _resolveBoundIdentifier(value);
          if (!identical(resolved, value)) {
            if (isNativeIntlFormatterType(value.staticType) ||
                _containsIntlFormatting(resolved)) {
              throw BuilderLoweringException(
                value,
                'A captured formatter requires a native prelude binding',
              );
            }
            return lowering.lower(resolved);
          }
        }
        if (value is MethodInvocation) {
          final helper = _admittedBuilderHelper(
            value,
            allowDynamicReturn: true,
          );
          if (helper != null) return lowering.lowerHelper(helper, value);
        }
        return _lowerInstalledValue(value, lowering);
      },
      // A value the build records is read from the app builder's own
      // recording of it.
      recorded: !contract.isAppValueSignature
          ? null
          : (value, shape) {
              if (values.referencesOuter(value)) return null;
              final undo = _checkpoint();
              final start = _hoist?.records.length ?? 0;
              _activeWidgetBuilder = null;
              final outerSlot = _recordingSlot;
              _recordingSlot = true;
              try {
                _translate(_resolveBoundIdentifier(value), <Issue>[]);
                final added = _hoist?.records.skip(start).toList() ?? [];
                final node = added.length == 1
                    ? current.recordedValue(added.single.key, shape)
                    : null;
                if (node == null) undo();
                return node;
              } finally {
                _activeWidgetBuilder = current;
                _recordingSlot = outerSlot;
              }
            },
      capture: (value) {
        // Inside an app builder's slot, its frame reads what the slot
        // records.
        final isOuter =
            values.referencesOuter(value) || _slotFrames.contains(previous);
        _activeWidgetBuilder = isOuter ? previous : null;
        try {
          return isOuter && previous != null
              ? previous.captureValue(value)
              : _translate(_resolveBoundIdentifier(value), issues);
        } finally {
          _activeWidgetBuilder = current;
        }
      },
    );
    current = WidgetBuilderLowering(
      expressions: values,
      resolve: _resolveBoundIdentifier,
      withConditionalBranch: _inConditionalBranch,
      withHelperBody: (helper, call, lower) => _inHelperBody(
        helper,
        call,
        issues,
        (_) => lower(),
        refused: const BuilderResult.nullResult(),
      ),
      nativeKey: (expression) => _nativeKeyReference(expression, issues),
      contract: contract,
      scope: 'builder${_builderScopeCounter++}',
      translateBody: (body) => _translate(body, issues),
      helperFor: _admittedBuilderHelper,
    );
    if (contract.isAppValueSignature || _slotFrames.contains(previous)) {
      _slotFrames.add(current);
    }
    _activeWidgetBuilder = current;
    try {
      return callback != null
          ? current.lowerCallbackBody(callback.body, callback.parameters)
          : definition != null
          ? current.lowerDefinition(definition)
          : current.lower(resolved as FunctionExpression);
    } on BuilderLoweringException catch (error) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message: error.toString(),
          location: _locationOf(error.node),
        ),
      );
      return '';
    } on FormatException catch (error) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message: error.message,
          location: _locationOf(expression),
        ),
      );
      return '';
    } finally {
      _activeWidgetBuilder = previous;
    }
  }

  String _translateBuilderCollection(Expression list, List<Issue> issues) {
    final previous = _activeWidgetBuilder;
    late final WidgetBuilderLowering current;
    late final BuilderExpressionLowering values;
    values = BuilderExpressionLowering(
      operations: _installedValueOperations,
      parent: previous?.expressions,
      extension: (value, lowering) {
        if (value is SimpleIdentifier &&
            !lowering.bindings.containsKey(value.element)) {
          final resolved = _resolveBoundIdentifier(value);
          if (!identical(resolved, value)) return lowering.lower(resolved);
        }
        if (value is MethodInvocation) {
          final helper = _admittedBuilderHelper(
            value,
            allowDynamicReturn: true,
          );
          if (helper != null) return lowering.lowerHelper(helper, value);
        }
        return _lowerInstalledValue(value, lowering);
      },
      capture: (value) {
        final outer =
            previous != null &&
            (values.referencesOuter(value) || _slotFrames.contains(previous));
        _activeWidgetBuilder = outer ? previous : null;
        try {
          return outer
              ? previous.captureValue(value)
              : _translate(_resolveBoundIdentifier(value), issues);
        } finally {
          _activeWidgetBuilder = current;
        }
      },
    );
    current = WidgetBuilderLowering(
      expressions: values,
      resolve: _resolveBoundIdentifier,
      withConditionalBranch: _inConditionalBranch,
      withHelperBody: (helper, call, lower) => _inHelperBody(
        helper,
        call,
        issues,
        (_) => lower(),
        refused: const BuilderResult.nullResult(),
      ),
      nativeKey: (expression) => _nativeKeyReference(expression, issues),
      contract: const WidgetBuilderContract(
        parameters: [WidgetBuilderParameter.buildContext],
      ),
      scope: 'builder${_builderScopeCounter++}',
      translateBody: (body) => _translate(body, issues),
      helperFor: _admittedBuilderHelper,
    );
    if (_slotFrames.contains(previous)) _slotFrames.add(current);
    _activeWidgetBuilder = current;
    try {
      final semantics = _collectionSemanticProbe();
      final budget = CollectionUnrollBudget();
      final result = WidgetCollectionLowering(
        expressions: values,
        resultFor: current.resultFor,
        withResolvedSpread: (source, lower) {
          final resolved = semantics.resolve(
            _resolveBoundIdentifier(source),
            const {},
            budget,
            stopAtConditionals: true,
            preserveHelpers: true,
          );
          if (resolved.workLimitExceeded || resolved.cycleDetected) {
            throw BuilderLoweringException(
              source,
              'Widget spread resolution is recursive or exceeds its work limit',
            );
          }
          return _translateWithBindings(
            resolved.expression,
            resolved.bindings,
            issues,
            (expression, _) {
              if (expression is MethodInvocation &&
                  isArtifactHelperInvocation(
                    expression,
                    admittedHelperPackages: _admittedHelperPackages,
                  )) {
                final helper =
                    _walk.inlined.helpers[expression.methodName.element] ??
                    _collectionHelpers[expression.methodName.element];
                if (helper != null) {
                  return current.withHelperResult(helper, expression, lower);
                }
              }
              return lower(expression);
            },
          );
        },
      ).lowerSource(list);
      return current.encodeResult(result, collection: true);
    } on BuilderLoweringException catch (error) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message: error.toString(),
          location: _locationOf(error.node),
        ),
      );
      return '';
    } on FormatException catch (error) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message: error.message,
          location: _locationOf(list),
        ),
      );
      return '';
    } finally {
      _activeWidgetBuilder = previous;
    }
  }

  String _translateExpression(Expression expr, List<Issue> issues) {
    final builder = _activeWidgetBuilder;
    if (builder != null && expr is MethodInvocation) {
      final type = expr.staticType;
      if (type is InterfaceType &&
          [type, ...type.allSupertypes].any(
            (type) =>
                type.element.name == 'Widget' &&
                type.element.library.identifier.startsWith('package:flutter/'),
          )) {
        final helper = _admittedBuilderHelper(expr);
        if (helper != null) return builder.translateHelper(helper, expr);
      }
    }
    if (builder != null &&
        (themeReadSegments(expr) != null ||
            _recognizeDeviceRead(expr) != null)) {
      return builder.value(
        expr,
        requireNativeBaseType: _customNativeValueBoundary,
      );
    }
    final primitive = expr.staticType;
    if (builder != null &&
        primitive != null &&
        (primitive.isDartCoreBool ||
            primitive.isDartCoreInt ||
            primitive.isDartCoreDouble ||
            primitive.isDartCoreNum ||
            primitive.isDartCoreString)) {
      try {
        if (_inSpanCollection && _walk.runtimeLoops.isNotEmpty) {
          return _spanCollectionBuilderValue(expr, issues);
        }
        return builder.value(
          expr,
          requireNativeBaseType: _customNativeValueBoundary,
        );
      } on BuilderLoweringException catch (error) {
        issues.add(
          Issue(
            code: IssueCode.propertyValueTypeMismatch,
            message: error.toString(),
            location: _locationOf(error.node),
          ),
        );
        return '';
      }
    }

    if (_activeWidgetBuilder == null &&
        expr is MethodInvocation &&
        classifyHoistType(expr.staticType) is HoistIsWidget) {
      final helper = _walk.inlined.helpers[expr.methodName.element];
      if (helper != null &&
          (helper.roots.any(_containsIntlFormatting) ||
              expr.argumentList.arguments.any(
                (a) => _containsIntlFormatting(
                  _resolveBoundIdentifier(a.argumentExpression),
                ),
              ))) {
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message:
                'A widget helper that evaluates formatting requires an installed native widget binding',
            location: _locationOf(expr),
          ),
        );
        return '';
      }
    }
    final formatting = _tryIntlFormattingValue(expr, issues);
    if (formatting != null) return formatting;
    // Parenthesis is semantically transparent — unwrap it uniformly so every
    // type-dispatch below (and at the slot/param entry points that pre-resolve
    // before dispatching) sees through it. A PARTIAL unwrap would be a new
    // asymmetry: e.g. a parenthesized conditional at a numeric slot reaching
    // the generic path instead of the per-branch-coercing slot path, emitting
    // bare ints the runtime `v<double>` decode silently nulls.
    if (expr is ParenthesizedExpression) {
      return _translate(expr.expression, issues);
    }
    final rootAccess = _rootParamAccess(expr);
    if (rootAccess != null) {
      if (!rootAccess.param.isHostData) {
        issues.add(
          rootAccess.stateful
              ? _hostDataStateShapeIssue(rootAccess.param, expr)
              : _hostDataTypeIssue(rootAccess.param, expr),
        );
        return '';
      }
      if (rootAccess.isRefused && _isDescriptorMemberSyntax(expr)) {
        issues.add(_hostDataMemberIssue(rootAccess.param, expr));
        return '';
      }
      if (rootAccess.isMember && !rootAccess.isRefused) {
        if (rootAccess.param.hasNonNullDefault) {
          issues.add(
            _hostDataDefaultIssue(
              rootAccess.param,
              expr,
              stateful: rootAccess.stateful,
            ),
          );
          return '';
        }
        return rootAccess.dsl(_rfwPathPart);
      }
    }
    final loopReference = _runtimeLoopReference(expr);
    if (loopReference != null) {
      if (loopReference.isRefused) {
        issues.add(
          Issue(
            code: IssueCode.unsupportedCollectionFlow,
            message: loopReference.indexed
                ? 'A run-time loop value cannot be read by index. Read the '
                      'value itself or one of its named members.'
                : 'A run-time loop value can only read exact stored members '
                      'from its derived host-data shape.',
            location: _locationOf(expr),
          ),
        );
        return '';
      }
      return loopReference.dsl(_rfwPathPart);
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
                  'flow back; dismiss with '
                  '`context.surfaceEvent(PaywallEvents.skip)`',
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
                    'screen. Close a standalone paywall through a callback '
                    'the app passes in, or present it via a flow.',
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

        final trigger = recogniseNavigationTrigger(
          expr,
          canonicalPaywallIdFor: canonicalPaywallIdFor,
        );
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
              modalSheet.triggerOccurrence ??= _measuredEventOccurrence;
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
    if (expr is StringInterpolation || expr is AdjacentStrings) {
      return _stringInterpolation(expr as StringLiteral, issues);
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
      return _foldedLiteral(expr.value);
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
      return _kNoValue;
    }
    if (expr is ListLiteral) {
      return _listLiteral(expr, issues);
    }
    if (expr is SetOrMapLiteral) {
      return _setOrMapLiteral(expr, issues);
    }
    if (expr is RecordLiteral) {
      return _recordLiteral(expr, issues);
    }
    if (expr is ConditionalExpression) {
      return _conditionalExpression(expr, issues);
    }
    // Rewrites coalesced custom-widget params after fallback validation.
    // Outside an inline definition, this lookup is inert.
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
    final scalerRecipe = _textScalerRecipe(expr, issues);
    if (scalerRecipe != null) return scalerRecipe;
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
        return _throughParameter(
          expr,
          boundArg,
          () => _translate(boundArg, issues),
        );
      }
      // Each placement of a const widget local is its own scope.
      if (_constPlacementStep(expr) case final step
          when step.isNotEmpty && _constReads.add(expr)) {
        _placementReads.add((read: expr, bound: null));
        try {
          return _inScope(step, () => _translate(expr, issues));
        } finally {
          _constReads.remove(expr);
          _placementReads.removeLast();
        }
      }
      // A reference to a leading `final` local binding resolves-through to its
      // initializer (element-keyed, before the name-based lowerings).
      final localInitializer = _walk.inlined.localBindings[expr.element];
      if (localInitializer != null) {
        return _throughLocal(
          expr,
          localInitializer,
          issues,
          () => _translate(localInitializer, issues),
        );
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
      // A `FormalParameterElement` is a closure's own parameter, never a field
      // or constructor arg; a same-named one must defer, not match by name.
      // In a `State.build()` a parameter, field, or handler is reachable only
      // through `widget.X`, so a bare name binds to the const and is folded.
      if (expr.element is! LocalVariableElement &&
          expr.element is! FormalParameterElement &&
          !isConstDeclarationReference(expr)) {
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
        if (_walk.rootStateContext && _currentLocalFields.contains(expr.name)) {
          return 'data.local${_rfwPathPart(expr.name)}';
        }
        final stateFields = _walk.stateFields;
        if (stateFields != null && stateFields.containsKey(expr.name)) {
          return 'state${_rfwPathPart(expr.name)}';
        }
        if (_walk.argNames[expr.name] case final argName?) {
          // A constructor-parameter reference inside a custom-widget definition
          // body — lowered to the RFW `args.` namespace. In a stateful walk,
          // the State's `build()` reaches constructor params via `widget.X`
          // instead, but `_walk.argNames` is still populated so another
          // stateless-only path stays consistent.
          return 'args${_rfwPathPart(argName)}';
        }
        // Root constructor parameters use the host-data namespace.
        final rootParam = _rootParamRead(expr);
        if (rootParam != null) {
          if (!rootParam.isHostData) {
            issues.add(_hostDataTypeIssue(rootParam, expr));
            return '';
          }
          if (rootParam.hasNonNullDefault) {
            issues.add(
              _hostDataDefaultIssue(rootParam, expr, stateful: false),
            );
            return '';
          }
          return 'data.context${_rfwPathPart(expr.name)}';
        }
      }
    }
    // A MediaQuery / Localizations / platform read lowers to `data.device.*`;
    // one outside the contract refuses rather than falling through.
    final deviceRead = _recognizeDeviceRead(expr);
    if (deviceRead != null) return _deviceRead(deviceRead, expr, issues);
    if (expr is InstanceCreationExpression) {
      return _instanceCreation(expr, issues);
    }
    if (expr is MethodInvocation) {
      return _methodInvocation(expr, issues);
    }
    if (expr is CascadeExpression) {
      return _normalizePresentDsl(
        issues,
        () => _structured.cascadeExpression(expr, issues),
      );
    }
    if (expr is PropertyAccess) {
      final frameworkConst = _frameworkConstValue(expr);
      if (frameworkConst?.kind == FrameworkConstKind.systemUiOverlayStyle) {
        return frameworkConst!.dsl;
      }
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
    // Runtime name bindings take precedence over const declarations.
    if (isConstDeclarationReference(expr)) {
      final translated = _translateConstIdentifier(
        expr,
        issues,
        IssueCode.unrecognizedMethodCall,
        (initializer) => _translate(initializer, issues),
      );
      if (translated != null) return translated;
      final reservedOwner = _constNamespaceLookalikeOwner(expr);
      if (reservedOwner != null) {
        issues.add(
          _frameworkNamespaceReservedIssue(
            expr,
            reservedOwner,
            IssueCode.unrecognizedMethodCall,
          ),
        );
        return '';
      }
      issues.add(
        _constIdentifierUnresolvedIssue(
          expr,
          IssueCode.unrecognizedMethodCall,
          capabilityGapSubject: 'expression:${_nodeKind(expr)}',
        ),
      );
      return '';
    }
    // Same code as the general refusal, so a split still binds the closure.
    if (generatorCallback(expr) case final generator?) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message:
              "Restage can't translate "
              '`${readableSource(expr.toSource())}` (${_locationOf(expr)}): '
              '${generator.problem(null)}. Try ${generator.fix(null)}.',
          location: _declarationOf(expr),
        ),
      );
      return '';
    }
    issues.add(
      _appOnlyValueIssue(expr, IssueCode.unrecognizedMethodCall) ??
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            capabilityGapSubject: 'expression:${_nodeKind(expr)}',
            message:
                "Restage can't translate "
                '`${readableSource(expr.toSource())}` (${_locationOf(expr)}). '
                "Try computing the value in the screen's build method and "
                'passing it in.',
            // The message names its place, so the issue names the declaration.
            location: _declarationOf(expr),
          ),
    );
    return '';
  }

  /// A same-file const initializer that requires structured translation.
  Expression? _constIdentifierInitializer(Expression expr) {
    if (expr is! SimpleIdentifier && expr is! PrefixedIdentifier) return null;
    if (tryFoldConstant(expr) != null) return null;
    if (_constNamespaceLookalikeOwner(expr) != null) return null;
    return resolveConstIdentifierInitializer(expr);
  }

  /// Translates one reachable const initializer with shared cycle protection.
  String? _translateConstIdentifier(
    Expression expr,
    List<Issue> issues,
    IssueCode cycleCode,
    String Function(Expression) translateInitializer,
  ) {
    final initializer = _constIdentifierInitializer(expr);
    if (initializer == null) return null;
    final declaration = constDeclarationElement(expr);
    if (declaration == null) return null;
    if (!_constDeclarationsInFlight.add(declaration)) {
      issues.add(_constIdentifierCycleIssue(expr, cycleCode));
      return '';
    }
    try {
      return _inDeclarationScope(() => translateInitializer(initializer));
    } finally {
      _constDeclarationsInFlight.remove(declaration);
    }
  }

  /// Runs [body] with declaration-owned names isolated from use-site bindings.
  T _inDeclarationScope<T>(T Function() body) {
    final saved = _walk;
    _walk = _walk.copyWith(
      argNames: const {},
      stateFields: null,
      eventHandlers: const {},
      rootStateContext: false,
      params: const {},
      classKey: null,
      validatedCoalesceParams: <String>{},
      modalSheet: null,
      modalSheetCloseFlag: null,
    );
    try {
      return body();
    } finally {
      _walk = saved;
    }
  }

  /// The reserved owner name for an application-defined class constant.
  String? _constNamespaceLookalikeOwner(Expression expr) =>
      frameworkConstNamespaceLookalikeOwner(
        expr,
        isFrameworkLibrary: _frameworkOrUnresolved,
      );

  /// Whether [expr] resolves through an active runtime name binding. Decided
  /// by the resolved element: a const declaration a name happens to shadow is
  /// bound to the constant by Dart, so it takes the const path instead.
  bool _isNameBoundIdentifier(Expression expr) {
    if (expr is! SimpleIdentifier) return false;
    if (expr.element is LocalVariableElement) return false;
    if (isConstDeclarationReference(expr)) return false;
    return _walk.eventHandlers.containsKey(expr.name) ||
        (_walk.stateFields?.containsKey(expr.name) ?? false) ||
        _walk.argNames.containsKey(expr.name);
  }

  /// Creates the diagnostic for an application-defined reserved namespace.
  Issue _frameworkNamespaceReservedIssue(
    Expression expr,
    String owner,
    IssueCode code,
  ) => Issue(
    code: code,
    message:
        "'$owner' is the name of a framework value type, so "
        "'${expr.toSource()}' is not lowered to this class's own value. "
        'Rename the class, or inline the value at the use site.',
    location: _locationOf(expr),
  );

  Issue _constIdentifierCycleIssue(Expression expr, IssueCode code) => Issue(
    code: code,
    capabilityGapSubject: 'constDeclarationCycle',
    message:
        "The const declaration '${expr.toSource()}' is cyclic and "
        'cannot be lowered. Break the declaration cycle.',
    location: _locationOf(expr),
  );

  /// Creates the diagnostic for an unsupported cross-file const reference.
  Issue _constIdentifierUnresolvedIssue(
    Expression expr,
    IssueCode code, {
    String? capabilityGapSubject,
  }) => Issue(
    code: code,
    capabilityGapSubject: capabilityGapSubject,
    message:
        "Cannot fold the const reference '${expr.toSource()}' to a "
        'value: it is declared in another file and is not a scalar this '
        'codegen can evaluate. Inline the value at the use site, or move '
        'the const into the same file.',
    location: _locationOf(expr),
  );

  /// Renders a folded constant — an [int], [double], [bool], or [String] —
  /// as an RFW DSL literal fragment.
  String _foldedLiteral(Object value) {
    if (value is String) return _stringLiteral(value);
    if (value is num) return rfwNumberLiteral(value);
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
    message:
        'Cannot fold the const-object field reference '
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

  String _rfwMapKey(String name) =>
      isRfwIdentifier(name) ? name : _stringLiteral(name);

  String _rfwPathPart(String name) => '.${_rfwMapKey(name)}';

  /// Shared refusal text for stateless and stateful host-data reads.
  String _hostDataRefusal(String subject, RootContextParam param) {
    final problem = param.hostDataProblem;
    final reason = problem == null
        ? ''
        : " At '${problem.path}': ${problem.detail}.";
    return 'Cannot read $subject: it is declared '
        "'${param.type.getDisplayString()}', and Restage does "
        'not support that type as host data. Host data parameters must be a '
        'scalar (bool, int, double, num, String), Object?, a List of '
        'non-nullable host-data values, or a Map<String, …> whose values are '
        'host data, optionally nullable, or a plain const data class.$reason';
  }

  String _hostDataDefaultRefusal(String subject, RootContextParam param) =>
      'Cannot read $subject as host data: omitting the value would select its '
      'Dart default `${param.defaultValueCode}`, which the emitted surface '
      'cannot apply. Make the parameter required or remove its non-null '
      'default.';

  /// Rejects a non-host-data parameter read in a stateless root.
  Issue _hostDataTypeIssue(RootContextParam param, AstNode node) => Issue(
    code: IssueCode.unrecognizedMethodCall,
    capabilityGapSubject: 'hostDataType:${param.type.getDisplayString()}',
    message: _hostDataRefusal("the parameter '${param.name}'", param),
    location: _locationOf(node),
  );

  /// Rejects the same read through a stateful root's widget.
  Issue _hostDataStateShapeIssue(RootContextParam param, AstNode node) => Issue(
    code: IssueCode.stateShapeUnsupported,
    message: _hostDataRefusal('widget.${param.name}', param),
    location: _locationOf(node),
  );

  Issue _hostDataMemberIssue(RootContextParam param, Expression node) => Issue(
    code: IssueCode.unrecognizedMethodCall,
    message:
        "Cannot read '${node.toSource()}': Restage does not support "
        "reading a member of the host data parameter '${param.name}'. "
        'Supply the value itself, or declare a separate parameter for it.',
    location: _locationOf(node),
  );

  Issue _hostDataDefaultIssue(
    RootContextParam param,
    AstNode node, {
    required bool stateful,
  }) => Issue(
    code: stateful
        ? IssueCode.stateShapeUnsupported
        : IssueCode.unrecognizedMethodCall,
    capabilityGapSubject: stateful ? null : 'hostDataDefault:${param.name}',
    message: _hostDataDefaultRefusal(
      stateful ? 'widget.${param.name}' : "the parameter '${param.name}'",
      param,
    ),
    location: _locationOf(node),
  );

  /// Returns the root field identity at the base of [source], if any.
  _RootParamAccess? _rootParamAccess(Expression source) {
    final expr = _stripParens(source);
    if (expr is SimpleIdentifier && !_walk.rootStateContext) {
      final param = _rootParamForElement(expr.element);
      return param == null
          ? null
          : _RootParamAccess.root(param: param, stateful: false);
    }
    if (expr is PrefixedIdentifier) {
      if (_isInheritedStateWidgetReceiver(expr.prefix) &&
          _walk.rootStateContext) {
        final param = _rootParamForElement(identifierElement(expr.identifier));
        if (param != null) {
          return _RootParamAccess.root(param: param, stateful: true);
        }
      }
      final base = _rootParamAccess(expr.prefix);
      return base?.append(identifierElement(expr.identifier));
    }
    if (expr is PropertyAccess) {
      final target = expr.target;
      if (target is ThisExpression && !_walk.rootStateContext) {
        final param = _rootParamForElement(
          identifierElement(expr.propertyName),
        );
        return param == null
            ? null
            : _RootParamAccess.root(param: param, stateful: false);
      }
      if (target != null) {
        return _rootParamAccess(
          target,
        )?.append(identifierElement(expr.propertyName));
      }
    }
    if (expr is MethodInvocation) {
      final target = expr.target;
      if (target != null) return _rootParamAccess(target)?.refuse();
    }
    if (expr is IndexExpression) {
      final target = expr.target;
      if (target != null) return _rootParamAccess(target)?.refuse();
    }
    if (expr is CascadeExpression) {
      return _rootParamAccess(expr.target)?.refuse();
    }
    return null;
  }

  /// Returns an exact, unextended root parameter read.
  RootContextParam? _rootParamRead(Expression expr) {
    final access = _rootParamAccess(expr);
    return access == null || access.isMember ? null : access.param;
  }

  bool _isDescriptorMemberSyntax(Expression source) {
    final expr = _stripParens(source);
    return expr is PrefixedIdentifier ||
        expr is PropertyAccess ||
        expr is IndexExpression;
  }

  bool _isInheritedStateWidgetReceiver(SimpleIdentifier receiver) =>
      _isStateWidgetGetter(receiver.element);

  bool _isStateWidgetGetter(Element? element) {
    if (element is! GetterElement || element.name != 'widget') return false;
    final base = element.baseElement;
    return base.enclosingElement is ClassElement &&
        base.enclosingElement.name == 'State' &&
        _isFrameworkValueType(base);
  }

  RootContextParam? _rootParamForElement(Element? element) {
    final field = _unwrapPropertyAccessor(element);
    if (field is! FieldElement || field.isStatic) return null;
    for (final param in _walk.rootParams.values) {
      final rootField = param.field;
      if (rootField != null &&
          identical(rootField.baseElement, field.baseElement)) {
        return param;
      }
    }
    return null;
  }

  /// A string interpolation outside a String slot: one value, or refused,
  /// since only a String slot's decoder joins parts.
  String _stringInterpolation(StringLiteral expr, List<Issue> issues) {
    final parts = _interpolationParts(expr, issues);
    if (parts == null) return '';
    if (parts.isEmpty) return '""';
    if (parts.length == 1) return parts.single;
    issues.add(
      Issue(
        code: IssueCode.unsupportedInterpolation,
        message:
            'A string that joins text and values works as the text of '
            'a Text and as a String property of a built-in widget or of a '
            'custom widget your app renders. Here, pass the finished string '
            'in as one value. Found: ${expr.toSource()}.',
        location: _locationOf(expr),
      ),
    );
    return '';
  }

  /// The parts of [expr] as DSL values: quoted literals and references in
  /// order, or `null` after a diagnostic. Adjacent strings join as in Dart.
  List<String>? _interpolationParts(StringLiteral expr, List<Issue> issues) {
    final issueStart = issues.length;
    final parts = <String>[];
    final text = StringBuffer();
    void flushText() {
      if (text.isEmpty) return;
      parts.add('"${_escapeForDsl(text.toString())}"');
      text.clear();
    }

    void collect(StringLiteral literal) {
      switch (literal) {
        case SimpleStringLiteral(:final value):
          text.write(value);
        case AdjacentStrings(:final strings):
          strings.forEach(collect);
        case StringInterpolation(:final elements):
          for (final element in elements) {
            if (element is InterpolationString) {
              text.write(element.value);
            } else if (element is InterpolationExpression) {
              flushText();
              final dsl = _stringInterpolationExpression(
                element.expression,
                issues,
              );
              if (dsl != null) parts.add(dsl);
            }
          }
      }
    }

    collect(expr);
    flushText();
    final refused = issues
        .skip(issueStart)
        .any((issue) => !issue.code.isBuildNotice);
    return refused ? null : parts;
  }

  /// Whether Text's [text] needs inline spans: an interpolation of several
  /// parts, directly or in any arm of a conditional.
  bool _needsTextSpans(Expression text) {
    if (_activeWidgetBuilder != null) return false;
    final value = _resolveBoundIdentifier(text);
    if (_containsIntlFormatting(value)) return false;
    if (value is MethodInvocation) {
      final helper = _walk.inlined.helpers[value.methodName.element];
      if (helper == null) return false;
      return _inHelperBody(
        helper,
        value,
        <Issue>[],
        _needsTextSpans,
        refused: false,
      );
    }
    if (value is ConditionalExpression) {
      return _needsTextSpans(value.thenExpression) ||
          _needsTextSpans(value.elseExpression);
    }
    if (!isInterpolatedString(value)) return false;
    var parts = 0;
    var inText = false;
    void count(StringLiteral literal) {
      switch (literal) {
        case SimpleStringLiteral(:final value):
          if (value.isNotEmpty && !inText) parts++;
          inText |= value.isNotEmpty;
        case AdjacentStrings(:final strings):
          strings.forEach(count);
        case StringInterpolation(:final elements):
          for (final element in elements) {
            if (element is InterpolationExpression) {
              parts++;
              inText = false;
            } else if (element is InterpolationString &&
                element.value.isNotEmpty) {
              if (!inText) parts++;
              inText = true;
            }
          }
      }
    }

    count(value as StringLiteral);
    return parts > 1;
  }

  /// Lowers Text's [text] to an inline span value; a conditional selects a
  /// span per arm.
  String _textSpanValue(Expression text, List<Issue> issues) {
    final value = _resolveBoundIdentifier(text);
    final helper = value is MethodInvocation
        ? _walk.inlined.helpers[value.methodName.element]
        : null;
    if (helper != null) {
      return _inHelperBody(
        helper,
        value as MethodInvocation,
        issues,
        (body) => _textSpanValue(body, issues),
        refused: '',
      );
    }
    if (value is ConditionalExpression) {
      return _conditionalSwitch(
        value,
        issues,
        (arm) => _textSpanValue(arm, issues),
      );
    }
    if (isInterpolatedString(value)) {
      String spans(List<Issue> into) {
        final parts = _interpolationParts(value as StringLiteral, into);
        if (parts == null) return '';
        if (parts.length == 1) return '{ text: ${parts.single} }';
        return '{ children: [${parts.map((p) => '{ text: $p }').join(', ')}] }';
      }

      // Parts the payload cannot read make the whole text a value.
      final read = _hoisted(value, issues, spans);
      if (read == null) return spans(issues);
      return read.isEmpty || read.startsWith('{') ? read : '{ text: $read }';
    }
    final before = issues.length;
    final plain = _translateSlotValue(text, PropertyType.string, issues);
    if (_diagnosedEmpty(plain, issues, before)) return '';
    return '{ text: $plain }';
  }

  /// Whether [value] for a widget's own String [property] joins text and
  /// values; that property's decoder joins a list of parts.
  bool _joinsStringParts(PropertyEntry property, Expression value) =>
      property.type == PropertyType.string &&
      property.synthetic == null &&
      _needsTextSpans(value);

  /// Lowers a String slot's value that joins text and values to a list of
  /// parts, which the slot's decoder joins; a conditional selects per arm.
  String _joinedStringValue(Expression text, List<Issue> issues) {
    final hoisted = _hoisted(
      text,
      issues,
      (scratch) => _joinedStringValueUnhoisted(text, scratch),
    );
    return hoisted ?? _joinedStringValueUnhoisted(text, issues);
  }

  String _joinedStringValueUnhoisted(Expression text, List<Issue> issues) {
    final value = _resolveBoundIdentifier(text);
    final helper = value is MethodInvocation
        ? _walk.inlined.helpers[value.methodName.element]
        : null;
    if (helper != null) {
      return _inHelperBody(
        helper,
        value as MethodInvocation,
        issues,
        (body) => _joinedStringValue(body, issues),
        refused: '',
      );
    }
    if (value is ConditionalExpression) {
      return _conditionalSwitch(
        value,
        issues,
        (arm) => _needsTextSpans(arm)
            ? _joinedStringValue(arm, issues)
            : _translateSlotValue(arm, PropertyType.string, issues),
      );
    }
    if (isInterpolatedString(value)) {
      final parts = _interpolationParts(value as StringLiteral, issues);
      if (parts == null) return '';
      return parts.length == 1 ? parts.single : '[${parts.join(', ')}]';
    }
    return _translateSlotValue(text, PropertyType.string, issues);
  }

  String _escapeForDsl(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n');

  String? _stringInterpolationExpression(
    Expression inner,
    List<Issue> issues,
  ) {
    if (inner is MethodInvocation && isUnsupportedCommerceHelperCall(inner)) {
      issues.add(unsupportedCommerceHelperIssue(inner, _locationOf(inner)));
      return null;
    }
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
            message:
                'Could not resolve the interpolated expression '
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
            message:
                'Only helpers that return a String value may appear '
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
        return 'state${_rfwPathPart(resolved.name)}';
      }
    }
    final rootAccess = _rootParamAccess(resolved);
    // A read the payload cannot carry is computed in the mount on its own,
    // so the copy around it stays delivered.
    if (rootAccess != null &&
        (!rootAccess.param.isHostData || rootAccess.isRefused)) {
      final hoisted = _hoisted(
        inner,
        issues,
        (scratch) => _translateSlotValue(inner, PropertyType.string, scratch),
      );
      if (hoisted != null) return hoisted;
    }
    if (rootAccess != null) {
      if (!rootAccess.param.isHostData) {
        issues.add(
          rootAccess.stateful
              ? _hostDataStateShapeIssue(rootAccess.param, inner)
              : _hostDataTypeIssue(rootAccess.param, inner),
        );
        return null;
      }
      if (rootAccess.isRefused && _isDescriptorMemberSyntax(resolved)) {
        issues.add(_hostDataMemberIssue(rootAccess.param, inner));
        return null;
      }
    }
    // A String-typed host data parameter interpolates as a `data.context`
    // reference; other types would stringify differently at render time.
    final rootShape = rootAccess?.shape;
    if (rootAccess != null && rootShape != null) {
      if (rootAccess.param.hasNonNullDefault) {
        issues.add(
          _hostDataDefaultIssue(
            rootAccess.param,
            inner,
            stateful: _walk.rootStateContext,
          ),
        );
        return null;
      }
    }
    final reference = _shapedReference(resolved);
    if (reference case (
      :final dsl,
      shape: HostDataScalarShape(
        kind: HostDataScalarKind.string,
        :final type,
      ),
    ) when type.nullabilitySuffix == NullabilitySuffix.none) {
      return dsl;
    }

    // Any other non-null String the surface can read: a build() local, a
    // condition, a widget argument.
    final type = inner.staticType;
    if (type != null &&
        type.isDartCoreString &&
        type.nullabilitySuffix == NullabilitySuffix.none) {
      final before = issues.length;
      final value = _translateSlotValue(inner, PropertyType.string, issues);
      if (_diagnosedEmpty(value, issues, before)) return null;
      if (value.isNotEmpty) return value;
    }

    issues.add(
      Issue(
        code: IssueCode.unsupportedInterpolation,
        message:
            "Restage can't translate `${readableSource(inner.toSource())}` "
            '(${_locationOf(inner)}) inside a string. Try interpolating a '
            "`String` from the screen's constructor, a field of its `State`, "
            'or a local variable in `build`.',
        location: _locationOf(inner),
      ),
    );
    return null;
  }

  String _listLiteral(
    ListLiteral expr,
    List<Issue> issues, {
    PropertyType? itemType,
    String? Function(CollectionSemanticOccurrence, int)? emitLeaf,
    CollectionUnrollBudget? budget,
  }) {
    final parts = <String>[];
    final ordinals = MeasurementCollectionOrdinals();
    final traversal = traverseCollectionList(
      expr,
      semantics: _collectionSemanticProbe(),
      session: _collectionSession,
      budget: budget,
    );
    final outer = _walk;
    _StateShift? shift;
    for (final entry in traversal.entries) {
      final ordinal = ordinals.next(entry);
      // Each element sits at its own slot, after whatever moves it.
      _walk = outer
          .armStep('[$ordinal]')
          .copyWith(stateShift: shift ?? outer.stateShift);
      shift ??= _countShift(entry);
      switch (entry) {
        case CollectionListElement(:final occurrence):
          parts.add(
            _translateOccurrence(
              occurrence,
              issues,
              itemType: itemType,
              emitLeaf: emitLeaf,
              ordinal: ordinal,
              measurementScope: _walk.measurementWidgetList?.element(
                ordinal,
                collectionOccurrence: occurrence,
              ),
            ),
          );
        case CollectionListRefusal(:final refusal):
          final runtimeIf = refusal.runtimeIf;
          if (runtimeIf != null) {
            final emitted = _emitRuntimeIf(
              runtimeIf,
              refusal,
              issues,
              ordinal: ordinal,
              itemType: itemType,
              emitLeaf: emitLeaf,
            );
            if (emitted != null) parts.add(emitted);
            continue;
          }
          final runtimeLoop = refusal.runtimeLoop;
          if (runtimeLoop == null) {
            _recordCollectionRefusal(refusal, issues);
            continue;
          }
          final emitted = _emitRuntimeLoop(
            runtimeLoop,
            refusal,
            issues,
            itemType: itemType,
            emitLeaf: emitLeaf,
            ordinal: ordinal,
          );
          if (emitted != null) parts.add(emitted);
      }
    }
    _walk = outer;
    return '[${parts.join(', ')}]';
  }

  // The shift [entry] causes when its emitted number of widgets can change:
  // a run-time loop, or a run-time condition whose branches differ in count.
  _StateShift? _countShift(CollectionListTraversalEntry entry) {
    if (entry is! CollectionListRefusal) return null;
    final refusal = entry.refusal;
    final at = refusal.location;
    if (refusal.runtimeLoop != null) {
      return _StateShift(at, at is SpreadElement ? 'spread' : 'loop');
    }
    if (refusal.runtimeIf case final candidate?
        when _branchCount(CollectionRuntimeConditional(candidate)) == null) {
      return _StateShift(at, 'condition');
    }
    return null;
  }

  // How many widgets [branch] always emits; null when it varies.
  int? _branchCount(CollectionRuntimeBranch branch) => switch (branch) {
    CollectionRuntimeLeaf() => 1,
    CollectionRuntimeIteration() => null,
    CollectionRuntimeGroup(:final members) => members.fold<int?>(
      0,
      (sum, member) => switch ((sum, _branchCount(member))) {
        (final a?, final b?) => a + b,
        _ => null,
      },
    ),
    CollectionRuntimeConditional(:final candidate) => switch ((
      _branchCount(candidate.thenBranch),
      candidate.elseBranch == null ? 0 : _branchCount(candidate.elseBranch!),
    )) {
      (final a?, final b?) when a == b => a,
      _ => null,
    },
  };

  /// Lowers a run-time collection-`if` to the elements it contributes.
  String? _emitRuntimeIf(
    CollectionRuntimeIfCandidate candidate,
    CollectionUnrollRefused refusal,
    List<Issue> issues, {
    required int ordinal,
    PropertyType? itemType,
    String? Function(CollectionSemanticOccurrence, int)? emitLeaf,
  }) {
    final before = issues.length;
    final emitted = _emitRuntimeIfCandidate(
      candidate,
      issues,
      ordinal: ordinal,
      itemType: itemType,
      emitLeaf: emitLeaf,
    );
    if (emitted == null) {
      if (issues.length == before) _recordCollectionRefusal(refusal, issues);
      return null;
    }
    return emitted;
  }

  String? _emitRuntimeIfCandidate(
    CollectionRuntimeIfCandidate candidate,
    List<Issue> issues, {
    required int ordinal,
    PropertyType? itemType,
    String? Function(CollectionSemanticOccurrence, int)? emitLeaf,
  }) {
    // Guarded loops omit absent elements and keep each callback in one
    // emitted branch when composed conditions repeat their selector text.
    if (_runtimeIfHasSingleEmission(candidate)) {
      return _emitTotalRuntimeIf(
        candidate,
        issues,
        ordinal: ordinal,
        itemType: itemType,
        emitLeaf: emitLeaf,
      );
    }
    final elements = <String>[];
    final refused = _emitGuardedLeaves(
      candidate,
      const _ConditionLowering(_unguarded),
      elements,
      issues,
      ordinal: ordinal,
      itemType: itemType,
      emitLeaf: emitLeaf,
    );
    if (refused) return null;
    return elements.join(', ');
  }

  /// Emits one guarded loop per leaf, composing [guard] with each condition
  /// along the path. True when a part refused.
  bool _emitGuardedLeaves(
    CollectionRuntimeIfCandidate candidate,
    _ConditionLowering guard,
    List<String> elements,
    List<Issue> issues, {
    required int ordinal,
    PropertyType? itemType,
    String? Function(CollectionSemanticOccurrence, int)? emitLeaf,
  }) {
    final conditionIssues = <Issue>[];
    final lowering = _withTranslationBindings(
      candidate.bindings,
      () => _lowerCondition(candidate.condition, conditionIssues),
    );
    if (lowering == null) return true;
    issues.addAll(conditionIssues);
    final thenGuard = _ConditionLowering(
      (present, absent) => guard(lowering(present, absent), absent),
    );
    if (_copiedUnder(
      candidate.condition,
      _copiesBranch(thenGuard, then: true),
      () => _emitGuardedBranch(
        candidate.thenBranch,
        thenGuard,
        elements,
        issues,
        ordinal: ordinal,
        itemType: itemType,
        emitLeaf: emitLeaf,
      ),
    )) {
      return true;
    }
    final otherwise = candidate.elseBranch;
    if (otherwise == null) return false;
    final elseGuard = _ConditionLowering(
      (present, absent) => guard(lowering(absent, present), absent),
    );
    return _copiedUnder(
      candidate.condition,
      _copiesBranch(elseGuard, then: true),
      () => _emitGuardedBranch(
        otherwise,
        elseGuard,
        elements,
        issues,
        ordinal: ordinal,
        itemType: itemType,
        emitLeaf: emitLeaf,
      ),
    );
  }

  bool _emitGuardedBranch(
    CollectionRuntimeBranch branch,
    _ConditionLowering guard,
    List<String> elements,
    List<Issue> issues, {
    required int ordinal,
    PropertyType? itemType,
    String? Function(CollectionSemanticOccurrence, int)? emitLeaf,
  }) {
    switch (branch) {
      case CollectionRuntimeConditional(:final candidate):
        return _emitGuardedLeaves(
          candidate,
          guard,
          elements,
          issues,
          ordinal: ordinal,
          itemType: itemType,
          emitLeaf: emitLeaf,
        );
      case CollectionRuntimeIteration(:final candidate, :final refusal):
        if (itemType != PropertyType.widget &&
            itemType != PropertyType.inlineSpan) {
          _recordCollectionRefusal(refusal, issues);
          return true;
        }
        final loop = _emitRuntimeLoop(
          candidate,
          refusal,
          issues,
          ordinal: ordinal,
          itemType: itemType,
          emitLeaf: emitLeaf,
        );
        if (loop == null) return true;
        elements.add(
          '...for ${_absentLoopIdentifier()} in '
          '${guard(_kPresentSelector, _kAbsentSelector)}: [$loop]',
        );
        return false;
      case CollectionRuntimeGroup(:final members):
        for (final member in members) {
          if (_emitGuardedBranch(
            member,
            guard,
            elements,
            issues,
            ordinal: ordinal,
            itemType: itemType,
            emitLeaf: emitLeaf,
          )) {
            return true;
          }
        }
        return false;
      case CollectionRuntimeLeaf():
        final dsl = _emitRuntimeIfBranch(
          branch,
          issues,
          ordinal: ordinal,
          itemType: itemType,
          emitLeaf: emitLeaf,
        );
        if (dsl == null) return true;
        elements.add(
          '...for ${_absentLoopIdentifier()} in '
          '${guard(_kPresentSelector, _kAbsentSelector)}: $dsl',
        );
        return false;
    }
  }

  String? _emitTotalRuntimeIf(
    CollectionRuntimeIfCandidate candidate,
    List<Issue> issues, {
    required int ordinal,
    PropertyType? itemType,
    String? Function(CollectionSemanticOccurrence, int)? emitLeaf,
  }) => _armChecked(
    issues,
    () => _emitTotalRuntimeIfArms(
      candidate,
      issues,
      ordinal: ordinal,
      itemType: itemType,
      emitLeaf: emitLeaf,
    ),
  );

  String? _emitTotalRuntimeIfArms(
    CollectionRuntimeIfCandidate candidate,
    List<Issue> issues, {
    required int ordinal,
    PropertyType? itemType,
    String? Function(CollectionSemanticOccurrence, int)? emitLeaf,
  }) {
    final conditionIssues = <Issue>[];
    final lowering = _withTranslationBindings(
      candidate.bindings,
      () => _lowerCondition(candidate.condition, conditionIssues),
    );
    if (lowering == null) return null;
    issues.addAll(conditionIssues);
    final thenDsl = _inArm(
      candidate.condition,
      0,
      () => _copiedUnder(
        candidate.condition,
        _copiesBranch(lowering, then: true),
        () => _emitRuntimeIfBranch(
          candidate.thenBranch,
          issues,
          ordinal: ordinal,
          itemType: itemType,
          emitLeaf: emitLeaf,
        ),
      ),
    );
    if (thenDsl == null) return null;
    final elseDsl = _inArm(
      candidate.condition,
      1,
      () => _copiedUnder(
        candidate.condition,
        _copiesBranch(lowering, then: false),
        () => _emitRuntimeIfBranch(
          candidate.elseBranch!,
          issues,
          ordinal: ordinal,
          itemType: itemType,
          emitLeaf: emitLeaf,
        ),
      ),
    );
    if (elseDsl == null) return null;
    return lowering(thenDsl, elseDsl);
  }

  /// Whether a switch can select one element without copying a branch.
  bool _runtimeIfHasSingleEmission(CollectionRuntimeIfCandidate candidate) {
    return _withTranslationBindings(candidate.bindings, () {
      final otherwise = candidate.elseBranch;
      return otherwise != null &&
          !_conditionCopiesBranch(candidate.condition) &&
          _branchHasSingleEmission(candidate.thenBranch) &&
          _branchHasSingleEmission(otherwise);
    });
  }

  bool _conditionCopiesBranch(Expression expression) {
    final condition = _resolveBoundIdentifier(expression);
    return switch (condition) {
      PrefixExpression(:final operator, :final operand)
          when operator.lexeme == '!' =>
        _conditionCopiesBranch(operand),
      BinaryExpression(:final operator) =>
        operator.lexeme == '&&' || operator.lexeme == '||',
      _ => false,
    };
  }

  bool _branchHasSingleEmission(CollectionRuntimeBranch branch) =>
      switch (branch) {
        CollectionRuntimeLeaf() => true,
        // A spread yields its own element count, so it is guarded per element.
        CollectionRuntimeGroup() || CollectionRuntimeIteration() => false,
        CollectionRuntimeConditional(:final candidate) =>
          _runtimeIfHasSingleEmission(candidate),
      };

  String? _emitRuntimeIfBranch(
    CollectionRuntimeBranch branch,
    List<Issue> issues, {
    required int ordinal,
    PropertyType? itemType,
    String? Function(CollectionSemanticOccurrence, int)? emitLeaf,
  }) {
    switch (branch) {
      case CollectionRuntimeConditional(:final candidate):
        return _emitRuntimeIfCandidate(
          candidate,
          issues,
          ordinal: ordinal,
          itemType: itemType,
          emitLeaf: emitLeaf,
        );
      case CollectionRuntimeLeaf(:final occurrence):
        final before = issues.length;
        final dsl = _translateOccurrence(
          occurrence,
          issues,
          itemType: itemType,
          emitLeaf: emitLeaf,
          ordinal: ordinal,
          measurementScope: _walk.measurementWidgetList?.element(
            ordinal,
            collectionOccurrence: occurrence,
          ),
        );
        if (dsl.isEmpty || issues.length != before) return null;
        return dsl;
      case CollectionRuntimeGroup() || CollectionRuntimeIteration():
        throw StateError('A spread branch is emitted as guarded elements');
    }
  }

  /// A loop name no authored loop in scope shadows.
  String _absentLoopIdentifier() {
    final taken = {
      for (final loop in _walk.runtimeLoops) loop.identifier,
      ..._kRfwLoopReservedWords,
    };
    var name = _kAbsentLoopIdentifier;
    var suffix = 0;
    while (taken.contains(name)) {
      name = '$_kAbsentLoopIdentifier${++suffix}';
    }
    return name;
  }

  String? _emitRuntimeLoop(
    CollectionRuntimeLoopCandidate candidate,
    CollectionUnrollRefused refusal,
    List<Issue> issues, {
    required int ordinal,
    PropertyType? itemType,
    String? Function(CollectionSemanticOccurrence, int)? emitLeaf,
  }) {
    // The loop is translated through the helper calls its spread crossed,
    // so the copy records it inside them.
    String? emitted;
    _throughLocals(candidate.spreadProvenance, 0, issues, () {
      emitted = _withTranslationBindings(
        candidate.bindings,
        () => _emitBoundRuntimeLoop(
          candidate,
          refusal,
          issues,
          ordinal: ordinal,
          itemType: itemType,
          emitLeaf: emitLeaf,
        ),
      );
      return emitted ?? '';
    });
    return emitted;
  }

  String? _emitBoundRuntimeLoop(
    CollectionRuntimeLoopCandidate candidate,
    CollectionUnrollRefused refusal,
    List<Issue> issues, {
    required int ordinal,
    PropertyType? itemType,
    String? Function(CollectionSemanticOccurrence, int)? emitLeaf,
  }) {
    String? emit(List<Issue> sink, {required bool inMount}) => _emitLoopOver(
      candidate,
      refusal,
      sink,
      ordinal: ordinal,
      itemType: itemType,
      emitLeaf: emitLeaf,
      inMount: inMount,
    );
    final restore = _checkpoint();
    final direct = <Issue>[];
    final dsl = emit(direct, inMount: false);
    if (dsl != null || _islands == null || _hoist!.speculating) {
      issues.addAll(direct);
      return dsl;
    }
    // A body that needs its item in the mount walks a list the mount
    // publishes.
    restore();
    final published = <Issue>[];
    if (_itemsInMount(candidate, any: true) != null) {
      final again = emit(published, inMount: true);
      if (again != null) {
        issues.addAll(published);
        return again;
      }
    }
    restore();
    issues.addAll(direct);
    return null;
  }

  String? _emitLoopOver(
    CollectionRuntimeLoopCandidate candidate,
    CollectionUnrollRefused refusal,
    List<Issue> issues, {
    required int ordinal,
    required bool inMount,
    PropertyType? itemType,
    String? Function(CollectionSemanticOccurrence, int)? emitLeaf,
  }) {
    final identifier = candidate.pattern == null
        ? candidate.identifier
        : _absentLoopIdentifier();
    if (!isRfwIdentifier(identifier) ||
        _kRfwLoopReservedWords.contains(identifier)) {
      issues.add(
        Issue(
          code: IssueCode.unsupportedCollectionFlow,
          message:
              "The collection-for name '$identifier' cannot be used in "
              'an RFW loop. Choose a non-reserved name containing only '
              'letters, digits, and underscores.',
          location: _locationOf(refusal.location),
        ),
      );
      return null;
    }
    final input = _runtimeLoopInput(
      candidate,
      refusal,
      issues,
      inMount: inMount,
    );
    if (input == null) return null;

    final before = issues.length;
    final saved = _walk;
    _walk = _walk.copyWith(
      runtimeLoops: [
        ..._walk.runtimeLoops,
        _RuntimeLoopBinding(
          candidate.binding,
          identifier,
          input.elementShape,
          root: input.root,
          items: input.items,
          elements: candidate.patternVariables,
        ),
      ],
    );
    String? template;
    try {
      if (_branchHasSingleEmission(candidate.template)) {
        template = _emitRuntimeIfBranch(
          candidate.template,
          issues,
          ordinal: ordinal,
          itemType: itemType,
          emitLeaf: emitLeaf,
        );
      } else if (itemType == PropertyType.widget ||
          itemType == PropertyType.inlineSpan) {
        final elements = <String>[];
        if (!_emitGuardedBranch(
          candidate.template,
          const _ConditionLowering(_unguarded),
          elements,
          issues,
          ordinal: ordinal,
          itemType: itemType,
          emitLeaf: emitLeaf,
        )) {
          template = '[${elements.join(', ')}]';
        }
      }
    } finally {
      _walk = saved;
    }
    if (template == null) {
      if (issues.length == before) _recordCollectionRefusal(refusal, issues);
      return null;
    }
    if (template.isEmpty || issues.length != before) return null;
    if (_containsConstructorCall(template, identifier)) {
      issues.add(
        Issue(
          code: IssueCode.unsupportedCollectionFlow,
          message:
              "The collection-for name '$identifier' conflicts with an "
              'RFW constructor used by its template. Rename the loop value.',
          location: _locationOf(refusal.location),
        ),
      );
      return null;
    }
    return '...for $identifier in ${input.dsl}: $template';
  }

  ({
    String dsl,
    HostDataShape elementShape,
    RootContextParam? root,
    String? items,
  })?
  _runtimeLoopInput(
    CollectionRuntimeLoopCandidate candidate,
    CollectionUnrollRefused refusal,
    List<Issue> issues, {
    bool inMount = false,
  }) {
    final iterable = candidate.iterable;
    if (_itemsInMount(candidate, any: inMount) case final items?) {
      final outer = switch (_hoist!.values[items]!.item) {
        final item? => _walk.runtimeLoops.lastWhereOrNull(
          (loop) => loop.item == item,
        ),
        null => null,
      };
      return (
        dsl: outer == null
            ? 'data.context${_rfwPathPart(items)}'
            : '${outer.identifier}${_rfwPathPart(items)}',
        elementShape: HostDataScalarShape(
          iterable.staticType!,
          HostDataScalarKind.object,
        ),
        root: null,
        items: items,
      );
    }
    if (!_isResolvedList(iterable.staticType)) {
      _recordCollectionRefusal(refusal, issues);
      return null;
    }
    final outer = _runtimeLoopReference(iterable);
    if (outer != null && !outer.isRefused) {
      final shape = outer.shape;
      if (shape is HostDataListShape) {
        return (
          dsl: outer.dsl(_rfwPathPart),
          elementShape: shape.elementShape,
          root: null,
          items: null,
        );
      }
    }
    final rootAccess = _rootParamAccess(iterable);
    final shape = rootAccess?.shape;
    if (rootAccess == null ||
        rootAccess.isRefused ||
        rootAccess.param.hasNonNullDefault ||
        shape is! HostDataListShape ||
        !_isResolvedList(shape.type)) {
      _recordCollectionRefusal(refusal, issues);
      return null;
    }
    return (
      dsl: rootAccess.dsl(_rfwPathPart),
      elementShape: shape.elementShape,
      root: rootAccess.isMember ? null : rootAccess.param,
      items: null,
    );
  }

  /// The key of the item list the mount computes for a split surface's loop
  /// over an iterable it can evaluate: one the payload cannot read, a
  /// destructuring loop, or, with [any], one whose body needs its items.
  String? _itemsInMount(
    CollectionRuntimeLoopCandidate candidate, {
    bool any = false,
  }) {
    final hoist = _hoist;
    final iterable = candidate.iterable;
    final type = iterable.staticType;
    if (_islands == null ||
        hoist == null ||
        hoist.speculating ||
        type is! InterfaceType ||
        type.allSupertypes.every((t) => !t.isDartCoreIterable) &&
            !type.isDartCoreIterable ||
        candidate.pattern == null &&
            (_isPlainObjectListInput(iterable) ||
                !any &&
                    (_rootParamAccess(iterable) != null ||
                        _runtimeLoopReference(iterable) != null))) {
      return null;
    }
    // Reached through a helper, the list is walked where the helper's loop
    // is written, inside the helper the copy runs.
    final walked = switch (candidate.loop?.forLoopParts) {
      final ForEachParts parts when candidate.spreadProvenance.isNotEmpty =>
        parts.iterable,
      _ => iterable,
    };
    final analysis = hoist.analyzer.analyze(walked);
    if (analysis is! HoistEvaluable) return null;
    // A nested loop's list is computed per item of a list the mount walks:
    // one it publishes, or a screen input's own list.
    if (analysis.item case final outer?
        when hoist.values[outer]?.kind != HoistValueKind.items &&
            !_walk.runtimeLoops.any((loop) => loop.root?.name == outer)) {
      return null;
    }
    final site = _valueSite;
    _valueSite = walked;
    final String key;
    try {
      key = hoist
          .add(
            analysis.items(
              type,
              pattern: switch (candidate.pattern) {
                final DartPattern pattern => _writtenSource(pattern),
                null => candidate.identifier,
              },
            ),
          )
          .key;
    } finally {
      _valueSite = site;
    }
    return key;
  }

  // A screen input's list of objects, which carries per-item values itself.
  bool _isPlainObjectListInput(Expression iterable) {
    final access = _rootParamAccess(iterable);
    final shape = access?.shape;
    return access != null &&
        !access.isMember &&
        !access.isRefused &&
        !access.param.hasNonNullDefault &&
        shape is HostDataListShape &&
        shape.elementShape is HostDataObjectShape &&
        _isResolvedList(shape.type);
  }

  bool _containsConstructorCall(String dsl, String identifier) {
    var quoted = false;
    var escaped = false;
    var index = 0;
    while (index < dsl.length) {
      final unit = dsl.codeUnitAt(index);
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5C) {
          escaped = true;
        } else if (unit == 0x22) {
          quoted = false;
        }
        index++;
        continue;
      }
      if (unit == 0x22) {
        quoted = true;
        index++;
        continue;
      }
      if (!dsl.startsWith(identifier, index)) {
        index++;
        continue;
      }
      final before = index == 0 ? null : dsl.codeUnitAt(index - 1);
      var cursor = index + identifier.length;
      final after = cursor == dsl.length ? null : dsl.codeUnitAt(cursor);
      if ((before == null || !_isRfwIdentifierUnit(before)) &&
          (after == null || !_isRfwIdentifierUnit(after))) {
        while (cursor < dsl.length &&
            _isRfwWhitespace(dsl.codeUnitAt(cursor))) {
          cursor++;
        }
        if (cursor < dsl.length && dsl.codeUnitAt(cursor) == 0x28) return true;
      }
      index += identifier.length;
    }
    return false;
  }

  bool _isRfwIdentifierUnit(int unit) =>
      unit == 0x5F ||
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A);

  bool _isRfwWhitespace(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

  bool _isResolvedList(DartType? type) =>
      type is InterfaceType &&
      type.isDartCoreList &&
      type.nullabilitySuffix == NullabilitySuffix.none;

  _RuntimeLoopReference? _runtimeLoopReference(Expression expression) {
    if (expression is ParenthesizedExpression) {
      return _runtimeLoopReference(expression.expression);
    }
    if (expression is SimpleIdentifier) {
      for (final binding in _walk.runtimeLoops.reversed) {
        // The mount reads a walked item's members as per-item values.
        if (binding.items != null) continue;
        if (identical(binding.element, expression.element)) {
          return _RuntimeLoopReference(
            binding,
            const [],
            shape: binding.shape,
            indexed: false,
          );
        }
      }
      return null;
    }
    if (expression is PrefixedIdentifier) {
      final target = _runtimeLoopReference(expression.prefix);
      return target?.append(identifierElement(expression.identifier));
    }
    if (expression is PropertyAccess && expression.target != null) {
      final target = _runtimeLoopReference(expression.target!);
      return target?.append(identifierElement(expression.propertyName));
    }
    if (expression is IndexExpression) {
      final target = _runtimeLoopReference(expression.realTarget);
      return target?.withIndex();
    }
    return null;
  }

  ({String dsl, HostDataShape shape})? _shapedReference(Expression source) {
    final resolved = _resolveBoundIdentifier(source);
    final root = _rootParamAccess(resolved);
    if (root != null) {
      final shape = root.shape;
      return root.param.isHostData && !root.isRefused && shape != null
          ? (dsl: root.dsl(_rfwPathPart), shape: shape)
          : null;
    }
    final loop = _runtimeLoopReference(resolved);
    final shape = loop?.shape;
    return loop != null && !loop.isRefused && shape != null
        ? (dsl: loop.dsl(_rfwPathPart), shape: shape)
        : null;
  }

  void _recordCollectionRefusal(
    CollectionUnrollRefused refusal,
    List<Issue> issues,
  ) {
    issues.add(
      Issue(
        code: IssueCode.unsupportedCollectionFlow,
        message: collectionRefusalMessage(
          refusal,
          _locationOf(refusal.location),
        ),
        location: _locationOf(refusal.location),
      ),
    );
  }

  bool _admitOrdinaryLeaf(Expression expression, List<Issue> issues) {
    final refusal = _collectionSession.admitOrdinaryLeaf(
      expression,
      _collectionSemanticProbe(),
      bindings: {
        ..._walk.inlined.localBindings,
        ..._walk.paramBindings,
      },
    );
    if (refusal == null) return true;
    _recordCollectionRefusal(refusal, issues);
    return false;
  }

  CollectionSemanticProbe _collectionSemanticProbe() => CollectionSemanticProbe(
    bindingFor: (identifier) {
      final element = identifier.element;
      if (element == null) return null;
      return _walk.paramBindings[element] ??
          _walk.inlined.localBindings[element];
    },
    helperFor: (invocation) {
      if (!isArtifactHelperInvocation(
        invocation,
        admittedHelperPackages: _admittedHelperPackages,
      )) {
        return null;
      }
      final helper =
          _walk.inlined.helpers[invocation.methodName.element] ??
          _collectionHelpers[invocation.methodName.element];
      // Such a call is an island, which the leaf translates whole.
      if (helper == null || _repeatsCode(invocation)) return null;
      final bindings = bindHelperArguments(
        helper.params,
        invocation.argumentList.arguments.toList(),
      );
      if (bindings == null) return null;
      return CollectionResolvedHelper(
        body: helper.body,
        parameterBindings: bindings,
      );
    },
  );

  Map<Element, HelperDef> _collectionHelperDefinitions(
    Expression expression,
  ) {
    final definitions = Map<Element, HelperDef>.identity();
    for (final entry in inlinableHelperDefinitionsIn(expression).entries) {
      final element = entry.key;
      if (_isFrameworkValueType(element)) continue;
      final name = element.name;
      if (name != null &&
          helpers.find(name, element.library?.identifier ?? '') != null) {
        continue;
      }
      definitions[element] = entry.value;
    }
    return definitions;
  }

  String _translateOccurrence(
    CollectionSemanticOccurrence occurrence,
    List<Issue> issues, {
    PropertyType? itemType,
    String? Function(CollectionSemanticOccurrence, int)? emitLeaf,
    int ordinal = 0,
    MeasurementOccurrenceScope? measurementScope,
  }) {
    if (emitLeaf != null) return emitLeaf(occurrence, ordinal) ?? '';
    final saved = _walk;
    final unrolled = _unrolled.length;
    _unrolled.addAll([
      for (final step in occurrence.structuralPath)
        if (step.kind == CollectionStructuralOccurrenceKind.loopIteration &&
            step.node is ForElement &&
            !_unrolled.any((known) => identical(known.loop, step.node)))
          (loop: step.node as ForElement, ordinal: step.ordinal),
    ]);
    // Each unrolled iteration is its own island scope.
    final iterations = [
      for (final step in occurrence.structuralPath)
        if (step.kind == CollectionStructuralOccurrenceKind.loopIteration)
          '${step.ordinal}',
    ];
    if (iterations.isNotEmpty) {
      _walk = _walk.copyWith(
        islandScope: [..._walk.islandScope, ...iterations],
      );
    }
    try {
      return _throughLocals(
        [...occurrence.spreadProvenance, ...occurrence.sourceProvenance],
        0,
        issues,
        () => itemType != null
            ? _translateSlotElement(
                occurrence.terminalExpression,
                occurrence.bindings,
                itemType,
                issues,
                measurementScope: measurementScope,
              )
            : _translateWithBindings(
                occurrence.terminalExpression,
                occurrence.bindings,
                issues,
                _translate,
                measurementScope: measurementScope,
              ),
      );
    } finally {
      _walk = saved;
      _unrolled.length = unrolled;
    }
  }

  // Whether every record of [key] is an app builder slot's own.
  static bool _slotOnly(_HoistSession hoist, String key) {
    final records = [
      for (final record in hoist.records)
        if (record.key == key) record,
    ];
    return records.isNotEmpty && records.every((record) => record.slot);
  }

  // The builder frames inside an app builder's slot.
  final Set<WidgetBuilderLowering> _slotFrames = HashSet.identity();

  // The statically unrolled loop iterations being translated, outermost first.
  final _unrolled = <({ForElement loop, int ordinal})>[];

  // [translate] through each build local and helper parameter the
  // collection resolver crossed from [from] on, as a read of it.
  String _throughLocals(
    List<CollectionSemanticSourceStep> steps,
    int from,
    List<Issue> issues,
    String Function() translate,
  ) {
    for (var index = from; index < steps.length; index++) {
      final step = steps[index];
      String rest() => _throughLocals(steps, index + 1, issues, translate);
      // Each call of a helper the resolver inlined is its own scope, as an
      // inlined call's is.
      if (step case CollectionSemanticSourceStep(
        kind: CollectionSemanticSourceKind.helper,
        source: final MethodInvocation call,
      )) {
        _callSites.add(call);
        // The helper's body is where the copy runs what the list holds.
        _hoist?.helperBodies[call] =
            _walk.inlined.helpers[call.methodName.element]?.body ?? step.target;
        try {
          return _inScope([islandCallStep(call)], rest);
        } finally {
          _callSites.removeLast();
        }
      }
      final read = step.source;
      if (read is! SimpleIdentifier) continue;
      if (step.kind == CollectionSemanticSourceKind.constDeclaration) {
        return _inScope(_constPlacementStep(read), rest);
      }
      if (step.kind != CollectionSemanticSourceKind.binding) continue;
      final argument = _walk.paramBindings[read.element];
      if (argument != null) {
        if (!identical(argument, step.target)) continue;
        return _throughParameter(read, argument, rest);
      }
      final initializer = _walk.inlined.localBindings[read.element];
      if (initializer == null || !identical(initializer, step.target)) {
        continue;
      }
      return _throughLocal(read, initializer, issues, rest);
    }
    return translate();
  }

  String _translateDoubleElement(
    Expression expression,
    Map<Element, Expression> bindings,
    List<Issue> issues,
  ) => _translateWithBindings(
    expression,
    bindings,
    issues,
    _translateDoubleScalar,
  );

  String _translateSlotElement(
    Expression expression,
    Map<Element, Expression> bindings,
    PropertyType type,
    List<Issue> issues, {
    MeasurementOccurrenceScope? measurementScope,
  }) => _translateWithBindings(
    expression,
    bindings,
    issues,
    (bound, sink) => _translateSlotValue(bound, type, sink),
    measurementScope: measurementScope,
  );

  T _translateWithBindings<T>(
    Expression expression,
    Map<Element, Expression> bindings,
    List<Issue> issues,
    T Function(Expression, List<Issue>) translate, {
    MeasurementOccurrenceScope? measurementScope,
  }) => _withTranslationBindings(
    bindings,
    () => translate(expression, issues),
    measurementScope: measurementScope,
  );

  T _withTranslationBindings<T>(
    Map<Element, Expression> bindings,
    T Function() translate, {
    MeasurementOccurrenceScope? measurementScope,
  }) {
    final saved = _walk;
    final entersMeasurementScope = measurementScope != null;
    _walk = _walk.copyWith(
      inlined: InlinedDefinitions(
        localBindings: {
          ..._walk.inlined.localBindings,
          ...bindings,
        },
        helpers: _walk.inlined.helpers,
      ),
      measurementScope: measurementScope ?? _walk.measurementScope,
      measurementWidget: !entersMeasurementScope
          ? _walk.measurementWidget
          : null,
      measurementWidgetList: !entersMeasurementScope
          ? _walk.measurementWidgetList
          : null,
    );
    try {
      return translate();
    } finally {
      _walk = saved;
    }
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
          message:
              'Set literals, spreads, collection-if, and collection-for '
              'are not supported in map literals. Use a static string-keyed '
              'map.',
          location: _locationOf(expr),
        ),
      );
    }
    return '{ ${parts.join(', ')} }';
  }

  String _recordLiteral(RecordLiteral expr, List<Issue> issues) {
    String defer(String reason) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          capabilityGapSubject: 'expression:${_nodeKind(expr)}',
          message: 'Record literal cannot be encoded: $reason.',
          location: _locationOf(expr),
        ),
      );
      return '';
    }

    final staticType = expr.staticType;
    if (staticType is! RecordType) {
      return defer('its resolved static type is not a record type');
    }
    final classification = classifyRecordType(staticType);
    if (classification is! RecordAdmitted) {
      final reason = classification is RecordExcluded
          ? classification.reason
          : 'its resolved static type is not a record type';
      return defer(reason);
    }

    final valueByLabel = <String, Expression>{};
    for (final field in expr.fields) {
      if (field is! RecordLiteralNamedField) {
        return defer('positional record fields are unsupported');
      }
      valueByLabel[field.name.lexeme] = field.fieldExpression;
    }

    final issuesBefore = issues.length;
    final entries = <String>[];
    // The classifier exposes the analyzer's canonical label order rather than
    // the source spelling, so two author orderings of the same record emit
    // byte-identically.
    for (final label in classification.labels) {
      final value = valueByLabel[label.name];
      if (value == null) {
        return defer("the '${label.name}' label has no value");
      }
      final shape = label.shape;
      final emitted = _translateSlotValue(
        value,
        shape.propertyType,
        issues,
        property: syntheticProperty(label.name, shape),
      );
      entries.add('${_rfwMapKey(label.name)}: $emitted');
    }

    // A label may defer after earlier labels translated cleanly. The record is
    // one value contract, so any such issue suppresses the whole map rather
    // than exposing a partially successful encoding.
    if (issues.length > issuesBefore) return '';
    return '{${entries.join(', ')}}';
  }

  String _mapLiteralKey(Expression expr, List<Issue> issues) {
    String? key;
    if (expr is SimpleStringLiteral) {
      key = expr.value;
    } else {
      // The unified scalar boundary, so a const-object scalar field used as a
      // map key folds consistently with emission (this path bypasses _translate
      // and so the const-object hook there).
      final folded = _foldScalarConstant(expr);
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
    return _rfwMapKey(key);
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
    if (prefix == 'widget' && _walk.stateFields != null) {
      if (_walk.argNames[identifier] case final argName?) {
        return 'args${_rfwPathPart(argName)}';
      }
    }
    // Stateful roots read constructor parameters through `widget`.
    final rootParam = _rootParamRead(expr);
    if (rootParam != null) {
      if (!rootParam.isHostData) {
        issues.add(_hostDataStateShapeIssue(rootParam, expr));
        return '';
      }
      if (rootParam.hasNonNullDefault) {
        issues.add(
          _hostDataDefaultIssue(rootParam, expr, stateful: true),
        );
        return '';
      }
      return 'data.context${_rfwPathPart(identifier)}';
    }
    if (prefix == 'widget' && _walk.rootStateContext) {
      issues.add(
        Issue(
          code: IssueCode.stateShapeUnsupported,
          message:
              'Root source State.build() cannot read widget.$identifier. '
              'Root sources are not called by another RFW widget, so there is '
              'no args.$identifier binding to emit. Move the value into a '
              'constant, host data, or an explicit supported State field.',
          location: _locationOf(expr),
        ),
      );
      return '';
    }

    // Radii have no wire form of their own outside the sites that read them.
    final frameworkConst = _frameworkConstValue(expr);
    if (frameworkConst != null &&
        frameworkConst.kind != FrameworkConstKind.radius &&
        frameworkConst.kind != FrameworkConstKind.borderRadius) {
      return frameworkConst.dsl;
    }

    if (prefix == 'Colors') {
      // The `Colors.*` arm lowers against a hard-coded Material colour table,
      // so it must fire ONLY for the real `package:flutter` `Colors` — a
      // custom class that happens to be named `Colors` would otherwise be
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
          message:
              "Unsupported Material color 'Colors.$identifier'. "
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
      // custom class named `Icons` (or an unresolved prefix) defers.
      if (!_prefixResolvesToFlutter(expr.prefix)) {
        return _deferFrameworkConstLookalike(expr, prefix, identifier, issues);
      }
      return _resolveIconCodepoint(expr, issues);
    }

    // The const-factory `.zero` accessors lower to the same value as their
    // explicit zero constructors (`EdgeInsets.all(0)` / `BorderRadius` zero) —
    // without this they fall through to the bare-name path and emit `"zero"`,
    // which the value-type floor then rejects. Gated to the real framework
    // type: a resolved custom `EdgeInsets` / `BorderRadius` look-alike with a
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
      if (!_frameworkOrUnresolved(identifierElement(expr.prefix))) {
        return _deferFrameworkConstLookalike(expr, prefix, identifier, issues);
      }
      return prefix == 'EdgeInsetsDirectional'
          ? '{start: 0.0, top: 0.0, end: 0.0, bottom: 0.0}'
          : '{left: 0.0, top: 0.0, right: 0.0, bottom: 0.0}';
    }
    if ((prefix == 'BorderRadius' || prefix == 'BorderRadiusDirectional') &&
        identifier == 'zero') {
      if (!_frameworkOrUnresolved(identifierElement(expr.prefix))) {
        return _deferFrameworkConstLookalike(expr, prefix, identifier, issues);
      }
      return prefix == 'BorderRadiusDirectional'
          ? '${_kBorderRadiusCornerSentinel}topStart: 0.0, topEnd: 0.0, bottomStart: 0.0, bottomEnd: 0.0)'
          : '0';
    }
    // `Offset.zero` lowers to the same `{x, y}` map the `Offset(0, 0)` ctor
    // produces — without this it falls through to the bare-name path and
    // emits `"zero"`, which the value-type floor then rejects. Element-gated
    // like the sibling `.zero` accessors: a resolved custom `Offset`
    // look-alike with a `zero` member defers rather than lowering as the
    // framework zero value.
    if (prefix == 'Offset' && identifier == 'zero') {
      if (!_frameworkOrUnresolved(identifierElement(expr.prefix))) {
        return _deferFrameworkConstLookalike(expr, prefix, identifier, issues);
      }
      return '{x: 0.0, y: 0.0}';
    }

    // A concrete framework `Alignment.<member>` used by the catalog's flat
    // alignment decoder. This is a static-const family rather than an enum, so
    // it needs an explicit element-gated lowering after the general unresolved
    // non-enum fall-through was closed. A custom `Alignment` look-alike and
    // an unresolved prefix both continue to the diagnosed path below.

    // A `FontWeight.<member>` reference. A resolved CUSTOM class named
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
      if (!_frameworkOrUnresolved(identifierElement(expr.prefix))) {
        return _deferFrameworkConstLookalike(expr, prefix, identifier, issues);
      }
      if (_isFrameworkValueType(identifierElement(expr.prefix))) {
        final canonical = _canonicalFontWeightName(expr);
        if (canonical != null) return '"$canonical"';
        issues.add(
          Issue(
            code: IssueCode.unresolvedIdentifier,
            message:
                "Couldn't resolve 'FontWeight.$identifier' to a canonical "
                'font weight (w100-w900). Use a standard FontWeight value.',
            location: _locationOf(expr),
          ),
        );
        return '';
      }
    }

    // A `TextDecoration.<member>` reference. Like FontWeight, a resolved
    // CUSTOM class named `TextDecoration` must NOT lower to the bare member
    // name — the runtime defaults an unknown decoration string to
    // `TextDecoration.none`, a silent drop for the author's own type. Defer the
    // resolved-custom case; the real framework class (and an unresolved
    // synthetic prefix) keeps the member-name path below, which the decoder
    // resolves.
    if (prefix == 'TextDecoration' &&
        !_frameworkOrUnresolved(identifierElement(expr.prefix))) {
      return _deferFrameworkConstLookalike(expr, prefix, identifier, issues);
    }
    if (prefix == 'TextDecoration' &&
        _isFrameworkValueType(identifierElement(expr.prefix))) {
      return '"$identifier"';
    }

    // A `Curves.<member>` reference. Like FontWeight/TextDecoration, a resolved
    // CUSTOM class named `Curves` must NOT lower to the bare member name: the
    // curve decoder would resolve a coincidentally-supported name (e.g.
    // `easeIn`) to the REAL framework curve — a value-substitution silent-wrong
    // the curve validator backstop cannot catch, since it only rejects names
    // OUTSIDE the supported set. Defer the resolved-custom case; the real
    // framework class (and an unresolved synthetic prefix) keeps the
    // member-name path below, where the catalog validator backstops the
    // supported curve set on the direct-paywall path.
    if (prefix == 'Curves' &&
        !_frameworkOrUnresolved(identifierElement(expr.prefix))) {
      return _deferFrameworkConstLookalike(expr, prefix, identifier, issues);
    }
    if (prefix == 'Curves' &&
        _isFrameworkValueType(identifierElement(expr.prefix))) {
      return '"$identifier"';
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

    // A device read through a bound local, or a prefixed framework value.
    final prefixedDeviceRead = _recognizeDeviceRead(expr);
    if (prefixedDeviceRead != null) {
      return _deviceRead(prefixedDeviceRead, expr, issues);
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
      final owner = _constNamespaceLookalikeOwner(expr);
      issues.add(
        owner == null
            ? _nonFiniteNumericIssue(expr)
            : _frameworkNamespaceReservedIssue(
                expr,
                owner,
                IssueCode.nonFiniteNumericValue,
              ),
      );
      return '';
    }

    // Enum reference: `MainAxisAlignment.center` → "center". The catalog
    // declares which property accepts which enum; runtime/validation paths
    // confirm the value is recognized.
    final member = _unwrapPropertyAccessor(identifierElement(expr.identifier));
    if (member is FieldElement && member.isEnumConstant) {
      return '"$identifier"';
    }

    // Same-file structured consts translate through their initializers.
    final constDsl = _translateConstIdentifier(
      expr,
      issues,
      IssueCode.unresolvedIdentifier,
      (initializer) => _translate(initializer, issues),
    );
    if (constDsl != null) return constDsl;

    final reservedOwner = _constNamespaceLookalikeOwner(expr);
    if (reservedOwner != null) {
      issues.add(
        _frameworkNamespaceReservedIssue(
          expr,
          reservedOwner,
          IssueCode.unresolvedIdentifier,
        ),
      );
      return '';
    }
    // Report unsupported cross-file consts explicitly.
    if (isConstDeclarationReference(expr)) {
      issues.add(
        _constIdentifierUnresolvedIssue(
          expr,
          IssueCode.unresolvedIdentifier,
        ),
      );
      return '';
    }

    // A dotted read must resolve through the retained host-data descriptor.
    final memberRootAccess = _rootParamAccess(expr);
    if (memberRootAccess?.isMember ?? false) {
      issues.add(_hostDataMemberIssue(memberRootAccess!.param, expr));
      return '';
    }
    issues.add(
      _appOnlyValueIssue(expr, IssueCode.unresolvedIdentifier) ??
          Issue(
            code: IssueCode.unresolvedIdentifier,
            message:
                "'${expr.toSource()}' is not a resolved enum constant "
                'or portable const value.',
            location: _locationOf(expr),
          ),
    );
    return '';
  }

  /// Whether [expr] is a constant that evaluates to a non-finite double —
  /// `double.infinity` / `.negativeInfinity` / `.nan`, or a custom `const`
  /// equal to one. Reached only after [tryFoldConstant] declined [expr] (a
  /// finite const already folded), so this is the non-finite-or-unresolved
  /// case.
  ///
  /// The three `double` non-finite members are matched by name. Other constants
  /// use their resolved value.
  bool _isNonFiniteDoubleConstant(PrefixedIdentifier expr) {
    if (expr.prefix.name == 'double' &&
        const {
          'infinity',
          'negativeInfinity',
          'nan',
        }.contains(expr.identifier.name)) {
      return true;
    }
    final variable = _unwrapPropertyAccessor(
      identifierElement(expr.identifier),
    );
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
    message:
        'A non-finite double (`${node.toSource()}`) has no '
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
    final element = identifierElement(expr.identifier);
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
    final element = identifierElement(expr.identifier);
    if (element is PropertyAccessorElement) {
      final icon = element.variable.computeConstantValue();
      final codepoint = icon?.getField('codePoint')?.toIntValue();
      if (codepoint != null) {
        final family = icon?.getField('fontFamily')?.toStringValue();
        final package = icon?.getField('fontPackage')?.toStringValue();
        // The Material font is the wire default, so a Material icon travels
        // as a bare codepoint with no family alongside it.
        final isDefaultFont =
            family == _kDefaultIconFontFamily && package == null;
        if (family != null && !isDefaultFont) _resolvedIconFontFamily = family;
        // Not mirroring is the wire default, so only a mirroring icon fills
        // the slot.
        _resolvedIconMatchTextDirection =
            icon?.getField('matchTextDirection')?.toBoolValue() ?? false;
        // Recorded field for field, so the generated reference rebuilds the
        // exact icon rather than a value synthesised from its code point.
        if (icon != null && isIconDataValue(icon)) {
          try {
            // Rebuilt before the null check so a refusal is diagnosed even
            // when nothing is collecting this call's icons.
            final reference = iconDataReference(icon);
            _currentIconReferences?.add(reference);
          } on IconCarriageFailure catch (failure) {
            issues.add(
              Issue(
                code: failure is IconCodePointCollision
                    ? IssueCode.collidingIconCodePoints
                    : IssueCode.unreconstructableIconData,
                message:
                    'This surface renders '
                    '${expr.prefix.name}.${expr.identifier.name}, but '
                    '${failure.reason}.',
                location: _locationOf(expr),
              ),
            );
            return '';
          }
        }
        return '$codepoint';
      }
    }
    issues.add(
      Issue(
        code: IssueCode.unresolvedIdentifier,
        message:
            "Couldn't resolve '${expr.prefix.name}.${expr.identifier.name}"
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
  /// the inlining classifier's framework-const recognition: a custom class
  /// that happens to be named `Colors` / `Icons` must NOT enter those arms, and
  /// an UNRESOLVED prefix (`element == null`) is NOT recognised — it defers.
  /// The translator runs on resolved ASTs in production, so a null element is
  /// genuinely-unresolvable input; name-matching it would re-open the
  /// silent-wrong in a degraded/error-recovery build, so the safe direction is
  /// to defer (the recognised set is the resolved-real-Flutter case only).
  bool _prefixResolvesToFlutter(SimpleIdentifier prefix) =>
      libraryIsFlutter(identifierElement(prefix));

  /// The wire value of a framework static const [expr] names, gated by the
  /// framework-library predicate so a look-alike never substitutes.
  FrameworkConstValue? _frameworkConstValue(Expression expr) {
    final element = switch (expr) {
      PrefixedIdentifier(:final identifier) => identifierElement(identifier),
      PropertyAccess(:final propertyName) => identifierElement(propertyName),
      _ => null,
    };
    if (!_isFrameworkValueType(element)) return null;
    final value = frameworkStaticConst(expr);
    return value == null ? null : encodeFrameworkConst(value);
  }

  /// True when [element] is unresolved (`null` — a synthetic-test input) OR
  /// resolves to a framework value-type library (`dart:` / `package:flutter/`).
  /// The value-type recognition arms that also serve unresolved synthetic
  /// inputs (the bare-call `_methodInvocation` arms, the `.zero` const-factory
  /// arms) gate on this: a resolved CUSTOM look-alike (non-null,
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
    NodeList<Argument> args,
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
      if (arg is! NamedArgument) {
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message:
                'Duration accepts only named unit arguments '
                '(days / hours / minutes / seconds / milliseconds / '
                'microseconds).',
            location: loc,
          ),
        );
        return '';
      }
      final unit = arg.name.lexeme;
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
      final folded = _foldScalarConstant(arg.argumentExpression);
      if (folded is! int) {
        issues.add(
          Issue(
            code: IssueCode.unresolvedIdentifier,
            message:
                "Duration '$unit' must be a const integer to lower to a "
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
          message:
              'Sub-millisecond Duration values cannot be represented; the '
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
          message:
              'Duration value is out of range; its millisecond total does '
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
  /// custom lookalike or an unresolved prefix) and returns the empty-string
  /// sentinel. Deferring here is the translator-strict half of the
  /// classifier-broad / translator-strict pattern: the classifier may fold a
  /// custom scalar const into the composable set, but the translator refuses
  /// to lower a `Colors` / `Icons` reference that is not the framework's.
  String _deferFrameworkConstLookalike(
    PrefixedIdentifier expr,
    String prefix,
    String _identifier,
    List<Issue> issues,
  ) {
    issues.add(
      _frameworkNamespaceReservedIssue(
        expr,
        _constNamespaceLookalikeOwner(expr) ?? prefix,
        IssueCode.unresolvedIdentifier,
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
        message:
            "'${expr.toSource()}' does not resolve to package:flutter's "
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

  String? _textScalerRecipe(Expression expr, List<Issue> issues) {
    Element? member;
    String? name;
    NodeList<Argument>? arguments;
    if (expr is PrefixedIdentifier) {
      member = expr.identifier.element;
      name = expr.identifier.name;
    } else if (expr is PropertyAccess) {
      member = expr.propertyName.element;
      name = expr.propertyName.name;
    } else if (expr is InstanceCreationExpression) {
      member = expr.constructorName.element;
      name = expr.constructorName.name?.name;
      arguments = expr.argumentList.arguments;
    } else if (expr is MethodInvocation) {
      member = expr.methodName.element;
      name = expr.methodName.name;
      arguments = expr.argumentList.arguments;
    }
    if (member == null ||
        !libraryIsFlutter(member) ||
        member.enclosingElement?.name != 'TextScaler')
      return null;
    if (name == 'noScaling' && arguments == null) return '{kind: "none"}';
    if (name == 'linear' &&
        arguments != null &&
        arguments.length == 1 &&
        arguments.single is! NamedArgument) {
      return '{kind: "linear", factor: ${_translate(arguments.single as Expression, issues)}}';
    }
    return null;
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
    NodeList<Argument> args,
    List<Issue> issues,
    String loc, {
    required bool fromConstructor,
  }) {
    return _normalizeNullablePresentDsl(
      issues,
      () => _emitValueType(
        type,
        variant,
        args,
        issues,
        loc,
        fromConstructor: fromConstructor,
      ),
    );
  }

  String? _emitValueType(
    String type,
    String? variant,
    NodeList<Argument> args,
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
      case 'EdgeInsetsDirectional':
        return variant == null
            ? null
            : _structured.edgeInsets(
                variant,
                args.toList(),
                issues,
                loc,
                directional: type == 'EdgeInsetsDirectional',
              );
      case 'BorderRadius':
      case 'BorderRadiusDirectional':
        return variant == null
            ? null
            : _structured.borderRadius(
                variant,
                args.toList(),
                issues,
                loc,
                directional: type == 'BorderRadiusDirectional',
              );
      case 'Size':
        // Only the height factory lowers here; `Size(width, height)` is a
        // structured value handled by its own recipe.
        return variant == 'fromHeight'
            ? _structured.sizeFromHeight(args.toList(), issues, loc)
            : null;
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
    NodeList<Argument> args,
    List<Issue> issues,
    String loc, {
    required bool fromConstructor,
  }) {
    final key = recipeKey(library: null, typeName: type, variant: variant);
    String? value;
    if (_recipeDispatcher.hasRecipe(key)) {
      value = _recipeDispatcher.tryTranslate(
        key,
        args.toList(),
        issues,
        loc,
      );
    }
    value ??= _tryValueType(
      type,
      variant,
      args,
      issues,
      loc,
      fromConstructor: fromConstructor,
    );
    return value;
  }

  String? _nativeChildDelegate(
    InstanceCreationExpression expression,
    List<Issue> issues,
  ) {
    final constructor = constructionConstructor(expression);
    final owner = constructor?.enclosingElement;
    if (owner?.library.identifier !=
        'package:flutter/src/widgets/scroll_delegate.dart')
      return null;
    final name = owner?.name;
    if (name != 'SliverChildBuilderDelegate' &&
        name != 'SliverChildListDelegate')
      return null;
    final variant = constructor?.name;
    if (variant != 'new' &&
        !(name == 'SliverChildListDelegate' && variant == 'fixed')) {
      return null;
    }
    final values = <String>['_s: ${_stringLiteral(name!)}'];
    if (variant == 'fixed') values.add('fixed: true');
    final builder = name == 'SliverChildBuilderDelegate';
    for (final argument in expression.argumentList.arguments) {
      if (argument is! NamedArgument) {
        final value = builder
            ? _translateWidgetBuilder(
                argument.argumentExpression,
                const PropertyEntry(
                  wireId: WireId.unallocatedProperty,
                  name: 'builder',
                  type: PropertyType.widgetBuilder,
                  description: '',
                  builderContract: WidgetBuilderContract(
                    parameters: [
                      WidgetBuilderParameter.buildContext,
                      WidgetBuilderParameter.itemIndex,
                    ],
                    nullableResult: true,
                  ),
                ),
                issues,
              )
            : _translateSlotValue(
                argument.argumentExpression,
                PropertyType.widgetList,
                issues,
              );
        values.add('${builder ? 'builder' : 'children'}: $value');
      } else {
        final name = argument.name.lexeme;
        final scalar = switch (name) {
          'semanticIndexCallback' => const ScalarCallbackContract(
            parameters: [
              ScalarCallbackParameter.widget,
              ScalarCallbackParameter.itemIndex,
            ],
          ),
          'findChildIndexCallback' => const ScalarCallbackContract(
            parameters: [ScalarCallbackParameter.valueKey],
          ),
          _ => null,
        };
        final parameter = constructor!.formalParameters
            .where((p) => p.name == name)
            .firstOrNull;
        final type = parameter == null
            ? null
            : inferPropertyType(parameter.type);
        if (parameter == null || type == null) {
          issues.add(
            Issue(
              code: IssueCode.propertyValueTypeMismatch,
              message: 'Unsupported native delegate argument: $name.',
              location: _locationOf(argument),
            ),
          );
          return '{}';
        }
        final property = PropertyEntry(
          wireId: WireId.unallocatedProperty,
          name: name,
          type: type,
          description: '',
          scalarContract: scalar,
          constructorNullable:
              parameter.type.nullabilitySuffix == NullabilitySuffix.question,
        );
        final value = _translateSlotValue(
          argument.argumentExpression,
          type,
          issues,
          property: property,
        );
        values.add('$name: $value');
      }
    }
    return '{${values.join(', ')}}';
  }

  String? _nativeGridValue(
    InstanceCreationExpression expression,
    List<Issue> issues,
  ) {
    final constructor = constructionConstructor(expression);
    final name = constructor?.enclosingElement.name;
    if (!kGridValueRecipes.any((recipe) => recipe.typeName == name))
      return null;
    if (!isGridValueConstructor(constructor)) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message:
              'This native value requires its declared Flutter constructor.',
          location: _locationOf(expression),
        ),
      );
      return '{}';
    }
    final physics = name!.endsWith('ScrollPhysics');
    if (physics && _nativePhysicsDepth >= 64) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message: 'Scroll physics parent chain exceeds its structural limit.',
          location: _locationOf(expression),
        ),
      );
      return '{}';
    }
    if (physics) _nativePhysicsDepth++;
    try {
      return _tryValueOrRecipe(
        name,
        constructor!.name == 'new' ? null : constructor.name,
        expression.argumentList.arguments,
        issues,
        _locationOf(expression),
        fromConstructor: true,
      );
    } finally {
      if (physics) _nativePhysicsDepth--;
    }
  }

  /// Removes only wrappers whose evaluation cannot change the selected value
  /// or throw. Other result shapes must pass normal exact Color translation.
  Expression _rootColorSource(Expression expression) {
    if (_activeWidgetBuilder != null || constValueAnchor(expression) != null) {
      return expression;
    }
    var current = expression;
    final seen = <Expression>{};
    while (seen.add(current)) {
      final resolved = _resolveBoundIdentifier(current);
      if (!identical(resolved, current)) {
        current = resolved;
        continue;
      }
      if (current is ConditionalExpression) {
        final selected = installedNativeConstantValue(
          current.condition,
        )?.toBoolValue();
        if (selected != null) {
          current = selected ? current.thenExpression : current.elseExpression;
          continue;
        }
      }
      if (current is AsExpression) {
        final target = current.type.type;
        final source = current.expression.staticType;
        if (target is InterfaceType &&
            source is InterfaceType &&
            target.element.name == 'Color' &&
            target.element.library.identifier == 'dart:ui' &&
            (source.nullabilitySuffix != NullabilitySuffix.question ||
                target.nullabilitySuffix == NullabilitySuffix.question) &&
            [
              source,
              ...source.allSupertypes,
            ].any((type) => type.element == target.element)) {
          current = current.expression;
          continue;
        }
      }
      break;
    }
    return current;
  }

  Expression? _installedColorExpression(Expression expression) {
    final source = constValueAnchor(expression) ?? _stripParens(expression);
    if (installedNativeConstructorType(source) == 'flutter.Color')
      return source;
    var resolved = _resolveBoundIdentifier(source);
    final seen = <Element>{};
    while (true) {
      final local = constDeclarationElement(resolved);
      if (local is! LocalVariableElement) break;
      if (!seen.add(local)) return null;
      final initializer = resolveConstDeclarationInitializer(resolved);
      if (initializer == null) return null;
      resolved = _resolveBoundIdentifier(initializer);
    }
    final type = resolved.staticType;
    if (type is! InterfaceType ||
        ![type, ...type.allSupertypes].any(
          (type) =>
              type.element.name == 'Color' &&
              type.element.library.identifier == 'dart:ui',
        ))
      return null;
    if (!isInstalledNativeConstant(resolved) &&
        _isInertNativeSelection(resolved))
      return resolved;
    if (resolved is InstanceCreationExpression &&
        resolved.isConst &&
        !identical(source, resolved)) {
      return resolved;
    }
    final accessor = resolved is PropertyAccess
        ? resolved.propertyName.element
        : null;
    final declaration =
        constDeclarationElement(resolved) ??
        (accessor is PropertyAccessorElement &&
                accessor.isStatic &&
                accessor.variable.isConst
            ? accessor.variable
            : null);
    if (declaration == null ||
        declaration.library?.identifier ==
            'package:flutter/src/material/colors.dart')
      return null;
    return resolved;
  }

  String _optionalNativeColor(Expression value, List<Issue> issues) {
    value = _rootColorSource(value);
    try {
      if (value.staticType?.nullabilitySuffix == NullabilitySuffix.question ||
          value.staticType?.isDartCoreNull == true ||
          _isNullLiteral(_resolveBoundIdentifier(value))) {
        throw BuilderLoweringException(
          value,
          'This native Color destination requires a non-null value.',
        );
      }
      final borrowed = _nativeBindingRead(value, type: 'flutter.Color');
      if (borrowed != null) return borrowed;
      if (_installedColorExpression(value) case final expression?) {
        final native = _tryNativeCallValue(
          expression,
          issues,
          type: 'flutter.Color',
        );
        if (native != null) return native;
      }
      if (_activeWidgetBuilder case final builder?) {
        return builder.value(
          value,
          requireNativeBaseType: true,
          requireNonNull: true,
          nativeDestination: 'Color',
        );
      }
      if (constValueAnchor(value) != null &&
          value is InstanceCreationExpression) {
        final constant = constantConstructionValue(value);
        final constantType = constant?.type;
        final owner = constantType is InterfaceType
            ? constantType.element
            : constructionConstructor(value)?.enclosingElement;
        if ((owner?.name != 'Color' ||
                owner?.library.identifier != 'dart:ui') &&
            (constant == null || exactColorConstant(constant) == null)) {
          throw BuilderLoweringException(
            value,
            'Color cannot cross a custom constructor boundary without proof of its native base runtime subtype.',
          );
        }
        final encoded = constant == null
            ? null
            : encodeFrameworkConst(constant);
        return encoded?.dsl ??
            _translateSlotValue(value, PropertyType.color, issues);
      }
      final values = BuilderExpressionLowering(
        operations: _installedValueOperations,
        capture: (expression) => _translate(expression, issues),
        extension: (expression, lowering) {
          final resolved = _resolveBoundIdentifier(expression);
          return identical(resolved, expression)
              ? null
              : lowering.lower(resolved);
        },
      );
      final node = values.lower(value);
      if (!values.provesNativeBase(node, 'Color')) {
        throw BuilderLoweringException(
          value,
          'Color cannot cross a custom constructor boundary without proof of its native base runtime subtype.',
        );
      }
      if (values.nodes[node].type.nullable) {
        throw BuilderLoweringException(
          value,
          'This native Color destination requires a non-null value.',
        );
      }
      final lowered = values.nodes[node];
      if (lowered.op == 'literal' && lowered.value is Map<String, Object?>) {
        return exactColorLiteral(lowered.value! as Map<String, Object?>);
      }
      // Color(int) already denotes the exact ARGB representation.
      if (lowered.op == 'argbColor') {
        return _translateSlotValue(value, PropertyType.color, issues);
      }
      // The native Color graph is already proven. Project its exact fields
      // through the same scalar envelopes used by ordinary native arguments.
      return '{${colorValueType.fields.entries.map((field) {
        final token = field.key == 'material' ? values.materialColorToken(node) : null;
        if (token != null) return 'material: ${_stringLiteral(token)}';
        final projection = values.add(ValueNode('field', field.value, inputs: [node], name: field.key));
        return '${field.key}: ${_encodeScalarValueProgram(values, projection)}';
      }).join(', ')}}';
    } on BuilderLoweringException catch (error) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message: error.toString(),
          location: _locationOf(error.node),
        ),
      );
      return '';
    }
  }

  String? _optionalNativeValue(
    Expression expr,
    List<Issue> issues, {
    String? expected,
  }) {
    final before = issues.length;
    try {
      final value = emitOptionalNativeValue(
        expr,
        translateBinding: (value, type) {
          if (_hoist == null || _hoist!.speculating) return null;
          if (constValueAnchor(value) != null) return null;
          final borrowed = _nativeBindingRead(value, type: type);
          if (borrowed != null) return borrowed;
          final expression = _stripParens(value);
          final active = _activeWidgetBuilder;
          if (active != null && expression is SimpleIdentifier) {
            var native = active.expressions.localFor(expression.element)?.$2;
            for (
              BuilderExpressionLowering? scope = active.expressions;
              native == null && scope != null;
              scope = scope.lexicalParent ?? scope.parent
            ) {
              final node = scope.bindings[expression.element];
              if (node != null) native = scope.nodes[node].type;
            }
            if (native?.kind == 'native' && native?.nativeType == type) {
              return active.nativeValue(
                expression,
                (value, lowering) => lowering.lower(value),
              );
            }
          }
          if (active != null && !active.isProjectingBody ||
              expression is FunctionExpression ||
              isInstalledNativeConstant(expression) ||
              _isInertNativeSelection(expression)) {
            return _tryNativeCallValue(expression, issues, type: type);
          }
          return null;
        },
        translate: (value) => _translate(value, issues),
        translateColor: (value) => _optionalNativeColor(value, issues),
        resolve: _resolveBoundIdentifier,
        translateConstant: (value, lower) => _translateConstIdentifier(
          value,
          issues,
          IssueCode.unrecognizedMethodCall,
          lower,
        ),
        expected: expected,
      );
      return issues.skip(before).any((issue) => !issue.code.isInformational)
          ? ''
          : value;
    } on BuilderLoweringException catch (error) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message: error.toString(),
          location: _locationOf(error.node),
        ),
      );
      return '';
    } on FormatException catch (error) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: error.message,
          location: _locationOf(expr),
        ),
      );
      return '';
    }
  }

  String _instanceCreation(
    InstanceCreationExpression expr,
    List<Issue> issues,
  ) {
    final optional = _optionalNativeValue(expr, issues);
    if (optional != null) return optional;
    final constructor = constructionConstructor(expr);
    final styleClass = constructor?.enclosingElement;
    if (isIconThemeDataClass(styleClass)) return _iconThemeData(expr, issues);
    if (isSystemUiOverlayStyleClass(styleClass) && constructor?.name == 'new') {
      return _tryValueOrRecipe(
        styleClass!.name!,
        null,
        expr.argumentList.arguments,
        issues,
        _locationOf(expr),
        fromConstructor: true,
      )!;
    }
    final typeName = expr.constructorName.type.name.lexeme;
    final constructorName = expr.constructorName.name?.name;
    final gridValue = _nativeGridValue(expr, issues);
    if (gridValue != null) return gridValue;
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
    final formattedText =
        expr.argumentList.arguments.firstOrNull?.argumentExpression;
    final substituted =
        formattedText != null && _containsIntlFormatting(formattedText)
        ? null
        : _tryNumberFormatSubstitution(expr, issues);
    if (substituted != null) return substituted;

    // Value-substitution gate. The framework-value recognition below (the
    // recipe dispatch + the per-type value arms) is NAME-based. A resolved
    // class that is neither `dart:` nor `package:flutter/` is custom code: it
    // cannot be a framework value type, so route it straight to widget
    // construction — a custom `@RestageWidget` resolves there; a custom
    // look-alike of a value type (its own `EdgeInsets` / `Color` / …) defers
    // with an `unknownWidget` diagnostic — rather than lowering it as the
    // framework value (a value-wrong blob the type-aware floor cannot catch,
    // since any structurally-valid value passes). A null element (unresolved
    // synthetic input) keeps the name-based recognition; an
    // `InstanceCreationExpression` only parses when the analyzer resolved a
    // constructor, so production always takes the gated path.
    final ctorClass = _classOfInstanceCreation(expr);
    if (ctorClass != null && !_isFrameworkValueType(ctorClass)) {
      // A resolved custom type is either a `@RestageWidget` (→ widget
      // construction) or a custom STRUCTURED VALUE used as a property value
      // (a discovered data class in the merged catalog). Try the structured
      // value first — a `null` result means it is not a structured type, so it
      // falls through to widget construction. Scoped to non-framework types, so
      // a framework value (`Offset`, `EdgeInsets`) never routes here (its
      // wire bytes are unchanged, emitted by the value-type path below).
      final structuredValue = _customStructuredValue.tryEmit(expr, issues);
      if (structuredValue != null) return structuredValue;
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

    final nativeDelegate = _nativeChildDelegate(expr, issues);
    if (nativeDelegate != null) return nativeDelegate;

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
    final shapeBorder = _normalizeNullablePresentDsl(
      issues,
      () => _structured.shapeBorder(
        prefix: prefix,
        typeName: typeName,
        constructorName: constructorName,
        args: expr.argumentList.arguments,
        issues: issues,
        loc: _locationOf(expr),
      ),
    );
    if (shapeBorder != null) return shapeBorder;
    if (_isShapeBorderClass(_classOfInstanceCreation(expr))) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message:
              'Unsupported ShapeBorder/OutlinedBorder value: '
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
    // resolved `package:flutter/` `Text`: a custom `Text` look-alike resolves
    // elsewhere and is rejected, and an unresolved `Text` (uncompilable source)
    // is never rewritten. The strong intl gate below would already block a
    // coherent build (intl resolved ⟹ Text resolved), but requiring resolution
    // here makes the no-bypass property explicit rather than inferred.
    if (expr.constructorName.type.name.lexeme != 'Text') return null;
    if (expr.constructorName.name != null) return null;
    final textClass = _classOfInstanceCreation(expr);
    if (textClass == null || !_isFrameworkValueType(textClass)) return null;

    final args = expr.argumentList.arguments;
    final positionals = args.whereType<Expression>().toList();
    if (positionals.isEmpty) return null;
    final first = positionals.first;
    if (first is! MethodInvocation) return null;

    // The strong element gate: the first positional is a real `package:intl/`
    // NumberFormat `.format()` call. `numberFormatAdoptTarget` returns null for
    // a custom look-alike, an unresolved reference, or a non-format call.
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
          if (a is! NamedArgument) {
            return defer(
              'the NumberFormat.currency call has a positional argument this '
              'version cannot extract',
            );
          }
          final param = a.name.lexeme;
          final widgetProp = paramToProp[param];
          if (widgetProp == null) {
            return defer(
              'the NumberFormat `$param:` argument has no faithful '
              '$adoptTarget equivalent',
            );
          }
          if (!_isConstFormatConfigLiteral(a.argumentExpression)) {
            return defer(
              'the NumberFormat `$param:` argument is not a compile-time '
              'constant; a dynamic format configuration is not adopted',
            );
          }
          config[widgetProp] = a.argumentExpression;
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
          if (a is! Expression || !_isConstFormatConfigLiteral(a)) {
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
    final valueExpr = fmtArgs.singleOrNull;
    if (valueExpr is! Expression) {
      return defer(
        'the .format(...) call does not take exactly one positional value',
      );
    }

    // Numeric-substitution gate: the value must render identically through
    // the substitute's `double` value slot. `NumberFormat.format` accepts
    // `num`, so the original
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
    final carried = <NamedArgument>[];
    for (final a in args.whereType<NamedArgument>()) {
      final name = a.name.lexeme;
      if (isDiscardedWidgetKeyArgument(a)) {
        _activeWidgetBuilder?.observeKey(a.argumentExpression);
        if (_activeWidgetBuilder == null) {
          return defer('the Text `key:` is not reproduced by $adoptTarget');
        }
        continue;
      }
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
      emitted.add('${_rfwMapKey(cfg.key)}: $lowered');
    }

    for (final a in carried) {
      final name = a.name.lexeme;
      // `style` decomposes through the entry's native recipe (TextStyle ->
      // flat props), exactly as a hand-authored substitute would.
      final decomposed = _tryDecompose(
        entry,
        name,
        a.argumentExpression,
        scratch,
      );
      if (decomposed != null) {
        emitted.addAll(decomposed);
        continue;
      }
      final lowered = lowerSlot(name, a.argumentExpression);
      if (lowered == null) {
        return defer('$adoptTarget has no `$name` property');
      }
      emitted.add('${_rfwMapKey(name)}: $lowered');
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
        message:
            'Auto-adopted the `$adoptTarget` catalog widget for a '
            'Text(NumberFormat.${ctorName ?? ''}(...).format(...)) number '
            'formatting idiom — the substitute runs the same formatting, so '
            'the rendered output is identical. The emitted blob references '
            '$adoptTarget, not Text.',
        location: _locationOf(expr),
      ),
    );

    return _catalogCall(entry, emitted);
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
        message:
            'Could not auto-adopt the `$adoptTarget` catalog widget for '
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
    final typeName = instanceCreationTypeName(expr);
    final constructorName = instanceCreationMemberName(expr);
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
      widgetClass: cls,
    );
  }

  String? _tryTextRichMethodInvocation(
    MethodInvocation expr,
    List<Issue> issues,
  ) {
    final target = expr.target;
    if (target is! SimpleIdentifier || !isTextRichInvocation(expr)) return null;

    final cls =
        _classOfMethodInvocation(expr) ??
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
      widgetClass: cls,
    );
  }

  String _textRich({
    required NodeList<Argument> args,
    required Expression anchor,
    required String? flutterType,
    required List<Issue> issues,
    ClassElement? widgetClass,
    bool occurrenceScoped = false,
  }) {
    final scope = _walk.measurementScope;
    if (scope != null && !occurrenceScoped && widgetClass != null) {
      final saved = _walk;
      _walk = _walk.copyWith(
        measurementScope: null,
        measurementWidget: scope.widget(widgetClass),
        measurementWidgetList: null,
      );
      try {
        return _textRich(
          args: args,
          anchor: anchor,
          flutterType: flutterType,
          issues: issues,
          widgetClass: widgetClass,
          occurrenceScoped: true,
        );
      } finally {
        _walk = saved;
      }
    }
    final entry = _textRichEntry(flutterType);
    if (entry == null) {
      issues.add(
        Issue(
          code: IssueCode.unknownWidget,
          message:
              "Widget 'Text.rich' is not a known catalog widget. Add a "
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
          message:
              "Catalog widget '${entry.name}' must declare a "
              "'textSpan' PropertyType.inlineSpan slot for Text.rich.",
          location: _locationOf(anchor),
        ),
      );
      return '';
    }

    final positionals = args.whereType<Expression>().toList();
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
    final emitted = <String>['${_rfwMapKey(textSpanProp.name)}: $span'];
    for (final arg in args.whereType<NamedArgument>()) {
      final name = arg.name.lexeme;
      if (isDiscardedWidgetKeyArgument(arg)) {
        final key = _catalogNativeKey(entry, arg.argumentExpression, issues);
        if (key != null) emitted.add('key: $key');
        _activeWidgetBuilder?.observeKey(arg.argumentExpression);
        continue;
      }

      final before = issues.length;
      final decomposed = _tryDecompose(
        entry,
        name,
        arg.argumentExpression,
        issues,
      );
      if (issues.length > before) return '';
      if (decomposed != null) {
        emitted.addAll(decomposed);
        continue;
      }

      final prop = entry.properties.firstWhereOrNull((p) => p.name == name);
      if (prop == null) {
        if (_reportUndecomposableArgument(
          entry,
          name,
          arg.argumentExpression,
          issues,
        )) {
          return '';
        }
        issues.add(
          Issue(
            code: IssueCode.unknownProperty,
            message: _undeclaredPropertyMessage(entry, name),
            location: _locationOf(arg),
          ),
        );
        return '';
      }
      final value = _translateSlotValue(
        arg.argumentExpression,
        prop.type,
        issues,
        property: prop,
      );
      if (value.isEmpty && issues.length > before) return '';
      emitted.add('${_rfwMapKey(name)}: $value');
    }

    return _catalogCall(entry, emitted);
  }

  WidgetEntry? _textRichEntry(String? flutterType) {
    if (flutterType != null) {
      final resolved = catalog.widgets.firstWhereOrNull(
        (w) => w.flutterType == flutterType,
      );
      if (resolved != null) return resolved;
    }
    return kTextRichLowering.resolve(catalog).firstOrNull;
  }

  String? _textSpanMap(
    Expression expr,
    List<Issue> issues, {
    required int depth,
    List<Object> spanPath = const ['textSpan'],
    Map<Expression, List<List<Object>>>? recognizerSources,
    List<CollectionSemanticOccurrence> collectionOccurrences = const [],
  }) {
    recognizerSources ??= <Expression, List<List<Object>>>{};
    final stripped = _resolveBoundIdentifier(expr);
    if (depth > kMaxInlineSpanDepth) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message:
              'TextSpan tree exceeds kMaxInlineSpanDepth '
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
          message:
              'Whole TextSpan conditionals are not supported by this '
              'transpiler increment. Put the conditional on a carried span '
              'value, such as text: condition ? a : b.',
          location: _locationOf(stripped),
        ),
      );
      return null;
    }

    final spanArgs = _textSpanArguments(stripped, issues);
    if (spanArgs == null) return null;

    final spanClass = stripped is InstanceCreationExpression
        ? _classOfInstanceCreation(stripped)
        : stripped is MethodInvocation
        ? _classOfMethodInvocation(stripped)
        : null;
    final parts = <String>[];
    for (final positional in spanArgs.whereType<Expression>()) {
      issues.add(
        Issue(
          code: IssueCode.unknownProperty,
          message:
              'TextSpan positional arguments are not carried by the '
              'inlineSpan emitter. Use named text:, style:, and children: '
              'arguments only.',
          location: _locationOf(positional),
        ),
      );
      return null;
    }

    for (final arg in spanArgs.whereType<NamedArgument>()) {
      final name = arg.name.lexeme;
      if (!_kCarriedTextSpanProps.contains(name)) {
        _addTextSpanUncarriedPropIssue(name, arg, issues);
        return null;
      }

      switch (name) {
        case 'text':
          if (arg.argumentExpression is NullLiteral) continue;
          final before = issues.length;
          final value = _translateSlotValue(
            arg.argumentExpression,
            PropertyType.string,
            issues,
          );
          if (value.isEmpty && issues.length > before) return null;
          parts.add('text: $value');
        case 'style':
          if (arg.argumentExpression is NullLiteral) continue;
          final style = _textSpanStyleMap(arg.argumentExpression, issues);
          if (style == null) return null;
          parts.add('style: $style');
        case 'children':
          if (_resolveBoundIdentifier(arg.argumentExpression) is NullLiteral)
            continue;
          final children = _textSpanChildren(
            arg.argumentExpression,
            issues,
            depth,
            spanPath,
            recognizerSources,
            collectionOccurrences,
          );
          if (children == null) return null;
          parts.add('children: $children');
        case 'recognizer':
          if (_resolveBoundIdentifier(arg.argumentExpression) is NullLiteral)
            continue;
          final value = _textSpanRecognizerMap(
            arg.argumentExpression,
            issues,
            spanPath,
            recognizerSources,
            spanClass,
            collectionOccurrences,
          );
          if (value == null) return null;
          parts.add('recognizer: $value');
      }
    }

    return '{ ${parts.join(', ')} }';
  }

  NodeList<Argument>? _textSpanArguments(
    Expression expr,
    List<Issue> issues,
  ) {
    if (expr is InstanceCreationExpression) {
      final constructor = expr.constructorName.element;
      final name =
          constructor?.enclosingElement.name ?? instanceCreationTypeName(expr);
      final unnamed = constructor == null
          ? instanceCreationMemberName(expr) == null
          : constructor == constructor.enclosingElement.unnamedConstructor;
      if (name != 'TextSpan' || !unnamed) {
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
          message:
              "TextSpan.style requires the catalog's Text(style: "
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
          message:
              'TextSpan.style must be a TextStyle(...) value whose fields '
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
    List<Object> spanPath,
    Map<Expression, List<List<Object>>> recognizerSources,
    List<CollectionSemanticOccurrence> collectionOccurrences,
  ) {
    final budget = CollectionUnrollBudget();
    final resolution = _collectionSemanticProbe().resolve(
      expr,
      const {},
      budget,
    );
    if (resolution.workLimitExceeded) {
      _recordCollectionRefusal(budget.workRefusal(expr), issues);
      return null;
    }
    if (resolution.expression is NullLiteral) return 'null';
    if (resolution.expression is! ListLiteral) {
      issues.add(
        Issue(
          code: IssueCode.unsupportedCollectionFlow,
          message:
              'TextSpan.children requires an admitted bounded list expression.',
          location: _locationOf(expr),
        ),
      );
      return null;
    }
    final before = issues.length;
    final saved = _inSpanCollection;
    _inSpanCollection = true;
    try {
      final result = _translateWithBindings(
        resolution.expression,
        resolution.bindings,
        issues,
        (list, sink) => _listLiteral(
          list as ListLiteral,
          sink,
          itemType: PropertyType.inlineSpan,
          budget: budget,
          emitLeaf: (occurrence, ordinal) => _translateWithBindings(
            occurrence.terminalExpression,
            occurrence.bindings,
            sink,
            (child, childIssues) =>
                _textSpanMap(
                  child,
                  childIssues,
                  depth: depth + 1,
                  spanPath: [...spanPath, 'children', ordinal],
                  recognizerSources: recognizerSources,
                  collectionOccurrences: [...collectionOccurrences, occurrence],
                ) ??
                '',
          ),
        ),
      );
      return issues.length == before ? result : null;
    } finally {
      _inSpanCollection = saved;
    }
  }

  String? _textSpanRecognizerMap(
    Expression expression,
    List<Issue> issues,
    List<Object> spanPath,
    Map<Expression, List<List<Object>>> recognizerSources,
    InterfaceElement? spanClass,
    List<CollectionSemanticOccurrence> collectionOccurrences,
  ) {
    try {
      final resolved = _resolveBoundIdentifier(expression);
      if (isBorrowedTextSpanRecognizer(resolved)) {
        final reference =
            _nativeBindingRead(expression, type: 'flutter.GestureRecognizer') ??
            _tryNativeCallValue(
              resolved,
              issues,
              type: 'flutter.GestureRecognizer',
            );
        if (reference == null)
          throw ArgumentError(
            'A borrowed recognizer requires an installed binding.',
          );
        return '{ borrowed: $reference }';
      }
      final recipe = readTextSpanRecognizer(
        expression,
        resolve: _resolveBoundIdentifier,
        bindings: [
          ..._walk.paramBindings.values,
          ..._walk.inlined.localBindings.values,
        ],
      );
      final evaluation = <Object>[
        for (final occurrence in collectionOccurrences) ...[
          for (final step in occurrence.structuralPath)
            (step.node, step.kind, step.ordinal),
          for (final step in occurrence.identitySourceProvenance)
            (step.source, step.kind),
        ],
      ];
      final previous = recognizerSources.putIfAbsent(
        recipe.constructor,
        () => [],
      );
      if (previous.any(
        (key) => const ListEquality<Object>().equals(key, evaluation),
      )) {
        throw ArgumentError(
          'Sharing a recognizer between spans requires installed ownership.',
        );
      }
      previous.add(evaluation);
      final parts = <String>['kind: ${_stringLiteral(recipe.kind)}'];
      for (final entry in recipe.configuration.entries) {
        final value = _resolveBoundIdentifier(entry.value);
        if (entry.key == 'supportedDevices') {
          if (value is NullLiteral) {
            parts.add('supportedDevices: null');
            continue;
          }
          if (value is! SetOrMapLiteral || value.isMap)
            throw ArgumentError(
              'supportedDevices requires a static native PointerDeviceKind set.',
            );
          final names = <String>[];
          for (final item in value.elements) {
            if (item is! Expression)
              throw ArgumentError(
                'supportedDevices requires static enum members.',
              );
            final member = _resolveBoundIdentifier(item);
            final field = _unwrapPropertyAccessor(_enumMemberElement(member));
            final owner = field?.enclosingElement;
            final name = _enumMemberName(member);
            if (name == null ||
                !const {
                  'touch',
                  'mouse',
                  'stylus',
                  'invertedStylus',
                  'trackpad',
                  'unknown',
                }.contains(name) ||
                (owner != null &&
                    (owner is! EnumElement ||
                        owner.name != 'PointerDeviceKind' ||
                        owner.library.identifier != 'dart:ui'))) {
              throw ArgumentError(
                'supportedDevices requires exact native PointerDeviceKind members.',
              );
            }
            names.add(_stringLiteral(name));
          }
          parts.add('supportedDevices: [${names.join(', ')}]');
        } else {
          final before = issues.length;
          final lowered = _translateSlotValue(
            value,
            entry.key == 'duration' ? PropertyType.duration : PropertyType.real,
            issues,
          );
          if (lowered.isEmpty || issues.length > before) return null;
          parts.add(
            '${entry.key}: ${entry.key.endsWith('SlopTolerance') ? RfwConstructorPresenceEncoder.supplied(lowered) : lowered}',
          );
        }
      }
      for (final entry in recipe.callbacks.entries) {
        final element = recipe.callbackElements[entry.key];
        var scope = _walk.measurementWidget?.nestedValue(spanPath);
        for (final occurrence in collectionOccurrences) {
          scope = scope?.enterCollectionOccurrence(occurrence);
        }
        final occurrence = element == null || spanClass == null
            ? null
            : scope?.widget(spanClass).event(element);
        final marker = occurrence == null
            ? null
            : measurementRouteEmissionPlan?.markerFor(occurrence);
        final detailType =
            kTextSpanRecognizerDetailCallbacks[recipe.kind]?[entry.key];
        if (detailType != null) {
          if (_resolveBoundIdentifier(entry.value) is NullLiteral) continue;
          final callback =
              _nativeBindingRead(entry.value, type: detailType) ??
              _tryNativeCallValue(entry.value, issues, type: detailType);
          if (callback == null)
            throw ArgumentError(
              'A detail callback requires an installed typed binding.',
            );
          parts.add('${entry.key}: $callback');
          if (marker != null) {
            final measurement = _measurementTapEvent(
              marker,
              occurrence!,
              entry.value,
              issues,
            );
            if (measurement.isEmpty) return null;
            parts.add('${entry.key}Measurement: $measurement');
          }
          continue;
        }
        if (marker != null && _handlerArms(entry.value) > 1)
          throw ArgumentError('A measured span callback requires one handler.');
        final saved = _measuredEventOccurrence;
        final savedCallback = _inSpanRecognizerCallback;
        _inSpanRecognizerCallback = true;
        _measuredEventOccurrence = occurrence ?? saved;
        final String lowered;
        try {
          lowered = _translateSlotValue(
            entry.value,
            PropertyType.event,
            issues,
          );
        } finally {
          _inSpanRecognizerCallback = savedCallback;
          _measuredEventOccurrence = saved;
        }
        if (lowered.isEmpty) return null;
        final emitted = marker == null
            ? lowered
            : _measuredEventHandler(
                lowered,
                marker,
                occurrence!,
                entry.value,
                issues,
              );
        parts.add('${entry.key}: $emitted');
      }
      return '{ ${parts.join(', ')} }';
    } on BuilderLoweringException catch (error) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'TextSpan.recognizer: ${error.reason}',
          location: _locationOf(error.node),
        ),
      );
      return null;
    } on ArgumentError catch (error) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'TextSpan.recognizer: ${error.message}',
          location: _locationOf(expression),
        ),
      );
      return null;
    }
  }

  void _addTextSpanUncarriedPropIssue(
    String name,
    NamedArgument arg,
    List<Issue> issues,
  ) {
    final knownDeferred = _kDeferredTextSpanProps.contains(name)
        ? ' This property is intentionally deferred in this increment.'
        : '';
    issues.add(
      Issue(
        code: IssueCode.unknownProperty,
        message:
            'Text.rich inline-span emission carries only TextSpan '
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
        message:
            'Text.rich requires its positional argument to be a '
            'TextSpan(...) tree.',
        location: _locationOf(expr),
      ),
    );
  }

  void _addNonFlutterTextRichIssue(Expression expr, List<Issue> issues) {
    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message:
            "'${expr.toSource()}' does not resolve to package:flutter's "
            'Text.rich. A custom class named Text is not emitted as the '
            'framework rich-text widget.',
        location: _locationOf(expr),
      ),
    );
  }

  void _addNonFlutterTextSpanIssue(Expression expr, List<Issue> issues) {
    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message:
            "'${expr.toSource()}' does not resolve to package:flutter's "
            'TextSpan. A custom class named TextSpan is not emitted as an '
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
  }) => cls == null
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

    if (isSystemUiOverlayStyleCopyWith(expr)) {
      return _systemUiOverlayStyle(expr, issues);
    }
    if (isIconThemeDataCopyWith(expr) || isIconThemeDataLerp(expr)) {
      return _iconThemeData(expr, issues);
    }

    if (isUnsupportedCommerceHelperCall(expr)) {
      issues.add(unsupportedCommerceHelperIssue(expr, _locationOf(expr)));
      return '';
    }
    // `context.surfaceEvent(...)` lowers as the event helper it is.
    if (isContextSurfaceEvent(expr)) {
      final element = expr.methodName.element;
      final helper = element == null
          ? helpers.findByNameOnly(method)
          : helpers.find(method, element.library?.identifier ?? '');
      if (helper != null) {
        final helperArgs = _translateOnboardingEventArgs(expr, issues);
        if (helperArgs == null) return '';
        return _safeHelperTranslate(expr, helper, helperArgs, issues);
      }
    }

    final callable = expr.methodName.element;
    final owner = callable?.enclosingElement;
    if (callable is MethodElement &&
        callable.isStatic &&
        owner is ClassElement) {
      final identity = _flutterTypeOfClass(
        owner,
        constructorName: callable.name,
      );
      if (catalog.widgets.any((entry) => entry.flutterType == identity)) {
        return _catalogWidgetConstruction(
          widgetName: owner.name!,
          flutterType: identity,
          widgetClass: owner,
          constructorName: callable.name,
          args: args,
          issues: issues,
          anchor: expr,
        );
      }
    }

    // Inline helpers captured by resolved element identity, including static calls.
    // Run before static value substitution so captured widget helpers inline.
    final helper = _walk.inlined.helpers[expr.methodName.element];
    // A call that reads an argument that runs code more than once is not
    // inlined: the widget around it renders in the app as written.
    if (helper != null && !_repeatsCode(expr)) {
      return _inlineHelperBody(helper, expr, issues);
    }

    // A helper refused for a named prelude shape reports that shape
    // rather than falling through as an unrecognised widget.
    final helperElement = expr.methodName.element;
    final helperRefusal =
        isArtifactHelperInvocation(
          expr,
          admittedHelperPackages: _admittedHelperPackages,
        )
        ? refusedHelperDefinitionsIn(expr)[helperElement] ??
              recordedHelperRefusal(helperElement!)
        : null;
    if (helperRefusal != null) {
      issues.add(
        Issue(
          code: IssueCode.customWidgetInliningDeferred,
          capabilityGapSubject: 'helper:${expr.methodName.name}',
          message:
              "The helper '${_helperName(expr)}' cannot be inlined: "
              '$helperRefusal.',
          location: _locationOf(expr),
        ),
      );
      return '';
    }

    final textRich = _tryTextRichMethodInvocation(expr, issues);
    if (textRich != null) return textRich;

    // Number/currency formatting: a `NumberFormat.<ctor>(...).format(<value>)`
    // call on the real intl `NumberFormat` defers with a diagnostic that NAMES
    // the catalog widget to adopt (RestagePrice / RestageFormattedNumber).
    // Element-gated on `package:intl/` so a custom class named NumberFormat
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
    // whose target class resolves to a non-framework library is a custom
    // static-method look-alike (a real framework value construction parses as
    // an InstanceCreationExpression, handled there); route it to widget
    // construction (defer). A `target == null` bare call and an unresolved
    // target keep the name-based recognition (the synthetic-test affordance).
    if (target is SimpleIdentifier && !_frameworkOrUnresolved(target.element)) {
      // A static method is never a construction of its owner.
      if (expr.methodName.element case final MethodElement helper
          when helper.isStatic) {
        final reason =
            isInArtifactHelperPackage(
              expr,
              helper,
              admittedHelperPackages: _admittedHelperPackages,
            )
            ? 'a helper must return a widget or a value of a class type'
            : 'it is declared outside this package and the dependency '
                  'packages that publish custom Restage widgets';
        issues.add(
          Issue(
            code: IssueCode.customWidgetInliningDeferred,
            capabilityGapSubject: 'helper:$method',
            message:
                "The helper '${target.name}.$method' cannot be inlined: "
                '$reason.',
            location: _locationOf(expr),
          ),
        );
        return '';
      }
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
      final shapeBorder = _normalizeNullablePresentDsl(
        issues,
        () => _structured.shapeBorder(
          prefix: target.name,
          typeName: method,
          constructorName: null,
          args: args,
          issues: issues,
          loc: _locationOf(expr),
        ),
      );
      if (shapeBorder != null) return shapeBorder;
    }

    // `Border.<factory>` reaching here is an unsupported Border factory —
    // `Border.all` and the default `Border(...)` are handled by the table.
    if (target is SimpleIdentifier && target.name == 'Border') {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message:
              'Unsupported Border factory: Border.$method. '
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
          message:
              'Unsupported Color factory: Color.$method. '
              'Supported: Color(0xAARRGGBB), Color.fromARGB, Color.fromRGBO.',
          location: _locationOf(expr),
        ),
      );
      return '';
    }

    // Helper-call recognition: a free-function call with no target whose name
    // and declaring library are both registered in the helper table. This runs
    // BEFORE the catalog widget construction path so that recognized helpers
    // are never accidentally routed as widget lookups.
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
        if (_kScreenEventHelperNames.contains(helper.name)) {
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
          final distributed = _tryDistributeConditionalValueHelper(
            expr,
            helper,
            issues,
          );
          if (distributed != null) return distributed;
        }
        final positional = <String>[];
        final named = <String, String>{};
        for (final a in expr.argumentList.arguments) {
          if (a is NamedArgument) {
            named[a.name.lexeme] = _translateHelperArgument(
              a.argumentExpression,
              issues,
            );
          } else {
            positional.add(
              _translateHelperArgument(a.argumentExpression, issues),
            );
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
          message: _wholeTextThemeStyleRead(segments)
              ? "The theme read '$path' reads a whole TextStyle. A slot that "
                    'takes a TextStyle accepts it and binds each field; this '
                    'one does not, so read the fields individually — '
                    "'$path.{${kThemeContractTextThemeFieldKinds.keys.join(', ')}}'."
              : "The theme read '$path' is not part of the published "
                    "'data.theme.*' contract. Supported reads cover the "
                    "'colorScheme' colour roles, 'iconTheme.{color, size}', "
                    "'defaultTextStyle.<field>', 'textTheme.<style>.<field>' "
                    "where <field> is one of "
                    "{${kThemeContractTextThemeFieldKinds.keys.join(', ')}}, "
                    "and 'brightness'.",
          location: location,
        ),
      );
      return '';
    }
    return 'data.theme.$path';
  }

  /// Whether [segments] name a published text-theme style with no field —
  /// `textTheme.titleLarge`, a whole `TextStyle` the contract does not carry.
  bool _wholeTextThemeStyleRead(List<String> segments) =>
      segments.length == 2 &&
      segments.first == 'textTheme' &&
      kThemeContractTextThemeStyles.contains(segments[1]);

  /// Recognises a device read through the canonical [deviceRead] walk.
  DeviceRead? _recognizeDeviceRead(Expression expr) =>
      deviceRead(expr, bindings: _walk.inlined.localBindings);

  /// Lowers a recognised device read to its `data.device.<path>` reference,
  /// refusing a read outside the published contract.
  String _deviceRead(DeviceRead read, Expression expr, List<Issue> issues) {
    final path = read.path;
    if (path == null || !kDeviceContractPaths.contains(path)) {
      issues.add(_deviceReadOutOfContractIssue(expr));
      return '';
    }
    // A custom widget reads its OWN context, which sits below whatever the
    // screen composes it under, so the mount-point inset is not its value.
    if (_kContextDependentDevicePaths.contains(path) &&
        (_walk.classKey != null ||
            (_hoist != null &&
                _hoist!.analyzer.analyze(expr) is! HoistEvaluable))) {
      issues.add(
        Issue(
          code: IssueCode.themeReadOutOfContract,
          message:
              "The device read '${expr.toSource()}' needs the screen's "
              'root context. Read it in the screen and pass the value down.',
          location: _locationOf(expr),
        ),
      );
      return '';
    }
    return 'data.device.$path';
  }

  /// Context-dependent snapshot reads that require the authored root context.
  static const Set<String> _kKeyboardAndAccessibilityPaths = {
    'viewInsetsTop',
    'viewInsetsBottom',
    'viewInsetsLeft',
    'viewInsetsRight',
    'boldText',
    'disableAnimations',
    'accessibleNavigation',
    'highContrast',
  };

  static const Set<String> _kContextDependentDevicePaths = {
    'safeAreaTop',
    'safeAreaBottom',
    'safeAreaLeft',
    'safeAreaRight',
    'viewPaddingTop',
    'viewPaddingBottom',
    'viewPaddingLeft',
    'viewPaddingRight',
    ..._kKeyboardAndAccessibilityPaths,
  };

  Issue _deviceReadOutOfContractIssue(Expression expr) => Issue(
    code: IssueCode.themeReadOutOfContract,
    message:
        "The device read '${expr.toSource()}' is not part of the "
        "published 'data.device.*' contract. Supported reads are "
        '`MediaQuery.sizeOf(context).width|height|shortestSide|'
        'longestSide`, '
        '`MediaQuery.paddingOf(context).top|bottom|left|right`, '
        '`MediaQuery.viewPaddingOf(context).top|bottom|left|right`, '
        '`MediaQuery.viewInsetsOf(context).top|bottom|left|right`, '
        'the accessibility flag helpers, '
        '`MediaQuery.devicePixelRatioOf(context)`, '
        '`MediaQuery.orientationOf(context)` (and the equivalent '
        '`MediaQuery.of(context)` chains), '
        '`Localizations.localeOf(context).languageCode|countryCode`, and '
        '`defaultTargetPlatform`.',
    location: _locationOf(expr),
  );

  /// Refuses a condition using an operator the blob's data language lacks.
  Issue _deviceConditionIssue(Expression expr, String reason) => Issue(
    code: IssueCode.themeReadOutOfContract,
    message:
        "The condition '${expr.toSource()}' cannot be expressed in "
        'the shipped blob: $reason. The blob matches device data by '
        'equality only, on the platform identifier, the orientation, and '
        'the locale subtags.',
    location: _locationOf(expr),
  );

  String _translateHelperArgument(Expression expr, List<Issue> issues) {
    final descriptorId = _constDescriptorId(expr);
    if (descriptorId != null) return _stringLiteral(descriptorId);
    return _translate(expr, issues);
  }

  Map<Element, Expression> get _scalarConstantBindings => <Element, Expression>{
    ..._walk.inlined.localBindings,
    ..._walk.paramBindings,
  };

  Object? _foldScalarConstant(Expression expression) => tryFoldScalarConstant(
    expression,
    localBindings: _scalarConstantBindings,
  );

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
      final value = a.argumentExpression;
      if (_stripParens(value) is ConditionalExpression) {
        if (condIndex != null) {
          issues.add(
            Issue(
              code: IssueCode.unrecognizedMethodCall,
              message:
                  "'${helper.name}' has more than one conditional "
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
    final slotExpr = condArg.argumentExpression;
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
      final valueExpr = i == condIndex ? stripped : a.argumentExpression;
      final translated = _translateHelperArgument(valueExpr, issues);
      if (a is NamedArgument) {
        named[a.name.lexeme] = translated;
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
      if (arg is NamedArgument) {
        named[arg.name.lexeme] = _translateHelperArgument(
          arg.argumentExpression,
          issues,
        );
        continue;
      }
      if (positional.isEmpty) {
        final descriptorId = _onboardingEventDescriptorId(
          arg.argumentExpression,
        );
        if (descriptorId == null) {
          issues.add(
            Issue(
              code: IssueCode.unrecognizedMethodCall,
              message:
                  'Expected a const SurfaceEvent, a static field or a '
                  'top-level constant; got ${arg.toSource()}.',
              location: _locationOf(arg),
            ),
          );
          return null;
        }
        if (kReservedCommerceEventNames.contains(descriptorId)) {
          issues.add(
            unsupportedCommerceEventIssue(descriptorId, _locationOf(arg)),
          );
          return null;
        }
        _currentFiredEvents?.add(
          surfaceEventConstant(arg.argumentExpression)!,
        );
        positional.add(_stringLiteral(descriptorId));
        continue;
      }
      // A scalar event value is wrapped under the reserved `value` key so the
      // event always carries a string-keyed args map: a bare scalar would be
      // coerced to an empty map at the runtime boundary (and a flow
      // `.capture()` reads the reserved `value` key). A map literal already
      // carries named fields, so it is emitted as-is.
      // A map value is the event's arguments, as the SDK delivers it, so
      // its keys must be Strings.
      final mapType = _dartCoreMapType(arg.argumentExpression.staticType);
      final keyType = mapType?.typeArguments.first;
      if (mapType != null &&
          (!keyType!.isDartCoreString ||
              keyType.nullabilitySuffix != NullabilitySuffix.none)) {
        issues.add(
          Issue(
            code: IssueCode.invalidEventConfiguration,
            message:
                'An event value that is a map becomes the event '
                'arguments, so its keys must be Strings; got '
                '${mapType.getDisplayString()}. Declare it as a '
                'Map<String, ...>.',
            location: _locationOf(arg),
          ),
        );
        return null;
      }
      final value = arg.argumentExpression;
      // A map literal is the event's own argument object, entry by entry,
      // even where the mount computes its values.
      final translated = value is SetOrMapLiteral && value.isMap
          ? _setOrMapLiteral(value, issues)
          : _translateHelperArgument(value, issues);
      positional.add(
        mapType != null
            ? translated
            : '{ $kCapturedEventValueKey: $translated }',
      );
    }
    return HelperCallArgs(positional: positional, named: named);
  }

  String? _onboardingEventDescriptorId(Expression expr) {
    final field = surfaceEventConstant(expr);
    return field?.computeConstantValue()?.getField('id')?.toStringValue();
  }

  String? _constDescriptorId(Expression expr) {
    // An event constructed in place, `const SurfaceEvent<T>('id')`.
    if (expr is InstanceCreationExpression &&
        (expr.isConst || expr.inConstantContext) &&
        expr.constructorName.type.element?.name == 'SurfaceEvent') {
      final arguments = expr.argumentList.arguments;
      if (arguments.length != 1 || arguments.single is NamedArgument) {
        return null;
      }
      final id = tryFoldScalarConstant(arguments.single.argumentExpression);
      return id is String ? id : null;
    }
    // A named event, a static field or a top-level constant.
    if (surfaceEventConstant(expr) case final event?) {
      return event.computeConstantValue()?.getField('id')?.toStringValue();
    }
    Element? element;
    if (expr is SimpleIdentifier) {
      element = expr.element;
    } else if (expr is PrefixedIdentifier) {
      element = identifierElement(expr.identifier);
    } else if (expr is PropertyAccess) {
      element = identifierElement(expr.propertyName);
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
    switch (scanRootModalSheet(expr)) {
      case RootModalSheetLowers(:final sheet):
        return sheet;
      case RootModalSheetRefused(:final reason):
        issues.add(_modalSheetUnsupportedIssue(reason, expr));
        return null;
      case RootModalSheetNone():
        return null;
    }
  }

  List<RecognisedNavigation> _findRootNavigationTriggers(
    Expression expr,
    List<Issue> issues, {
    required Element? buildContextParameter,
  }) {
    final scanner = _RootNavigationTriggerScanner(
      buildContextParameter: buildContextParameter,
      canonicalPaywallIdFor: canonicalPaywallIdFor,
    );
    expr.accept(scanner);
    // A split surface runs a navigation it cannot lower as an action.
    if (scanner.resultDrop != null && _islands == null) {
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
    final existingEventNames = _authoredEventNames(expr).toSet();
    if (triggers.isNotEmpty && !existingEventNames.contains('skip')) {
      issues.add(
        _navigationUnsupportedIssue(
          'a screen-navigation paywall lowers to a flow that needs a '
          'dismiss event to terminate; add a skip affordance '
          '(`context.surfaceEvent(PaywallEvents.skip)`)',
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

  Iterable<String> _authoredEventNames(Expression expr) {
    final names = <String>[];
    void collect(Expression expression, InlinedDefinitions inlined) {
      final scanner = _PaywallEventNameScanner(helpers, inlined: inlined);
      expression.accept(scanner);
      names.addAll(scanner.names);
    }

    collect(expr, _walk.inlined);
    for (final blueprint in _reachableCustomWidgetBlueprints(expr)) {
      visitStaticallyAdmittedExpressions(
        blueprint.buildExpression,
        inlined: blueprint.inlined,
        admittedHelperPackages: _admittedHelperPackages,
        visit: (expression, bindings) {
          if (expression is! MethodInvocation) return;
          final name = _authoredEventCallName(expression);
          if (name != null) names.add(name);
        },
      );
    }
    return names;
  }

  Iterable<CustomWidgetBlueprint> _reachableCustomWidgetBlueprints(
    Expression expr,
  ) sync* {
    final pending = [
      for (final widgetClass in customWidgetClassesIn(
        expr,
        inlined: _walk.inlined,
        admittedHelperPackages: _admittedHelperPackages,
      ))
        customWidgetKey(widgetClass),
    ];
    final visited = <String>{};
    for (var index = 0; index < pending.length; index++) {
      final key = pending[index];
      if (!visited.add(key)) continue;
      final classification = customWidgetClassifications[key];
      if (classification is! ComposableWidget ||
          classification.requiredMechanisms
              .difference(_kImplementedMechanisms)
              .isNotEmpty) {
        continue;
      }
      final blueprint = customWidgetBlueprints[key];
      if (blueprint == null) continue;
      yield blueprint;
      pending.addAll(classification.composedCustomWidgets);
    }
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
    final sheetEntries = kModalSheetLowering.resolve(catalog);
    final sheetEntry = sheetEntries.firstWhereOrNull(
      (entry) => entry.library == WidgetLibrary.material,
    );
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
      if (value != null) {
        emitted.add('${_rfwMapKey(property.name)}: $value');
      }
    }
    return _catalogCall(sheetEntry, emitted);
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
      if (arg is! NamedArgument) {
        issues.add(
          _modalSheetUnsupportedIssue(
            'positional arguments have no declarative sheet equivalent',
            arg,
          ),
        );
        return null;
      }
      final name = arg.name.lexeme;
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
          builderExpr ??= arg.argumentExpression;
        case ModalSheetArgumentDisposition.pageBuilder:
          pageBuilderExpr ??= arg.argumentExpression;
        case ModalSheetArgumentDisposition.map:
          mapped[name] = arg.argumentExpression;
        case ModalSheetArgumentDisposition.animationStyle:
          final animation = _modalSheetAnimationStyleSlots(
            arg.argumentExpression,
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
        _walk = _walk.copyWith(
          modalSheetCloseFlag: context.flagName,
          measurementScope: context.triggerOccurrence?.sheetBuilder(),
          measurementWidget: null,
          measurementWidgetList: null,
        );
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
        instanceCreationTypeName(expr) != 'AnimationStyle' ||
        instanceCreationMemberName(expr) != null ||
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
      if (arg is! NamedArgument) {
        issues.add(
          _modalSheetUnsupportedIssue(
            'AnimationStyle accepts only named fields in sheet lowering',
            arg,
          ),
        );
        return null;
      }
      final fieldName = arg.name.lexeme;
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
      if (isCurve && _supportedCurveName(arg.argumentExpression) == null) {
        issues.add(
          _modalSheetUnsupportedIssue(
            '$fieldName must be a supported Curves.* value',
            arg.argumentExpression,
          ),
        );
        return null;
      }
      final value = _emitModalSheetSlot(
        sheetEntry,
        slotName,
        arg.argumentExpression,
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
      if (!_frameworkOrUnresolved(identifierElement(expr.prefix))) return null;
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
    final property = sheetEntry.properties.firstWhereOrNull(
      (candidate) => candidate.name == propName,
    );
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

  String? _shaderMaskAlias({
    required ClassElement? widgetClass,
    required Expression anchor,
    required List<Issue> issues,
  }) {
    if (!libraryIsFlutter(widgetClass) ||
        anchor is! InstanceCreationExpression) {
      return null;
    }
    final target = kShaderMaskLowering.resolve(catalog).firstOrNull;
    if (target == null) return null;
    final (:arguments, :reason) = recogniseShaderMask(
      anchor,
      resolve: _resolveBoundIdentifier,
    );
    if (arguments == null) {
      issues.add(
        Issue(
          code: IssueCode.shaderMaskFormUnsupported,
          capabilityGapSubject: 'widget:${widgetClass!.name}',
          message:
              "`${widgetClass.name}` renders from your app's code because "
              '$reason.',
          location: _locationOf(anchor),
        ),
      );
      return '';
    }
    final emitted = <String>[];
    for (final property in target.properties) {
      final expression = arguments[property.name];
      if (expression == null) continue;
      final before = issues.length;
      String value;
      if (property.name == 'gradient' &&
          expression is InstanceCreationExpression) {
        final args = expression.argumentList.arguments
            .where(
              (arg) => arg is! NamedArgument || arg.name.lexeme != 'transform',
            )
            .toList();
        final type = expression.constructorName.element!.enclosingElement.name!;
        value = type == 'LinearGradient'
            ? _structured.linearGradient(args, issues, _locationOf(expression))
            : _recipeDispatcher.tryTranslate(
                recipeKey(library: null, typeName: type, variant: null),
                args,
                issues,
                _locationOf(expression),
              )!;
      } else {
        value = _translateSlotValue(
          expression,
          property.type,
          issues,
          property: property,
        );
      }
      if (issues.skip(before).any((issue) => !issue.code.isInformational)) {
        return '';
      }
      emitted.add(
        '${_rfwMapKey(property.name)}: '
        '${RfwConstructorPresenceEncoder.encode(property, value)}',
      );
    }
    return _catalogCall(target, emitted);
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
  /// (the caller continues to the `unknownWidget` path) for a custom
  /// look-alike, an unresolved construction, or a catalog without RestagePager.
  /// Otherwise returns the emitted `RestagePager(...)` DSL, or `''` after
  /// recording a deferral Issue.
  String? _pageViewAlias({
    required ClassElement? widgetClass,
    required String? constructorName,
    required NodeList<Argument> args,
    required Expression anchor,
    required List<Issue> issues,
  }) {
    // Strict identity: only the real `package:flutter` PageView aliases.
    if (!libraryIsFlutter(widgetClass)) return null;
    // The alias target must be present in the merged catalog; without it (a
    // catalog lacking restage.material) this is not aliasable here.
    final pager = kPagerLowering.resolve(catalog).firstOrNull;
    if (pager == null) return null;

    final loc = _locationOf(anchor);
    void defer(String reason, {String? subject}) {
      issues.add(
        Issue(
          code: IssueCode.pageViewFormUnsupported,
          capabilityGapSubject: subject ?? 'widget:PageView',
          message:
              'PageView could not be lowered to the declarative paged '
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
      if (arg is! NamedArgument) {
        defer('a positional argument has no declarative equivalent');
        return '';
      }
      final name = arg.name.lexeme;
      if (isDiscardedWidgetKeyArgument(arg)) {
        if (!isLegacyScalarWidgetKey(arg.argumentExpression)) {
          defer('the native key requires the original PageView owner');
          return '';
        }
        _keyNotKept(arg.argumentExpression, issues);
        return '';
      }
      switch (name) {
        case 'children':
          childrenExpr = arg.argumentExpression;
        case 'scrollDirection':
          scrollDirectionExpr = arg.argumentExpression;
        case 'pageSnapping':
          pageSnappingExpr = arg.argumentExpression;
        case 'onPageChanged':
          onPageChangedExpr = arg.argumentExpression;
        case 'controller':
          {
            final flat = _pageControllerFlatten(arg.argumentExpression);
            if (flat == null) {
              defer(
                "the 'controller' argument must be a literal "
                'PageController(initialPage:, viewportFraction:) with no '
                'other arguments',
              );
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
      final value = _translateSlotValue(expr, p.type, issues, property: p);
      if (value.isEmpty && issues.length > before) return false;
      emitted.add(
        '${_rfwMapKey(propName)}: '
        '${RfwConstructorPresenceEncoder.encode(p, value)}',
      );
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

    return _catalogCall(pager, emitted);
  }

  /// Recognises an inline literal `package:flutter` `PageController(...)` for
  /// the PageView alias's controller flatten. Returns the `initialPage` and
  /// `viewportFraction` value expressions (either may be `null` when the author
  /// omitted it — RestagePager's defaults equal PageController's), or `null`
  /// for any non-flattenable shape: a non-construction (a bound identifier, a
  /// factory call), a custom `PageController` look-alike, a named
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
      if (arg is! NamedArgument) return null; // a positional argument
      switch (arg.name.lexeme) {
        case 'initialPage':
          initialPage = arg.argumentExpression;
        case 'viewportFraction':
          viewportFraction = arg.argumentExpression;
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
  /// custom look-alike, an unresolved construction, or a catalog without
  /// RestageDraggableSheet. Otherwise returns the emitted DSL, or `''` after
  /// recording a deferral Issue.
  String? _draggableScrollableSheetAlias({
    required ClassElement? widgetClass,
    required String? constructorName,
    required NodeList<Argument> args,
    required Expression anchor,
    required List<Issue> issues,
  }) {
    // Strict identity: only the real `package:flutter` DraggableScrollableSheet
    // aliases; a custom look-alike falls through to `unknownWidget`.
    if (!libraryIsFlutter(widgetClass)) return null;
    final sheet = kDraggableSheetLowering.resolve(catalog).firstOrNull;
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
          message:
              'DraggableScrollableSheet could not be lowered to the '
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
    final hasControllerSlot = sheet.properties.any(
      (p) => p.name == 'controller',
    );
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
      if (arg is! NamedArgument) {
        defer('a positional argument has no declarative equivalent');
        return '';
      }
      final name = arg.name.lexeme;
      final disposition = kDraggableSheetArgumentDispositions[name];
      if (disposition == null) {
        defer("the '$name' argument has no RestageDraggableSheet equivalent");
        return '';
      }
      switch (disposition) {
        case DraggableSheetArgumentDisposition.drop:
          break;
        case DraggableSheetArgumentDisposition.map:
          mapped[name] = arg.argumentExpression;
        case DraggableSheetArgumentDisposition.builder:
          builderExpr = arg.argumentExpression;
        case DraggableSheetArgumentDisposition.snapSizes:
          if (!_isAbsentOrEmptyList(arg.argumentExpression)) {
            defer(
              kDraggableSheetSnapSizesUnsupportedReason,
              subject: 'param:snapSizes',
            );
            return '';
          }
        case DraggableSheetArgumentDisposition.shouldCloseOnMinExtent:
          final value = _staticBoolLiteral(arg.argumentExpression);
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
        final value = _translateSlotValue(
          expr,
          property.type,
          issues,
          property: property,
        );
        if (value.isEmpty && issues.length > before) return '';
        emitted.add('${_rfwMapKey(property.name)}: $value');
      }
    }

    return _catalogCall(sheet, emitted);
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
  /// caller continues to the `unknownWidget` path) for a custom look-alike,
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
    // custom look-alike falls through to `unknownWidget`.
    if (!libraryIsFlutter(widgetClass)) return null;
    final isRadio = widgetName == 'RadioGroup';
    final lowering = isRadio ? kRadioGroupLowering : kDropdownLowering;
    final target = lowering.resolve(catalog).firstOrNull;
    if (target == null) return null;

    final loc = _locationOf(anchor);
    void defer(String reason) {
      issues.add(
        Issue(
          code: IssueCode.singleSelectFormUnsupported,
          capabilityGapSubject: 'widget:$widgetName',
          message:
              '$widgetName could not be lowered to the declarative '
              'single-select surface: $reason.',
          location: loc,
        ),
      );
    }

    // A named constructor (`.adaptive`, etc.) is not the carrier form.
    if (constructorName != null) {
      defer(
        "the named constructor '$widgetName.$constructorName' is not "
        'supported (the unnamed constructor only)',
      );
      return '';
    }

    // The recogniser reads the construction's `<T>` type argument (the
    // String-keyed gate) as well as its argument list, so it takes the whole
    // creation expression. The dispatch only reaches here for an
    // `InstanceCreationExpression` anchor.
    if (anchor is! InstanceCreationExpression) return null;
    final outcome = isRadio
        ? recogniseRadioGroup(anchor)
        : recogniseDropdown(anchor);
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
            message:
                'two options emit the same value ($value) — each option '
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
            message:
                'the catalog ${target.name} has no onChanged property; '
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

    return _catalogCall(target, parts);
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
  /// caller continues to the `unknownWidget` path) for a custom look-alike,
  /// an unresolved construction, or a catalog without RestageToggleButtons.
  /// Otherwise returns the emitted DSL, or `''` after recording a deferral.
  String? _toggleButtonsAlias({
    required ClassElement? widgetClass,
    required Expression anchor,
    required List<Issue> issues,
  }) {
    // Strict identity: only the real `package:flutter` widget aliases; a
    // custom look-alike falls through to `unknownWidget`.
    if (!libraryIsFlutter(widgetClass)) return null;
    final target = kToggleButtonsLowering.resolve(catalog).firstOrNull;
    if (target == null) return null;

    final loc = _locationOf(anchor);
    void defer(String reason) {
      issues.add(
        Issue(
          code: IssueCode.toggleButtonsFormUnsupported,
          capabilityGapSubject: 'widget:ToggleButtons',
          message:
              'ToggleButtons could not be lowered to the declarative '
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
            message:
                'the catalog ${target.name} has no $propName property; '
                'regenerate the catalog.',
            location: _locationOf(expr),
          ),
        );
        return false;
      }
      final before = issues.length;
      final value = _translateSlotValue(expr, p.type, issues, property: p);
      if (value.isEmpty && issues.length > before) return false;
      emitted.add(
        '${_rfwMapKey(propName)}: '
        '${RfwConstructorPresenceEncoder.encode(p, value)}',
      );
      return true;
    }

    if (!emit('children', recognised.children)) return '';
    if (!emit('isSelected', recognised.isSelected)) return '';

    final onPressed = recognised.onPressed;
    if (onPressed != null && onPressed is! NullLiteral) {
      if (!emit('onPressed', onPressed)) return '';
    }

    return _catalogCall(target, emitted);
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
  /// caller continues to the `unknownWidget` path) for a custom look-alike,
  /// an unresolved construction, or a catalog without the target widget.
  /// Otherwise returns the emitted DSL, or `''` after recording a deferral.
  String? _segmentedButtonAlias({
    required ClassElement? widgetClass,
    required Expression anchor,
    required List<Issue> issues,
  }) {
    // Strict identity: only the real `package:flutter` widget aliases; a
    // custom look-alike falls through to `unknownWidget`.
    if (!libraryIsFlutter(widgetClass)) return null;
    final target = kSegmentedButtonLowering.resolve(catalog).firstOrNull;
    if (target == null) return null;

    final loc = _locationOf(anchor);
    void defer(String reason) {
      issues.add(
        Issue(
          code: IssueCode.segmentedButtonFormUnsupported,
          capabilityGapSubject: 'widget:SegmentedButton',
          message:
              'SegmentedButton could not be lowered to the declarative '
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
            message:
                'two segments emit the same value ($value) — each segment '
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
            message:
                'the catalog ${target.name} has no onChanged property; '
                'regenerate the catalog',
            location: _locationOf(onSelectionChanged),
          ),
        );
        return '';
      }
      // The event slot unwraps the closure; a host-imperative body defers
      // loud there rather than lowering as a value.
      final value = slot(
        onSelectionChanged,
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

    return _catalogCall(target, parts);
  }

  /// Whether [expr] is a single-expression closure whose body is a call to a
  /// registered event helper; the lookup mirrors [_methodInvocation].
  bool _wrapsEventHelper(Expression expr) {
    final stripped = _stripParens(expr);
    if (stripped is! FunctionExpression) return false;
    final body = stripped.body;
    if (body is! ExpressionFunctionBody) return false;
    final call = _stripParens(body.expression);
    if (call is! MethodInvocation) return false;
    if (isContextSurfaceEvent(call)) return true;
    if (call.target != null) return false;
    final element = call.methodName.element;
    final helper = element != null
        ? helpers.find(call.methodName.name, element.library?.identifier ?? '')
        : helpers.findByNameOnly(call.methodName.name);
    return helper?.returnCategory == HelperReturnCategory.voidCallback;
  }

  /// Unwraps a single-expression callback closure to its body expression so the
  /// declarative event lowers at the event slot.
  /// `(s) => context.surfaceEvent(x)` yields `context.surfaceEvent(x)`; a
  /// direct call (no closure)
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

  /// The event to lower at an event slot, or null when the slot must refuse.
  /// Refuses a `(v) => <event>` whose event reads the closure's own parameter.
  Expression? _eventSlotExpression(Expression rawExpr, List<Issue> issues) {
    if (!_wrapsEventHelper(rawExpr)) return rawExpr;
    final event = _eventBodyOf(rawExpr);
    final closure = _stripParens(rawExpr);
    if (closure is! FunctionExpression) return event;
    final call = _stripParens(event) as MethodInvocation;
    final helper = isContextSurfaceEvent(call)
        ? 'context.surfaceEvent'
        : call.methodName.name;
    final declared = <Element>{
      for (final parameter
          in closure.parameters?.parameters ?? const <FormalParameter>[])
        if (parameter.declaredFragment?.element case final element?) element,
    };
    if (declared.isNotEmpty) {
      final census = _ClosureParameterCensus(declared);
      event.accept(census);
      if (census.found) {
        issues.add(
          Issue(
            code: IssueCode.invalidEventConfiguration,
            message:
                'The callback value reaches the event automatically. '
                'Pass `$helper(...)` directly to the callback, without a '
                'closure.',
            location: _locationOf(rawExpr),
          ),
        );
        return null;
      }
    }
    _currentEventClosureNotices?.add(
      Issue(
        code: IssueCode.idiomAutoSubstituted,
        message:
            'Lowered a closure around `$helper(...)` to its event. '
            'Pass `$helper(...)` directly to the callback instead: the '
            'closure returns the callback without calling it, so the '
            "compiled widget never fires the event in your app's own build.",
        location: _locationOf(rawExpr),
        buildNoticeIdentity:
            '$kEventClosureNoticePrefix${_locationOf(rawExpr)}',
      ),
    );
    return event;
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
    required NodeList<Argument> args,
    required Expression anchor,
    required List<Issue> issues,
    String? constructorName,
    bool occurrenceScoped = false,
  }) {
    var splitPlaced = false;
    final occurrenceScope = _walk.measurementScope;
    // A function call is not a widget occurrence: it renders from the app.
    final callsFunction =
        anchor is MethodInvocation &&
        switch (anchor.methodName.element) {
          ConstructorElement() => false,
          ExecutableElement() => true,
          _ => false,
        };
    if (!occurrenceScoped && occurrenceScope != null && !callsFunction) {
      if (widgetClass == null) {
        issues.add(
          Issue(
            code: IssueCode.invalidEventConfiguration,
            message:
                'A measured widget occurrence must resolve to its exact '
                'class declaration.',
            location: _locationOf(anchor),
          ),
        );
        return '';
      }
      final saved = _walk;
      _walk = _walk.copyWith(
        measurementScope: null,
        measurementWidget: occurrenceScope.widget(widgetClass),
        measurementWidgetList: null,
      );
      try {
        return _catalogWidgetConstruction(
          widgetName: widgetName,
          flutterType: flutterType,
          widgetClass: widgetClass,
          args: args,
          anchor: anchor,
          issues: issues,
          constructorName: constructorName,
          occurrenceScoped: true,
        );
      } finally {
        _walk = saved;
      }
    }
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
      final callee = _resolvedCallee(anchor);
      if (callee == null) {
        // Unresolved source keeps the name lookup.
        entry = candidates.firstOrNull;
      } else if (callee is InterfaceElement) {
        // A resolved class binds only the entry declaring that same class.
        final identity = _classIdentity(callee);
        entry = candidates.firstWhereOrNull(
          (candidate) => _entryClassIdentity(candidate) == identity,
        );
        // Silent-regression guard. A DESIGN-PACKAGE class whose canonical
        // identity matches nothing while its bare name does means the mapping
        // and the catalog disagree about where a framework symbol lives.
        final declaringLibrary = callee.library.identifier;
        if (entry == null &&
            candidates.isNotEmpty &&
            kDesignPackageLibraryPrefixes.any(declaringLibrary.startsWith)) {
          final named = candidates.first;
          issues.add(
            Issue(
              code: IssueCode.designPackageIdentityDrift,
              message:
                  "'$widgetName' is declared in '$declaringLibrary', "
                  'which canonicalises to an identity no catalog entry '
                  'carries, while the name alone matches the catalog entry '
                  "'${named.library.namespace}.${named.name}'. Binding by name "
                  'would render a different type. The identity mapping needs '
                  'to be reconciled with the package, most likely because a '
                  'symbol moved between files.',
              location: _locationOf(anchor),
            ),
          );
          return '';
        }
      }
    }
    if (entry != null) _recordRfwCatalogConstructorOrigin(entry);
    _CustomWidgetFactoryRoute? customWidgetFactoryRoute;
    // A registered custom widget that can inline still inlines —
    // its composition travels in the blob and renders with no runtime factory.
    // One that cannot inline (imperative or not yet supported) falls
    // through to the catalog reference below, resolved by the runtime-
    // registered factory. Built-in catalog widgets are never custom widgets,
    // so they always reference (unchanged). Without this, emitting a custom
    // catalog would flip every registered widget — including inlinable ones —
    // to a reference across every surface.
    if (entry != null &&
        widgetClass != null &&
        WidgetLibrary.builtInByNamespace(entry.library.namespace) == null) {
      final key = customWidgetKey(widgetClass);
      final classification = customWidgetClassifications[key];
      // Unclassified, it renders from its registered factory.
      if (classification == null) {
        _currentPlacedCustomWidgets?.add(widgetClass);
        _currentPlacedCustomWidgetSites?.add(anchor);
      }
      if (classification != null) {
        final identity = (
          classKey: key,
          remoteLibrary: entry.library.namespace,
        );
        customWidgetFactoryRoute = _forcedCustomWidgetFactoryRoutes[identity];
        final issueMark = issues.length;
        final inlined = _tryInlineCustomWidget(
          classification,
          key,
          args,
          anchor,
          issues,
          catalogEntry: entry,
        );
        if (inlined != null && inlined.isNotEmpty) return inlined;
        if (customWidgetFactoryRoute == null) {
          final inlineIssues = issues.sublist(issueMark)
            ..sort((left, right) {
              final codeOrder = left.code.name.compareTo(right.code.name);
              if (codeOrder != 0) return codeOrder;
              final messageOrder = left.message.compareTo(right.message);
              if (messageOrder != 0) return messageOrder;
              return left.location.compareTo(right.location);
            });
          customWidgetFactoryRoute = (
            widgetName: entry.name,
            reason: inlineIssues.isEmpty
                ? _customWidgetFactoryReason(
                    classification,
                    entry.name,
                    anchor,
                  )
                : 'Restage could not inline it: '
                      '${_withoutFinalPeriod(inlineIssues.first.message)}',
          );
        }
        // A body that inlined unmeasured keeps inlining when measured, so a
        // refusal only measurement raises is the author's to fix, with every
        // other cause the body reported.
        if (issues.skip(issueMark).any(_measuredRefusals.contains)) {
          return '';
        }
        // Not inlined (imperative, not yet supported, or an inline-attempt
        // diagnostic): discard any inline-specific diagnostics and reference
        // the registered catalog entry below.
        issues.removeRange(issueMark, issues.length);
        _currentPlacedCustomWidgets?.add(widgetClass);
        _currentPlacedCustomWidgetSites?.add(anchor);
        // A split widget's delivered definition shadows that entry.
        if (splitWidgetDefinitions[key] case final split?) {
          splitPlaced = true;
          _currentWidgetDefinitions?.addAll(split.definitions);
          _currentWidgetDefinitionStates?.addAll(split.states);
          for (final origin in split.origins) {
            _currentRfwCatalogConstructorOrigins?.putIfAbsent(
              origin.constructorName,
              () => origin,
            );
          }
          _currentReferencedCustomLibraries?.addAll(split.libraries);
          // The events its build fires are the placing surface's too.
          _currentFiredEvents?.addAll(split.fired);
        }
      }
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
          issues.add(
            _withUnbuiltCatalogNote(
              _customWidgetIssue(
                classification,
                widgetClass,
                widgetName,
                anchor,
              ),
              widgetClass,
            ),
          );
          return '';
        }
      }
      if (widgetName == 'ShaderMask' || widgetName == 'ColorFiltered') {
        final aliased = _shaderMaskAlias(
          widgetClass: widgetClass,
          anchor: anchor,
          issues: issues,
        );
        if (aliased != null) return aliased;
      }
      // PageView → RestagePager alias. A vanilla-Flutter `PageView(...)` is the
      // faithful Flutter spelling of the declarative paged surface; recognise
      // it and lower to the `RestagePager` catalog widget (carry-all-or-defer).
      // Placed AFTER the custom-widget classification check (a custom
      // `@RestageWidget` named `PageView` still inlines above) and gated on the
      // resolved `package:flutter` identity inside the alias — a custom
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
      // inside the alias — a custom look-alike or an unresolved construction
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
      // inside the alias — a custom look-alike or an unresolved construction
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
      // `package:flutter` identity inside the alias — a custom look-alike or
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
      // inside the alias — a custom look-alike or an unresolved construction
      // returns `null` and falls through below.
      if (widgetName == 'SegmentedButton') {
        final aliased = _segmentedButtonAlias(
          widgetClass: widgetClass,
          anchor: anchor,
          issues: issues,
        );
        if (aliased != null) return aliased;
      }
      final statePackage = _appStateBuilderPackage(widgetClass);
      final unknown = Issue(
        code: IssueCode.unknownWidget,
        capabilityGapSubject: 'widget:$widgetName',
        message: statePackage != null
            ? "`$widgetName` (package:$statePackage) renders from your "
                  "app's code because it builds from your app's state."
            : "`$widgetName` renders from your app's code because it isn't "
                  "in Restage's widget catalog. Try promoting it with "
                  '`restage widget promote ${_locationOf(anchor)}` if '
                  'designers should place it on other screens.',
        location: _locationOf(anchor),
      );
      issues.add(unknown);
      return '';
    }

    // A referenced CUSTOM (non-built-in) catalog widget resolves against its
    // imported library at runtime — record it so the emitter imports it. A
    // built-in widget needs no extra import (the preamble covers it), and an
    // inlinable custom widget returned above (it carries its own definition).
    if (WidgetLibrary.builtInByNamespace(entry.library.namespace) == null) {
      // The reference emits the widget's bare name into the blob. If that name
      // collides with a surface root or a DIFFERENT catalog widget, the
      // reference is ambiguous: name resolution would bind it to the root (a
      // self-recursion) or to the other widget (a silent wrong render), never
      // to this custom widget. Fail loud rather than emit an
      // admitted-but-wrong reference. (The inline path raises the same class of
      // diagnostic; a widget that reaches the reference path — imperative, or
      // not yet inlineable with a rolled-back diagnostic — needs
      // its own guard here. Locals capture the promoted `entry` so the closure
      // below can read them.)
      final refName = entry.name;
      final refFlutterType = entry.flutterType;
      final conflict =
          (refName == paywallRootWidgetName ||
              refName == onboardingScreenRootWidgetName)
          ? 'a reserved surface root widget name'
          : catalog.widgets.any(
              (w) => w.name == refName && w.flutterType != refFlutterType,
            )
          ? 'another catalog widget with the same name'
          : null;
      if (conflict != null) {
        issues.add(
          Issue(
            code: IssueCode.customWidgetNameCollision,
            message:
                "The custom widget '$refFlutterType' cannot be referenced: "
                "its name '$refName' collides with $conflict. Rename the "
                'widget class so its name is unique across the catalog and '
                'the surface roots.',
            location: refFlutterType,
          ),
        );
        return '';
      }
      _currentReferencedCustomLibraries?.add(entry.library.namespace);
      if (widgetClass != null) {
        final identity = (
          classKey: customWidgetKey(widgetClass),
          remoteLibrary: entry.library.namespace,
        );
        _currentCustomWidgetReferences?.add(identity);
        if (customWidgetFactoryRoute == null &&
            firstAnnotation(widgetClass, 'RestageWidget') != null) {
          customWidgetFactoryRoute = (
            widgetName: entry.name,
            reason: 'Restage could not read its build()',
          );
        }
        if (customWidgetFactoryRoute != null) {
          _recordCustomWidgetFactoryRoute(
            identity,
            customWidgetFactoryRoute,
          );
        }
      }
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
        for (final a in args.whereType<NamedArgument>()) a.name.lexeme,
      };
      for (final e in implied.entries) {
        if (!authorNamed.contains(e.key)) {
          emitted.add('${_rfwMapKey(e.key)}: ${e.value}');
        }
      }
    }

    // Positional args map to the catalog's `positional: true` properties in
    // declaration order. Properties without `positional: true` accept named
    // args only; they would otherwise capture the first positional slot and
    // collide with their own named-arg form (e.g. Icon's `size` would absorb
    // the IconData positional and then duplicate when `size:` is also named).
    final positionals = args.whereType<Expression>().toList();
    String? textSpan;
    final sourceParameters = _walk.measurementWidget == null
        ? const <Expression, FormalParameterElement>{}
        : _resolvedSourceParameters(anchor, args);
    final positionalProps = entry.properties
        .where((p) => p.positional)
        .toList();
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
      if (entry.name == 'Text' &&
          propName == 'text' &&
          _needsTextSpans(positionals[i])) {
        textSpan = _textSpanValue(positionals[i], issues);
        if (textSpan.isEmpty) return '';
        continue;
      }
      final isIconSlot = positionalProp.synthetic == _kIconDataSynthetic;
      if (isIconSlot) _resetResolvedIcon();
      final value = _joinsStringParts(positionalProp, positionals[i])
          ? _joinedStringValue(positionals[i], issues)
          : _translateSlotValue(
              positionals[i],
              positionalProp.type,
              issues,
              property: positionalProp,
              sourceParameter: sourceParameters[positionals[i]],
            );
      if (value.isEmpty && issues.length > before) return '';
      emitted.add(
        '${_rfwMapKey(propName)}: '
        '${RfwConstructorPresenceEncoder.encode(positionalProp, value)}',
      );
      if (isIconSlot) {
        final family = _iconFontFamilyEmission(entry);
        if (family != null) emitted.add(family);
        final mirroring = _iconMatchTextDirectionEmission(entry);
        if (mirroring != null) emitted.add(mirroring);
      }
    }

    // Native keys cross as declared references to their installed objects.
    for (final a in args.whereType<NamedArgument>()) {
      final name = a.name.lexeme;
      if (isDiscardedWidgetKeyArgument(a)) {
        final key = _catalogNativeKey(entry, a.argumentExpression, issues);
        if (key != null) emitted.add('key: $key');
        _activeWidgetBuilder?.observeKey(a.argumentExpression);
        continue;
      }
      if (entry.name == 'Text' &&
          name == 'text' &&
          _needsTextSpans(a.argumentExpression)) {
        textSpan = _textSpanValue(a.argumentExpression, issues);
        if (textSpan.isEmpty) return '';
        continue;
      }

      if (name == 'decoration' && _hasSynthetic(entry, _kInputDecorationText)) {
        final lowered = _inputDecoration(entry, a.argumentExpression, issues);
        if (lowered == null) return '';
        emitted.addAll(lowered);
        continue;
      }
      final keyboard = entry.properties.firstWhereOrNull(
        (p) => p.name == name && p.synthetic == _kTextInputTypeSynthetic,
      );
      if (keyboard != null) {
        final value = _textInputType(keyboard, a.argumentExpression, issues);
        if (value == null) return '';
        emitted.add('${_rfwMapKey(name)}: $value');
        continue;
      }
      if (entry.properties.any(
        (p) =>
            p.name == name && p.synthetic == _kScrollNotificationDepthSynthetic,
      )) {
        final depth = _scrollNotificationDepth(a.argumentExpression, issues);
        if (depth == null) return '';
        if (depth.isNotEmpty) emitted.add('${_rfwMapKey(name)}: $depth');
        continue;
      }

      // Structured-type decomposition. If this argument matches one of the
      // entry's native recipes, hoist mapped structured fields to flat
      // properties on the outer widget. Inner values route back through
      // `_translate`, so per-type value translators compose recursively.
      final decomposed = _withinNativeValueBoundary(
        !entry.flutterType.startsWith('package:flutter/') &&
            !entry.flutterType.startsWith('dart:ui#'),
        () => _tryDecompose(entry!, name, a.argumentExpression, issues),
      );
      if (decomposed != null) {
        emitted.addAll(decomposed);
        continue;
      }

      final prop = entry.properties.where((p) => p.name == name).firstOrNull;
      if (prop == null) {
        if (_reportUndecomposableArgument(
          entry,
          name,
          a.argumentExpression,
          issues,
        )) {
          continue;
        }
        issues.add(
          Issue(
            code: IssueCode.unknownProperty,
            message: _undeclaredPropertyMessage(entry, name),
            location: _locationOf(a),
          ),
        );
        continue;
      }
      final before = issues.length;
      final isIconSlot = prop.synthetic == _kIconDataSynthetic;
      if (isIconSlot) _resetResolvedIcon();
      final value = _withinNativeValueBoundary(
        !entry.flutterType.startsWith('package:flutter/') &&
            !entry.flutterType.startsWith('dart:ui#') &&
            !const {
              PropertyType.widget,
              PropertyType.widgetList,
              PropertyType.widgetBuilder,
              PropertyType.event,
            }.contains(prop.type),
        () => _joinsStringParts(prop, a.argumentExpression)
            ? _joinedStringValue(a.argumentExpression, issues)
            : _translateSlotValue(
                a.argumentExpression,
                prop.type,
                issues,
                property: prop,
                sourceParameter: sourceParameters[a.argumentExpression],
              ),
      );
      if (value.isEmpty && issues.length > before) return '';
      // An asymmetric `BorderRadius` value (a direct `borderRadius:` arg, e.g.
      // ClipRRect) fans out onto the per-corner slots instead of the uniform
      // one — never a single `borderRadius:` carrying the sentinel.
      final beforeSplice = issues.length;
      final corners = _spliceBorderRadiusCorners(
        entry,
        value,
        issues,
        _locationOf(a),
      );
      if (corners != null) {
        if (issues.length > beforeSplice) return '';
        emitted.addAll(corners);
        continue;
      }
      emitted.add(
        '${_rfwMapKey(name)}: '
        '${RfwConstructorPresenceEncoder.encode(prop, value)}',
      );
      if (isIconSlot) {
        final family = _iconFontFamilyEmission(entry);
        if (family != null) emitted.add(family);
        final mirroring = _iconMatchTextDirectionEmission(entry);
        if (mirroring != null) emitted.add(mirroring);
      }
    }

    // A `PreferredSizeWidget` slot cannot report a size of its own once it
    // is rendered, so the authored bar's height travels beside it.
    final barHeight = _preferredSizeHeightEmission(entry, args, issues);
    if (barHeight != null) emitted.add(barHeight);

    if (_baselineWithoutTextBaseline(entry, args)
        case final Expression alignment) {
      issues.add(
        Issue(
          code: IssueCode.missingRequiredSlot,
          message:
              '${entry.name} aligns its children on their baselines but '
              'sets no textBaseline, which Flutter requires. Add '
              'textBaseline: TextBaseline.alphabetic.',
          location: _locationOf(alignment),
        ),
      );
      return '';
    }

    // Text that joins strings renders the same run as Text.rich with spans.
    if (textSpan != null) {
      return _interpolatedTextRich(
        textSpan,
        emitted,
        anchor,
        issues,
        localIssueStart,
      );
    }

    // An app widget the design builds keeps its identity on both paths.
    if (widgetClass != null &&
        firstAnnotation(widgetClass, 'RestageWidget') != null) {
      emitted.addAll(
        _appWidgetPlacement(
          anchor,
          entry,
          issues,
          split: splitPlaced ? widgetClass : null,
        ),
      );
    }
    return _catalogCall(entry, emitted);
  }

  // Whether [loop] gives each item a map the build records its positions
  // into: a list the mount walks, or a screen input's list of objects.
  bool _keysItems(_RuntimeLoopBinding loop) =>
      loop.item != null &&
      (_hoist!.values[loop.item]?.kind == HoistValueKind.items ||
          loop.shape is HostDataObjectShape);

  // Where a mount's build places the app widget [entry] at [node], through
  // its wrapper when it's the [split] class: the name and loop positions it
  // is keyed by on both paths, recorded for the build's copy. None outside a
  // mount. In a loop whose items the mount doesn't walk it adds [issues], so
  // the loop walks them in the mount.
  List<String> _appWidgetPlacement(
    Expression node,
    WidgetEntry entry,
    List<Issue> issues, {
    ClassElement? split,
  }) {
    final session = _islands;
    final hoist = _hoist;
    final loops = _walk.runtimeLoops;
    if (session == null || hoist == null) return const [];
    // The recorded copy can't place a widget inside another widget's build,
    // so that widget renders from the app.
    if (_definitionFrames.lastOrNull case final frame?) {
      issues.add(
        Issue(
          code: IssueCode.nestedStateIsland,
          message:
              "`${entry.name}` (${_locationOf(node)}) is an app widget inside "
              "`${frame.name}`, so `${frame.name}` renders from the app. Try "
              "passing `${entry.name}` to `${frame.name}` as a widget argument "
              "from the screen's build.",
          location: _locationOf(node),
        ),
      );
      return const [];
    }
    if (loops.any((loop) => !_keysItems(loop))) {
      issues.add(
        Issue(
          code: IssueCode.unsupportedCollectionFlow,
          message:
              "`${entry.name}` (${_locationOf(node)}) is inside a loop whose "
              "items Restage can't track one by one, so its State would be "
              'lost when a new design is shown. Try passing the list in '
              "through the screen's constructor.",
          location: _locationOf(node),
        ),
      );
      return const [];
    }
    final scope = _walk.islandScope.join('>');
    final widget = islandWidgetType(node);
    final key = '$scope/$widget';
    final peers = [
      for (final entry in session.order)
        if (entry.key == key) entry.node,
    ];
    final ordinal = switch (peers.indexWhere((peer) => identical(peer, node))) {
      -1 => peers.length,
      final index => index,
    };
    if (ordinal == peers.length) session.order.add((key: key, node: node));
    final name = islandIdentity(session.surface, scope, widget, ordinal).name;
    if (!session.recordPlacements.any(
      (placed) => identical(placed.node, node),
    )) {
      _recordsWithoutDesignState(node, kind: _Recorded.widget);
      session.recordPlacements.add((
        name: name,
        node: node,
        calls: [..._callSites],
        items: loops.isEmpty ? null : loops.last.item,
        widget: entry.name,
        split: split != null,
        place: split == null
            ? '${kSdkPrefixMarker}RestageRecording.itself'
            : spellBesideClass(
                session.library,
                split.library.identifier,
                split.name ?? '',
                splitAppName(entry.name),
              ),
      ));
    }
    return [
      '$kPlacementNameArgument: ${jsonEncode(name)}',
      if (loops.isNotEmpty)
        '$kPlacementItemsArgument: [${[
          for (final loop in loops) '${loop.identifier}'
                '${_rfwPathPart(hoist.add(itemIndexValue(loop.item!, label: _itemIndexLabel(loop))).key)}',
        ].join(', ')}]',
    ];
  }

  /// The `crossAxisAlignment: CrossAxisAlignment.baseline` argument of a flex
  /// [entry] that has no `textBaseline`, or null.
  Expression? _baselineWithoutTextBaseline(
    WidgetEntry entry,
    NodeList<Argument> args,
  ) {
    if (!entry.properties.any((p) => p.name == 'textBaseline')) return null;
    Expression? alignment;
    for (final argument in args.whereType<NamedArgument>()) {
      switch (argument.name.lexeme) {
        case 'textBaseline':
          return null;
        case 'crossAxisAlignment':
          final value = _stripParens(argument.argumentExpression);
          final name = switch (value) {
            PrefixedIdentifier(:final identifier) => identifier.name,
            PropertyAccess(:final propertyName) => propertyName.name,
            DotShorthandPropertyAccess(:final propertyName) =>
              propertyName.name,
            _ => null,
          };
          if (name == 'baseline') alignment = value;
      }
    }
    return alignment;
  }

  bool _hasSynthetic(WidgetEntry entry, String strategy) =>
      entry.properties.any((p) => p.synthetic == strategy);

  /// The flat properties an `InputDecoration` lowers to, or null after an
  /// issue.
  List<String>? _inputDecoration(
    WidgetEntry entry,
    Expression source,
    List<Issue> issues,
  ) {
    final decoration = _stripParens(source);
    if (decoration is! InstanceCreationExpression ||
        decoration.constructorName.type.name.lexeme != 'InputDecoration' ||
        decoration.constructorName.name != null) {
      issues.add(_inputDecorationIssue('decoration', source));
      return null;
    }
    final emitted = <String>[];
    for (final argument in decoration.argumentList.arguments) {
      if (argument is! NamedArgument) {
        issues.add(_inputDecorationIssue('decoration', argument));
        return null;
      }
      final name = argument.name.lexeme;
      final value = argument.argumentExpression;
      final text = entry.properties.firstWhereOrNull(
        (p) => p.name == name && p.synthetic == _kInputDecorationText,
      );
      if (text != null) {
        final before = issues.length;
        final lowered = _translateSlotValue(
          value,
          text.type,
          issues,
          property: text,
        );
        if (issues.length > before) return null;
        emitted.add('${_rfwMapKey(name)}: $lowered');
        continue;
      }
      if (name == 'border') {
        final border = _inputBorderName(value);
        final slot = entry.properties.firstWhereOrNull(
          (p) => p.synthetic == _kInputBorderSynthetic,
        );
        if (border == null || slot == null) {
          issues.add(_inputDecorationIssue('border', value));
          return null;
        }
        emitted.add('${_rfwMapKey(slot.name)}: ${_stringLiteral(border)}');
        continue;
      }
      if (name == 'prefixIcon') {
        final prefix = _prefixIcon(entry, value, issues);
        if (prefix == null) return null;
        emitted.addAll(prefix);
        continue;
      }
      issues.add(_inputDecorationIssue(name, argument));
      return null;
    }
    return emitted;
  }

  // Bare `InputBorder.none`, `UnderlineInputBorder()` or
  // `OutlineInputBorder()`.
  String? _inputBorderName(Expression source) {
    final border = _stripParens(source);
    if (border is PrefixedIdentifier &&
        border.prefix.name == 'InputBorder' &&
        border.identifier.name == 'none') {
      return 'none';
    }
    if (border is InstanceCreationExpression &&
        border.constructorName.name == null &&
        border.argumentList.arguments.isEmpty) {
      return switch (border.constructorName.type.name.lexeme) {
        'UnderlineInputBorder' => 'underline',
        'OutlineInputBorder' => 'outline',
        _ => null,
      };
    }
    return null;
  }

  // `Icon(<icon>)`, lowered with the family and mirroring beside it.
  List<String>? _prefixIcon(
    WidgetEntry entry,
    Expression source,
    List<Issue> issues,
  ) {
    final icon = _stripParens(source);
    final codepoint = entry.properties.firstWhereOrNull(
      (p) => p.synthetic == _kInputDecorationPrefixIcon,
    );
    if (icon is! InstanceCreationExpression ||
        icon.constructorName.type.name.lexeme != 'Icon' ||
        icon.argumentList.arguments.length != 1 ||
        icon.argumentList.arguments.single is NamedArgument ||
        codepoint == null) {
      issues.add(_inputDecorationIssue('prefixIcon', source));
      return null;
    }
    _resetResolvedIcon();
    final before = issues.length;
    final value = _translateSlotValue(
      icon.argumentList.arguments.single.argumentExpression,
      PropertyType.integer,
      issues,
      property: codepoint,
    );
    if (issues.length > before) return null;
    final emitted = ['${_rfwMapKey(codepoint.name)}: $value'];
    final family = _resolvedIconFontFamily;
    final mirrors = _resolvedIconMatchTextDirection;
    _resetResolvedIcon();
    final familySlot = entry.properties.firstWhereOrNull(
      (p) => p.synthetic == _kInputDecorationPrefixIconFontFamily,
    );
    if (family != null && familySlot != null) {
      emitted.add('${_rfwMapKey(familySlot.name)}: ${_stringLiteral(family)}');
    }
    final mirrorSlot = entry.properties.firstWhereOrNull(
      (p) => p.synthetic == _kInputDecorationPrefixIconMatchTextDirection,
    );
    if (mirrors && mirrorSlot != null) {
      emitted.add('${_rfwMapKey(mirrorSlot.name)}: true');
    }
    return emitted;
  }

  /// The depth a `(n) => n.depth == <int>` scroll notification predicate
  /// accepts, `''` for Flutter's default predicate, or `null` after a
  /// diagnostic.
  String? _scrollNotificationDepth(Expression source, List<Issue> issues) {
    final expr = _resolveBoundIdentifier(source);
    if (expr is Identifier) {
      final element = expr.element;
      if (element is TopLevelFunctionElement &&
          element.name == 'defaultScrollNotificationPredicate' &&
          element.library.identifier == _kScrollNotificationLibrary) {
        return '';
      }
    }
    final depth = _scrollDepthComparison(expr);
    if (depth != null) {
      final before = issues.length;
      final value = _translateSlotValue(depth, PropertyType.integer, issues);
      if (issues.length == before && value.isNotEmpty) return value;
      return null;
    }
    issues.add(
      Issue(
        code: IssueCode.unknownProperty,
        message:
            'notificationPredicate supports '
            '`(notification) => notification.depth == <int>` and '
            "Flutter's defaultScrollNotificationPredicate.",
        location: _locationOf(source),
      ),
    );
    return null;
  }

  /// The non-null `int` compared with the notification's depth in a
  /// synchronous one-parameter predicate, or `null` for any other shape.
  Expression? _scrollDepthComparison(Expression expr) {
    if (expr is! FunctionExpression) return null;
    final parameters = expr.parameters?.parameters;
    final body = expr.body;
    if (parameters == null ||
        parameters.length != 1 ||
        !parameters.single.isRequiredPositional ||
        body.isAsynchronous ||
        body.isGenerator) {
      return null;
    }
    final notification = parameters.single.declaredFragment?.element;
    final result = switch (body) {
      ExpressionFunctionBody(:final expression) => expression,
      BlockFunctionBody(:final block)
          when block.statements.length == 1 &&
              block.statements.single is ReturnStatement =>
        (block.statements.single as ReturnStatement).expression,
      _ => null,
    };
    final comparison = result == null ? null : _stripParens(result);
    if (notification == null ||
        comparison is! BinaryExpression ||
        comparison.operator.lexeme != '==') {
      return null;
    }
    bool isDepth(Expression side) {
      final read = _stripParens(side);
      final (target, property) = switch (read) {
        PrefixedIdentifier(:final prefix, :final identifier) => (
          prefix,
          identifier,
        ),
        PropertyAccess(:final target?, :final propertyName) => (
          _stripParens(target),
          propertyName,
        ),
        _ => (null, null),
      };
      final getter = property?.element;
      return target is SimpleIdentifier &&
          target.element == notification &&
          getter is PropertyAccessorElement &&
          getter.name == 'depth' &&
          getter.library.identifier == _kScrollNotificationLibrary;
    }

    bool readsNotification(Expression side) {
      var found = false;
      side.accept(_ElementReferenceVisitor(notification, () => found = true));
      return found;
    }

    for (final (read, value) in [
      (comparison.leftOperand, comparison.rightOperand),
      (comparison.rightOperand, comparison.leftOperand),
    ]) {
      final type = value.staticType;
      if (isDepth(read) &&
          !readsNotification(value) &&
          type != null &&
          type.isDartCoreInt &&
          type.nullabilitySuffix == NullabilitySuffix.none) {
        return value;
      }
    }
    return null;
  }

  // A named `TextInputType` constant from the property's allowed values.
  String? _textInputType(
    PropertyEntry property,
    Expression source,
    List<Issue> issues,
  ) {
    final keyboard = _stripParens(source);
    final allowed = property.constraints.allowedValues ?? const <String>[];
    if (keyboard is PrefixedIdentifier &&
        keyboard.prefix.name == 'TextInputType' &&
        allowed.contains(keyboard.identifier.name)) {
      return _stringLiteral(keyboard.identifier.name);
    }
    issues.add(
      Issue(
        code: IssueCode.unknownProperty,
        message:
            "keyboardType must be one of TextInputType's named keyboards: "
            '${allowed.join(', ')}.',
        location: _locationOf(source),
      ),
    );
    return null;
  }

  Issue _inputDecorationIssue(String name, AstNode anchor) => Issue(
    code: IssueCode.unknownProperty,
    message:
        "InputDecoration's $name is unsupported here. Supported: "
        'hintText, labelText and helperText as text, border as '
        'InputBorder.none, UnderlineInputBorder() or '
        'OutlineInputBorder(), and prefixIcon as Icon(<icon>).',
    location: _locationOf(anchor),
  );

  /// Forgets what the last icon slot resolved to, before the next one runs.
  void _resetResolvedIcon() {
    _resolvedIconFontFamily = null;
    _resolvedIconMatchTextDirection = false;
  }

  /// The `iconFontFamily` emission for the codepoint slot just translated on
  /// [entry], or `null` when the icon is a Material one (the wire default) or
  /// [entry] carries no family slot to put it in.
  String? _iconFontFamilyEmission(WidgetEntry entry) {
    final family = _resolvedIconFontFamily;
    _resolvedIconFontFamily = null;
    if (family == null) return null;
    final slot = entry.properties.firstWhereOrNull(
      (p) => p.synthetic == _kIconFontFamilySynthetic,
    );
    if (slot == null) return null;
    return '${_rfwMapKey(slot.name)}: ${_stringLiteral(family)}';
  }

  /// The `iconMatchTextDirection` emission for the codepoint slot just
  /// translated on [entry], or `null` when the icon does not mirror (the wire
  /// default) or [entry] carries no mirroring slot to put it in.
  String? _iconMatchTextDirectionEmission(WidgetEntry entry) {
    final mirrors = _resolvedIconMatchTextDirection;
    _resolvedIconMatchTextDirection = false;
    if (!mirrors) return null;
    final slot = entry.properties.firstWhereOrNull(
      (p) => p.synthetic == _kIconMatchTextDirectionSynthetic,
    );
    if (slot == null) return null;
    return '${_rfwMapKey(slot.name)}: true';
  }

  /// The height emission for [entry]'s `PreferredSizeWidget` slot, read
  /// from the widget the author put in it. A height it cannot read is
  /// refused.
  String? _preferredSizeHeightEmission(
    WidgetEntry entry,
    NodeList<Argument> args,
    List<Issue> issues,
  ) {
    final heightProp = entry.properties.firstWhereOrNull(
      (p) => p.synthetic == kPreferredSizeHeightSyntheticStrategy,
    );
    if (heightProp == null) return null;
    final slot = entry.properties.firstWhereOrNull(
      (p) =>
          p.type == PropertyType.widget &&
          p.widgetType == kPreferredSizeWidgetType,
    );
    if (slot == null) return null;
    final slotArg = args.whereType<NamedArgument>().firstWhereOrNull(
      (a) => a.name.lexeme == slot.name,
    );
    if (slotArg == null) return null;
    final bottomHeightProp = entry.properties.firstWhereOrNull(
      (p) => p.synthetic == kAppBarBottomHeightSyntheticStrategy,
    );
    if (bottomHeightProp != null) {
      final heights = _appBarSlotHeights(
        slotArg.argumentExpression,
        heightProp,
        issues,
      );
      if (heights != null) {
        final toolbarHeightProp = entry.properties.firstWhere(
          (p) => p.synthetic == kAppBarToolbarHeightSyntheticStrategy,
        );
        return '${_rfwMapKey(heightProp.name)}: ${heights.height}, '
            '${_rfwMapKey(toolbarHeightProp.name)}: ${heights.toolbar}, '
            '${_rfwMapKey(bottomHeightProp.name)}: ${heights.bottom}';
      }
    }
    final height = _preferredHeightOf(
      slotArg.argumentExpression,
      heightProp,
      issues,
    );
    if (height == null) {
      issues.add(
        Issue(
          code: IssueCode.unknownProperty,
          message:
              "The height of '${entry.name}.${slot.name}' cannot be read "
              'from this widget, and the enclosing widget needs it before the '
              'slot lays out. Use an AppBar, a TabBar, or a PreferredSize '
              'stating its own height.',
          location: _locationOf(slotArg),
        ),
      );
      return null;
    }
    return '${_rfwMapKey(heightProp.name)}: ${height.dsl}';
  }

  ({String height, String toolbar, String bottom})? _appBarSlotHeights(
    Expression source,
    PropertyEntry heightProp,
    List<Issue> issues,
  ) {
    final expr = _resolveBoundIdentifier(source);
    if (expr is NullLiteral) {
      return (height: 'null', toolbar: 'null', bottom: 'null');
    }
    final initializer = _constIdentifierInitializer(expr);
    if (initializer != null) {
      return _appBarSlotHeights(initializer, heightProp, issues);
    }
    if (expr is ConditionalExpression) {
      final branches =
          <Expression, ({String height, String toolbar, String bottom})?>{};
      var refused = false;
      ({String height, String toolbar, String bottom})? heightsFor(
        Expression branch,
      ) => branches.putIfAbsent(branch, () {
        final heights = _appBarSlotHeights(branch, heightProp, issues);
        refused |= heights == null;
        return heights;
      });

      final heights = (
        height: _conditionalSwitch(
          expr,
          issues,
          (branch) => heightsFor(branch)?.height ?? 'null',
        ),
        toolbar: _conditionalSwitch(
          expr,
          issues,
          (branch) => heightsFor(branch)?.toolbar ?? 'null',
        ),
        bottom: _conditionalSwitch(
          expr,
          issues,
          (branch) => heightsFor(branch)?.bottom ?? 'null',
        ),
      );
      return refused ? null : heights;
    }
    final constructor = expr is InstanceCreationExpression
        ? expr.constructorName.element
        : null;
    final owner = constructor?.enclosingElement;
    if (owner?.name == 'AppBar' &&
        owner?.library.identifier ==
            'package:flutter/src/material/app_bar.dart' &&
        constructor?.name == 'new') {
      final args = (expr as InstanceCreationExpression).argumentList.arguments;
      final bottom = _namedArgument(args, 'bottom');
      final bottomHeight =
          bottom == null || _resolveBoundIdentifier(bottom) is NullLiteral
          ? (value: 0.0, dsl: '0.0')
          : _preferredHeightOf(bottom, heightProp, issues);
      if (bottomHeight == null) return null;
      final toolbar = _namedArgument(args, 'toolbarHeight');
      final toolbarHeight = toolbar == null
          ? 'null'
          : _translateSlotValue(
              toolbar,
              PropertyType.real,
              issues,
              property: heightProp,
            );
      // A nullable bottom height is supplied even when it evaluates to null.
      final bottomDsl = bottom != null && _mayAskNullHeight(bottom)
          ? RfwConstructorPresenceEncoder.supplied(bottomHeight.dsl)
          : bottomHeight.dsl;
      return (height: 'null', toolbar: toolbarHeight, bottom: bottomDsl);
    }
    final height = _preferredHeightOf(expr, heightProp, issues);
    return height == null
        ? null
        : (height: height.dsl, toolbar: 'null', bottom: 'null');
  }

  /// The height [widget] asks its parent for, with its folded value when
  /// the fragment is a literal. `null` when the height cannot be read.
  ({double? value, String dsl})? _preferredHeightOf(
    Expression widget,
    PropertyEntry heightProp,
    List<Issue> issues,
  ) {
    final resolved = _resolveBoundIdentifier(widget);
    if (resolved is NullLiteral) return (value: 0.0, dsl: '0.0');
    if (resolved is ConditionalExpression) {
      var refused = false;
      final dsl = _conditionalSwitch(resolved, issues, (branch) {
        final height = _preferredHeightOf(branch, heightProp, issues);
        refused |= height == null;
        return height?.dsl ?? 'null';
      });
      return refused ? null : (value: null, dsl: dsl);
    }
    final call = _widgetCallOf(resolved);
    if (call == null) return null;
    switch (call.name) {
      case 'AppBar':
        final toolbar = _namedArgument(call.args, 'toolbarHeight');
        final bar = _appBarToolbarHeight(toolbar, heightProp, issues);
        if (bar == null) return null;
        final bottom = _namedArgument(call.args, 'bottom');
        if (bottom == null || _resolveBoundIdentifier(bottom) is NullLiteral) {
          return bar;
        }
        final under = _preferredHeightOf(bottom, heightProp, issues);
        if (under?.value == null || bar.value == null) return null;
        final total = bar.value! + under!.value!;
        return (value: total, dsl: '$total');
      case 'PreferredSize':
        final declared = _namedArgument(call.args, 'preferredSize');
        return declared == null
            ? null
            : _realFragment(declared, heightProp, issues);
      case 'TabBar':
        final tabs = _namedArgument(call.args, 'tabs');
        if (tabs is! ListLiteral) return null;
        var tallest = kRestageTabHeight;
        for (final element in tabs.elements) {
          final height = _tabHeightOf(element, heightProp, issues);
          if (height == null) return null;
          tallest = math.max(tallest, height);
        }
        final total = tallest + kRestageTabIndicatorWeight;
        return (value: total, dsl: '$total');
      default:
        return null;
    }
  }

  /// Whether [widget] is a nested AppBar, possibly behind a conditional,
  /// whose toolbar height is a nullable runtime value.
  bool _mayAskNullHeight(Expression widget) {
    final expr = _resolveBoundIdentifier(widget);
    final initializer = _constIdentifierInitializer(expr);
    if (initializer != null) return _mayAskNullHeight(initializer);
    if (expr is ConditionalExpression) {
      return _mayAskNullHeight(expr.thenExpression) ||
          _mayAskNullHeight(expr.elseExpression);
    }
    final call = _widgetCallOf(expr);
    if (call?.name != 'AppBar') return false;
    final toolbar = _namedArgument(call!.args, 'toolbarHeight');
    return toolbar != null && _isNullableRuntime(toolbar);
  }

  bool _isNullableRuntime(Expression source) {
    final expr = _resolveBoundIdentifier(source);
    if (expr is NullLiteral) return false;
    final initializer = _constIdentifierInitializer(expr);
    if (initializer != null) return _isNullableRuntime(initializer);
    if (expr is ConditionalExpression) {
      return _isNullableRuntime(expr.thenExpression) ||
          _isNullableRuntime(expr.elseExpression);
    }
    return expr.staticType?.nullabilitySuffix == NullabilitySuffix.question;
  }

  /// Resolves the toolbar default before an AppBar's parent adds its height.
  ({double? value, String dsl})? _appBarToolbarHeight(
    Expression? source,
    PropertyEntry heightProp,
    List<Issue> issues,
  ) {
    const defaultHeight = (
      value: kRestageToolbarHeight,
      dsl: '$kRestageToolbarHeight',
    );
    if (source == null) return defaultHeight;
    final expr = _resolveBoundIdentifier(source);
    if (expr is NullLiteral) return defaultHeight;
    final initializer = _constIdentifierInitializer(expr);
    if (initializer != null) {
      return _appBarToolbarHeight(initializer, heightProp, issues);
    }
    if (expr is ConditionalExpression) {
      var refused = false;
      final dsl = _conditionalSwitch(expr, issues, (branch) {
        final height = _appBarToolbarHeight(branch, heightProp, issues);
        refused |= height == null;
        return height?.dsl ?? 'null';
      });
      return refused ? null : (value: null, dsl: dsl);
    }
    final height = _realFragment(expr, heightProp, issues);
    if (height == null) return null;
    if (height.dsl == 'null') return defaultHeight;
    // A runtime null takes the slot's kToolbarHeight default, as in Flutter.
    return height;
  }

  /// The height one tab occupies: a stated height, else the taller size
  /// for a tab carrying both an icon and a label.
  double? _tabHeightOf(
    CollectionElement element,
    PropertyEntry heightProp,
    List<Issue> issues,
  ) {
    if (element is! Expression) return null;
    final call = _widgetCallOf(element);
    if (call == null || call.name != 'Tab') return null;
    final stated = _namedArgument(call.args, 'height');
    if (stated != null) {
      return _realFragment(stated, heightProp, issues)?.value;
    }
    final hasIcon = _namedArgument(call.args, 'icon') != null;
    final hasLabel =
        _namedArgument(call.args, 'text') != null ||
        _namedArgument(call.args, 'child') != null;
    return hasIcon && hasLabel ? kRestageTabWithIconHeight : kRestageTabHeight;
  }

  /// The constructor name and argument list of a widget construction, or
  /// `null` when the expression is not one.
  ({String name, NodeList<Argument> args})? _widgetCallOf(Expression source) {
    final expr = _resolveBoundIdentifier(source);
    final initializer = _constIdentifierInitializer(expr);
    if (initializer != null) return _widgetCallOf(initializer);
    return switch (expr) {
      InstanceCreationExpression(:final constructorName, :final argumentList) =>
        (
          name:
              constructorName.element?.enclosingElement.name ??
              constructorName.type.name.lexeme,
          args: argumentList.arguments,
        ),
      MethodInvocation(:final methodName, :final argumentList) => (
        name: methodName.name,
        args: argumentList.arguments,
      ),
      _ => null,
    };
  }

  /// The named argument [name] of an argument list, unwrapped.
  Expression? _namedArgument(NodeList<Argument> args, String name) => args
      .whereType<NamedArgument>()
      .firstWhereOrNull((a) => a.name.lexeme == name)
      ?.argumentExpression;

  /// [expr] lowered as a real, with its folded value when the lowering is
  /// a bare number.
  ({double? value, String dsl})? _realFragment(
    Expression expr,
    PropertyEntry heightProp,
    List<Issue> issues,
  ) {
    final before = issues.length;
    final dsl = _translateSlotValue(
      expr,
      PropertyType.real,
      issues,
      property: heightProp,
    );
    if (dsl.isEmpty || issues.length > before) return null;
    return (value: double.tryParse(dsl), dsl: dsl);
  }

  Map<Expression, FormalParameterElement> _resolvedSourceParameters(
    Expression anchor,
    NodeList<Argument> arguments,
  ) {
    final constructor = switch (anchor) {
      InstanceCreationExpression() => anchor.constructorName.element,
      MethodInvocation() => anchor.methodName.element,
      _ => null,
    };
    if (constructor is! ExecutableElement) {
      return const <Expression, FormalParameterElement>{};
    }
    final positional = constructor.formalParameters
        .where((parameter) => !parameter.isNamed)
        .toList(growable: false);
    var positionalIndex = 0;
    final result = Map<Expression, FormalParameterElement>.identity();
    for (final argument in arguments) {
      if (argument is NamedArgument) {
        final parameter = argument.correspondingParameter;
        if (parameter is FormalParameterElement) {
          result[argument.argumentExpression] = parameter;
        }
        continue;
      }
      if (positionalIndex < positional.length) {
        result[argument.argumentExpression] = positional[positionalIndex];
      }
      positionalIndex++;
    }
    return result;
  }

  /// A call to catalog widget [entry], recording its catalog origin.
  String _catalogCall(WidgetEntry entry, List<String> arguments) {
    _recordRfwCatalogConstructorOrigin(entry);
    return '${entry.name}(${arguments.join(', ')})';
  }

  void _recordRfwCatalogConstructorOrigin(WidgetEntry entry) {
    final calls = _currentRfwCatalogConstructorOrigins;
    if (calls == null) return;
    final next = fmt.RfwCatalogConstructorProvenance(
      constructorName: entry.name,
      catalogLibraryNamespace: entry.library.namespace,
      catalogWidgetWireId: entry.wireId,
    );
    final previous = calls.putIfAbsent(entry.name, () => next);
    if (!previous.matches(next)) {
      throw StateError(
        'One emitted RFW constructor spelling has conflicting catalog origins',
      );
    }
  }

  String _interpolatedTextRich(
    String textSpan,
    List<String> carried,
    Expression anchor,
    List<Issue> issues,
    int localIssueStart,
  ) {
    if (issues
        .skip(localIssueStart)
        .any((issue) => !issue.code.isInformational)) {
      return '';
    }
    final textRich = _textRichEntry(null);
    if (textRich == null) {
      issues.add(
        Issue(
          code: IssueCode.unknownWidget,
          capabilityGapSubject: 'widget:TextRich',
          message:
              "Widget 'TextRich' is not a known catalog widget. Add "
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
          message:
              "Catalog widget '${textRich.name}' must declare a "
              "'textSpan' PropertyType.inlineSpan slot before lowering "
              'interpolated Text spans.',
          location: _locationOf(anchor),
        ),
      );
      return '';
    }
    final textRichProps = {for (final p in textRich.properties) p.name};
    for (final property in carried) {
      final propName = _emittedPropertyName(property);
      if (propName == null) {
        issues.add(
          Issue(
            code: IssueCode.unknownProperty,
            message:
                'Interpolated Text could not identify emitted '
                'property fragment `$property`; the whole interpolation is '
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
            message:
                'Text with multi-segment string interpolation can '
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
            message:
                "Catalog widget '${textRich.name}' does not declare "
                "carried Text property '$propName'; the whole interpolation "
                'is deferred.',
            location: _locationOf(anchor),
          ),
        );
        return '';
      }
    }
    final outerArgs = [
      '${_rfwMapKey(textSpanProp.name)}: $textSpan',
      ...carried,
    ];
    return _catalogCall(textRich, outerArgs);
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
    List<Issue> issues, {
    String Function(Expression)? translateBody,
  }) => _inHelperBody(
    helper,
    call,
    issues,
    translateBody ?? (body) => _translate(body, issues),
    refused: '',
  );

  /// Runs [visit] on [helper]'s body with the call's arguments bound to its
  /// parameters; [refused] after a diagnostic when they do not bind 1:1.
  T _inHelperBody<T>(
    HelperDef helper,
    MethodInvocation call,
    List<Issue> issues,
    T Function(Expression body) visit, {
    required T refused,
  }) {
    final guardBuilder = _activeWidgetBuilder != null;
    if (guardBuilder && !_activeBuilderHelpers.add(helper)) {
      throw BuilderLoweringException(
        call,
        'Recursive helper is unsupported in a pure callback',
      );
    }
    final binding = bindHelperArguments(
      helper.params,
      call.argumentList.arguments.toList(),
    );
    if (binding == null) {
      if (guardBuilder) {
        _activeBuilderHelpers.remove(helper);
        throw BuilderLoweringException(
          call,
          'Pure helper arguments must bind exactly',
        );
      }
      issues.add(
        Issue(
          code: IssueCode.customWidgetInliningDeferred,
          capabilityGapSubject: 'helper:${call.methodName.name}',
          message:
              "The helper '${call.methodName.name}' cannot be inlined: "
              'its arguments do not bind one-to-one to its parameters.',
          location: _locationOf(call),
        ),
      );
      return refused;
    }
    final saved = _walk;
    final helperElement = call.methodName.element;
    final measurementScope = _walk.measurementScope;
    final measurementWidgetList = _walk.measurementWidgetList;
    _walk = _walk.copyWith(
      islandScope: [..._walk.islandScope, islandCallStep(call)],
      paramBindings: {..._walk.paramBindings, ...binding},
      measurementScope:
          measurementScope != null && helperElement is ExecutableElement
          ? measurementScope.enterHelper(helperElement)
          : measurementScope,
      measurementWidgetList:
          measurementWidgetList != null && helperElement is ExecutableElement
          ? measurementWidgetList.enterHelper(helperElement)
          : measurementWidgetList,
    );
    _callSites.add(call);
    _hoist?.helperBodies[call] = helper.body;
    try {
      return visit(helper.body);
    } finally {
      _callSites.removeLast();
      if (guardBuilder) _activeBuilderHelpers.remove(helper);
      _walk = saved;
    }
  }

  /// Inlines a composable custom widget when it is inlinable in this codegen
  /// increment — registering its RFW remote-widget definition (translating
  /// the blueprint's `build()` expression) and returning the call-site
  /// reference. Returns `null` when [classification] is not an inlinable-now
  /// [ComposableWidget] — an imperative, deferred-mechanism, or unclassifiable
  /// widget — so the caller emits the classified diagnostic instead.
  ///
  /// "Inlinable now" means every required inlining mechanism is one this
  /// increment emits — composition (always), constant-folding, theme-as-data,
  /// and declarative state.
  String? _tryInlineCustomWidget(
    WidgetClassification classification,
    String key,
    NodeList<Argument> args,
    Expression anchor,
    List<Issue> issues, {
    WidgetEntry? catalogEntry,
  }) {
    if (classification is! ComposableWidget) return null;
    if (args.any(
      (argument) => _containsIntlFormatting(
        _resolveBoundIdentifier(argument.argumentExpression),
      ),
    )) {
      if (catalogEntry != null) return null;
      issues.add(
        Issue(
          code: IssueCode.customWidgetInliningDeferred,
          message:
              'Formatting constructor arguments require an installed native widget binding',
          location: _locationOf(anchor),
        ),
      );
      return '';
    }
    final unmet = classification.requiredMechanisms.difference(
      _kImplementedMechanisms,
    );
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
    final name = _definitionName(blueprint);
    final emissionIdentity = catalogEntry == null
        ? null
        : (
            classKey: key,
            remoteLibrary: catalogEntry.library.namespace,
          );
    if (emissionIdentity != null &&
        _forcedCustomWidgetFactoryRoutes.containsKey(emissionIdentity)) {
      return null;
    }

    // Resolve the RFW widget name. The first widget to claim a name registers
    // its definition; a name a *different* classKey already claimed, or one
    // that shadows a catalog widget, would make a reference in the blob
    // ambiguous — diagnose it rather than emit.
    final claimedBy = owners[name];
    if (claimedBy == null) {
      // A surface root name, or a DIFFERENT catalog widget sharing this name,
      // is a real ambiguity; the widget's OWN catalog entry (same name AND
      // same source) is not — a registered inlinable widget inlines itself,
      // and its definition simply shadows the (unused) reference.
      final conflict = _inlineNameConflict(name, blueprint.classKey);
      if (conflict != null) {
        issues.add(_nameCollisionIssue(key, name, conflict));
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
      if (blueprint.state?.isNotEmpty ?? false) {
        if (_stateResetIssue(blueprint, blueprint.rfwName, anchor)
            case final issue?) {
          issues.add(issue);
          return '';
        }
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
        argNames: {for (final p in blueprint.params) p.readName: p.name},
        params: {for (final p in blueprint.params) p.name: p},
        // Custom-widget definitions cannot read root host data.
        rootParams: const {},
        classKey: blueprint.classKey,
        validatedCoalesceParams: {},
        stateFields: stateFields == null
            ? null
            : {for (final field in stateFields) field.name: field},
        eventHandlers: blueprint.eventHandlers,
        rootStateContext: false,
        inlined: blueprint.inlined,
        measurementScope: switch (saved.measurementWidget) {
          // A body every placement shares takes its definition's scope.
          final widget?
              when measurementRouteEmissionPlan?.sharedBodies.contains(
                    widget.widgetIdentity,
                  ) ??
                  false =>
            widget.enterSharedBody(),
          final widget => widget?.enterInlinedBody(),
        },
        measurementWidget: null,
        measurementWidgetList: null,
        // Positions and branches inside the body are the body's own.
        stateShift: null,
        armSites: const [],
        stateGuard: null,
      );
      final bodyMark = issues.length;
      _definitionFrames.add((
        name: name,
        key: blueprint.classKey,
        loops: _walk.runtimeLoops.length,
        builder: _activeWidgetBuilder,
      ));
      try {
        if (_admitOrdinaryLeaf(blueprint.buildExpression, issues)) {
          final body = _translate(blueprint.buildExpression, issues);
          if (_passThroughParam(body) case final param?) {
            (_passThroughs[definitions] ??= {})[name] = param;
          } else {
            definitions[name] = body;
          }
        }
        if (stateFields != null && stateFields.isNotEmpty) {
          definitionStates[name] = {
            for (final field in stateFields)
              field.name: _stateInitialLiteral(field),
          };
        }
      } finally {
        _definitionFrames.removeLast();
        _walk = saved;
      }
      // A body that cannot translate is not inlined; a registered widget is
      // then referenced by name.
      if (issues.skip(bodyMark).any((issue) => !issue.code.isBuildNotice)) {
        definitions.remove(name);
        definitionStates.remove(name);
        _passThroughs[definitions]?.remove(name);
        return '';
      }
    } else if (claimedBy != key) {
      issues.add(
        _nameCollisionIssue(key, name, 'another custom widget ($claimedBy)'),
      );
      return '';
    }
    final passThrough = _passThroughs[definitions]?[name];
    if (passThrough != null) definitionStates.remove(name);
    if (passThrough == null && !definitions.containsKey(name)) return '';
    final holding = _holdingState[definitions] ??= {};
    final stateful = definitionStates.containsKey(name)
        ? blueprint.rfwName
        : holding[name];
    if (stateful != null) {
      for (final frame in _definitionFrames) {
        holding[frame.name] ??= stateful;
      }
      if (_stateResetIssue(blueprint, stateful, anchor) case final issue?) {
        issues.add(issue);
        return '';
      }
    }
    if (emissionIdentity != null) {
      _currentCustomWidgetInlineClaims?.add(emissionIdentity);
    }

    // The call-site arguments translate in the caller's context — restored
    // above after any definition-body translation.
    if (passThrough != null) {
      final mark = issues.length;
      // Only the argument it returns is built; Flutter never reads the rest.
      final values = _customWidgetCallArgValues(
        blueprint,
        args,
        issues,
        catalogEntry: catalogEntry,
        only: passThrough,
      );
      if (issues.skip(mark).any((issue) => !issue.code.isBuildNotice)) {
        return '';
      }
      return values[passThrough];
    }
    final callArgs = _armChecked(
      issues,
      () => normalizeOptionalChild(
        issues,
        () => _customWidgetCallArgs(
          blueprint,
          args,
          issues,
          catalogEntry: catalogEntry,
        ),
      ),
    );
    return switch (callArgs) {
      CompleteDslEmission(:final value) => '$name($value)',
      AbsentDslEmission() => '$name()',
      RefusedDslEmission() => '',
    };
  }

  // Why rfw would start the state of [blueprint], or of the [stateful]
  // widget it places, again where Flutter keeps it; null when it wouldn't.
  Issue? _stateResetIssue(
    CustomWidgetBlueprint blueprint,
    String stateful,
    Expression anchor,
  ) {
    // Without a mount no island can form, so the design delivers as before,
    // with no notice.
    if (_islands == null) return null;
    final key = blueprint.classKey;
    for (final site in _walk.armSites) {
      _armLog.add((site.id, site.arm, site.slot, key));
    }
    final owner = blueprint.rfwName;
    final subject = stateful == owner
        ? "'$owner' keeps its state in the app because it"
        : "'$stateful' keeps its state in the app because '$owner', which "
              'places it,';
    final String cause;
    final String fix;
    final shift = _walk.stateShift;
    if (_repeatedHere() case final repeat?) {
      cause =
          'is placed in a $repeat (${_locationOf(anchor)}), where the '
          'delivered design would start its state again whenever the '
          '${repeat == 'loop' ? 'data changes' : 'builder runs'}';
      fix = "placing '$owner' outside the $repeat";
    } else if (shift != null) {
      final at = shift.node;
      cause =
          'follows `${readableSource(at.toSource())}` (${_locationOf(at)}), '
          'a ${shift.kind} whose number of widgets can change, and the '
          'delivered design would start its state again when it does';
      fix = at is IfElement && at.elseElement == null
          ? "placing '$owner' before it, or giving the condition an `else` "
                'that builds one widget'
          : "placing '$owner' before it";
    } else if (_walk.stateGuard case final guard?) {
      cause =
          'is in a branch of `${readableSource(guard.toSource())}` '
          '(${_locationOf(guard)}) that the delivered design builds in more '
          'than one place, so its state would start again whenever a '
          'different part of the condition decides that branch';
      fix =
          'giving the condition a single part, such as one bool the screen '
          'computes';
    } else if (_walk.armSites.any(
      (site) => _forcedArms.contains((site.id, site.slot, key)),
    )) {
      // Each branch renders its own copy from the app, so the state still
      // starts again when the branch changes, as the delivered design's does.
      final who = stateful == owner
          ? "'$owner'"
          : "'$owner', which places '$stateful',";
      return Issue(
        code: IssueCode.nestedStateIsland,
        message:
            '$who renders from the app because it is placed at the same spot '
            'in more than one branch of a condition (${_locationOf(anchor)}), '
            'and its state starts again whenever the condition changes branch. '
            "Try placing one '$owner' outside the condition and passing it the "
            'values that change, so it keeps its state.',
        location: _locationOf(anchor),
      );
    } else {
      return null;
    }
    return Issue(
      code: IssueCode.nestedStateIsland,
      message: '$subject $cause. Try $fix, if designers should change it.',
      location: _locationOf(anchor),
    );
  }

  // Per declaration class: each widget parameter its body places after a
  // shifting sibling or in a branch, and where.
  final Map<String, Map<String, (_StateShift?, List<_ArmSite>, Expression?)>>
  _paramPlacements = {};

  // Per declaration class: how often its body places each widget parameter.
  // An argument placed more than once is one island under one key, so it is
  // never islanded through the parameter.
  final Map<String, Map<String, Set<String>>> _paramPlacementCounts = {};

  // Notes that the declaration body being translated places its widget
  // parameter [dsl] where its position or branch can change.
  void _noteParamPlacement(String dsl, Expression at) {
    final frame = _definitionFrames.lastOrNull;
    if (frame != null) {
      if (_passThroughParam(dsl) case final placed?) {
        final copies = (_paramPlacementCounts[frame.key] ??= {})[placed] ??= {};
        // One entry per rendered copy: each unrolled copy of a constant list
        // is its own, and a loop or builder renders many.
        final copy =
            '${_stripParens(at).offset}@'
            '${[for (final step in _unrolled) step.ordinal].join('.')}';
        copies.add(copy);
        if (_repeatedHere() != null) copies.add('$copy+');
      }
    }
    if (frame == null ||
        (_walk.stateShift == null &&
            _walk.armSites.isEmpty &&
            _walk.stateGuard == null)) {
      return;
    }
    final param = _passThroughParam(dsl);
    if (param == null) return;
    (_paramPlacements[frame.key] ??= {})[param] = (
      _walk.stateShift,
      _walk.armSites,
      _walk.stateGuard,
    );
  }

  // Notes a stateful widget passed as [param] to [holder], which places it
  // more than once where its position can change: it is delivered there, so
  // its state starts again when it moves.
  void _noteRestartWhenMoved(
    CustomWidgetBlueprint holder,
    String param,
    Expression supplied,
    List<Issue> issues,
  ) {
    final moved = _paramPlacements[holder.classKey]?[param];
    final widget = _stripParens(supplied).staticType?.element;
    if (moved == null || widget is! ClassElement) return;
    final placed = customWidgetBlueprints[customWidgetKey(widget)];
    if (!(placed?.state?.isNotEmpty ?? false)) return;
    final (shift, _, guard) = moved;
    final after = shift?.node ?? guard;
    issues.add(
      Issue(
        code: IssueCode.stateRestartsWhenMoved,
        message:
            "'${holder.rfwName}' places its `$param` more than once"
            '${after == null ? ' in branches that can change' : ', after `${readableSource(after.toSource())}`'}, '
            "so the `${widget.name}` passed to it (${_locationOf(supplied)}) "
            'starts its state again when '
            '${after == null ? 'the branch changes' : 'that changes'}. Try '
            "placing `$param` once in '${holder.rfwName}'.",
        location: _locationOf(supplied),
      ),
    );
  }

  // The parameter a translated build [body] returns as is, or null: a
  // declaration's root must be a constructor call or a switch.
  static String? _passThroughParam(String body) =>
      RegExp(r'^args\.([A-Za-z_][A-Za-z0-9_]*)$').firstMatch(body.trim())?[1];

  /// The RFW name [blueprint]'s inlined definition emits under: its class
  /// name, or, when a surface root, a different catalog widget or another
  /// inlined class also uses that name, the name with a suffix derived from
  /// the class's identity.
  String _definitionName(CustomWidgetBlueprint blueprint) =>
      _definitionNames[(blueprint.classKey, blueprint.rfwName)] ??= () {
        final name = blueprint.rfwName;
        final shared =
            _inlineNameConflict(name, blueprint.classKey) != null ||
            customWidgetBlueprints.values.any(
              (other) =>
                  other.rfwName == name && other.classKey != blueprint.classKey,
            );
        if (!shared) return name;
        final digest = sha256.convert(utf8.encode(blueprint.classKey));
        return '${name}_${digest.toString().substring(0, 8)}';
      }();

  final Map<(String, String), String> _definitionNames = {};

  // A callback written in the body of a widget every placement shares is
  // routed by its spot in that body, as discovery decided.
  bool _routedPerSpot(Expression callback) {
    final shared = measurementRouteEmissionPlan?.sharedBodies;
    if (shared == null || shared.isEmpty) return false;
    final owner = callback.thisOrAncestorOfType<ClassDeclaration>();
    final element = owner?.declaredFragment?.element;
    if (element == null) return false;
    final widget = element.supertype?.element.name == 'State'
        ? element.supertype?.typeArguments.firstOrNull?.element
        : element;
    return widget is InterfaceElement &&
        shared.contains(measurementClassIdentity(widget));
  }

  // Per definitions map: each declaration that places a stateful one, by
  // name, and the stateful widget's name.
  final Expando<Map<String, String>> _holdingState = Expando();

  // The declaration bodies being translated, innermost last, with the loops
  // and builder active where each began.
  final List<
    ({String name, String key, int loops, WidgetBuilderLowering? builder})
  >
  _definitionFrames = [];

  // 'loop' or 'builder' when the current call site repeats within its own
  // body: rfw builds a fresh instance there on each rebuild.
  String? _repeatedHere() {
    final frame = _definitionFrames.lastOrNull;
    if (_walk.runtimeLoops.length > (frame?.loops ?? 0)) return 'loop';
    final builder = _activeWidgetBuilder;
    if (builder != null && !identical(builder, frame?.builder)) {
      return 'builder';
    }
    return null;
  }

  /// Why the RFW widget name [name] cannot be claimed by the custom widget
  /// [classKey] — a reserved surface root name, or a different catalog widget
  /// already carrying it — or `null` when the name is free.
  String? _inlineNameConflict(String name, String classKey) {
    if (name == paywallRootWidgetName ||
        name == onboardingScreenRootWidgetName) {
      return 'a reserved surface root widget name';
    }
    final shadowsOtherCatalogWidget = catalog.widgets.any(
      (w) => w.name == name && w.flutterType != classKey,
    );
    return shadowsOtherCatalogWidget ? 'the catalog widget' : null;
  }

  /// Diagnostic for a custom widget [key] whose emitted RFW name [name]
  /// collides with [conflict] — two widgets sharing one name make a
  /// reference in the emitted blob ambiguous.
  Issue _nameCollisionIssue(String key, String name, String conflict) {
    return Issue(
      code: IssueCode.customWidgetNameCollision,
      message:
          "The custom widget '$key' cannot be inlined: its RFW widget "
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
  /// double literal. Native keys require a factory route because inlining
  /// cannot retain the original widget owner.
  ///
  /// A matched catalog entry supplies the exact decoder type after resolved
  /// formal identity and named-or-positional correspondence agree.
  String _customWidgetCallArgs(
    CustomWidgetBlueprint blueprint,
    NodeList<Argument> args,
    List<Issue> issues, {
    WidgetEntry? catalogEntry,
  }) => [
    for (final MapEntry(:key, :value) in _customWidgetCallArgValues(
      blueprint,
      args,
      issues,
      catalogEntry: catalogEntry,
    ).entries)
      '${_rfwMapKey(key)}: $value',
  ].join(', ');

  /// The lowered value of each call-site argument [_customWidgetCallArgs]
  /// emits, by parameter name, in emission order; only [only]'s when given.
  Map<String, String> _customWidgetCallArgValues(
    CustomWidgetBlueprint blueprint,
    NodeList<Argument> args,
    List<Issue> issues, {
    WidgetEntry? catalogEntry,
    String? only,
  }) {
    // Collect call-site expressions by parameter name. Unmatched named
    // arguments are diagnosed.
    final supplied = <String, Expression>{};
    final suppliedProperties = <String, PropertyEntry>{};
    final parameterNames = {
      for (final parameter in blueprint.params) parameter.name,
    };
    var positionalIndex = 0;
    for (final arg in args) {
      final resolvedParam = _resolvedCustomWidgetParam(blueprint, arg);
      CustomWidgetParam? param;
      if (arg is NamedArgument) {
        final argName = arg.name.lexeme;
        // A key the widget forwards to its build is one of its parameters.
        if (isDiscardedWidgetKeyArgument(arg) &&
            !parameterNames.contains(argName)) {
          if (!isLegacyScalarWidgetKey(arg.argumentExpression)) {
            issues.add(
              Issue(
                code: IssueCode.customWidgetUnsupportedReducible,
                message:
                    'A native key requires the original custom widget owner; '
                    'this widget has no matching native factory key slot.',
                location: _locationOf(arg),
              ),
            );
          } else {
            _keyNotKept(arg.argumentExpression, issues);
          }
          continue;
        }
        if (!parameterNames.contains(argName)) {
          issues.add(
            Issue(
              code: IssueCode.unknownProperty,
              message:
                  "Argument '$argName' is not declared by "
                  "'${blueprint.rfwName}'.",
              location: _locationOf(arg),
            ),
          );
          continue;
        }
        param =
            resolvedParam ??
            blueprint.params.firstWhereOrNull(
              (candidate) => candidate.name == argName,
            );
      } else {
        param =
            resolvedParam ??
            (positionalIndex < blueprint.params.length
                ? blueprint.params[positionalIndex]
                : null);
        positionalIndex++;
      }
      if (param == null) continue;
      if (catalogEntry != null) {
        final property = resolvedParam == null
            ? null
            : _customWidgetCatalogProperty(
                catalogEntry,
                resolvedParam,
                arg,
              );
        if (property == null) {
          issues.add(
            Issue(
              code: IssueCode.customWidgetUnsupportedReducible,
              message:
                  "Argument '${param.name}' on "
                  "'${blueprint.rfwName}' has no exact catalog property "
                  'match.',
              location: _locationOf(arg),
            ),
          );
          continue;
        }
        suppliedProperties[param.name] = property;
      }
      supplied[param.name] = arg.argumentExpression;
    }
    // Emit one argument per parameter per the null-coalescing completion
    // table (a property the blueprint marked coalesced is `completion-required`
    // — its lowered fallback is cached under the definition's classKey):
    //   supplied value (not explicit null)      → the value         (row 4)
    //   supplied explicit `null`, coalesced      → the fallback       (row 3)
    //   omitted, constructor default exists      → the default        (row 1)
    //   omitted, no default, coalesced           → the fallback       (row 2)
    //   omitted, no default, not coalesced       → unbound (args.<name> = null)
    final emitted = <String, String>{};
    final fallbacks = _completionFallbacks[blueprint.classKey] ?? const {};
    for (final param in blueprint.params) {
      if (only != null && param.name != only) continue;
      final suppliedExpr = supplied[param.name];
      final fallback = fallbacks[param.name];
      if (suppliedExpr != null) {
        // Gate 0: a `Map` value bound to a custom-widget parameter. A
        // parameter carries no slot shape (only a numeric flag), so the value
        // lowers through the GENERIC map arm to the natural key-keyed
        // spelling `{k: v}` — while the property this parameter feeds inside
        // the definition body decodes the ENTRY LIST `[{key: k, value: v}]`.
        // Nothing downstream can tell the two apart: the blob parses, catalog
        // validation passes, and the generated factory's `isList` guard fails
        // only at render. Refuse at build time rather than emit a spelling the
        // decoder cannot read. Checked on the supplied expression itself, so a
        // conditional whose branches are maps is caught once, at the argument.
        if (_dartCoreMapType(_stripParens(suppliedExpr).staticType) != null) {
          issues.add(
            Issue(
              code: IssueCode.unsupportedCollectionFlow,
              message:
                  "The property '${param.name}' of "
                  "'${blueprint.rfwName}' is a map, and a map passed to an "
                  'inlined custom widget cannot carry the shape its slot '
                  'decodes. Pass the map to the widget that declares the '
                  'property instead of through this one.',
              location: _locationOf(suppliedExpr),
            ),
          );
          continue;
        }
        if (fallback != null && _isNullLiteral(suppliedExpr)) {
          // Row 3: explicit `null` fires the `??` → the fallback.
          emitted[param.name] = _coerceParamValue(param, fallback);
        } else {
          final beforeIssues = issues.length;
          // The argument sits where the body places the parameter.
          final saved = _walk;
          _walk = _walk.armStep(param.name);
          final placements =
              _paramPlacementCounts[blueprint.classKey]?[param.name]?.length ??
              0;
          final placed = (placements < 2)
              ? (_paramPlacements[blueprint.classKey]?[param.name])
              : null;
          if (placed case (
            final shift,
            final sites,
            final guard,
          )) {
            _walk = _walk.copyWith(
              stateShift: shift ?? _walk.stateShift,
              stateGuard: guard ?? _walk.stateGuard,
              armSites: [
                ..._walk.armSites,
                // The argument's own slot step is the parameter's spot.
                for (final site in sites)
                  _ArmSite(site.id, site.arm, site.slot, 1),
              ],
            );
          }
          final String lowered;
          try {
            lowered = _translateParamValue(
              param,
              suppliedExpr,
              issues,
              property: suppliedProperties[param.name],
            );
          } finally {
            _walk = saved;
          }
          // A refused value emits no argument rather than an empty one.
          if (lowered.isEmpty && issues.length > beforeIssues) continue;
          if (placements >= 2) {
            _noteRestartWhenMoved(
              blueprint,
              param.name,
              suppliedExpr,
              issues,
            );
          }
          if (fallback != null &&
              (_isRuntimeMissing(suppliedExpr) ||
                  _lowersToMissableRef(lowered))) {
            // Gate 3: a passed value that can be MISSING at runtime — a
            // nullable-typed expression, OR one that lowers to a
            // possibly-missing `data.context.*` host reference — would fall
            // to the factory default instead of the author's fallback (the
            // body's `??` is rewritten away). Diagnosed defer, never a silent
            // miss.
            issues.add(
              Issue(
                code: IssueCode.customWidgetUnsupportedReducible,
                message:
                    "The optional property '${param.name}' of "
                    "'${blueprint.rfwName}' is completed with a `?? fallback` "
                    'default, but the value passed here can be missing at '
                    'runtime, so that default would be lost. Pass a value that '
                    'is always present, or omit the property.',
                location: _locationOf(suppliedExpr),
              ),
            );
          } else {
            // Row 4: a passed value, unchanged.
            emitted[param.name] = lowered;
          }
        }
      } else if (param.defaultValue != null) {
        // Row 1: omitted + constructor default — the `??` never fires; the
        // existing default-completion path, unchanged.
        final defaultLiteral = _foldedLiteral(param.defaultValue!);
        emitted[param.name] = _coerceParamValue(param, defaultLiteral);
      } else if (fallback != null) {
        // Row 2: omitted, no default — the fallback.
        emitted[param.name] = _coerceParamValue(param, fallback);
      }
    }
    return emitted;
  }

  CustomWidgetParam? _resolvedCustomWidgetParam(
    CustomWidgetBlueprint blueprint,
    Argument argument,
  ) {
    final formal = argument.correspondingParameter;
    if (formal is! FieldFormalParameterElement) return null;
    final field = formal.field;
    if (field == null) return null;
    return blueprint.params.firstWhereOrNull(
      (param) => param.sourceField?.baseElement == field.baseElement,
    );
  }

  PropertyEntry? _customWidgetCatalogProperty(
    WidgetEntry entry,
    CustomWidgetParam param,
    Argument argument,
  ) {
    final formal = argument.correspondingParameter;
    if (formal is! FieldFormalParameterElement) return null;
    if (formal.isNamed) {
      if (argument is! NamedArgument || argument.name.lexeme != param.name) {
        return null;
      }
      return entry.properties.singleWhereOrNull(
        (property) => !property.positional && property.name == param.name,
      );
    }
    final constructor = formal.enclosingElement;
    if (constructor is! ConstructorElement) return null;
    final position = constructor.formalParameters
        .where((candidate) => candidate.isPositional)
        .toList(growable: false)
        .indexWhere(
          (candidate) => candidate.baseElement == formal.baseElement,
        );
    final properties = entry.properties
        .where((property) => property.positional)
        .toList(growable: false);
    return position >= 0 && position < properties.length
        ? properties[position]
        : null;
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
  /// missing at render time. `data.context.*` is host-supplied and omittable;
  /// `data.theme.*` is always published. Gate 3 defers a
  /// non-nullable-typed passed value that lowers to one of these — completing
  /// it into a coalesced property would resolve to the factory default instead
  /// of the author's fallback when the reference is absent.
  bool _lowersToMissableRef(String lowered) =>
      lowered.startsWith('data.context.');

  /// Translates a call-site value bound to [param] with the parameter's
  /// numeric coercion applied through the branches of a conditional — the
  /// parameter-level analogue of [_translateSlotValue]: a bare integer in
  /// either branch of a ternary bound to a numeric parameter must be
  /// normalised per branch or the definition body's `source.v<double>`
  /// decode silently nulls it. Also unwraps a callback closure and attaches
  /// any measurement marker.
  String _translateParamValue(
    CustomWidgetParam param,
    Expression expr,
    List<Issue> issues, {
    PropertyEntry? property,
  }) {
    final stripped = _stripParens(expr);
    final eventOccurrence = switch ((
      _walk.measurementWidget,
      param.sourceParameter,
    )) {
      (final widget?, final parameter?) => widget.event(parameter),
      _ => null,
    };
    final savedEventOccurrence = _measuredEventOccurrence;
    if (eventOccurrence != null) _measuredEventOccurrence = eventOccurrence;
    try {
      return _translateMeasuredParamValue(
        param,
        stripped,
        expr,
        eventOccurrence,
        issues,
        property: property,
      );
    } finally {
      _measuredEventOccurrence = savedEventOccurrence;
    }
  }

  String _translateMeasuredParamValue(
    CustomWidgetParam param,
    Expression stripped,
    Expression expr,
    MeasurementEventOccurrence? eventOccurrence,
    List<Issue> issues, {
    PropertyEntry? property,
  }) {
    late final String translated;
    final paramSlot = param.type == null
        ? null
        : inferPropertyType(param.type!);
    if (property != null) {
      translated = _translateSlotValue(
        stripped,
        property.type,
        issues,
        property: property,
        // A widget argument is measured where it is passed; an event's marker
        // is attached below.
        sourceParameter:
            property.type == PropertyType.widget ||
                property.type == PropertyType.widgetList
            ? param.sourceParameter
            : null,
      );
    } else if (paramSlot == PropertyType.widget ||
        paramSlot == PropertyType.widgetList) {
      // A widget argument is measured where it is passed.
      translated = _translateSlotValue(
        stripped,
        paramSlot!,
        issues,
        sourceParameter: param.sourceParameter,
      );
    } else if (_nativeContractOf(param.type) case final contract?) {
      // A native value crosses as a direct site would pass it.
      final before = issues.length;
      translated =
          _nativeBindingRead(
            stripped,
            type: contract,
            computed: true,
            construct: true,
          ) ??
          (contract == 'flutter.Key'
              ? _nativeKeyReference(stripped, issues)
              : null) ??
          '';
      if (translated.isEmpty && issues.length == before) {
        final source = readableSource(_writtenSource(stripped));
        // In a mount the call site renders from the app; without one it's
        // refused.
        issues.add(
          Issue(
            code: IssueCode.propertyValueTypeMismatch,
            message: _hoist == null
                ? '`$source` (${_locationOf(stripped)}): Restage passes this '
                      "value to a widget only through the screen's generated "
                      "widget, and this build doesn't use one. Try showing the "
                      'screen through ${_generatedMountName(stripped)}, or '
                      'removing the argument.'
                : 'App code builds the widget that takes `$source` '
                      "(${_locationOf(stripped)}) because Restage can't pass "
                      "`$source` through a design. Designs can't change that "
                      'widget.',
            location: _locationOf(stripped),
          ),
        );
      }
    } else {
      final paramType = param.type;
      final declaredListItemType = paramType == null
          ? null
          : _dartCoreListElementType(paramType);
      final listItemType = _listItemPropertyTypeForDartType(paramType);
      final rootParam = _rootParamRead(stripped);
      final type = param.isNumeric
          ? PropertyType.real
          : param.isVoidCallback
          ? PropertyType.event
          : _propertyTypeForParameter(paramType) ??
                _propertyTypeForParameter(rootParam?.type) ??
                PropertyType.unknown;
      translated = listItemType == null
          ? _translateSlotValue(stripped, type, issues)
          : _translateTypedListTerminal(
              stripped,
              listItemType,
              issues,
              declaredItemType: declaredListItemType,
            );
    }
    final value = _coerceParamValue(
      param,
      translated,
    );
    final marker = eventOccurrence == null
        ? null
        : measurementRouteEmissionPlan?.markerFor(eventOccurrence);
    if (marker == null) {
      if (eventOccurrence != null && measurementRouteEmissionPlan != null) {
        _noteUnavailableItem(eventOccurrence, expr, measured: false);
      }
      return value;
    }
    if (value.isEmpty) {
      issues.add(
        _measuredRefusal(
          Issue(
            code: IssueCode.invalidEventConfiguration,
            message:
                'The measured inlined custom-widget callback did not '
                'lower to an RFW event handler.',
            location: _locationOf(expr),
          ),
        ),
      );
      return '';
    }
    return _measuredEventHandler(
      value,
      marker,
      eventOccurrence!,
      expr,
      issues,
    );
  }

  /// Attaches [marker] to a lowered event, or pairs a state update with the
  /// measure-only tap event that carries it.
  String _measuredEventHandler(
    String value,
    String marker,
    MeasurementEventOccurrence occurrence,
    Expression expression,
    List<Issue> issues,
  ) {
    final handler = value.trimLeft();
    if (handler.startsWith('{nativeEvent: ')) {
      // The plan admits the slot by its declared type; Flutter discards
      // what the handler returns, such as an async method's Future.
      final tap = _measurementTapEvent(marker, occurrence, expression, issues);
      if (tap.isEmpty) return '';
      return '${value.substring(0, value.length - 1)}, measurement: $tap}';
    }
    final localSet = handler.startsWith(
      'event ${_stringLiteral(kLocalValueSetEventName)}',
    );
    if (handler.startsWith('event ') && !localSet) {
      return _attachMeasurementRouteMarker(
        value,
        marker,
        expression,
        issues,
        item: _measurementItem(occurrence, expression),
      );
    }
    if (!handler.startsWith('set ') && !localSet) {
      issues.add(
        _measuredRefusal(
          Issue(
            code: IssueCode.invalidEventConfiguration,
            message:
                'The measured callback did not lower to an RFW event or '
                'state update, so its private Measurement route cannot be '
                'emitted.',
            location: _locationOf(expression),
          ),
        ),
      );
      return '';
    }
    final tap = _measurementTapEvent(marker, occurrence, expression, issues);
    if (tap.isEmpty) return '';
    return '[$value, $tap]';
  }

  String _measurementTapEvent(
    String marker,
    MeasurementEventOccurrence occurrence,
    Expression expression,
    List<Issue> issues,
  ) => _attachMeasurementRouteMarker(
    'event ${_stringLiteral(kMeasurementPublicationTapEventNameV1)} {}',
    marker,
    expression,
    issues,
    item: _measurementItem(occurrence, expression),
  );

  Set<String> _localValueFields(
    Expression root,
    InlinedDefinitions inlined,
    Set<String> stateFields,
  ) {
    final scanner = _LocalValueWriteScanner(stateFields);
    root.accept(scanner);
    for (final binding in inlined.localBindings.values) {
      binding.accept(scanner);
    }
    for (final helper in inlined.helpers.values) {
      helper.body.accept(scanner);
    }
    return scanner.fields;
  }

  void _collectLocalSeeds(
    List<CustomWidgetStateField> rootState,
    Map<String, RecognisedSetState> handlers,
    Set<String> localFields,
    Map<String, Object> seeds,
    List<Issue> issues,
    Expression anchor,
  ) {
    for (final entry in handlers.entries) {
      // A literal write (a "Clear" or "Reset") lowers to a local set.
      final written = switch (entry.value) {
        SetStateBoolFlip(:final fieldName) => fieldName,
        SetStateLiteral() || SetStateUnrecognised() => null,
      };
      if (written != null && localFields.contains(written)) {
        issues.add(
          Issue(
            code: IssueCode.stateShapeUnsupported,
            message:
                "'$written' is set by a value callback and by "
                "'${entry.key}'. Only literal values can also be set.",
            location: _locationOf(anchor),
          ),
        );
      }
    }
    for (final field in rootState) {
      if (!localFields.contains(field.name)) continue;
      final value = field.initialValue;
      if (value is String || value is bool || value is int || value is double) {
        seeds[field.name] = field.isNumeric && value is int
            ? value.toDouble()
            : value!;
      } else {
        issues.add(
          Issue(
            code: IssueCode.stateShapeUnsupported,
            message:
                "'${field.name}' is set by a value callback, so it needs "
                'a string, number or bool initial value.',
            location: _locationOf(anchor),
          ),
        );
      }
    }
  }

  bool _declaresCompletion(Expression root) {
    final owner = root
        .thisOrAncestorOfType<ClassDeclaration>()
        ?.declaredFragment
        ?.element;
    return owner != null && paywallCompletionEvents(owner).isNotEmpty;
  }

  /// Notes why a plain tap in a loop records no item.
  void _noteUnavailableItem(
    MeasurementEventOccurrence occurrence,
    Expression expression, {
    required bool measured,
  }) {
    final identity = occurrence.itemIdentity;
    final slot = occurrence.sourceEventIdentity.value;
    if (identity is! MeasurementUnavailableItem ||
        (slot != 'onTap' && slot != 'onPressed')) {
      return;
    }
    final location = _locationOf(expression);
    _currentEventClosureNotices?.add(
      Issue(
        code: IssueCode.interactionItemUnavailable,
        message: measured
            ? 'Taps in this loop share one count: no item because '
                  '${identity.reason}.'
            : 'Taps here are not measured: ${identity.reason}.',
        location: location,
        buildNoticeIdentity: 'interaction-item\u0000$location',
      ),
    );
  }

  /// The item DSL a plain tap records, or null. Notes a loop without one.
  String? _measurementItem(
    MeasurementEventOccurrence occurrence,
    Expression expression,
  ) {
    if (occurrence.itemIdentity is MeasurementUnavailableItem) {
      _noteUnavailableItem(occurrence, expression, measured: true);
      return null;
    }
    final item = occurrence.tapItem;
    if (item == null) return null;
    _currentEmitsInteractionItems = true;
    return switch (item) {
      MeasurementStaticItem(:final value) => _stringLiteral(value),
      MeasurementLoopItem(:final loopIdentifier) =>
        '$loopIdentifier${_rfwPathPart(kHostListItemPositionKey)}',
      MeasurementUnavailableItem() => null,
    };
  }

  String _attachMeasurementRouteMarker(
    String value,
    String marker,
    Expression expression,
    List<Issue> issues, {
    String? item,
  }) {
    try {
      return MeasurementRouteEventMarkerEmitter.attach(
        value,
        marker: marker,
        item: item,
      );
    } on ArgumentError catch (error) {
      issues.add(
        Issue(
          code: IssueCode.invalidEventConfiguration,
          message: error.message?.toString() ?? error.toString(),
          location: _locationOf(expression),
        ),
      );
      return '';
    }
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
    return _translateSlotValue(expr, PropertyType.real, issues);
  }

  String _translateDoubleLiteral(Expression expr, List<Issue> issues) {
    return _translateSlotValue(
      expr,
      PropertyType.real,
      issues,
      coerce: false,
    );
  }

  /// Renders a State field's initial value as a DSL literal for the emitted
  /// `widget X { name: <literal>, … }` state block. A numeric field is
  /// coerced to a double literal so the binary form decodes through
  /// `source.v<double>` consistently with constructor-arg coercion. The
  /// caller has already validated that [CustomWidgetStateField.initialValue]
  /// is non-null via [_validateStateShape] — a null reaching here would be
  /// a translator contract violation, so we throw rather than silently emit
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
    final members =
        blueprint.buildExpression
            .thisOrAncestorOfType<ClassDeclaration>()
            ?.body
            .members ??
        const <ClassMember>[];
    for (final field in state) {
      if (field.initialValue == null) {
        final variable = [
          for (final member in members.whereType<FieldDeclaration>())
            ...member.fields.variables,
        ].firstWhereOrNull((v) => v.name.lexeme == field.name);
        final location = _locationOf(variable ?? anchor);
        final start = switch (variable?.initializer) {
          final initializer? => 'starts from `${initializer.toSource()}`',
          null => 'has no constant starting value',
        };
        return Issue(
          code: IssueCode.nestedStateIsland,
          message:
              "'$className' keeps its state in the app: the field "
              "'${field.name}' ($location) $start, which the delivered design "
              'cannot set yet. Try starting the field from a constant value, '
              'if designers should change it.',
          location: _locationOf(anchor),
        );
      }
    }
    // An unrecognised event-handler verdict means the classifier accepted
    // the widget as composable, but the translator cannot emit the handler.
    for (final MapEntry(key: handler, :value)
        in blueprint.eventHandlers.entries) {
      if (value case SetStateUnrecognised(:final reason)) {
        final method = members.whereType<MethodDeclaration>().firstWhereOrNull(
          (m) => m.name.lexeme == handler,
        );
        final location = _locationOf(method ?? anchor);
        final problem = reason.split(' — ').first;
        if (value is SetStateGenerator) {
          return Issue(
            code: IssueCode.nestedStateIsland,
            message:
                "'$className' keeps its state in the app: "
                '${value.problem(handler)} ($location). Try '
                '${value.fix(handler)}.',
            location: _locationOf(anchor),
          );
        }
        return Issue(
          code: IssueCode.nestedStateIsland,
          message:
              "'$className' keeps its state in the app: '$handler' "
              "($location) can't be delivered because $problem. Try "
              '${_setStateFix(reason, handler)}, if designers should change '
              'it.',
          location: _locationOf(anchor),
        );
      }
    }
    return null;
  }

  // The general fix for an unrecognised setState handler's [reason].
  static String _setStateFix(String reason, String handler) {
    const accepted =
        'one setState(...) call with one assignment of a constant, an enum '
        'value or `!field`';
    if (reason.contains('no primitive fields')) {
      return 'keeping the value it changes in a bool, number, String or '
          'enum field';
    }
    if (reason.contains('single assignment')) {
      return 'giving each field its own handler with $accepted';
    }
    if (reason.contains('rather than')) {
      return 'setting the field to a constant or `!field` with `=` in $accepted';
    }
    if (reason.contains('not a single setState') ||
        reason.contains('something other than setState')) {
      return "making '$handler' $accepted, and doing the rest elsewhere";
    }
    return 'writing the handler as $accepted';
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
          message:
              'Root State field "${field.name}" has an initialiser this '
              'transpiler increment cannot fold to a literal. Use a const '
              'bool, num, String, or enum value.',
          location: _locationOf(anchor),
        );
      }
    }
    for (final entry in eventHandlers.entries) {
      final verdict = entry.value;
      if (verdict is SetStateUnrecognised) {
        return _setStateUnrecognisedIssue(entry.key, verdict, anchor);
      }
    }
    return null;
  }

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
      case SetStateLiteral(:final fieldName, :final value)
          when _walk.rootStateContext &&
              _currentLocalFields.contains(fieldName):
        return 'event ${_stringLiteral(kLocalValueSetEventName)} '
            '{ key: ${_stringLiteral(fieldName)}, '
            'value: ${_foldedLiteral(value)} }';
      case SetStateLiteral(:final fieldName, :final value):
        final field = _walk.stateFields?[fieldName];
        final literal = _foldedLiteral(value);
        final coerced = field?.isNumeric == true
            ? asDoubleLiteral(literal)
            : literal;
        return 'set state${_rfwPathPart(fieldName)} = $coerced';
      case SetStateBoolFlip(:final fieldName):
        final path = 'state${_rfwPathPart(fieldName)}';
        return 'set $path = switch $path '
            '{ true: false, false: true }';
      case SetStateUnrecognised():
        issues.add(_setStateUnrecognisedIssue(methodName, verdict, anchor));
        return '';
    }
  }

  /// Builds the `stateShapeUnsupported` issue surfaced when a State method
  /// referenced as an event handler does not match the recognised
  /// single-assignment setState shape. Shared between the emit-time hit
  /// (`_emitSetStateHandler`) and the upfront validation path
  /// (`_validateRootStateShape`) so the wording stays in one place.
  Issue _setStateUnrecognisedIssue(
    String methodName,
    SetStateUnrecognised verdict,
    AstNode anchor,
  ) {
    return Issue(
      code: IssueCode.stateShapeUnsupported,
      message: verdict is SetStateGenerator
          ? 'State method "$methodName" is referenced as an event handler, '
                'but ${verdict.problem(methodName)}. Try '
                '${verdict.fix(methodName)}.'
          : 'State method "$methodName" is referenced as an event '
                'handler but its body is not a recognised setState shape '
                '(a single `setState(() => <field> = <literal>);` or '
                '`setState(() => <field> = !<field>);`). Specifically: '
                '${verdict.reason}.',
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
  ) => _conditionalSwitch(expr, issues, (branch) => _translate(branch, issues));

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
    String Function(Expression) translateBranch,
  ) => _armChecked(
    issues,
    () => _conditionalSwitchArms(expr, issues, translateBranch),
  );

  String _conditionalSwitchArms(
    ConditionalExpression expr,
    List<Issue> issues,
    String Function(Expression) translateBranch,
  ) {
    String branch(Expression value) => _inArm(
      expr,
      value.offset,
      () => _inConditionalBranch(expr, value, () => translateBranch(value)),
    );
    final builder = _activeWidgetBuilder;
    if (builder != null) {
      final condition = builder.value(expr.condition);
      final yes = builder.guarded(
        expr.condition,
        true,
        () => branch(expr.thenExpression),
      );
      final no = builder.guarded(
        expr.condition,
        false,
        () => branch(expr.elseExpression),
      );
      return _switchDsl(condition, [('true', yes), ('false', no)]);
    }
    final brightnessSwitch = _tryBrightnessSwitch(expr, issues, branch);
    if (brightnessSwitch != null) return brightnessSwitch;
    final intSwitch = _tryIntStateEqualitySwitch(expr, issues, branch);
    if (intSwitch != null) return intSwitch;
    final deviceSwitch = _tryDeviceTokenSwitch(expr, issues, branch);
    if (deviceSwitch != null) return deviceSwitch;
    final stringSwitch = _tryStringEqualitySwitch(expr, issues, branch);
    if (stringSwitch != null) return stringSwitch;
    final composedSwitch = _tryComposedConditionSwitch(expr, issues, branch);
    if (composedSwitch != null) return composedSwitch;
    final beforeCondition = issues.length;
    final cond = _conditionKey(expr.condition, issues);
    // Lower every part before refusing so each diagnosed part is reported.
    var refused = _diagnosedEmpty(cond, issues, beforeCondition);
    final beforeThen = issues.length;
    final thenDsl = branch(expr.thenExpression);
    refused |= _diagnosedEmpty(thenDsl, issues, beforeThen);
    final beforeElse = issues.length;
    final elseDsl = branch(expr.elseExpression);
    refused |= _diagnosedEmpty(elseDsl, issues, beforeElse);
    if (refused) return '';
    return _switchDsl(cond, [('true', thenDsl), ('false', elseDsl)]);
  }

  /// Translates one branch [arm] of the emitted switch [id].
  T _inArm<T>(Object id, int arm, T Function() translate) {
    final saved = _walk;
    _walk = _walk.copyWith(armSites: [..._walk.armSites, _ArmSite(id, arm)]);
    try {
      return translate();
    } finally {
      _walk = saved;
    }
  }

  // Each stateful placement in a branch: the switch, branch, slot and class.
  final List<(Object, int, String, String)> _armLog = [];

  // The switches, slots and classes whose branches place one stateful class
  // at one slot: rfw starts that state again when the branch changes.
  final Set<(Object, String, String)> _forcedArms = {};

  /// Translates the branches of one or more switches; when two branches
  /// place one stateful class at one slot, translates them again with that
  /// placement kept in the app.
  T _armChecked<T>(List<Issue> issues, T Function() translate) {
    final logMark = _armLog.length;
    final issueMark = issues.length;
    final restore = _checkpoint();
    final result = translate();
    final first = <(Object, String, String), int>{};
    final shared = <(Object, String, String)>{};
    for (final (id, arm, slot, key) in _armLog.skip(logMark)) {
      if (first.putIfAbsent((id, slot, key), () => arm) != arm) {
        shared.add((id, slot, key));
      }
    }
    shared.removeAll(_forcedArms);
    if (shared.isEmpty) return result;
    restore();
    issues.removeRange(issueMark, issues.length);
    _armLog.length = logMark;
    _forcedArms.addAll(shared);
    return translate();
  }

  /// Translates the [index]th path of a build with several with the
  /// measurement scope qualified by it, as source discovery keys it.
  T _inBuildBranch<T>(int index, T Function() translate) {
    final saved = _walk;
    _walk = _walk.copyWith(
      measurementScope: _walk.measurementScope?.enterBuildBranch(index),
      measurementWidgetList: _walk.measurementWidgetList?.enterBuildBranch(
        index,
      ),
    );
    try {
      return translate();
    } finally {
      _walk = saved;
    }
  }

  /// Translates [branch] with the measurement scope qualified by its path from
  /// [root] through the enclosing conditionals, as source discovery keys it.
  T _inConditionalBranch<T>(
    ConditionalExpression root,
    Expression branch,
    T Function() translate,
  ) {
    final scope = _walk.measurementScope;
    final list = _walk.measurementWidgetList;
    if (scope == null && list == null) return translate();
    final path = <bool>[];
    AstNode? child = branch;
    while (child != null && !identical(child, root)) {
      final parent = child.parent;
      if (parent is ConditionalExpression) {
        if (identical(parent.thenExpression, child)) {
          path.add(true);
        } else if (identical(parent.elseExpression, child)) {
          path.add(false);
        }
      }
      child = parent;
    }
    if (child == null) return translate();
    var qualifiedScope = scope;
    var qualifiedList = list;
    for (final then in path.reversed) {
      qualifiedScope = qualifiedScope?.enterConditionalBranch(then: then);
      qualifiedList = qualifiedList?.enterConditionalBranch(then: then);
    }
    final saved = _walk;
    _walk = _walk.copyWith(
      measurementScope: qualifiedScope,
      measurementWidgetList: qualifiedList,
    );
    try {
      return translate();
    } finally {
      _walk = saved;
    }
  }

  bool _diagnosedEmpty(String value, List<Issue> issues, int beforeIssues) =>
      value.isEmpty && issues.length > beforeIssues;

  /// A `switch` over [input]. An arm that yields no value (a Dart `null`) is
  /// left out, or spelled as a switch with no case when a default would
  /// otherwise catch it; a switch with no values at all yields no value.
  String _switchDsl(
    String input,
    List<(String, String)> arms, {
    String? defaultDsl,
  }) {
    final fallback = defaultDsl == _kNoValue ? null : defaultDsl;
    if (fallback == null && arms.every((arm) => arm.$2 == _kNoValue)) {
      return _kNoValue;
    }
    final cases = [
      for (final (key, value) in arms)
        if (value != _kNoValue)
          '$key: $value'
        else if (fallback != null)
          '$key: $_kNoValueSwitch',
      if (fallback != null) 'default: $fallback',
    ];
    return 'switch $input { ${cases.join(', ')} }';
  }

  /// Attempts to lower [expr] — a conditional testing the ambient theme's
  /// brightness — to a `switch` keyed on `data.theme.brightness`. Returns the
  /// switch DSL for `<brightness read> ==|!= Brightness.<light|dark>` in either
  /// operand order, `''` after a diagnostic for a comparison that involves a
  /// brightness read without matching that shape, and `null` when the condition
  /// is not about brightness at all so the caller falls through.
  String? _tryBrightnessSwitch(
    ConditionalExpression expr,
    List<Issue> issues,
    String Function(Expression) branch,
  ) {
    // A theme comparison held in a build local is still that comparison.
    final seesThrough = _seesThroughPreludes;
    _seesThroughPreludes = true;
    final Expression resolved;
    try {
      resolved = _resolveBoundIdentifier(_stripParens(expr.condition));
    } finally {
      _seesThroughPreludes = seesThrough;
    }
    final cond = _stripParens(resolved);
    if (cond is! BinaryExpression) return null;
    final bindings = _walk.inlined.localBindings;
    final match = brightnessComparison(
      cond,
      bindings: bindings,
      isFrameworkLibrary: _frameworkOrUnresolved,
    );
    if (match == null) {
      if (!comparisonInvolvesBrightnessRead(cond, bindings: bindings)) {
        return null;
      }
      issues.add(
        Issue(
          code: IssueCode.themeReadOutOfContract,
          message:
              'A brightness read lowers only as an equality against '
              '`Brightness.light` or `Brightness.dark` '
              '(`Theme.of(context).brightness == Brightness.dark ? a : b`). '
              '${cond.toSource()} is not that shape.',
          location: _locationOf(cond),
        ),
      );
      return '';
    }
    // Lower every arm before refusing so each diagnosed arm is reported.
    final beforeThen = issues.length;
    final thenDsl = branch(expr.thenExpression);
    var refused = _diagnosedEmpty(thenDsl, issues, beforeThen);
    final beforeElse = issues.length;
    final elseDsl = branch(expr.elseExpression);
    refused |= _diagnosedEmpty(elseDsl, issues, beforeElse);
    if (refused) return '';
    final matched = match.equals ? thenDsl : elseDsl;
    final other = match.equals ? elseDsl : thenDsl;
    return _switchDsl(
      'data.theme.brightness',
      [(_stringLiteral(match.token), matched)],
      defaultDsl: other,
    );
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
      if (cond is BinaryExpression) {
        final negated = _intStateComparison(cond);
        if (negated != null) {
          return _twoArmSwitch(
            expr,
            issues,
            branch,
            negated.ref,
            negated.key,
            negated: true,
          );
        }
      }
      if (cond is BinaryExpression && _comparisonInvolvesIntStateField(cond)) {
        issues.add(
          Issue(
            code: IssueCode.intStateConditionUnsupported,
            message:
                'Only `== <intLiteral>` and `!= <intLiteral>` '
                'comparisons on an integer state field or an integer '
                'constructor parameter lower to a switch (with the reference '
                'on the left and an integer literal on the right). `<`, `>`, '
                'a non-literal comparison, and the literal-on-the-left form '
                'are not supported — express the selection as an equality '
                'chain (`field == 0 ? … : field == 1 ? … : …`).',
            location: _locationOf(cond),
          ),
        );
        return '';
      }
      return null;
    }

    // Flatten consecutive same-reference `== <intLiteral>` arms into one
    // switch.
    final ref = head.ref;
    final arms = <(String, String)>[];
    // Lower every arm before refusing so each diagnosed arm is reported.
    var refused = false;
    Expression? defaultBranch;
    ConditionalExpression? current = expr;
    while (current != null) {
      final match = _intStateEquality(_stripParens(current.condition));
      if (match == null || match.ref != ref) {
        // The else chain reached a condition that is not `<sameField> ==
        // <intLiteral>` — this conditional (a different-field comparison, a
        // bool ref, …) is the default; [branch] lowers it normally, so a
        // different-field comparison recurses to its own nested switch.
        defaultBranch = current;
        break;
      }
      final beforeArm = issues.length;
      final armDsl = branch(current.thenExpression);
      refused |= _diagnosedEmpty(armDsl, issues, beforeArm);
      arms.add((match.key, armDsl));
      final elseExpr = _stripParens(current.elseExpression);
      if (elseExpr is ConditionalExpression) {
        current = elseExpr;
      } else {
        defaultBranch = current.elseExpression;
        current = null;
      }
    }
    final beforeDefault = issues.length;
    final defaultDsl = branch(defaultBranch!);
    refused |= _diagnosedEmpty(defaultDsl, issues, beforeDefault);
    if (refused) return '';
    return _switchDsl(ref, arms, defaultDsl: defaultDsl);
  }

  /// Lowers a condition bound straight to a boolean slot —
  /// `Visibility(visible: !trialUsed && isPro)` — to the switches a ternary
  /// condition produces, selecting `true` or `false`. `null` for a bare
  /// reference, which keeps the ordinary path.
  String? _booleanSlotCondition(Expression expr, List<Issue> issues) {
    final shaped =
        _isComposedCondition(expr) ||
        _distributedEquality(expr) != null ||
        (expr is BinaryExpression &&
            (_intStateComparison(expr) != null ||
                _stringComparison(expr) != null ||
                _deviceTokenComparison(expr) != null ||
                brightnessComparison(
                      expr,
                      bindings: _walk.inlined.localBindings,
                      isFrameworkLibrary: _frameworkOrUnresolved,
                    ) !=
                    null));
    if (!shaped) return null;
    final conditionIssues = <Issue>[];
    final lowering = _lowerCondition(expr, conditionIssues);
    if (lowering == null) return null;
    issues.addAll(conditionIssues);
    return lowering('true', 'false');
  }

  /// Renders both arms once into a 2-arm `switch` keyed on [ref]. [negated]
  /// swaps them, so a `!=` comparison selects the else branch on a match.
  String _twoArmSwitch(
    ConditionalExpression expr,
    List<Issue> issues,
    String Function(Expression) branch,
    String ref,
    String key, {
    required bool negated,
  }) {
    final beforeThen = issues.length;
    final thenDsl = branch(expr.thenExpression);
    var refused = _diagnosedEmpty(thenDsl, issues, beforeThen);
    final beforeElse = issues.length;
    final elseDsl = branch(expr.elseExpression);
    refused |= _diagnosedEmpty(elseDsl, issues, beforeElse);
    if (refused) return '';
    final onMatch = negated ? elseDsl : thenDsl;
    final otherwise = negated ? thenDsl : elseDsl;
    return _switchDsl(ref, [(key, onMatch)], defaultDsl: otherwise);
  }

  /// Lowers a conditional whose condition compares a String reference to a
  /// literal, flattening a same-reference `==` chain into one N-arm switch.
  /// `null` when the condition is not a string comparison.
  String? _tryStringEqualitySwitch(
    ConditionalExpression expr,
    List<Issue> issues,
    String Function(Expression) branch,
  ) {
    final head = _stringComparison(_stripParens(expr.condition));
    if (head == null) return null;
    if (head.negated) {
      return _twoArmSwitch(
        expr,
        issues,
        branch,
        head.ref,
        head.key,
        negated: true,
      );
    }
    final ref = head.ref;
    final arms = <(String, String)>[];
    var refused = false;
    Expression? defaultBranch;
    ConditionalExpression? current = expr;
    while (current != null) {
      final match = _stringComparison(_stripParens(current.condition));
      if (match == null || match.negated || match.ref != ref) {
        defaultBranch = current;
        break;
      }
      final beforeArm = issues.length;
      final armDsl = branch(current.thenExpression);
      refused |= _diagnosedEmpty(armDsl, issues, beforeArm);
      arms.add((match.key, armDsl));
      final elseExpr = _stripParens(current.elseExpression);
      if (elseExpr is ConditionalExpression) {
        current = elseExpr;
      } else {
        defaultBranch = current.elseExpression;
        current = null;
      }
    }
    final beforeDefault = issues.length;
    final defaultDsl = branch(defaultBranch!);
    refused |= _diagnosedEmpty(defaultDsl, issues, beforeDefault);
    if (refused) return '';
    return _switchDsl(ref, arms, defaultDsl: defaultDsl);
  }

  /// Lowers a conditional whose condition negates or composes other
  /// conditions. `null` when it is not a composition or an operand does not
  /// lower, leaving the caller's bool path to refuse it.
  String? _tryComposedConditionSwitch(
    ConditionalExpression expr,
    List<Issue> issues,
    String Function(Expression) branch,
  ) {
    final cond = _resolveBoundIdentifier(expr.condition);
    if (!_isComposedCondition(cond) && _distributedEquality(cond) == null) {
      return null;
    }
    // Collect separately: on a refusal the caller's bool path reports the
    // condition, so these would be a second diagnostic.
    final conditionIssues = <Issue>[];
    final lowering = _lowerCondition(cond, conditionIssues);
    if (lowering == null) return null;
    issues.addAll(conditionIssues);
    final beforeThen = issues.length;
    final thenDsl = _copiedUnder(
      expr.condition,
      _copiesBranch(lowering, then: true),
      () => branch(expr.thenExpression),
    );
    var refused = _diagnosedEmpty(thenDsl, issues, beforeThen);
    final beforeElse = issues.length;
    final elseDsl = _copiedUnder(
      expr.condition,
      _copiesBranch(lowering, then: false),
      () => branch(expr.elseExpression),
    );
    refused |= _diagnosedEmpty(elseDsl, issues, beforeElse);
    if (refused) return '';
    return lowering(thenDsl, elseDsl);
  }

  // Whether [lowering] emits its true branch, or with [then] false its false
  // branch, more than once: rfw rebinds such a copy when another part of the
  // condition starts deciding.
  static bool _copiesBranch(_ConditionLowering lowering, {required bool then}) {
    final marker = then ? '\u0001T' : '\u0001F';
    return marker.allMatches(lowering('\u0001T', '\u0001F')).length > 1;
  }

  // Runs [translate] with [condition] as the guard of a copied branch.
  T _copiedUnder<T>(Expression condition, bool copied, T Function() translate) {
    if (!copied) return translate();
    final saved = _walk;
    _walk = _walk.copyWith(stateGuard: condition);
    try {
      return translate();
    } finally {
      _walk = saved;
    }
  }

  bool _isComposedCondition(Expression cond) {
    if (cond is PrefixExpression) return cond.operator.lexeme == '!';
    if (cond is BinaryExpression) {
      final op = cond.operator.lexeme;
      return op == '&&' || op == '||';
    }
    return false;
  }

  /// Lowers a condition to a builder that wraps two already-rendered arms in
  /// the selecting switches, or `null` when it is not expressible as a
  /// composition of switches. Arms arrive as strings, so a composition that
  /// repeats one repeats text rather than re-rendering it.
  _ConditionLowering? _lowerCondition(
    Expression condition,
    List<Issue> issues,
  ) {
    final cond = _resolveBoundIdentifier(condition);
    final flag = devicePlatformFlag(cond);
    if (flag != null) {
      return _keyedLowering(
        'data.device.platform',
        _stringLiteral(flag),
        negated: false,
      );
    }
    if (cond is PrefixExpression && cond.operator.lexeme == '!') {
      final inner = _lowerCondition(cond.operand, issues);
      return inner == null
          ? null
          : _ConditionLowering(
              (whenTrue, whenFalse) => inner(whenFalse, whenTrue),
            );
    }
    if (cond is BinaryExpression) {
      final op = cond.operator.lexeme;
      if (op == '&&' || op == '||') {
        final left = _lowerCondition(cond.leftOperand, issues);
        if (left == null) return null;
        final right = _lowerCondition(cond.rightOperand, issues);
        if (right == null) return null;
        return op == '&&'
            ? _ConditionLowering(
                (whenTrue, whenFalse) =>
                    left(right(whenTrue, whenFalse), whenFalse),
              )
            : _ConditionLowering(
                (whenTrue, whenFalse) =>
                    left(whenTrue, right(whenTrue, whenFalse)),
              );
      }
      final device = _deviceTokenComparison(cond);
      if (device != null) {
        return _keyedLowering(
          'data.device.${device.path}',
          _stringLiteral(device.key),
          negated: device.negated,
        );
      }
      final brightness = brightnessComparison(
        cond,
        bindings: _walk.inlined.localBindings,
        isFrameworkLibrary: _frameworkOrUnresolved,
      );
      if (brightness != null) {
        return _keyedLowering(
          'data.theme.brightness',
          _stringLiteral(brightness.token),
          negated: !brightness.equals,
        );
      }
      final intMatch = _intStateComparison(cond);
      if (intMatch != null) {
        return _keyedLowering(
          intMatch.ref,
          intMatch.key,
          negated: intMatch.negated,
        );
      }
      final stringMatch = _stringComparison(cond);
      if (stringMatch != null) {
        return _keyedLowering(
          stringMatch.ref,
          stringMatch.key,
          negated: stringMatch.negated,
        );
      }
      final distributed = _distributedEquality(cond);
      if (distributed != null) {
        return _lowerEquality(
          distributed.operand,
          distributed.literal,
          issues,
          negated: distributed.negated,
        );
      }
      // A split surface's mount can compute any other comparison.
      if (_islands == null) return null;
    }
    final before = issues.length;
    final dsl = _conditionKey(cond, issues);
    if (dsl.isEmpty || issues.length > before) return null;
    return _ConditionLowering(
      (whenTrue, whenFalse) =>
          _switchDsl(dsl, [('true', whenTrue), ('false', whenFalse)]),
    );
  }

  /// [condition] as a switch key. A switch resolves its key as data, so a
  /// condition that lowers to a program is the value the mount computes;
  /// with no mount to compute it, it lowers as data or is refused.
  String _conditionKey(Expression condition, List<Issue> issues) {
    final site = _valueSite;
    _valueSite = condition;
    try {
      return _conditionKeyAt(condition, issues);
    } finally {
      _valueSite = site;
    }
  }

  String _conditionKeyAt(Expression condition, List<Issue> issues) {
    final dsl = _translateSlotValue(condition, PropertyType.boolean, issues);
    if (!dsl.startsWith(_kValueProgram)) return dsl;
    // A switch reads its key as data, so a key is never a program: it is the
    // value the mount computes, or, with none to compute it, data or refused.
    final hoist = _hoist;
    final type = condition.staticType;
    final verdict = classifyHoistType(type);
    final stripped = _stripParens(condition);
    final analysis = hoist?.analyzer.analyze(stripped);
    if (hoist == null ||
        verdict is! HoistCrosses ||
        type == null ||
        analysis is! HoistEvaluable) {
      return _translateSlotValueLegacy(condition, PropertyType.boolean, issues);
    }
    return _hoistedRead(
      hoist.add(analysis.value(verdict, type, expression: stripped)),
    );
  }

  static const _kValueProgram = '{ version: 1, program: ';

  /// An equality whose operand resolves to a conditional or a bound literal.
  ({Expression operand, Expression literal, bool negated})?
  _distributedEquality(Expression cond) {
    if (cond is! BinaryExpression) return null;
    final op = cond.operator.lexeme;
    if (op != '==' && op != '!=') return null;
    for (final (operand, literal) in [
      (cond.leftOperand, cond.rightOperand),
      (cond.rightOperand, cond.leftOperand),
    ]) {
      if (_equalityLiteral(literal) == null) continue;
      final resolved = _resolveBoundIdentifier(operand);
      if (resolved is ConditionalExpression ||
          _equalityLiteral(resolved) != null) {
        return (operand: operand, literal: literal, negated: op == '!=');
      }
    }
    return null;
  }

  /// The value of a string, int, or bool literal, or `null` for any other
  /// expression.
  Object? _equalityLiteral(Expression expr) => switch (_stripParens(expr)) {
    SimpleStringLiteral(:final value) => value,
    IntegerLiteral(:final value) => value,
    BooleanLiteral(:final value) => value,
    _ => null,
  };

  /// Lowers `operand == literal` (or `!=`), pushing the comparison into each
  /// arm when [operand] resolves to a conditional.
  _ConditionLowering? _lowerEquality(
    Expression operand,
    Expression literal,
    List<Issue> issues, {
    required bool negated,
  }) {
    final value = _resolveBoundIdentifier(operand);
    if (value is ConditionalExpression) {
      final selector = _lowerCondition(value.condition, issues);
      if (selector == null) return null;
      final whenThen = _lowerEquality(
        value.thenExpression,
        literal,
        issues,
        negated: negated,
      );
      if (whenThen == null) return null;
      final whenElse = _lowerEquality(
        value.elseExpression,
        literal,
        issues,
        negated: negated,
      );
      if (whenElse == null) return null;
      return _ConditionLowering(
        (whenTrue, whenFalse) => selector(
          whenThen(whenTrue, whenFalse),
          whenElse(whenTrue, whenFalse),
        ),
      );
    }
    final constant = _equalityLiteral(value);
    final expected = _equalityLiteral(literal);
    if (constant != null && expected != null) {
      final holds = (constant == expected) != negated;
      return _ConditionLowering(
        (whenTrue, whenFalse) => holds ? whenTrue : whenFalse,
      );
    }
    final stringRef = _stringConditionRef(value);
    final stringKey = _stringConditionKey(literal);
    if (stringRef != null && stringKey != null) {
      return _keyedLowering(stringRef, stringKey, negated: negated);
    }
    final intRef = _intConditionRef(value);
    final intKey = _intConditionKey(literal);
    if (intRef != null && intKey != null) {
      return _keyedLowering(intRef, intKey, negated: negated);
    }
    return null;
  }

  _ConditionLowering _keyedLowering(
    String ref,
    String key, {
    required bool negated,
  }) => _ConditionLowering(
    (whenTrue, whenFalse) => negated
        ? _switchDsl(ref, [(key, whenFalse)], defaultDsl: whenTrue)
        : _switchDsl(ref, [(key, whenTrue)], defaultDsl: whenFalse),
  );

  /// The `(ref, key, negated)` of an `<intRef> == <intLiteral>` or `!=`
  /// comparison, or `null` for any other shape.
  ({String ref, String key, bool negated})? _intStateComparison(
    BinaryExpression cond,
  ) {
    final op = cond.operator.lexeme;
    if (op != '==' && op != '!=') return null;
    final ref = _intConditionRef(cond.leftOperand);
    if (ref == null) return null;
    final key = _intConditionKey(cond.rightOperand);
    return key == null ? null : (ref: ref, key: key, negated: op == '!=');
  }

  /// The `(ref, key, negated)` of a `<stringRef> == '<literal>'` or `!=`
  /// comparison, in either operand order, or `null` for any other shape.
  ({String ref, String key, bool negated})? _stringComparison(Expression cond) {
    if (cond is! BinaryExpression) return null;
    final op = cond.operator.lexeme;
    if (op != '==' && op != '!=') return null;
    final negated = op == '!=';
    final left = _stringConditionRef(cond.leftOperand);
    if (left != null) {
      final key = _stringConditionKey(cond.rightOperand);
      return key == null ? null : (ref: left, key: key, negated: negated);
    }
    final right = _stringConditionRef(cond.rightOperand);
    if (right == null) return null;
    final key = _stringConditionKey(cond.leftOperand);
    return key == null ? null : (ref: right, key: key, negated: negated);
  }

  /// The constructor-parameter name a String-typed reference reads.
  String? _stringArgName(Expression expr) =>
      expr.staticType?.isDartCoreString == true ? _argName(expr) : null;

  /// The constructor-parameter name [expr] reads inside the custom-widget
  /// definition being translated, as a bare identifier or `widget.<name>`.
  String? _argName(Expression expr) {
    if (expr is SimpleIdentifier) return _walk.argNames[expr.name];
    if (expr is PrefixedIdentifier &&
        expr.prefix.name == 'widget' &&
        _walk.stateFields != null) {
      return _walk.argNames[expr.identifier.name];
    }
    return null;
  }

  /// The DSL key for a string switch arm, or `null` for a non-literal.
  String? _stringConditionKey(Expression expr) {
    final literal = _stripParens(expr);
    if (literal is! SimpleStringLiteral) return null;
    return _stringLiteral(literal.value);
  }

  /// The data reference for a String condition operand: a State field, a
  /// constructor parameter, or a host-data read of a String scalar.
  String? _stringConditionRef(Expression expr) {
    final resolved = _resolveBoundIdentifier(expr);
    if (resolved is SimpleIdentifier &&
        resolved.element is! LocalVariableElement &&
        resolved.element is! FormalParameterElement) {
      final field = _walk.stateFields?[resolved.name];
      if (field != null && field.initialValue is String) {
        return 'state${_rfwPathPart(resolved.name)}';
      }
    }
    final argName = _stringArgName(resolved);
    if (argName != null) return 'args${_rfwPathPart(argName)}';
    final root = _rootParamAccess(resolved);
    if (root != null && root.param.hasNonNullDefault) return null;
    final reference = _shapedReference(resolved);
    if (reference case (
      :final dsl,
      shape: HostDataScalarShape(kind: HostDataScalarKind.string),
    )) {
      return dsl;
    }
    return null;
  }

  /// Lowers a conditional whose condition matches device data by equality to a
  /// `switch` on `data.device.<path>`. Returns `''` after a diagnostic when the
  /// condition reads device data through an unsupported operator, and `null`
  /// when it does not read device data at all.
  String? _tryDeviceTokenSwitch(
    ConditionalExpression expr,
    List<Issue> issues,
    String Function(Expression) branch,
  ) {
    final cond = _stripParens(_resolveBoundIdentifier(expr.condition));
    // A bare platform flag — `kIsWeb`, or a `dart:io` `Platform.isX` getter.
    final flag = devicePlatformFlag(cond);
    if (flag != null) {
      return _deviceSwitch(
        path: 'platform',
        arms: <(String, Expression)>[(flag, expr.thenExpression)],
        defaultBranch: expr.elseExpression,
        issues: issues,
        branch: branch,
      );
    }
    final head = _deviceTokenComparison(expr.condition);
    if (head == null) {
      if (_readsDeviceData(expr.condition)) {
        // A negation or `&&` / `||` over lowerable operands belongs to the
        // composed attempt; only an unsupported shape refuses here.
        if (_isComposedCondition(cond) && _lowerCondition(cond, []) != null) {
          return null;
        }
        issues.add(_deviceConditionIssue(cond, _deviceConditionReason(cond)));
        return '';
      }
      return null;
    }
    if (head.negated) {
      // `p != X ? a : b` selects `b` when the value matches, so the arms swap.
      return _deviceSwitch(
        path: head.path,
        arms: <(String, Expression)>[(head.key, expr.elseExpression)],
        defaultBranch: expr.thenExpression,
        issues: issues,
        branch: branch,
      );
    }
    // Flatten consecutive SAME-path `==` arms into one switch.
    final arms = <(String, Expression)>[];
    Expression? defaultBranch;
    ConditionalExpression? current = expr;
    while (current != null) {
      final match = _deviceTokenComparison(current.condition);
      if (match == null || match.negated || match.path != head.path) {
        defaultBranch = current;
        break;
      }
      arms.add((match.key, current.thenExpression));
      final elseExpr = _stripParens(current.elseExpression);
      if (elseExpr is ConditionalExpression) {
        current = elseExpr;
      } else {
        defaultBranch = current.elseExpression;
        current = null;
      }
    }
    return _deviceSwitch(
      path: head.path,
      arms: arms,
      defaultBranch: defaultBranch!,
      issues: issues,
      branch: branch,
    );
  }

  /// Emits the device `switch`, lowering every arm before refusing.
  String _deviceSwitch({
    required String path,
    required List<(String, Expression)> arms,
    required Expression defaultBranch,
    required List<Issue> issues,
    required String Function(Expression) branch,
  }) {
    var refused = false;
    final armsDsl = <(String, String)>[];
    for (final (key, value) in arms) {
      final before = issues.length;
      final dsl = branch(value);
      refused |= _diagnosedEmpty(dsl, issues, before);
      armsDsl.add((_stringLiteral(key), dsl));
    }
    final beforeDefault = issues.length;
    final defaultDsl = branch(defaultBranch);
    refused |= _diagnosedEmpty(defaultDsl, issues, beforeDefault);
    if (refused) return '';
    return _switchDsl(
      'data.device.$path',
      armsDsl,
      defaultDsl: defaultDsl,
    );
  }

  /// The device-token equality [cond] expresses, via the canonical
  /// [deviceTokenComparison] recogniser the classifier also calls.
  ({String path, String key, bool negated})? _deviceTokenComparison(
    Expression cond,
  ) {
    final resolved = _stripParens(_resolveBoundIdentifier(cond));
    if (resolved is! BinaryExpression) return null;
    final match = deviceTokenComparison(
      resolved,
      bindings: _walk.inlined.localBindings,
      resolve: _resolveBoundIdentifier,
      isFrameworkLibrary: _frameworkOrUnresolved,
    );
    if (match == null) return null;
    return (path: match.path, key: match.key, negated: !match.equals);
  }

  /// Whether [expr] reads device data anywhere in a comparison tree.
  bool _readsDeviceData(Expression expr) {
    final e = _stripParens(_resolveBoundIdentifier(expr));
    if (_recognizeDeviceRead(e) != null) return true;
    if (e is BinaryExpression) {
      return _readsDeviceData(e.leftOperand) ||
          _readsDeviceData(e.rightOperand);
    }
    if (e is PrefixExpression) return _readsDeviceData(e.operand);
    return false;
  }

  String _deviceConditionReason(Expression cond) {
    const relational = {'<', '>', '<=', '>='};
    final e = _stripParens(cond);
    if (e is BinaryExpression && relational.contains(e.operator.lexeme)) {
      return 'the data language has no comparison or arithmetic operators, '
          'so a numeric comparison on device data cannot be expressed';
    }
    return 'only equality against a `TargetPlatform` value or a string '
        'literal lowers';
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
    if (e.element is LocalVariableElement ||
        e.element is FormalParameterElement) {
      return null;
    }
    final field = _walk.stateFields?[e.name];
    if (field == null || field.isNumeric || field.initialValue is! int) {
      return null;
    }
    return field;
  }

  /// The constructor-parameter name an `int`-typed reference reads. An `int`
  /// parameter carries [PropertyType.integer], so its call-site value stays a
  /// bare int and the switch keys match it.
  String? _intArgName(Expression expr) {
    if (expr.staticType?.isDartCoreInt != true) return null;
    return _argName(expr);
  }

  /// The data reference for an integer condition operand: a State field or a
  /// constructor parameter. The one definition of "an integer reference",
  /// shared by the equality decomposition and the near-miss check.
  String? _intConditionRef(Expression expr) {
    final resolved = _resolveBoundIdentifier(expr);
    final field = _intStateFieldOf(resolved);
    if (field != null) return 'state${_rfwPathPart(field.name)}';
    final argName = _intArgName(resolved);
    return argName == null ? null : 'args${_rfwPathPart(argName)}';
  }

  /// The `(ref, key)` of `<intRef> == <intLiteral>`, or `null` for any other
  /// shape.
  ({String ref, String key})? _intStateEquality(Expression cond) {
    if (cond is! BinaryExpression || cond.operator.lexeme != '==') return null;
    final ref = _intConditionRef(cond.leftOperand);
    if (ref == null) return null;
    final key = _intConditionKey(cond.rightOperand);
    return key == null ? null : (ref: ref, key: key);
  }

  /// The DSL key for an integer switch arm, or `null` for a non-literal.
  String? _intConditionKey(Expression expr) {
    final literal = _stripParens(expr);
    if (literal is! IntegerLiteral) return null;
    final value = literal.value;
    return value?.toString();
  }

  /// Whether [cond] compares an integer reference, so a near-miss gets the
  /// equality-only defer instead of the generic unsupported-expression error.
  bool _comparisonInvolvesIntStateField(BinaryExpression cond) {
    const comparisonOps = {'==', '!=', '<', '>', '<=', '>='};
    if (!comparisonOps.contains(cond.operator.lexeme)) return false;
    return _intConditionRef(cond.leftOperand) != null ||
        _intConditionRef(cond.rightOperand) != null;
  }

  String _normalizePresentDsl(
    List<Issue> issues,
    String Function() emit,
  ) => unwrapDslEmission(normalizePresentChild(issues, emit));

  String? _normalizeNullablePresentDsl(
    List<Issue> issues,
    String? Function() emit,
  ) {
    final issueStart = issues.length;
    final value = emit();
    return value == null
        ? null
        : unwrapDslEmission(normalizePresentValue(issues, issueStart, value));
  }

  String _translateTypedListTerminal(
    Expression source,
    PropertyType itemType,
    List<Issue> issues, {
    PropertyType? listType,
    DartType? declaredItemType,
  }) {
    final resolved = _resolveBoundIdentifier(_stripParens(source));
    // A theme read is a data reference to a published list, not a Dart list
    // expression; the slot's contract validation has already checked it.
    if (_recognizeThemeRead(resolved) != null) {
      return _translate(resolved, issues);
    }
    final rootAccess = _rootParamAccess(resolved);
    if (rootAccess == null || rootAccess.isRefused) {
      if (resolved is ListLiteral) {
        return _listLiteral(resolved, issues, itemType: itemType);
      }
      final sourceType = resolved.staticType;
      final elementType = sourceType == null
          ? null
          : _dartCoreListElementType(sourceType);
      if (elementType != null &&
          _typedListItemDecoderAcceptsDartType(
            itemType,
            elementType,
            listType: listType,
            declaredItemType: declaredItemType,
          )) {
        return _translateTypedListValue(resolved, itemType, issues);
      }
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message:
              "The list expression '${source.toSource()}' is declared "
              "'${sourceType?.getDisplayString() ?? '<unresolved>'}' and its "
              "elements cannot be assigned to a '${itemType.name}' item "
              'decoder at this site.',
          location: _locationOf(source),
        ),
      );
      return '';
    }
    final param = rootAccess.param;
    if (!param.isHostData || param.hasNonNullDefault) {
      return _translate(resolved, issues);
    }
    final rootShape = rootAccess.shape;
    if (rootShape is HostDataListShape &&
        _propertyTypeAcceptsHostDataShape(
          itemType,
          rootShape.elementShape,
        )) {
      return _translate(resolved, issues);
    }
    issues.add(
      Issue(
        code: IssueCode.propertyValueTypeMismatch,
        message:
            "Host data list 'data.context.${param.name}' is declared "
            "'${param.type.getDisplayString()}' and its elements cannot be "
            "assigned to a '${itemType.name}' item decoder at this site.",
        location: _locationOf(source),
      ),
    );
    return '';
  }

  String _translateTypedListValue(
    Expression source,
    PropertyType itemType,
    List<Issue> issues,
  ) {
    final resolved = _resolveBoundIdentifier(_stripParens(source));
    if (resolved is ConditionalExpression) {
      return _conditionalSwitch(
        resolved,
        issues,
        (branch) => _translateTypedListValue(branch, itemType, issues),
      );
    }
    if (resolved is ListLiteral) {
      return _listLiteral(resolved, issues, itemType: itemType);
    }
    return _translate(resolved, issues);
  }

  bool _typedListItemDecoderAcceptsDartType(
    PropertyType itemType,
    DartType dartType, {
    PropertyType? listType,
    DartType? declaredItemType,
  }) {
    final frameworkItemName = switch (listType) {
      PropertyType.boxShadowList => 'BoxShadow',
      PropertyType.shadowList => 'Shadow',
      PropertyType.fontFeatureList => 'FontFeature',
      PropertyType.fontVariationList => 'FontVariation',
      _ => null,
    };
    if (frameworkItemName != null) {
      return _isExactFrameworkType(dartType, frameworkItemName);
    }
    if (listType == PropertyType.selectionOptionList) {
      return _isSelectionOptionType(dartType);
    }
    if (_propertyTypeAcceptsHostDataType(itemType, dartType) ||
        inferPropertyType(dartType) == itemType) {
      return true;
    }
    if (itemType == PropertyType.textDecoration) {
      return _isExactFrameworkType(dartType, 'TextDecoration');
    }
    if (declaredItemType == null || declaredItemType != dartType) return false;
    if (inferPropertyType(declaredItemType) != null ||
        _isSelectionOptionType(declaredItemType)) {
      return true;
    }
    final element = declaredItemType.element;
    if (element != null &&
        _kTranslatedTypedListFrameworkItems.contains(element.name) &&
        _isFrameworkValueType(element)) {
      return true;
    }
    if (element is! ClassElement) return false;
    final ref = _dartTypeRefOfClass(element);
    return ref != null && _customStructuredByDartType.containsKey(ref);
  }

  bool _isExactFrameworkType(DartType type, String name) {
    final element = type.element;
    return element?.name == name && _isFrameworkValueType(element);
  }

  bool _isSelectionOptionType(DartType type) {
    final element = type.element;
    return element?.name == 'RestageSelectionOption' &&
        element?.library?.identifier == _kSelectionOptionLibraryOrigin;
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
    FormalParameterElement? sourceParameter,
    bool coerce = true,
  }) {
    final ref =
        property?.structuredRef ??
        (property?.valueShape is StructuredShape
            ? (property!.valueShape as StructuredShape).structuredRef
            : null);
    final structured = ref == null
        ? null
        : _nativeCatalogIndex.structuredByRef(ref);
    final native = structured == null
        ? null
        : nativeBindingRoute(structured.sourceType);
    if (native != null) {
      final resolved = _resolveBoundIdentifier(_stripParens(expr));
      if (_isNullLiteral(resolved) && property?.constructorNullable == true)
        return 'null';
      // The mount records the app's own object where the build computes it.
      final binding = _nativeBindingRead(
        resolved,
        type: native.contractType,
        computed: _islands != null,
      );
      if (binding != null) return binding;
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message:
              'A native ${native.dartType} requires an exact constructor-supplied binding.',
          location: _locationOf(expr),
        ),
      );
      return '';
    }
    if (structured != null &&
        optionalNativeDecoder(
              structured.sourceType,
              namespace: structured.library.namespace,
            ) !=
            null) {
      return _optionalNativeValue(
            expr,
            issues,
            expected: structured.sourceType,
          ) ??
          '';
    }
    final dsl = _translateSlotValueUnrecorded(
      expr,
      type,
      issues,
      property: property,
      sourceParameter: sourceParameter,
      coerce: coerce,
    );
    _recordEmission(expr, dsl);
    return dsl;
  }

  String _translateSlotValueUnrecorded(
    Expression expr,
    PropertyType type,
    List<Issue> issues, {
    PropertyEntry? property,
    FormalParameterElement? sourceParameter,
    bool coerce = true,
  }) {
    if (type == PropertyType.color) {
      expr = _rootColorSource(expr);
      final borrowed = _nativeBindingRead(expr, type: 'flutter.Color');
      if (borrowed != null) return borrowed;
    }
    final colorExpression = type == PropertyType.color
        ? _installedColorExpression(expr)
        : null;
    if (colorExpression != null) {
      try {
        final native = _tryNativeCallValue(
          colorExpression,
          issues,
          type: 'flutter.Color',
        );
        if (native != null) return native;
      } on BuilderLoweringException catch (error) {
        issues.add(
          Issue(
            code: IssueCode.propertyValueTypeMismatch,
            message: error.reason,
            location: _locationOf(error.node),
          ),
        );
        return '';
      }
    }
    final beforeValidation = issues.length;
    _validateDataRefForSlot(expr, type, issues, property: property);
    if (issues.length > beforeValidation) return '';
    final staticType = expr.staticType;
    final verdict = classifyHoistType(staticType);
    if (staticType != null &&
        verdict is HoistCrosses &&
        verdict.kind == HoistValueKind.scalar &&
        _readsKeyboardOrAccessibility(expr) &&
        !_propertyTypeAcceptsHostDataType(type, staticType)) {
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message:
              "The device expression '${expr.toSource()}' cannot be assigned "
              "to a '${type.name}' property type at this site.",
          location: _locationOf(expr),
        ),
      );
      return '';
    }
    if (type == PropertyType.scalarCallback &&
        property?.constructorNullable == true &&
        _isNullLiteral(_resolveBoundIdentifier(expr)))
      return 'null';
    if (type == PropertyType.scalarCallback &&
        property?.scalarContract != null) {
      return _translateScalarCallback(expr, property!.scalarContract!, issues);
    }
    if (type == PropertyType.widgetBuilder && property != null) {
      return _translateWidgetBuilder(expr, property, issues);
    }
    bool hasKey(AstNode node) {
      if (node is FunctionExpression) return false;
      if (node is NamedArgument && isDiscardedWidgetKeyArgument(node)) {
        return true;
      }
      return node.childEntities.whereType<AstNode>().any(hasKey);
    }

    final keySemantics = _collectionSemanticProbe();
    final keyBudget = CollectionUnrollBudget();
    final activeKeyNodes = <AstNode>{};
    var keySearchExhausted = false;
    bool hasNativeKey(
      AstNode node, [
      Map<Element, Expression> bindings = const {},
    ]) {
      if (node is FunctionExpression ||
          keySearchExhausted ||
          !activeKeyNodes.add(node))
        return false;
      try {
        if (!keyBudget.tryChargeWork()) {
          keySearchExhausted = true;
          _recordCollectionRefusal(keyBudget.workRefusal(node), issues);
          return false;
        }
        if (node is Expression) {
          final resolved = keySemantics.resolve(
            node,
            bindings,
            keyBudget,
            stopAtConditionals: true,
          );
          if (resolved.workLimitExceeded) {
            keySearchExhausted = true;
            _recordCollectionRefusal(keyBudget.workRefusal(node), issues);
            return false;
          }
          if (!identical(resolved.expression, node)) {
            return hasNativeKey(resolved.expression, resolved.bindings);
          }
          bindings = resolved.bindings;
        }
        if (node is NamedArgument && isDiscardedWidgetKeyArgument(node)) {
          final resolved = keySemantics.resolve(
            node.argumentExpression,
            bindings,
            keyBudget,
            stopAtConditionals: true,
          );
          if (resolved.workLimitExceeded) {
            keySearchExhausted = true;
            _recordCollectionRefusal(keyBudget.workRefusal(node), issues);
            return false;
          }
          final key = _resolveBoundIdentifier(resolved.expression);
          return _rootParamRead(key) != null ||
              installedNativeConstantType(key) == 'flutter.Key';
        }
        return node.childEntities.whereType<AstNode>().any(
          (child) => hasNativeKey(child, bindings),
        );
      } finally {
        activeKeyNodes.remove(node);
      }
    }

    final list = type == PropertyType.widgetList
        ? _resolveBoundIdentifier(_stripParens(expr))
        : null;
    FormalParameterElement? resolvedParameter() {
      AstNode? node = expr;
      while (node is Expression || node is NamedArgument) {
        if (node is Argument && node.correspondingParameter != null) {
          return node.correspondingParameter;
        }
        node = node?.parent;
      }
      return null;
    }

    final parameter = sourceParameter ?? resolvedParameter();
    final constructor = parameter?.enclosingElement;
    final owner = constructor is ConstructorElement
        ? constructor.enclosingElement
        : null;
    // Borrowed keys and native delegates retain child identity through frames.
    final nativeKeyedChildren =
        parameter?.name == 'children' &&
        ((owner?.name == 'GridView' &&
                owner?.library.identifier ==
                    'package:flutter/src/widgets/scroll_view.dart') ||
            (owner?.name == 'SliverChildListDelegate' &&
                owner?.library.identifier ==
                    'package:flutter/src/widgets/scroll_delegate.dart'));
    if (list != null &&
        ((list is ListLiteral &&
                (_activeWidgetBuilder != null ||
                    (nativeKeyedChildren && hasKey(list)))) ||
            hasNativeKey(list))) {
      return _translateBuilderCollection(list, issues);
    }
    if (_activeWidgetBuilder != null &&
        (const {
          PropertyType.fontWeight,
          PropertyType.boolean,
          PropertyType.integer,
          PropertyType.real,
          PropertyType.length,
          PropertyType.string,
          PropertyType.enumValue,
          PropertyType.color,
        }.contains(type))) {
      try {
        final scalar = expr.staticType;
        if (_inSpanCollection &&
            _walk.runtimeLoops.isNotEmpty &&
            scalar != null &&
            (scalar.isDartCoreString ||
                scalar.isDartCoreBool ||
                scalar.isDartCoreNum ||
                scalar.isDartCoreInt ||
                scalar.isDartCoreDouble)) {
          return _spanCollectionBuilderValue(
            expr,
            issues,
            asDouble: type == PropertyType.real || type == PropertyType.length,
          );
        }
        return _activeWidgetBuilder!.value(
          expr,
          asDouble: type == PropertyType.real || type == PropertyType.length,
          requireNativeBaseType: _customNativeValueBoundary,
          nativeDestination: switch (type) {
            PropertyType.color => 'Color',
            PropertyType.fontWeight => 'FontWeight',
            _ => null,
          },
        );
      } on BuilderLoweringException catch (error) {
        issues.add(
          Issue(
            code: IssueCode.propertyValueTypeMismatch,
            message: error.toString(),
            location: _locationOf(error.node),
          ),
        );
        return '';
      }
    }
    if (_activeWidgetBuilder != null &&
        (themeReadSegments(expr) != null ||
            _recognizeDeviceRead(expr) != null)) {
      return _activeWidgetBuilder!.value(
        expr,
        requireNativeBaseType: _customNativeValueBoundary,
      );
    }
    if (type != PropertyType.event && type != PropertyType.widget) {
      final hoisted = _hoisted(
        expr,
        issues,
        (scratch) => _translateSlotValueUnrecorded(
          expr,
          type,
          scratch,
          property: property,
          sourceParameter: sourceParameter,
          coerce: coerce,
        ),
      );
      if (hoisted != null) return hoisted;
    }
    final widgetOccurrence = _walk.measurementWidget;
    final eventOccurrence =
        type == PropertyType.event &&
            widgetOccurrence != null &&
            sourceParameter != null
        ? widgetOccurrence.event(sourceParameter)
        : null;
    final marker = eventOccurrence == null
        ? null
        : measurementRouteEmissionPlan?.markerFor(eventOccurrence);
    final saved = _walk;
    if (type == PropertyType.widget || type == PropertyType.widgetList) {
      _walk = _walk.armStep(property?.name ?? sourceParameter?.name ?? '');
    }
    if (widgetOccurrence != null && sourceParameter != null) {
      if (type == PropertyType.widget) {
        _walk = _walk.copyWith(
          measurementScope: widgetOccurrence.child(
            sourceParameter,
            ordinal: 0,
          ),
          measurementWidget: null,
          measurementWidgetList: null,
        );
      } else if (type == PropertyType.widgetList) {
        _walk = _walk.copyWith(
          measurementScope: null,
          measurementWidget: null,
          measurementWidgetList: widgetOccurrence.widgetList(sourceParameter),
        );
      }
    }
    // Each arm of a conditional measured callback carries its own marker.
    final conditional = _stripParens(expr);
    if (marker != null && conditional is ConditionalExpression) {
      if (_handlerArms(conditional) > 1) {
        issues.add(
          _measuredRefusal(
            Issue(
              code: IssueCode.invalidEventConfiguration,
              message:
                  'A measured callback can run only one handler, but '
                  'this conditional runs a different one in each arm. Keep '
                  'one handler and set the others to null, or give each arm '
                  'its own widget.',
              location: _locationOf(conditional),
            ),
          ),
        );
        return '';
      }
      return _conditionalSwitch(
        conditional,
        issues,
        (arm) => _translateSlotValue(
          arm,
          type,
          issues,
          property: property,
          sourceParameter: sourceParameter,
          coerce: coerce,
        ),
      );
    }
    final savedEventOccurrence = _measuredEventOccurrence;
    if (eventOccurrence != null) _measuredEventOccurrence = eventOccurrence;
    final String value;
    try {
      value = _translateSlotValueCore(
        expr,
        type,
        issues,
        property: property,
        coerce: coerce,
      );
    } finally {
      _walk = saved;
      _measuredEventOccurrence = savedEventOccurrence;
    }
    if (issues
        .skip(beforeValidation)
        .any((issue) => issue.code == IssueCode.propertyValueTypeMismatch)) {
      return '';
    }
    if (type == PropertyType.widget) _noteParamPlacement(value, expr);
    if (type != PropertyType.event) return value;
    if (value.isEmpty) {
      if (marker != null) {
        issues.add(
          _measuredRefusal(
            Issue(
              code: IssueCode.invalidEventConfiguration,
              message:
                  'The measured callback produced no RFW event handler, '
                  'so its private Measurement route cannot be emitted.',
              location: _locationOf(expr),
            ),
          ),
        );
      }
      return value;
    }
    if (marker == null) {
      if (eventOccurrence != null && measurementRouteEmissionPlan != null) {
        _noteUnavailableItem(eventOccurrence, expr, measured: false);
      }
      return value;
    }
    if (value == _kNoValue) return value;
    return _measuredEventHandler(
      value,
      marker,
      eventOccurrence!,
      expr,
      issues,
    );
  }

  /// The arms of a conditional, at any depth, that are not `null`.
  int _handlerArms(Expression expr) {
    final value = _resolveBoundIdentifier(expr);
    if (value is ConditionalExpression) {
      return _handlerArms(value.thenExpression) +
          _handlerArms(value.elseExpression);
    }
    return value is NullLiteral ? 0 : 1;
  }

  // The mount's binding of the app's closure [expression], which Flutter calls
  // with its own arguments; null outside a mount or for a type with no id.
  // [argument], the expression as written, names the slot's own type; a
  // catalog slot takes only its [expected] callback type.
  String? _typedClosureBinding(
    Expression expression,
    Expression argument, {
    String? expected,
  }) {
    final declared = switch (argument.parent) {
      NamedArgument(:final correspondingParameter?) =>
        correspondingParameter.type,
      _ => null,
    };
    final callback = declared is FunctionType
        ? declared
        : expression.staticType;
    if (_islands == null || callback is! FunctionType) return null;
    String type;
    try {
      type = installedNativeTypeId(callback);
    } on ArgumentError {
      return null;
    }
    // The slot may be optional; the callback passed is not.
    if (callback.nullabilitySuffix == NullabilitySuffix.question) {
      type = type.substring(0, type.length - 1);
    }
    if (expected != null && type != expected) return null;
    return _nativeBindingRead(expression, type: type, computed: true);
  }

  // A refusal for each `context.surfaceEvent` below [node] that fires a
  // reserved commerce event.
  List<Issue> _reservedEventIssues(AstNode node) {
    final calls = _EventHelperCalls();
    node.accept(calls);
    return [
      for (final call in calls.calls)
        if (call.argumentList.arguments.firstOrNull?.argumentExpression
            case final event?)
          if (_reservedEventId(event) case final id?)
            unsupportedCommerceEventIssue(id, _locationOf(event)),
    ];
  }

  // The reserved commerce name [event] can fire, either arm of a
  // conditional included.
  String? _reservedEventId(Expression event) {
    final stripped = _stripParens(event);
    if (stripped is ConditionalExpression) {
      return _reservedEventId(stripped.thenExpression) ??
          _reservedEventId(stripped.elseExpression);
    }
    final id = _constDescriptorId(stripped);
    return kReservedCommerceEventNames.contains(id) ? id : null;
  }

  String _translateSlotValueCore(
    Expression rawExpr,
    PropertyType type,
    List<Issue> issues, {
    PropertyEntry? property,
    bool coerce = true,
  }) {
    if (type == PropertyType.event &&
        property?.callbackSignature != null &&
        _islands != null) {
      // A typed callback that doesn't lower is the app's own closure.
      final scratch = <Issue>[];
      final legacy = _translateSlotValueLegacy(
        rawExpr,
        type,
        scratch,
        property: property,
        coerce: coerce,
      );
      if (scratch.any((issue) => !issue.code.isBuildNotice)) {
        final expression = _resolveBoundIdentifier(_stripParens(rawExpr));
        if (_typedClosureBinding(
              expression,
              rawExpr,
              expected: eventNativeType(property!),
            )
            case final action?) {
          return '{nativeEvent: $action}';
        }
      }
      issues.addAll(scratch);
      return legacy;
    }
    if (type == PropertyType.event && property?.callbackSignature == null) {
      final scratch = <Issue>[];
      final legacy = _translateSlotValueLegacy(
        rawExpr,
        type,
        scratch,
        property: property,
        coerce: coerce,
      );
      // A completed declarative translation may intentionally emit no handler.
      // Navigation refusals also retain their diagnostic and context boundary.
      if (!scratch.any((issue) => !issue.code.isBuildNotice) ||
          _islands == null &&
              scratch.any(
                (issue) => issue.code == IssueCode.navigationFormUnsupported,
              )) {
        issues.addAll(scratch);
        return legacy;
      }
      final expression = _resolveBoundIdentifier(_stripParens(rawExpr));
      final callback = expression.staticType;
      if (callback is FunctionType && callback.formalParameters.isEmpty) {
        String? reference;
        final native = <Issue>[];
        try {
          reference =
              _nativeBindingRead(expression, type: kNativeVoidCallbackType) ??
              (expression is FunctionExpression
                  ? _tryNativeCallValue(
                      expression,
                      native,
                      type: kNativeVoidCallbackType,
                    )
                  : null);
        } on BuilderLoweringException catch (error) {
          if (_islands == null) {
            issues.add(
              Issue(
                code: IssueCode.propertyValueTypeMismatch,
                message: error.reason,
                location: _locationOf(error.node),
              ),
            );
            return '';
          }
        }
        // An action whose arguments read design state calls the app's
        // callback with values the payload evaluates.
        if (reference == null &&
            _islands != null &&
            _splitsAction(expression)) {
          final split = <Issue>[];
          _splitRefusal = null;
          _splittingAction = true;
          try {
            reference = _tryNativeCallValue(
              expression as FunctionExpression,
              split,
              type: kNativeVoidCallbackType,
            );
          } on BuilderLoweringException catch (error) {
            reference = null;
            final source = readableSource(_writtenSource(error.node));
            final read = switch (error.node) {
              SimpleIdentifier(:final element) => element,
              PropertyAccess(:final propertyName) => propertyName.element,
              _ => null,
            };
            // The argument of the callback itself, not of a call inside it.
            AstNode? argument;
            for (AstNode? node = error.node; node != null; node = node.parent) {
              if (node.parent is ArgumentList) argument = node;
              if (node is FunctionExpression) break;
            }
            _splitRefusal ??=
                read != null &&
                    (_islands?.isDesignStateMember(read) ?? false) &&
                    argument != null
                ? (
                    node: error.node,
                    problem:
                        'the callback works out '
                        '`${readableSource(_writtenSource(argument))}` from '
                        '`$source` in your app\'s code, which the design '
                        "can't do",
                    fix:
                        _fieldTypeFix(source, switch (read) {
                          PropertyAccessorElement(:final returnType) =>
                            returnType,
                          VariableElement(:final type) => type,
                          _ => null,
                        }) ??
                        'passing a bool, int, double or String State field, '
                            'or choosing between values with `?:`, as in '
                            "`annualSelected ? 'annual' : 'monthly'`",
                  )
                : (
                    node: error.node,
                    problem:
                        'the callback reads `$source`, which is neither a '
                        'State field, a constant nor a field of the widget, so '
                        "the design can't pass it",
                    fix:
                        'passing only State fields, constants and widget '
                        'fields, and working out the rest inside your '
                        'callback',
                  );
          } finally {
            _splittingAction = false;
          }
          if (reference != null) {
            native.addAll(split);
          } else if (_splitRefusal case (
            :final node,
            :final problem,
            :final fix,
          )) {
            _designMiss(node, problem, fix);
          }
        }
        if (reference != null) {
          issues.addAll(native);
          return '{nativeEvent: $reference}';
        }
        // An action: the mount holds the app's own closure.
        final action = _islands == null
            ? null
            : _nativeBindingRead(
                expression,
                type: kNativeVoidCallbackType,
                computed: true,
              );
        if (action != null) return '{nativeEvent: $action}';
        issues.addAll(native);
      } else if (_typedClosureBinding(
            expression,
            rawExpr,
            expected: property == null ? null : eventNativeType(property),
          )
          case final action?) {
        // Any other callback crosses as its slot's own type.
        return '{nativeEvent: $action}';
      }
      issues.addAll(scratch);
      return legacy;
    }
    bool nativeBoundary(Expression value) {
      final owner = value.thisOrAncestorOfType<ArgumentList>()?.parent;
      return owner is InstanceCreationExpression &&
          _isFrameworkValueType(_classOfInstanceCreation(owner));
    }

    final nativeConstructor =
        nativeBoundary(rawExpr) &&
        nativeBoundary(_resolveBoundIdentifier(rawExpr));
    final eligible =
        nativeConstructor &&
        const {
          PropertyType.boolean,
          PropertyType.integer,
          PropertyType.real,
          PropertyType.length,
        }.contains(type);
    if (!eligible)
      return _translateSlotValueLegacy(
        rawExpr,
        type,
        issues,
        property: property,
        coerce: coerce,
      );
    final scratch = <Issue>[];
    final old = _translateSlotValueLegacy(
      rawExpr,
      type,
      scratch,
      property: property,
      coerce: coerce,
    );
    if (!scratch.any((issue) => !issue.code.isBuildNotice)) {
      issues.addAll(scratch);
      return old;
    }
    final programIssues = <Issue>[];
    final program = _tryScalarValueProgram(
      rawExpr,
      programIssues,
      asDouble:
          coerce && (type == PropertyType.real || type == PropertyType.length),
    );
    if (program != null &&
        program.isNotEmpty &&
        !programIssues.any((issue) => !issue.code.isBuildNotice)) {
      issues.addAll(programIssues);
      return program;
    }
    issues.addAll(scratch);
    return old;
  }

  String _translateSlotValueLegacy(
    Expression rawExpr,
    PropertyType type,
    List<Issue> issues, {
    PropertyEntry? property,
    bool coerce = true,
  }) {
    if (type == PropertyType.event && _containsIntlFormatting(rawExpr)) {
      final modalSheet = _walk.modalSheet;
      final activeModalTrigger =
          modalSheet != null &&
          switch (recogniseModalSheetTrigger(rawExpr)) {
            ModalSheetRecognised(:final sheet) =>
              identical(sheet.call, modalSheet.sheet.call) &&
                  sheet.call.argumentList.arguments.every(
                    (argument) =>
                        argument is NamedArgument &&
                        switch (kModalSheetArgumentDispositions[sheet
                            .function]?[argument.name.lexeme]) {
                          ModalSheetArgumentDisposition.animationStyle ||
                          ModalSheetArgumentDisposition.builder ||
                          ModalSheetArgumentDisposition.pageBuilder => true,
                          _ => !_containsIntlFormatting(
                            argument.argumentExpression,
                          ),
                        },
                  ),
            _ => false,
          };
      // Sheet bodies and animation styles are validated when the sheet lowers.
      if (!activeModalTrigger) {
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message:
                'Formatting in an event callback requires an installed native callback binding',
            location: _locationOf(rawExpr),
          ),
        );
        return '';
      }
    }
    if (type == PropertyType.event && _walk.rootStateContext) {
      final local = recogniseLocalValueWrite(rawExpr);
      if (local != null && _currentLocalFields.contains(local)) {
        return 'event ${_stringLiteral(kLocalValueSetEventName)} '
            '{ key: ${_stringLiteral(local)} }';
      }
    }
    // A value-callback closure `(v) => <event>` carries only the event on the
    // wire; any other closure stays intact for the recognisers that match it.
    final expr = type == PropertyType.event
        ? _eventSlotExpression(rawExpr, issues)
        : rawExpr;
    if (expr == null) return '';
    // Rewrite only when this slot accepts the coalesced fallback.
    final coalesce = _coalesceParamAt(expr);
    if (coalesce != null) {
      return _translateCoalesce(coalesce, issues);
    }
    // Resolve a named-intermediate binding (helper param / `final` local)
    // BEFORE the type-special dispatch below: the `alignmentXY` branch calls
    // `_structured.alignmentGeometry` directly rather than `_translate`,
    // so a bound reference used in such a slot would otherwise bypass the
    // resolve-through and over-claim. Inert outside inlining (both maps empty).
    // A widget a build local holds is placed through that local.
    if (expr case final SimpleIdentifier read
        when type == PropertyType.widget || type == PropertyType.widgetList) {
      if (_constPlacementStep(read) case final step
          when step.isNotEmpty && _constReads.add(read)) {
        _placementReads.add((read: read, bound: null));
        try {
          return _inScope(
            step,
            () => _translateSlotValueLegacy(
              read,
              type,
              issues,
              property: property,
              coerce: coerce,
            ),
          );
        } finally {
          _constReads.remove(read);
          _placementReads.removeLast();
        }
      }
      final argument = _walk.paramBindings[read.element];
      final initializer = _walk.inlined.localBindings[read.element];
      if (argument != null) {
        return _throughParameter(
          read,
          argument,
          () => _translateSlotValueLegacy(
            argument,
            type,
            issues,
            property: property,
            coerce: coerce,
          ),
        );
      }
      if (initializer != null &&
          (!identical(_resolveBoundIdentifier(read), read) ||
              (_islands?.sharedLocals.contains(read.element?.baseElement) ??
                  false))) {
        return _throughLocal(
          read,
          initializer,
          issues,
          () => _translateSlotValueLegacy(
            initializer,
            type,
            issues,
            property: property,
            coerce: coerce,
          ),
        );
      }
    }
    final resolved = _resolveBoundIdentifier(expr);
    if (resolved is ConditionalExpression) {
      return _conditionalSwitch(
        resolved,
        issues,
        (branch) => _translateSlotValueCore(
          branch,
          type,
          issues,
          property: property,
        ),
      );
    }
    if (type == PropertyType.boolean) {
      final condition = _booleanSlotCondition(resolved, issues);
      if (condition != null) return condition;
    }
    final frameworkConst = _frameworkConstValue(resolved);
    if (frameworkConst != null && type != PropertyType.unknown) {
      if (frameworkConst.fits(type)) {
        return frameworkConst.dsl;
      }
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message:
              "'${resolved.toSource()}' is "
              '${frameworkConst.kind.label} and cannot be assigned to a '
              "'${type.name}' property type at this site.",
          location: _locationOf(resolved),
        ),
      );
      return '';
    }
    // Preserve the authored TextDecoration member before const-object expansion
    // reaches the private constructor behind the static constant.
    if (type == PropertyType.textDecoration &&
        resolved is PrefixedIdentifier &&
        resolved.prefix.name == 'TextDecoration') {
      return _prefixedIdentifier(resolved, issues);
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
        return _translateSlotValueCore(
          initializer,
          type,
          issues,
          property: property,
          coerce: coerce,
        );
      }
      final scalar = tryScalarFoldConstObjectField(resolved);
      if (scalar != null) {
        final value = _foldedLiteral(scalar);
        return coerce ? _coerceForPropertyType(type, value) : value;
      }
      issues.add(_constObjectFieldUnresolvedIssue(resolved));
      return '';
    }
    // Translate same-file consts with the destination slot's value shape.
    if (!_isNameBoundIdentifier(resolved)) {
      final constDsl = _translateConstIdentifier(
        resolved,
        issues,
        resolved is PrefixedIdentifier
            ? IssueCode.unresolvedIdentifier
            : IssueCode.unrecognizedMethodCall,
        (initializer) => _translateSlotValue(
          initializer,
          type,
          issues,
          property: property,
        ),
      );
      if (constDsl != null) return constDsl;
    }
    final inspectedItemType = _inspectedListItemPropertyType(type);
    if (inspectedItemType != null && resolved is NullLiteral) return 'null';
    if (inspectedItemType != null) {
      return emitTypedList(
        expr,
        _translate,
        issues,
        _locationOf(expr),
        resolveExpression: _resolveBoundIdentifier,
        semanticProbe: _collectionSemanticProbe(),
        locationOf: _locationOf,
        translateElement: (element, bindings, issues) =>
            _translateSlotElement(element, bindings, inspectedItemType, issues),
        terminalItemType: inspectedItemType,
        translateTerminal: (source, itemType, issues) =>
            _translateTypedListTerminal(
              source,
              itemType,
              issues,
              listType: type,
            ),
      );
    }
    final traversedItemType = _traversedListItemPropertyType(type);
    if (traversedItemType != null && resolved is ListLiteral) {
      return _listLiteral(resolved, issues, itemType: traversedItemType);
    }
    final valueShape = property?.valueShape;
    if (valueShape is ScalarShape && valueShape.isOpaqueStringKeyedMap) {
      return _customMapSlotValue(resolved, issues);
    }
    // A concrete-`Alignment` slot (`alignmentXY`) decodes a `{x, y}` map
    // (`RestageDecoders.alignmentXY`), so a Dart-source `Alignment.<member>`
    // / `Alignment(x, y)` must lower to that map HERE rather than fall
    // through to the generic enum-string path — which would emit a bare
    // member name the runtime decoder nulls (a silent drop to the default).
    // The shared, element-gated `_structured.alignmentGeometry` does the
    // lowering: it value-asserts the member coordinates, defers a resolved
    // custom `Alignment` look-alike with a diagnostic (never the substituted
    // value or a bare string), and diagnoses `AlignmentDirectional` /
    // unsupported members.
    if (type == PropertyType.alignmentXY) {
      return _normalizePresentDsl(
        issues,
        () => _structured.alignmentGeometry(
          resolved,
          issues,
          _locationOf(expr),
        ),
      );
    }
    if (type == PropertyType.enumValue && property != null) {
      final enumValue = _enumValueSlot(resolved, property, issues);
      if (enumValue != null) return enumValue;
    }
    final value = _translate(resolved, issues);
    return coerce ? _coerceForPropertyType(type, value) : value;
  }

  String _customMapSlotValue(Expression expr, List<Issue> issues) {
    if (expr is! SetOrMapLiteral) {
      return _translate(expr, issues);
    }

    final issuesBefore = issues.length;
    if (!expr.isMap) {
      _addUnsupportedCustomMapElement(expr, issues);
      return '';
    }

    final mapType = _dartCoreMapType(expr.staticType);
    final keyShape = mapType == null
        ? null
        : resolveValueShape(mapType.typeArguments[0]);
    final valueShape = mapType == null
        ? null
        : _customMapValueShape(mapType.typeArguments[1]);
    final entries = <String>[];

    // Preserve authored entry order. The decoder reconstructs a Dart Map whose
    // iteration order can be observed by the app's build(), unlike record
    // label order; sorting here would change behavior rather than normalize
    // bytes.
    for (final element in expr.elements) {
      if (element is! MapLiteralEntry) {
        _addUnsupportedCustomMapElement(expr, issues);
        continue;
      }
      final key = _customMapEntryKey(
        element.key,
        keyShape,
        expr,
        issues,
      );
      final shape =
          valueShape ?? _customMapValueShape(element.value.staticType);
      final value = _translateSlotValue(
        element.value,
        shape?.propertyType ?? PropertyType.unknown,
        issues,
        property: shape == null ? null : syntheticProperty('value', shape),
      );
      entries.add('{key: $key, value: $value}');
    }

    // One map is one value contract. A failed key or value suppresses every
    // entry, including entries that translated before the failure.
    if (issues.length > issuesBefore) return '';
    return '[${entries.join(', ')}]';
  }

  InterfaceType? _dartCoreMapType(DartType? type) =>
      type == null ? null : dartCoreMapType(type);

  CatalogValueShape? _customMapValueShape(DartType? type) {
    if (type == null) return null;
    if (_dartCoreMapType(type) != null) {
      return ScalarShape.opaqueStringKeyedMap();
    }

    final shape = resolveValueShape(type);
    if (shape != null) return shape;

    final element = type is InterfaceType ? type.element : null;
    if (element is! ClassElement) return null;
    final ref = _dartTypeRefOfClass(element);
    final structured = ref == null ? null : _customStructuredByDartType[ref];
    if (structured == null) return null;
    return StructuredShape(
      propertyType: PropertyType.structured,
      structuredRef: WireIdRef(
        library: structured.library.namespace,
        wireId: structured.wireId,
      ),
    );
  }

  String _customMapEntryKey(
    Expression source,
    CatalogValueShape? expectedShape,
    SetOrMapLiteral map,
    List<Issue> issues,
  ) {
    final key = _stripParens(source);
    var shape = expectedShape;
    final staticType = key.staticType;
    if (shape == null && staticType != null) {
      shape = resolveValueShape(staticType);
    }

    if (shape is ScalarShape &&
        shape.propertyType == PropertyType.string &&
        key is SimpleStringLiteral) {
      return _stringLiteral(key.value);
    }
    final enumMember = _unwrapPropertyAccessor(_enumMemberElement(key));
    if (shape is EnumShape &&
        enumMember is FieldElement &&
        enumMember.isEnumConstant) {
      return _translateSlotValue(
        key,
        shape.propertyType,
        issues,
        property: syntheticProperty('key', shape),
      );
    }

    _addUnsupportedCustomMapElement(map, issues);
    return '';
  }

  void _addUnsupportedCustomMapElement(
    SetOrMapLiteral expr,
    List<Issue> issues,
  ) {
    issues.add(
      Issue(
        code: IssueCode.unsupportedCollectionFlow,
        message:
            'Set literals, spreads, collection-if, and collection-for '
            'are not supported in map literals. Use a static string-keyed '
            'map.',
        location: _locationOf(expr),
      ),
    );
  }

  /// Slot-aware generic enum lowering. The context-free fallback at
  /// `_prefixedIdentifier` preserves unresolved synthetic expression tests, but
  /// a catalog `enumValue` slot has enough identity to be stricter: the member
  /// must resolve to the enum type the catalog names, and the emitted name must
  /// be present on that same resolved declaration. The generated decoder uses
  /// `RestageDecoders.enumByName<T>(T.values, ...)`, so the analyzer
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
    // A theme read is a data reference the slot's contract validation has
    // already checked, not an enum member to resolve.
    if (_recognizeThemeRead(expr) != null) return null;
    if (expr is! PrefixedIdentifier && expr is! PropertyAccess) return null;

    final memberName = _enumMemberName(expr);
    if (memberName == null) return null;

    final resolvedMember = _unwrapPropertyAccessor(_enumMemberElement(expr));
    final memberOwner =
        resolvedMember is FieldElement &&
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
    if (expr is PrefixedIdentifier) return identifierElement(expr.identifier);
    if (expr is PropertyAccess) return identifierElement(expr.propertyName);
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
      target = identifierElement(expr.prefix);
    } else if (expr is PropertyAccess) {
      final receiver = expr.target;
      if (receiver is SimpleIdentifier) {
        target = receiver.element;
      } else if (receiver is PrefixedIdentifier) {
        target =
            identifierElement(receiver.identifier) ??
            identifierElement(receiver.prefix);
      } else if (receiver is PropertyAccess) {
        target = identifierElement(receiver.propertyName);
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
    final seen = <Element>{};
    while (true) {
      if (current is ParenthesizedExpression) {
        current = current.expression;
        continue;
      }
      if (current is SimpleIdentifier) {
        final element = current.element;
        if (element == null || !seen.add(element)) break;
        // A value the app computes reads a build local by name; an attempt
        // to deliver sees through to what it holds.
        if (!_seesThroughPreludes &&
            (_islands?.preludeLocals.contains(element.baseElement) ?? false)) {
          break;
        }
        Expression? local;
        for (
          var scope = _activeWidgetBuilder?.expressions;
          scope != null;
          scope = scope.parent
        ) {
          local = scope.localInitializers[element];
          if (local != null) break;
        }
        final bound =
            local ??
            _walk.paramBindings[element] ??
            _walk.inlined.localBindings[element];
        if (bound == null) break;
        current = bound;
        continue;
      }
      break;
    }
    return current;
  }

  String _systemUiOverlayStyle(
    Expression source,
    List<Issue> issues, {
    List<Map<String, Expression>> overrides = const [],
  }) {
    final expr = _resolveBoundIdentifier(source);
    if (expr is MethodInvocation) {
      final helper = _walk.inlined.helpers[expr.methodName.element];
      if (helper != null) {
        return _inlineHelperBody(
          helper,
          expr,
          issues,
          translateBody: (body) => _systemUiOverlayStyle(
            body,
            issues,
            overrides: overrides,
          ),
        );
      }
    }
    if (expr is ConditionalExpression) {
      return _conditionalSwitch(
        expr,
        issues,
        (branch) => _systemUiOverlayStyle(branch, issues, overrides: overrides),
      );
    }
    if (expr is MethodInvocation && isSystemUiOverlayStyleCopyWith(expr)) {
      final target = expr.target;
      final arguments = expr.argumentList.arguments;
      final fields = <String, Expression>{
        for (final argument in arguments)
          if (argument is NamedArgument)
            argument.name.lexeme: argument.argumentExpression,
      };
      if (target != null &&
          fields.length == arguments.length &&
          fields.keys.every(kSystemUiOverlayStyleFields.containsKey)) {
        if (overrides.length >= kMaxStructuredCopyWithLayers) {
          issues.add(
            Issue(
              code: IssueCode.unrecognizedMethodCall,
              message:
                  'SystemUiOverlayStyle.copyWith chains support at most '
                  '$kMaxStructuredCopyWithLayers calls.',
              location: _locationOf(expr),
            ),
          );
          return '';
        }
        return _systemUiOverlayStyle(
          target,
          issues,
          overrides: [fields, ...overrides],
        );
      }
    }

    final entries = <String>[];
    final constant = frameworkStaticConst(expr);
    final constantFields = constant == null
        ? null
        : systemUiOverlayStyleFields(constant);
    if (constantFields != null) {
      for (final field in constantFields.entries) {
        if (!field.value.isNull) {
          entries.add(
            '${field.key}: '
            '${encodeSystemUiOverlayStyleField(field.key, field.value)!}',
          );
        }
      }
    } else if (expr is InstanceCreationExpression &&
        isSystemUiOverlayStyleClass(
          expr.constructorName.element?.enclosingElement,
        ) &&
        expr.constructorName.element?.name == 'new') {
      for (final argument in expr.argumentList.arguments) {
        if (argument is! NamedArgument ||
            !kSystemUiOverlayStyleFields.containsKey(argument.name.lexeme)) {
          return _unsupportedOverlayStyle(expr, issues);
        }
        final name = argument.name.lexeme;
        final value = _translateSlotValue(
          argument.argumentExpression,
          kSystemUiOverlayStyleFields[name]!,
          issues,
        );
        entries.add('$name: $value');
      }
    } else {
      final translated = _translateConstIdentifier(
        expr,
        issues,
        IssueCode.unrecognizedMethodCall,
        (initializer) => _systemUiOverlayStyle(
          initializer,
          issues,
          overrides: overrides,
        ),
      );
      return translated ?? _unsupportedOverlayStyle(expr, issues);
    }

    if (overrides.isNotEmpty) {
      final layers = <String>[];
      for (final override in overrides) {
        final fields = <String>[];
        for (final field in override.entries) {
          final value = _translateSlotValue(
            field.value,
            kSystemUiOverlayStyleFields[field.key]!,
            issues,
          );
          fields.add('${field.key}: $value');
        }
        layers.add('{${fields.join(', ')}}');
      }
      entries.add('$kStructuredCopyWithKey: [${layers.join(', ')}]');
    }
    return '{${entries.join(', ')}}';
  }

  /// Lowers an `IconThemeData` constructor, `fallback()`, `copyWith` or `lerp`
  /// value. [layers] are lowered `copyWith` maps applied after the value.
  String _iconThemeData(
    Expression source,
    List<Issue> issues, {
    List<String> layers = const [],
    int depth = 0,
  }) {
    String nested(Expression value, {List<String> layers = const []}) =>
        _iconThemeData(value, issues, layers: layers, depth: depth + 1);
    final expr = _resolveBoundIdentifier(source);
    if (depth > kMaxStructuredCopyWithLayers) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message:
              'IconThemeData values support at most '
              '$kMaxStructuredCopyWithLayers nested operations.',
          location: _locationOf(expr),
        ),
      );
      return '';
    }
    if (expr is NullLiteral && layers.isEmpty) return 'null';
    if (expr is MethodInvocation) {
      final helper = _walk.inlined.helpers[expr.methodName.element];
      if (helper != null) {
        return _inlineHelperBody(
          helper,
          expr,
          issues,
          translateBody: (body) => nested(body, layers: layers),
        );
      }
    }
    if (expr is ConditionalExpression) {
      return _conditionalSwitch(
        expr,
        issues,
        (branch) => nested(branch, layers: layers),
      );
    }
    final location = _locationOf(expr);
    String fields(NodeList<Argument> args) =>
        _tryValueOrRecipe(
          'IconThemeData',
          null,
          args,
          issues,
          location,
          fromConstructor: true,
        ) ??
        '';
    if (expr is MethodInvocation &&
        expr.target != null &&
        isIconThemeDataCopyWith(expr)) {
      return nested(
        expr.target!,
        layers: [fields(expr.argumentList.arguments), ...layers],
      );
    }
    final String base;
    if (expr is MethodInvocation && isIconThemeDataLerp(expr)) {
      final args = expr.argumentList.arguments;
      if (args.length != 3 || args.any((arg) => arg is NamedArgument)) {
        return _unsupportedIconTheme(expr, issues);
      }
      final ends = [
        for (final (name, end) in [
          ('a', args[0].argumentExpression),
          ('b', args[1].argumentExpression),
        ])
          if (_resolveBoundIdentifier(end) is! NullLiteral)
            '$name: ${nested(end)}',
      ];
      final t = _translateSlotValue(
        args[2].argumentExpression,
        PropertyType.real,
        issues,
      );
      base = '$kIconThemeDataLerpKey: {${[...ends, 't: $t'].join(', ')}}';
    } else if (expr is InstanceCreationExpression &&
        isIconThemeDataClass(expr.constructorName.element?.enclosingElement)) {
      switch (expr.constructorName.element?.name) {
        case 'fallback':
          base = '$kIconThemeDataFallbackKey: true';
        case 'new':
          final before = issues.length;
          base = _mapBody(fields(expr.argumentList.arguments));
          if (issues.length > before) return '';
        default:
          return _unsupportedIconTheme(expr, issues);
      }
    } else {
      final translated = _translateConstIdentifier(
        expr,
        issues,
        IssueCode.unrecognizedMethodCall,
        (initializer) => nested(initializer, layers: layers),
      );
      return translated ?? _unsupportedIconTheme(expr, issues);
    }
    final entries = [
      if (base.isNotEmpty) base,
      if (layers.isNotEmpty) '$kStructuredCopyWithKey: [${layers.join(', ')}]',
    ];
    return '{${entries.join(', ')}}';
  }

  /// The entries of a lowered `{...}` map.
  String _mapBody(String map) => map.length < 2 || !map.startsWith('{')
      ? map
      : map.substring(1, map.length - 1).trim();

  String _unsupportedIconTheme(Expression expr, List<Issue> issues) {
    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message:
            'Unsupported IconThemeData expression: ${expr.toSource()}. '
            'Use its constructor, fallback, copyWith, or lerp.',
        location: _locationOf(expr),
      ),
    );
    return '';
  }

  String _unsupportedOverlayStyle(Expression expr, List<Issue> issues) {
    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message:
            'Unsupported SystemUiOverlayStyle expression: '
            '${expr.toSource()}. Use its constructor, constants, or copyWith.',
        location: _locationOf(expr),
      ),
    );
    return '';
  }

  /// Resolves a strict-double list through active bindings and const aliases.
  DoubleListSourceResolution _resolveDoubleListSource(Expression expr) {
    var current = expr;
    var inConstDeclaration = false;
    final seen = <Element>{};
    for (var depth = 0; depth < 256; depth += 1) {
      if (current is ParenthesizedExpression) {
        current = current.expression;
        continue;
      }
      if (current is SimpleIdentifier) {
        final element = current.element;
        Expression? local;
        for (
          var scope = _activeWidgetBuilder?.expressions;
          scope != null;
          scope = scope.parent
        ) {
          local = scope.localInitializers[element];
          if (local != null) break;
        }
        final bound =
            local ??
            _walk.paramBindings[element] ??
            _walk.inlined.localBindings[element];
        if (bound != null) {
          if (element != null && !seen.add(element)) {
            return DoubleListSourceResolution(
              source: current,
              disposition: DoubleListSourceDisposition.cycle,
            );
          }
          current = bound;
          continue;
        }
      }
      final declaration = constDeclarationElement(current);
      if (declaration != null) {
        if (!seen.add(declaration)) {
          return DoubleListSourceResolution(
            source: current,
            disposition: DoubleListSourceDisposition.cycle,
          );
        }
        inConstDeclaration = true;
        final initializer = resolveConstIdentifierInitializer(current);
        if (initializer == null) {
          return DoubleListSourceResolution(
            source: current,
            disposition: DoubleListSourceDisposition.constant,
          );
        }
        current = initializer;
        continue;
      }
      if (inConstDeclaration) {
        return DoubleListSourceResolution(
          source: current,
          disposition: DoubleListSourceDisposition.constant,
        );
      }
      if (current is ListLiteral &&
          current.elements.any((element) => element is! Expression)) {
        return DoubleListSourceResolution(
          source: current,
          disposition: DoubleListSourceDisposition.collectionFlow,
        );
      }
      if (current is ConditionalExpression) {
        return DoubleListSourceResolution(
          source: current,
          disposition: DoubleListSourceDisposition.conditional,
        );
      }
      return DoubleListSourceResolution(
        source: current,
        disposition: DoubleListSourceDisposition.ordinary,
      );
    }
    return DoubleListSourceResolution(
      source: current,
      disposition: DoubleListSourceDisposition.depthLimit,
    );
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
    final readName = switch (read) {
      SimpleIdentifier(:final name) => name,
      PrefixedIdentifier(:final prefix, :final identifier)
          when prefix.name == 'widget' =>
        identifier.name,
      _ => null,
    };
    final name = _walk.argNames[readName];
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
          message:
              "The optional property '${coalesce.name}' is coalesced "
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

  /// The refusal for [expr] when it reads a value that exists only in the
  /// running app: an `X.of(context)` lookup or a `static final` field.
  Issue? _appOnlyValueIssue(Expression expr, IssueCode code) {
    Issue refuse(String message) =>
        Issue(code: code, message: message, location: _locationOf(expr));
    final stripped = _stripParens(expr);
    // The mount's library must be able to name what the app evaluates.
    if (_hoist?.analyzer.analyze(stripped) case HoistUnwritable(
      unnamed: final name?,
    )) {
      return refuse(
        "'${stripped.toSource()}' is evaluated in the app, and "
        "${_currentSourcePath ?? "the screen's file"} can't refer to "
        "'$name'. Import it there.",
      );
    }
    Expression? current = expr;
    for (var depth = 0; current != null && depth < 16; depth++) {
      current = _stripParens(current);
      if (current is MethodInvocation) {
        final target = current.target;
        if (current.methodName.name == 'copyWith' && target != null) {
          current = target;
          continue;
        }
        if (_isContextLookup(current)) {
          return refuse(
            "'${current.toSource()}' reads from the running app. Pass the "
            'value in as a constructor input, or use Theme.of(context).',
          );
        }
        return null;
      }
      final (receiver, member) = switch (current) {
        PrefixedIdentifier(:final prefix, :final identifier) => (
          prefix,
          identifierElement(identifier),
        ),
        PropertyAccess(:final target, :final propertyName) => (
          target,
          propertyName.element,
        ),
        SimpleIdentifier() => (null, current.element),
        _ => (null, null),
      };
      final variable = _unwrapPropertyAccessor(member);
      if (variable is VariableElement &&
          variable is! LocalVariableElement &&
          variable.isFinal &&
          !variable.isConst &&
          (variable is TopLevelVariableElement ||
              (variable is FieldElement && variable.isStatic))) {
        return refuse(
          "'${current.toSource()}' is static final, so its value exists only "
          'in the running app. Make it const, or pass it in as a constructor '
          'input.',
        );
      }
      final bound = current is SimpleIdentifier
          ? _walk.paramBindings[current.element] ??
                _walk.inlined.localBindings[current.element]
          : null;
      current = bound ?? receiver;
    }
    return null;
  }

  /// Whether [call] is a static `of` lookup on an app class taking a
  /// `BuildContext`, such as an inherited design-system theme.
  bool _isContextLookup(MethodInvocation call) {
    final method = call.methodName.element;
    if (call.methodName.name != 'of' ||
        method is! MethodElement ||
        !method.isStatic ||
        _isFrameworkValueType(method.enclosingElement)) {
      return false;
    }
    return call.argumentList.arguments.any(
      (argument) =>
          argument.argumentExpression.staticType?.element?.name ==
          'BuildContext',
    );
  }

  /// Why [name] is not a property of [entry]: the reason its package left it
  /// out, or the properties the catalog does declare.
  String _undeclaredPropertyMessage(WidgetEntry entry, String name) {
    final dropped = catalog.exclusions.firstWhereOrNull(
      (exclusion) =>
          exclusion.location == '${entry.flutterType}.$name' &&
          exclusion.target == 'rfw',
    );
    if (dropped != null) {
      return "'${entry.name}' leaves out its optional property '$name': "
          '${reasonClause(dropped.reason)}.';
    }
    return "Property '$name' is not declared on '${entry.name}'. "
        'Catalog properties: '
        '${entry.properties.map((p) => p.name).join(", ")}.';
  }

  /// The package of [widgetClass] when it is another package's widget whose
  /// builder callback receives a value, such as a state-management builder;
  /// `null` otherwise.
  String? _appStateBuilderPackage(ClassElement? widgetClass) {
    if (widgetClass == null || _isFrameworkValueType(widgetClass)) return null;
    final library = widgetClass.library.identifier;
    if (!library.startsWith('package:')) return null;
    final package = library.substring('package:'.length).split('/').first;
    final surface = _currentSourceUnit;
    final surfaceUri = surface is CompilationUnit
        ? surface.declaredFragment?.source.uri
        : null;
    if (surfaceUri != null &&
        surfaceUri.scheme == 'package' &&
        surfaceUri.pathSegments.first == package) {
      return null;
    }
    // A builder that hands its child a data value, beyond framework plumbing
    // such as the context, a child widget, constraints or a callback.
    bool isStateValue(DartType type) {
      if (type is FunctionType) return false;
      final library = type.element?.library?.identifier;
      return library == null || !library.startsWith('package:flutter/');
    }

    final buildsFromState = widgetClass.constructors.any(
      (constructor) => constructor.formalParameters.any((parameter) {
        final type = parameter.type;
        return type is FunctionType &&
            type.returnType.element?.name == 'Widget' &&
            type.formalParameters.any((value) => isStateValue(value.type));
      }),
    );
    return buildsFromState ? package : null;
  }

  /// [issue], noting when [widgetClass] is a `@RestageWidget` whose package
  /// has no widget in the catalog at all: its widget catalog did not build.
  Issue _withUnbuiltCatalogNote(Issue issue, ClassElement widgetClass) {
    final annotated = widgetClass.metadata.annotations.any(
      (annotation) =>
          annotation.element?.enclosingElement?.name == 'RestageWidget',
    );
    final library = widgetClass.library.identifier;
    if (!annotated || !library.startsWith('package:')) return issue;
    final package = '${library.substring(0, library.indexOf('/'))}/';
    if (catalog.widgets.any((entry) => entry.flutterType.startsWith(package))) {
      return issue;
    }
    return Issue(
      code: issue.code,
      message:
          "${issue.message} This package's widget catalog did not "
          'build, so the widget has no entry yet: fix the widget catalog '
          'errors first.',
      location: issue.location,
      capabilityGapSubject: issue.capabilityGapSubject,
      buildNoticeIdentity: issue.buildNoticeIdentity,
    );
  }

  /// The diagnostic for a recognised custom widget that has no catalog entry
  /// and does not inline, from its [classification].
  Issue _customWidgetIssue(
    WidgetClassification classification,
    ClassElement widgetClass,
    String widgetName,
    Expression anchor,
  ) {
    final issue = _customWidgetGap(classification, widgetName, anchor).issue;
    final flutterType = '${widgetClass.library.identifier}#${widgetClass.name}';
    final exclusion = catalog.exclusions.firstWhereOrNull(
      (exclusion) => exclusion.isOf(flutterType) && exclusion.target == 'rfw',
    );
    if (exclusion == null ||
        catalog.widgets.any((entry) => entry.flutterType == flutterType)) {
      return issue;
    }
    // The widget's package left it out of its catalog, and says why.
    return Issue(
      code: issue.code,
      capabilityGapSubject: issue.capabilityGapSubject,
      message:
          "'$widgetName' is left out of the catalog: "
          '${reasonClause(exclusion.reason)}.',
      location: _locationOf(anchor),
    );
  }

  /// Why a custom widget renders from the app's compiled code, as a clause.
  String _customWidgetFactoryReason(
    WidgetClassification classification,
    String widgetName,
    Expression anchor,
  ) => _customWidgetGap(classification, widgetName, anchor).reason;

  /// The one table behind a custom widget's diagnostic and its factory reason.
  ({Issue issue, String reason}) _customWidgetGap(
    WidgetClassification classification,
    String widgetName,
    Expression anchor,
  ) {
    String withoutEntry(String why) =>
        "The custom widget '$widgetName' has no catalog entry, and Restage "
        'cannot inline it into the delivered surface: $why. Add it to your '
        "widget catalog and it renders from your app's compiled code: "
        'export it from a library annotated @RestageLibrary, document the '
        'widget and each of its properties, and fix any widget catalog error '
        'this build reports for it.';
    switch (classification) {
      case ComposableWidget():
        final mechanisms = classification.requiredMechanisms;
        final note = mechanisms.isEmpty
            ? ''
            : ' (needs ${mechanisms.map((m) => m.name).join(", ")})';
        return (
          issue: Issue(
            code: IssueCode.customWidgetInliningDeferred,
            capabilityGapSubject: 'customWidget:$widgetName',
            message: withoutEntry(
              'it is pure composition$note, which Restage does not yet inline',
            ),
            location: _locationOf(anchor),
          ),
          reason:
              'Restage does not yet inline its build() into delivered surfaces',
        );
      case ImperativeWidget():
        // A genuine RFW boundary reads "cannot express".
        if (classification.disposition == CustomWidgetDisposition.deadEnd) {
          final blocker = classification.blockers.firstWhere(
            (b) => b.disposition == CustomWidgetDisposition.deadEnd,
          );
          return (
            issue: Issue(
              code: IssueCode.customWidgetImperative,
              message: withoutEntry(
                'its build() uses ${blocker.detail}'
                '${_readableBlockerLocation(blocker.location)}, which a '
                'delivered surface cannot express',
              ),
              location: blocker.location,
            ),
            reason: 'build() uses ${blocker.detail}',
          );
        }
        final blocker = classification.blockers.first;
        return (
          issue: Issue(
            code: IssueCode.customWidgetUnsupportedReducible,
            capabilityGapSubject: 'customWidget:$widgetName',
            message: withoutEntry(
              'its build() uses ${blocker.detail}'
              '${_readableBlockerLocation(blocker.location)}, which is not '
              'supported in delivered surfaces',
            ),
            location: blocker.location,
          ),
          reason: 'build() uses ${blocker.detail}',
        );
      case UnclassifiableWidget(:final ownKey?):
        return (
          issue: Issue(
            code: classification.diagnosticCode,
            capabilityGapSubject: 'customWidget:$widgetName',
            message:
                "`$widgetName` renders from your app's code because its "
                'build() creates its own key (`$ownKey`). Try passing the key '
                "in through `$widgetName`'s constructor.",
            location: _locationOf(anchor),
          ),
          reason: classification.reason,
        );
      case UnclassifiableWidget():
        return (
          issue: Issue(
            code: classification.diagnosticCode,
            capabilityGapSubject: 'customWidget:$widgetName',
            message: withoutEntry(
              'Restage does not yet recognise it (${classification.reason})',
            ),
            location: _locationOf(anchor),
          ),
          reason: classification.reason,
        );
    }
  }

  // A blocker's location, `<file>#<class>@<line>:<column>`, as the message
  // names it: ` (<file>:<line>:<column>)`, or nothing when it isn't one.
  static String _readableBlockerLocation(String location) => switch (RegExp(
    r'^(.+?)#[^@]*@(\d+:\d+)$',
  ).firstMatch(location)) {
    final match? =>
      ' (${match[1]!.startsWith('package:') ? 'lib/${match[1]!.split('/').skip(1).join('/')}' : match[1]}:${match[2]})',
    null => '',
  };

  static String _withoutFinalPeriod(String message) => message.endsWith('.')
      ? message.substring(0, message.length - 1)
      : message;

  void _recordCustomWidgetFactoryRoute(
    _CustomWidgetEmissionIdentity identity,
    _CustomWidgetFactoryRoute route,
  ) {
    final routes = _currentCustomWidgetFactoryRoutes;
    if (routes == null) return;
    final existing = routes[identity];
    if (existing == null || route.reason.compareTo(existing.reason) < 0) {
      routes[identity] = route;
    }
  }

  List<Issue> _customWidgetFactoryNotices(
    Map<_CustomWidgetEmissionIdentity, _CustomWidgetFactoryRoute> routes,
  ) {
    final ordered = routes.entries.toList()
      ..sort((left, right) {
        final classOrder = left.key.classKey.compareTo(right.key.classKey);
        if (classOrder != 0) return classOrder;
        return left.key.remoteLibrary.compareTo(right.key.remoteLibrary);
      });
    return [
      for (final entry in ordered)
        Issue(
          code: IssueCode.customWidgetAppFactoryUsed,
          message:
              "Custom widget '${entry.value.widgetName}' renders from "
              "your app's compiled code because ${entry.value.reason}. That "
              'is fine: delivered surfaces still set its arguments, and '
              'changes to its build() or defaults ship with your next app '
              'release.',
          location: entry.key.classKey,
          buildNoticeIdentity:
              '${entry.key.classKey}\u0000${entry.key.remoteLibrary}',
        ),
    ];
  }

  /// Splits a comma-separated argument list at the top level only, respecting
  /// nested parentheses, brackets, and quoted strings.
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
  /// gate, so a resolved custom `BorderRadius` look-alike still defers there.
  bool _isAsymmetricBorderRadiusCtor(Expression expr) {
    final stripped = _stripParens(expr);
    final String className;
    final String? ctorName;
    if (stripped is InstanceCreationExpression) {
      className = instanceCreationTypeName(stripped);
      ctorName = instanceCreationMemberName(stripped);
    } else if (stripped is MethodInvocation) {
      final target = stripped.target;
      if (target is! SimpleIdentifier) return false;
      className = target.name;
      ctorName = stripped.methodName.name;
    } else {
      return false;
    }
    return className == 'BorderRadiusDirectional' ||
        (className == 'BorderRadius' &&
            _kAsymmetricBorderRadiusCtors.contains(ctorName));
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
      // Structured values rewrite their sentinels into corner maps, so one
      // left here sits inside a condition, which per-corner slots can't split.
      if (value.contains(_kBorderRadiusCornerSentinel)) {
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message:
                "A BorderRadius with different corners can't be chosen "
                'by a condition here. Put the condition inside each '
                "corner's radius instead.",
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
    final directionalCorners =
        value.contains('topStart:') ||
        value.contains('topEnd:') ||
        value.contains('bottomStart:') ||
        value.contains('bottomEnd:');
    final hasAllCorners = _kBorderRadiusCornerProperty.entries
        .where(
          (e) =>
              (e.key.endsWith('Start') || e.key.endsWith('End')) ==
              directionalCorners,
        )
        .map((e) => e.value)
        .every(
          (name) => entry.properties.any(
            (p) =>
                p.name == name && p.synthetic == _kBorderRadiusCornerSynthetic,
          ),
        );
    if (!hasAllCorners) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message:
              'An asymmetric BorderRadius is not representable on '
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

  /// Validates theme and shaped host-data references against [type], including
  /// conditional branches and coalesced fallbacks.
  void _validateDataRefForSlot(
    Expression source,
    PropertyType type,
    List<Issue> issues, {
    PropertyEntry? property,
  }) {
    var current = source;
    while (current is ParenthesizedExpression) {
      current = current.expression;
    }
    if (current is ConditionalExpression) {
      _validateDataRefForSlot(
        current.thenExpression,
        type,
        issues,
        property: property,
      );
      _validateDataRefForSlot(
        current.elseExpression,
        type,
        issues,
        property: property,
      );
      return;
    }
    // Null-coalescing optional property — `<prop> ?? <fallback>`. The fallback
    // is hoisted to the call site for completion, so it never reaches a body
    // slot to be validated there; validate it against THIS slot's type here,
    // before the rewrite, exactly as if it were written directly.
    final coalesce = _coalesceParamAt(current);
    if (coalesce != null) {
      _validateDataRefForSlot(
        coalesce.fallback,
        type,
        issues,
        property: property,
      );
      // Record that this property's fallback was validated against a slot —
      // the body rewrite is sound only for validated coalesced reads (see
      // [_translateCoalesce]).
      _walk.validatedCoalesceParams.add(coalesce.name);
      return;
    }
    final devicePath = _recognizeDeviceRead(current)?.path;
    if (devicePath != null) {
      final deviceKind = kDeviceContractPathKinds[devicePath];
      if (deviceKind == null) return;
      if (propertyTypeAcceptsDeviceKind(type, deviceKind)) return;
      issues.add(
        Issue(
          code: IssueCode.propertyValueTypeMismatch,
          message:
              "Device value 'data.device.$devicePath' cannot be "
              "assigned to a '${type.name}' property type at this site.",
          location: _locationOf(current),
        ),
      );
      return;
    }
    // Binding-aware: a `scheme.primary` fallback is a PrefixedIdentifier, not a
    // PropertyAccess — `_recognizeThemeRead` resolves it through the active
    // theme-local bindings, so a PropertyAccess-only guard would silently skip
    // it and bypass this kind check.
    final segments = _recognizeThemeRead(current);
    if (segments == null) {
      _validateShapedReferenceForSlot(current, type, issues);
      return;
    }
    final kind = kThemeContractPathKinds[segments.join('.')];
    if (kind == null) return;
    if (propertyTypeAcceptsThemeKind(type, kind, property: property)) return;
    issues.add(
      Issue(
        code: IssueCode.propertyValueTypeMismatch,
        message:
            "Theme value 'data.theme.${segments.join('.')}' cannot be "
            "assigned to a '${type.name}' property type at this site.",
        location: _locationOf(current),
      ),
    );
  }

  /// Validates a shaped host-data read against a property slot.
  void _validateShapedReferenceForSlot(
    Expression source,
    PropertyType type,
    List<Issue> issues,
  ) {
    if (type == PropertyType.unknown) return;
    final reference = _shapedReference(source);
    if (reference == null) return;
    if (_propertyTypeAcceptsHostDataShape(type, reference.shape)) return;
    final typeCode = reference.shape.type.getDisplayString();
    issues.add(
      Issue(
        code: IssueCode.propertyValueTypeMismatch,
        message:
            "Host data value '${reference.dsl}' is declared "
            "'$typeCode' and cannot be assigned to a "
            "'${type.name}' property type at this site.",
        location: _locationOf(source),
      ),
    );
  }

  String _locationOf(AstNode node) {
    final constant = constValueAnchor(node);
    if (constant != null) return _locationOf(constant);
    // An inlined helper or widget body reports against its own file.
    final unit = node.root;
    final current = _currentSourceUnit;
    if (current != null && unit != current && unit is CompilationUnit) {
      final location = unit.lineInfo.getLocation(node.offset);
      return '${_unitPath(unit, current)}:${location.lineNumber}:'
          '${location.columnNumber}';
    }
    // Without a source context, the node's own unit gives a readable place.
    final path =
        _currentSourcePath ??
        (unit is CompilationUnit ? _unitPath(unit, unit) : null);
    final li =
        _currentLineInfo ?? (unit is CompilationUnit ? unit.lineInfo : null);
    if (path == null || li == null) return _declarationOf(node);
    final loc = li.getLocation(node.offset);
    return '$path:${loc.lineNumber}:${loc.columnNumber}';
  }

  // Where [node] is when its file cannot be named: the enclosing class and
  // member as written, or its file position when it has neither.
  String _declarationOf(AstNode node) {
    final owner = node
        .thisOrAncestorOfType<ClassDeclaration>()
        ?.declaredFragment
        ?.element
        .name;
    final member = switch (node.thisOrAncestorMatching(
      (n) =>
          n is MethodDeclaration ||
          n is FunctionDeclaration ||
          n is VariableDeclaration &&
              n.parent?.parent is TopLevelVariableDeclaration,
    )) {
      MethodDeclaration(:final name) ||
      FunctionDeclaration(:final name) ||
      VariableDeclaration(:final name) => name.lexeme,
      _ => null,
    };
    final declaration = [owner, member].nonNulls.join('.');
    if (declaration.isNotEmpty) return declaration;
    // A node in a unit always has a file position, so this can't recurse.
    return node.root is CompilationUnit ? _locationOf(node) : node.toSource();
  }

  /// A helper call's name as written: `Owner.method` for a static.
  String _helperName(MethodInvocation expr) => switch (expr.target) {
    SimpleIdentifier(:final name) => '$name.${expr.methodName.name}',
    _ => expr.methodName.name,
  };

  /// [unit]'s path as the surface's own path is spelled: package-relative
  /// within the surface's package, its full URI otherwise.
  String _unitPath(CompilationUnit unit, AstNode surface) {
    final uri = unit.declaredFragment?.source.uri;
    if (uri == null) {
      return unit.declaredFragment?.source.shortName ?? 'this file';
    }
    final surfaceUri = surface is CompilationUnit
        ? surface.declaredFragment?.source.uri
        : null;
    if (uri.scheme == 'package' &&
        surfaceUri?.scheme == 'package' &&
        uri.pathSegments.first == surfaceUri!.pathSegments.first) {
      return 'lib/${uri.pathSegments.skip(1).join('/')}';
    }
    return '$uri';
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
    final owner = constructionConstructor(expr)?.enclosingElement;
    if (owner is ClassElement) return owner;
    final element = expr.constructorName.type.element;
    return element is ClassElement ? element : null;
  }

  /// The class a resolved construction names, the element a resolved call
  /// targets otherwise, or `null` when the source did not resolve.
  Element? _resolvedCallee(Expression anchor) => switch (anchor) {
    final InstanceCreationExpression creation =>
      constructionConstructor(creation)?.enclosingElement ??
          switch (creation.constructorName.type.element) {
            final InterfaceElement type => type,
            _ => null,
          },
    MethodInvocation(:final methodName, :final target) =>
      switch (methodName.element) {
        ConstructorElement(:final enclosingElement) => enclosingElement,
        final Element element => element,
        null => target is SimpleIdentifier ? target.element : null,
      },
    _ => null,
  };

  /// The canonical `'<library URI>#<class name>'` of [cls].
  String _classIdentity(InterfaceElement cls) =>
      '${canonicalFrameworkLibraryUri(cls.library.identifier)}#${cls.name}';

  /// The class part of [entry]'s Flutter type, without constructor or type
  /// arguments.
  String _entryClassIdentity(WidgetEntry entry) {
    final type = entry.flutterType;
    final hash = type.indexOf('#');
    if (hash < 0) return type;
    final end = type.indexOf(RegExp('[.<]'), hash);
    return end < 0 ? type : type.substring(0, end);
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
    // Canonicalised so a design-package class joins the catalog on the
    // framework identity the catalog records. `customWidgetKey` canonicalises
    // identically — the classifier and this lookup must not disagree about
    // whether a construction is a catalog widget.
    final libraryUri = canonicalFrameworkLibraryUri(cls.library.identifier);
    final className = cls.name;
    if (className == null || className.isEmpty) return null;
    final constructorSuffix = constructorName == null || constructorName.isEmpty
        ? ''
        : '.$constructorName';
    return '$libraryUri#$className$constructorSuffix';
  }

  /// Returns hoisted flat-property emissions when [expr] matches a native
  /// decomposition recipe for [entry]'s constructor argument [argName].
  /// Reports the decompose-only mismatch for [entry].[argName] and returns
  /// true when that argument targets a native decomposition recipe, so the
  /// caller skips the generic unknown-property report.
  ///
  /// Such an argument is compiled by decomposing a literal constructor of the
  /// recipe's structured type into flat catalog properties, and the catalog
  /// declares no property under the argument's own name. Without this check,
  /// an author passing a value the recipe cannot match (a theme read, a
  /// variable, a function result) would be told the argument does not exist
  /// at all, which points away from the actual remedy.
  bool _reportUndecomposableArgument(
    WidgetEntry entry,
    String argName,
    Expression expr,
    List<Issue> issues,
  ) {
    final recipes = entry.decomposes
        .where((r) => r.targetArg == argName)
        .toList();
    if (recipes.isEmpty) return false;
    // The source-type fragment is the constructor name the author writes
    // (`TextStyle`, `BoxDecoration`), which is what the remedy must name;
    // the entry's display name is advisory and may differ.
    final typeNames =
        recipes
            .map(
              (r) => _nativeCatalogIndex
                  .structuredByRef(r.structuredRef)
                  ?.sourceType
                  .split('#')
                  .last,
            )
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    final typeLabel = typeNames.isEmpty ? '' : '${typeNames.join(' or ')} ';
    final appOnly = _appOnlyValueIssue(expr, IssueCode.unrecognizedMethodCall);
    if (appOnly != null) {
      issues.add(appOnly);
      return true;
    }
    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message:
            "Property '$argName' on '${entry.name}' takes a literal "
            '${typeLabel}constructor. The compiler decomposes it into flat '
            'catalog properties at build time and cannot decompose this '
            'expression. Construct the value inline; values inside it, like '
            'a Theme.of(context) color, resolve when the surface renders.',
        location: _locationOf(expr),
      ),
    );
    return true;
  }

  List<String>? _tryDecompose(
    WidgetEntry entry,
    String argName,
    Expression expr,
    List<Issue> issues,
  ) {
    if (entry.decomposes.isEmpty) return null;

    final relevantRecipes = entry.decomposes
        .where((r) => r.targetArg == argName)
        .toList();
    if (relevantRecipes.isEmpty) return null;
    final candidateRecipes = relevantRecipes
        .where((r) => r.construction != null)
        .toList();
    if (candidateRecipes.length != relevantRecipes.length) {
      issues.add(
        Issue(
          code: IssueCode.unknownProperty,
          message:
              "Native decomposition for '${entry.name}.$argName' is "
              'missing native construction metadata.',
          location: _locationOf(expr),
        ),
      );
      return const [];
    }

    final resolved = _resolveBoundIdentifier(expr);
    final declaration = constDeclarationElement(resolved);
    final constantNull =
        declaration is VariableElement &&
        !dependsOnBuildEnvironment(declaration) &&
        declaration.computeConstantValue()?.isNull == true;
    if (resolved is NullLiteral || constantNull) {
      final argument = expr.parent;
      if (argument is NamedArgument &&
          argument.correspondingParameter?.type.nullabilitySuffix ==
              NullabilitySuffix.question) {
        return const [];
      }
    }

    final index = _nativeCatalogIndex;
    final constant = _constantConstruction(expr);
    for (final recipe in candidateRecipes) {
      final construction = recipe.construction!;

      final structured = index.structuredByRef(recipe.structuredRef);
      final variant = index.variantByRef(construction.variantRef);
      if (structured == null || variant == null) continue;

      final match = _matchNativeInvocation(
        constant?.base ?? expr,
        construction,
        owningWidget: entry,
        resultStructured: structured,
        variant: variant,
      );
      if (match != null && constant != null) {
        _applyCopyWith(variant, match, constant.overrides);
      }
      if (match == null) {
        final themed = _decomposeThemeTextStyle(
          expr,
          recipe: recipe,
          structured: structured,
          entry: entry,
          issues: issues,
        );
        if (themed != null) return themed;
        continue;
      }

      final out = <String>[];
      final mappedFields = recipe.fieldMappings.map((m) => m.fieldRef).toSet();
      final mappedArguments = <String>{};
      for (final mapping in recipe.fieldMappings) {
        var sourceExpr = match.fieldExpressions[mapping.fieldRef];
        if (sourceExpr == null) continue;
        final destProp = index.widgetProperty(
          _widgetRef(entry),
          mapping.propertyRef,
        );
        if (destProp == null) continue;
        if (destProp.synthetic == _kBorderRadiusCircularSynthetic) {
          sourceExpr = _resolveBoundIdentifier(sourceExpr);
          final constant = _constantConstruction(sourceExpr);
          if (constant != null && constant.overrides.isEmpty) {
            sourceExpr = constant.base;
          }
        }
        // Inspect bindings before choosing the circular-only radius transform.
        if (destProp.synthetic == _kBorderRadiusCircularSynthetic &&
            (_isAsymmetricBorderRadiusCtor(sourceExpr) ||
                _frameworkConstValue(_stripParens(sourceExpr))?.kind ==
                    FrameworkConstKind.borderRadius)) {
          final before = issues.length;
          final translated = _translate(sourceExpr, issues);
          final hadError = issues
              .skip(before)
              .any((i) => !i.code.isInformational);
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
              '${_rfwMapKey(destProp.name)}: '
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
        out.add('${_rfwMapKey(destProp.name)}: $value');
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
        final destProp = index.widgetProperty(
          _widgetRef(entry),
          mapping.propertyRef,
        );
        if (destProp == null) continue;
        final translated = _decompositionValue(
          mapping.transform,
          sourceExpr,
          owningWidget: entry,
          destination: destProp,
          issues: issues,
        );
        if (translated == null) continue;
        final value = _coerceForPropertyType(destProp.type, translated);
        out.add('${_rfwMapKey(destProp.name)}: $value');
      }

      for (final supplied in match.fieldExpressions.entries) {
        if (mappedFields.contains(supplied.key)) continue;
        final field = index.structuredField(recipe.structuredRef, supplied.key);
        final fieldName = field?.name ?? supplied.key.value;
        issues.add(
          Issue(
            code: IssueCode.unknownProperty,
            message:
                "Native decomposition field '$fieldName' on "
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
            message:
                "Native decomposition argument '${unmapped.key}' on "
                "'${structured.name}' is not mapped to a structured field.",
            location: _locationOf(unmapped.value),
          ),
        );
      }

      return out;
    }
    return null;
  }

  /// Expands a whole-style theme read into the flat properties [recipe] maps,
  /// each bound to its published `data.theme.textTheme.*` reference, with a
  /// trailing `copyWith(...)` overriding the fields it names. Returns `null`
  /// when [expr] is not such a read, so the caller falls through.
  List<String>? _decomposeThemeTextStyle(
    Expression expr, {
    required DecompositionRecipe recipe,
    required StructuredEntry structured,
    required WidgetEntry entry,
    required List<Issue> issues,
  }) {
    if (structured.sourceType.split('#').last != 'TextStyle') return null;
    var read = _stripParens(expr);
    var overrides = const <String, Expression>{};
    if (read is MethodInvocation && read.methodName.name == 'copyWith') {
      final target = read.target;
      if (target == null) return null;
      overrides = <String, Expression>{
        for (final argument in read.argumentList.arguments)
          if (argument is NamedArgument)
            argument.name.lexeme: argument.argumentExpression,
      };
      if (overrides.length != read.argumentList.arguments.length) return null;
      read = target;
    }
    final segments = _recognizeThemeRead(read);
    final String base;
    var fromApp = false;
    if (segments != null && _wholeTextThemeStyleRead(segments)) {
      base = 'data.theme.${segments.join('.')}';
    } else {
      fromApp = true;
      // A style the app computes is read from the mount, field by field.
      final whole = _hoistedStyleRead(expr);
      final hoisted =
          whole ?? (identical(read, expr) ? null : _hoistedStyleRead(read));
      if (hoisted == null) return null;
      if (whole != null) overrides = const <String, Expression>{};
      base = hoisted;
    }

    // Scoped to the published fields, so the same source compiles the same
    // way whatever slot it lands in.
    final fields = fromApp
        ? kHoistedTextStyleFields.keys
        : kThemeContractTextThemeFieldKinds.keys;
    final unpublished = overrides.keys
        .where((name) => !fields.contains(name))
        .toList();
    if (!fromApp && unpublished.isNotEmpty) {
      issues.add(
        Issue(
          code: IssueCode.themeReadOutOfContract,
          message:
              "copyWith on a theme style cannot set '${unpublished.first}'"
              '. A theme style carries ${fields.join(', ')}; build a literal '
              'TextStyle to set anything else.',
          location: _locationOf(expr),
        ),
      );
      return const [];
    }

    final index = _nativeCatalogIndex;
    final emitted = <String>[];
    final overridden = <String>{};
    for (final mapping in recipe.fieldMappings) {
      final field = index.structuredField(
        recipe.structuredRef,
        mapping.fieldRef,
      );
      final fieldName = field?.name;
      if (fieldName == null) continue;
      final destination = index.widgetProperty(
        _widgetRef(entry),
        mapping.propertyRef,
      );
      if (destination == null) continue;
      final override = overrides[fieldName];
      if (override != null) {
        overridden.add(fieldName);
        final translated = _decompositionValue(
          mapping.transform,
          override,
          owningWidget: entry,
          destination: destination,
          issues: issues,
        );
        if (translated == null) continue;
        emitted.add(
          '${_rfwMapKey(destination.name)}: '
          '${_coerceForPropertyType(destination.type, translated)}',
        );
        continue;
      }
      final path = '$base.$fieldName';
      if (fromApp) {
        if (!fields.contains(fieldName)) continue;
        emitted.add(
          '${_rfwMapKey(destination.name)}: '
          '${_coerceForPropertyType(destination.type, path)}',
        );
        continue;
      }
      final kind = kThemeContractTextThemeFieldKinds[fieldName];
      if (kind == null) continue;
      if (!propertyTypeAcceptsThemeKind(
        destination.type,
        kind,
        property: destination,
      )) {
        issues.add(
          Issue(
            code: IssueCode.propertyValueTypeMismatch,
            message:
                "Theme value '$path' cannot be assigned to "
                "the '${destination.type.name}' property "
                "'${entry.name}.${destination.name}' the style decomposes to.",
            location: _locationOf(expr),
          ),
        );
        return const [];
      }
      emitted.add(
        '${_rfwMapKey(destination.name)}: '
        '${_coerceForPropertyType(destination.type, path)}',
      );
    }
    if (emitted.isEmpty) return null;

    final unmapped = overrides.keys.where((n) => !overridden.contains(n));
    if (unmapped.isNotEmpty) {
      issues.add(
        Issue(
          code: IssueCode.unknownProperty,
          message:
              "copyWith argument '${unmapped.first}' has no flat property "
              "on '${entry.name}' to carry it.",
          location: _locationOf(expr),
        ),
      );
      return const [];
    }

    return emitted;
  }

  /// The payload's read of a mount-computed `TextStyle` [expr], when the
  /// mount can compute it.
  String? _hoistedStyleRead(Expression expr) {
    final hoist = _hoist;
    if (hoist == null || hoist.speculating) return null;
    final stripped = _stripParens(expr);
    final verdict = classifyHoistType(stripped.staticType);
    if (verdict is! HoistCrosses || verdict.kind != HoistValueKind.textStyle) {
      return null;
    }
    final analysis = hoist.analyzer.analyze(stripped);
    if (analysis is! HoistEvaluable) return null;
    if (_designStateRead(stripped) != null) return null;
    return _hoistedRead(
      hoist.add(
        analysis.value(
          verdict,
          stripped.staticType!,
          expression: stripped,
        ),
      ),
    );
  }

  /// The construction a constant [expr] evaluates to, with the named
  /// arguments of a trailing `copyWith` to apply over it, or `null` when
  /// [expr] is not a constant construction.
  ({InstanceCreationExpression base, List<NamedArgument> overrides})?
  _constantConstruction(Expression expr) {
    var current = _stripParens(expr);
    var overrides = const <NamedArgument>[];
    if (current is MethodInvocation &&
        current.methodName.name == 'copyWith' &&
        current.target != null) {
      final named = current.argumentList.arguments.whereType<NamedArgument>();
      if (named.length != current.argumentList.arguments.length) return null;
      overrides = named.toList();
      current = _stripParens(current.target!);
    }
    final seen = <Element>{};
    for (var resolved = false; ; resolved = true) {
      if (current is InstanceCreationExpression) {
        return resolved || overrides.isNotEmpty
            ? (base: current, overrides: overrides)
            : null;
      }
      final declaration = constDeclarationElement(current);
      if (declaration != null && !seen.add(declaration)) return null;
      final next = isConstObjectFieldAccess(current)
          ? resolveConstObjectFieldInitializer(current)
          : resolveConstIdentifierInitializer(current);
      if (next == null) return null;
      current = _stripParens(next);
    }
  }

  /// Binds each `copyWith` argument over the base construction's match.
  void _applyCopyWith(
    FactoryVariant variant,
    _NativeInvocationMatch match,
    List<NamedArgument> overrides,
  ) {
    final parameters = factoryVariantCallableFields(variant).parameters;
    for (final override in overrides) {
      final name = override.name.lexeme;
      final parameter = parameters.firstWhereOrNull(
        (p) => p.kind == FactoryParameterKind.named && p.name == name,
      );
      final mapped =
          parameter != null &&
          _bindNativeParameter(
            variant,
            parameter,
            override.argumentExpression,
            match.parameterExpressions,
            match.fieldExpressions,
          );
      if (!mapped) match.unmappedArguments[name] = override.argumentExpression;
    }
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
          final translated = _translateSlotValue(
            sourceExpr,
            destination.type,
            issues,
            property: destination,
          );
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
          message: invocation.memberName == null
              ? 'Native decomposition for ${destination.name} expected '
                    "a '${structured.name}' value constructed through the "
                    'catalog variant ${invocation.variantRef.wireId.value}.'
              : "'${destination.name}' expects a '${structured.name}' value "
                    'written as '
                    '${structured.name}.${invocation.memberName}(...).',
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
            message:
                'Native decomposition for ${destination.name} is missing '
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
            message:
                'Native decomposition for ${destination.name} does not '
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
    if (value is num || value is bool) return _foldedLiteral(value);
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
      final fallbackTypeName = instanceCreationTypeName(expr);
      if (!_matchesDartType(receiver, actualType, fallbackTypeName)) {
        return null;
      }
      if (!_matchesMember(
        instanceCreationMemberName(expr),
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
    NodeList<Argument> args,
  ) {
    final parameterExpressions = <WireId, Expression>{};
    final fieldExpressions = <WireId, Expression>{};
    final unmappedArguments = <String, Expression>{};
    final parameters = factoryVariantCallableFields(variant).parameters;

    var positionalIndex = 0;
    for (final arg in args) {
      if (arg is NamedArgument) {
        final name = arg.name.lexeme;
        final parameter = parameters.firstWhereOrNull(
          (p) => p.kind == FactoryParameterKind.named && p.name == name,
        );
        if (parameter == null) {
          unmappedArguments[name] = arg.argumentExpression;
          continue;
        }
        final mapped = _bindNativeParameter(
          variant,
          parameter,
          arg.argumentExpression,
          parameterExpressions,
          fieldExpressions,
        );
        if (!mapped) unmappedArguments[name] = arg.argumentExpression;
      } else {
        final position = positionalIndex;
        final parameter = parameters.firstWhereOrNull(
          (p) =>
              p.kind == FactoryParameterKind.positional &&
              p.position == positionalIndex,
        );
        positionalIndex++;
        if (parameter == null) {
          unmappedArguments['#$position'] = arg.argumentExpression;
          continue;
        }
        final mapped = _bindNativeParameter(
          variant,
          parameter,
          arg.argumentExpression,
          parameterExpressions,
          fieldExpressions,
        );
        if (!mapped) {
          unmappedArguments['#$position'] = arg.argumentExpression;
        }
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
  _ModalSheetEmitContext({required this.sheet, required this.flagName});

  final RecognisedModalSheet sheet;
  final String flagName;

  /// The measured callback that opens the sheet, once translated.
  MeasurementEventOccurrence? triggerOccurrence;
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

  /// The lowering of the transitions whose event appears in [emitted], or
  /// null when the design fires none.
  NavigationLowering? toLowering({required Iterable<String> emitted}) {
    final transitions = [
      for (final entry in entries)
        if (emitted.any((text) => text.contains('event "${entry.event}"')))
          NavigationTransition(
            event: entry.event,
            pushedId: entry.trigger.paywallSourceId,
          ),
    ];
    if (transitions.isEmpty) return null;
    return NavigationLowering(
      entryId: entryId,
      transitions: transitions,
      terminatingEvent: 'skip',
    );
  }
}

final class _NavigationTriggerEntry {
  const _NavigationTriggerEntry({required this.trigger, required this.event});

  final RecognisedNavigation trigger;
  final String event;
}

/// Finds a read of any element in [parameters] anywhere under a node.
final class _ClosureParameterCensus extends RecursiveAstVisitor<void> {
  _ClosureParameterCensus(this.parameters);

  final Set<Element> parameters;
  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (parameters.contains(node.element)) found = true;
    super.visitSimpleIdentifier(node);
  }
}

final class _LocalValueWriteScanner extends RecursiveAstVisitor<void> {
  _LocalValueWriteScanner(this.stateFields);

  final Set<String> stateFields;
  final Set<String> fields = {};

  @override
  void visitFunctionExpression(FunctionExpression node) {
    final field = recogniseLocalValueWrite(node);
    if (field != null && stateFields.contains(field)) fields.add(field);
    super.visitFunctionExpression(node);
  }
}

final class _RootNavigationTriggerScanner extends RecursiveAstVisitor<void> {
  _RootNavigationTriggerScanner({
    required this.buildContextParameter,
    required this.canonicalPaywallIdFor,
  });

  final Element? buildContextParameter;
  final CanonicalPaywallIdFor? canonicalPaywallIdFor;
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

    final outcome = recogniseNavigationTrigger(
      node,
      canonicalPaywallIdFor: canonicalPaywallIdFor,
    );
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
    if (parent is! NamedArgument) return false;
    return isNavigationTriggerSlotName(parent.name.lexeme);
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
      if (arg is NamedArgument) return null;
      return arg is SimpleIdentifier ? arg : null;
    }
    final args = pushCall.argumentList.arguments;
    if (args.isEmpty) return null;
    final first = args.first;
    if (first is NamedArgument) return null;
    return first is SimpleIdentifier ? first : null;
  }
}

final class _PaywallEventNameScanner extends RecursiveAstVisitor<void> {
  _PaywallEventNameScanner(
    this.helpers, {
    required InlinedDefinitions inlined,
  }) : _inlinedHelpers = inlined.helpers,
       _bindings = Map<Element, Expression>.of(inlined.localBindings);

  final HelperRegistry helpers;
  final Map<Element, HelperDef> _inlinedHelpers;
  final Map<Element, Expression> _bindings;
  final List<String> names = [];
  final Set<Element> _activeBindings = {};
  final Set<Element> _activeHelpers = {};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    final binding = element == null ? null : _bindings[element];
    if (element != null && binding != null && _activeBindings.add(element)) {
      try {
        binding.accept(this);
      } finally {
        _activeBindings.remove(element);
      }
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = _authoredEventCallName(node);
    if (name != null) names.add(name);
    final element = node.methodName.element;
    final helper = _inlinedHelpers[element];
    if (element != null && helper != null && _activeHelpers.add(element)) {
      final bindings = bindHelperArguments(
        helper.params,
        node.argumentList.arguments.toList(),
      );
      if (bindings != null) {
        final savedBindings = Map<Element, Expression>.of(_bindings);
        _bindings.addAll(bindings);
        try {
          helper.body.accept(this);
        } finally {
          _bindings
            ..clear()
            ..addAll(savedBindings);
        }
      }
      _activeHelpers.remove(element);
    }
    super.visitMethodInvocation(node);
  }
}

// The `context.surfaceEvent` calls a recorded build rewrites.
final class _EventHelperCalls extends RecursiveAstVisitor<void> {
  final List<MethodInvocation> calls = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.element != null && isContextSurfaceEvent(node)) {
      calls.add(node);
    }
    super.visitMethodInvocation(node);
  }
}

// The event a `context.surfaceEvent(...)` call fires, or null.
String? _authoredEventCallName(MethodInvocation node) =>
    isContextSurfaceEvent(node) ? authoredEventName(node) : null;

// ---------------------------------------------------------------------------
// Helpers for string-interpolation decomposition.
// ---------------------------------------------------------------------------

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
/// shipping a value the slot's decoder would silently null). The `brightness`
/// kind is accepted by no slot: it is branched on, never assigned.
bool propertyTypeAcceptsThemeKind(
  PropertyType type,
  ThemeContractValueKind kind, {
  PropertyEntry? property,
}) => switch (type) {
  PropertyType.color => kind == ThemeContractValueKind.color,
  PropertyType.length ||
  PropertyType.real => kind == ThemeContractValueKind.size,
  PropertyType.fontWeight => kind == ThemeContractValueKind.fontWeight,
  PropertyType.string => kind == ThemeContractValueKind.text,
  PropertyType.stringList => kind == ThemeContractValueKind.textList,
  PropertyType.textDecoration => kind == ThemeContractValueKind.textDecoration,
  // `enumValue` spans every catalog enum, so an enum-valued token binds
  // only where the slot's shape names that token's own enum.
  PropertyType.enumValue =>
    _kThemeKindEnumSymbols[kind] != null &&
        _slotEnumSymbol(property) == _kThemeKindEnumSymbols[kind],
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
  PropertyType.booleanList ||
  PropertyType.integerList ||
  PropertyType.realList ||
  PropertyType.scalarCallback ||
  PropertyType.widgetBuilder ||
  PropertyType.event ||
  PropertyType.dataReference ||
  PropertyType.gradient ||
  PropertyType.border ||
  PropertyType.boxShadowList ||
  PropertyType.locale ||
  PropertyType.paint ||
  PropertyType.shadowList ||
  PropertyType.fontFeatureList ||
  PropertyType.fontVariationList ||
  PropertyType.shapeBorder ||
  PropertyType.structured ||
  PropertyType.inlineSpan ||
  PropertyType.decorationImage ||
  PropertyType.selectionOptionList ||
  PropertyType.unknown => false,
};

/// The enum each enum-valued theme kind names, so its token binds only where
/// the slot's shape declares that same enum. A kind absent here is not an
/// enum token and binds to no `enumValue` slot.
const Map<ThemeContractValueKind, String> _kThemeKindEnumSymbols = {
  ThemeContractValueKind.fontStyle: 'FontStyle',
  ThemeContractValueKind.textDecorationStyle: 'TextDecorationStyle',
  ThemeContractValueKind.leadingDistribution: 'TextLeadingDistribution',
  ThemeContractValueKind.textBaseline: 'TextBaseline',
  ThemeContractValueKind.textOverflow: 'TextOverflow',
};

/// The enum a slot's declared shape names, or `null` when it has no enum
/// shape, so an enum-keyed kind fails closed.
String? _slotEnumSymbol(PropertyEntry? property) {
  final shape = property?.valueShape;
  return shape is EnumShape ? shape.enumRef.symbolName : null;
}

/// Whether a slot of catalog property [type] accepts a device-contract value
/// of [kind]. Exhaustive over [PropertyType]; a new slot type answers `false`.
bool propertyTypeAcceptsDeviceKind(
  PropertyType type,
  DeviceContractValueKind kind,
) => switch (type) {
  PropertyType.length ||
  PropertyType.real => kind == DeviceContractValueKind.size,
  PropertyType.string ||
  PropertyType.enumValue => kind == DeviceContractValueKind.token,
  PropertyType.boolean => kind == DeviceContractValueKind.boolean,
  PropertyType.color ||
  PropertyType.fontWeight ||
  PropertyType.widget ||
  PropertyType.widgetList ||
  PropertyType.edgeInsets ||
  PropertyType.alignment ||
  PropertyType.alignmentXY ||
  PropertyType.offset ||
  PropertyType.duration ||
  PropertyType.curve ||
  PropertyType.integer ||
  PropertyType.stringList ||
  PropertyType.booleanList ||
  PropertyType.integerList ||
  PropertyType.realList ||
  PropertyType.scalarCallback ||
  PropertyType.widgetBuilder ||
  PropertyType.event ||
  PropertyType.dataReference ||
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
  PropertyType.unknown => false,
};

/// Whether [dartType] exactly matches [type]'s runtime decoder.
bool _propertyTypeAcceptsHostDataType(PropertyType type, DartType dartType) {
  final shape = deriveHostDataShape(dartType, root: 'value').shape;
  return shape != null && _propertyTypeAcceptsHostDataShape(type, shape);
}

bool _propertyTypeAcceptsHostDataShape(
  PropertyType type,
  HostDataShape shape,
) {
  final scalar = shape is HostDataScalarShape ? shape.kind : null;
  final listElementScalar = switch (shape) {
    HostDataListShape(
      elementShape: HostDataScalarShape(:final kind),
    ) =>
      kind,
    _ => null,
  };
  return switch (type) {
    PropertyType.length ||
    PropertyType.real => scalar == HostDataScalarKind.doubleValue,
    PropertyType.color ||
    PropertyType.duration ||
    PropertyType.integer => scalar == HostDataScalarKind.integer,
    PropertyType.string => scalar == HostDataScalarKind.string,
    PropertyType.boolean => scalar == HostDataScalarKind.boolean,
    PropertyType.stringList => listElementScalar == HostDataScalarKind.string,
    PropertyType.booleanList => listElementScalar == HostDataScalarKind.boolean,
    PropertyType.integerList => listElementScalar == HostDataScalarKind.integer,
    PropertyType.realList =>
      listElementScalar == HostDataScalarKind.doubleValue ||
          listElementScalar == HostDataScalarKind.number,
    _ => false,
  };
}

PropertyType? _inspectedListItemPropertyType(PropertyType type) =>
    switch (type) {
      PropertyType.stringList => PropertyType.string,
      PropertyType.booleanList => PropertyType.boolean,
      PropertyType.integerList => PropertyType.integer,
      PropertyType.realList => PropertyType.real,
      PropertyType.boxShadowList ||
      PropertyType.shadowList ||
      PropertyType.fontFeatureList ||
      PropertyType.fontVariationList ||
      PropertyType.selectionOptionList => PropertyType.unknown,
      _ => null,
    };

PropertyType? _traversedListItemPropertyType(PropertyType type) =>
    switch (type) {
      PropertyType.widgetList => PropertyType.widget,
      _ => null,
    };

PropertyType? _listItemPropertyTypeForDartType(DartType? type) {
  final elementType = type == null ? null : _dartCoreListElementType(type);
  if (elementType == null) return null;
  if (elementType.isDartCoreString) return PropertyType.string;
  if (elementType.isDartCoreBool) return PropertyType.boolean;
  if (elementType.isDartCoreInt) return PropertyType.integer;
  if (elementType.isDartCoreDouble || elementType.isDartCoreNum) {
    return PropertyType.real;
  }
  return PropertyType.unknown;
}

/// Returns the exact element type of a core List.
DartType? _dartCoreListElementType(DartType type) {
  if (type is! InterfaceType ||
      !type.isDartCoreList ||
      type.typeArguments.length != 1) {
    return null;
  }
  final elementType = type.typeArguments.single;
  return elementType.nullabilitySuffix == NullabilitySuffix.none
      ? elementType
      : null;
}

PropertyType? _propertyTypeForParameter(DartType? type) {
  if (type == null) return null;
  if (isEventCallbackType(type)) return PropertyType.event;
  final shape = deriveHostDataShape(type, root: 'value').shape;
  return switch (shape) {
    HostDataScalarShape(kind: HostDataScalarKind.string) => PropertyType.string,
    HostDataScalarShape(kind: HostDataScalarKind.boolean) =>
      PropertyType.boolean,
    HostDataScalarShape(kind: HostDataScalarKind.integer) =>
      PropertyType.integer,
    HostDataScalarShape(
      kind: HostDataScalarKind.doubleValue || HostDataScalarKind.number,
    ) =>
      PropertyType.real,
    HostDataListShape(
      elementShape: HostDataScalarShape(kind: HostDataScalarKind.string),
    ) =>
      PropertyType.stringList,
    HostDataListShape(
      elementShape: HostDataScalarShape(kind: HostDataScalarKind.boolean),
    ) =>
      PropertyType.booleanList,
    HostDataListShape(
      elementShape: HostDataScalarShape(kind: HostDataScalarKind.integer),
    ) =>
      PropertyType.integerList,
    HostDataListShape(
      elementShape: HostDataScalarShape(
        kind: HostDataScalarKind.doubleValue || HostDataScalarKind.number,
      ),
    ) =>
      PropertyType.realList,
    _ => PropertyType.unknown,
  };
}

final class _RootParamAccess {
  const _RootParamAccess._({
    required this.param,
    required this.stateful,
    required this.shape,
    required this.parts,
    required this.isRefused,
  });

  factory _RootParamAccess.root({
    required RootContextParam param,
    required bool stateful,
  }) => _RootParamAccess._(
    param: param,
    stateful: stateful,
    shape: param.hostDataShape,
    parts: const [],
    isRefused: false,
  );

  final RootContextParam param;
  final bool stateful;
  final HostDataShape? shape;
  final List<String> parts;
  final bool isRefused;

  bool get isMember => parts.isNotEmpty || isRefused;

  _RootParamAccess append(Element? element) {
    final current = shape;
    final field = current is HostDataObjectShape
        ? current.fieldFor(element)
        : null;
    if (field == null) return refuse();
    return _RootParamAccess._(
      param: param,
      stateful: stateful,
      shape: field.shape,
      parts: [...parts, field.wireKey],
      isRefused: false,
    );
  }

  _RootParamAccess refuse() => _RootParamAccess._(
    param: param,
    stateful: stateful,
    shape: null,
    parts: parts,
    isRefused: true,
  );

  String dsl(String Function(String) pathPart) =>
      'data.context${pathPart(param.name)}${parts.map(pathPart).join()}';
}

/// Sentinel for [_WalkContext.copyWith] that distinguishes "argument omitted"
/// (keep the current value) from "argument explicitly null" (set to null) for
/// the nullable walk-scoped fields.
const Object _kWalkUnset = _WalkUnset();

class _WalkUnset {
  const _WalkUnset();
}

/// Immutable translation state saved and restored around nested walks.
final class _WalkContext {
  const _WalkContext({
    required this.argNames,
    required this.stateFields,
    required this.eventHandlers,
    required this.rootStateContext,
    required this.inlined,
    required this.params,
    required this.rootParams,
    required this.classKey,
    required this.paramBindings,
    required this.runtimeLoops,
    required this.modalSheet,
    required this.modalSheetCloseFlag,
    required this.validatedCoalesceParams,
    required this.measurementScope,
    required this.measurementWidget,
    required this.measurementWidgetList,
    required this.islandScope,
    this.stateShift,
    this.armSites = const [],
    this.stateGuard,
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
      rootParams = const {},
      classKey = null,
      paramBindings = const {},
      runtimeLoops = const [],
      modalSheet = null,
      modalSheetCloseFlag = null,
      validatedCoalesceParams = {},
      measurementScope = null,
      measurementWidget = null,
      measurementWidgetList = null,
      islandScope = const [],
      stateShift = null,
      armSites = const [],
      stateGuard = null;

  /// Constructor parameters keyed by fields read in a custom-widget body.
  /// Empty for root paywalls. Bare names lower to `args`; `widget.X` also lowers
  /// when X is present and [stateFields] marks a stateful definition.
  final Map<String, String> argNames;

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

  /// Root constructor parameters by name; empty in custom-widget definitions.
  /// Bare root reads lower through the matching `data.context` key.
  final Map<String, RootContextParam> rootParams;

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

  /// Active run-time loop values in lexical order.
  final List<_RuntimeLoopBinding> runtimeLoops;

  /// Active root-level modal-sheet lowering, when the root paywall contains
  /// exactly one supported show*Sheet trigger. The context lets the event-slot
  /// translator rewrite that source closure to a set-state handler, and lets
  /// sheet content rewrite the exact Navigator.pop(context) close form.
  final _ModalSheetEmitContext? modalSheet;

  /// Set only while translating the modal sheet builder subtree. This prevents
  /// an unrelated Navigator.pop(context) in the underlay from being treated as
  /// a sheet-close control.
  final String? modalSheetCloseFlag;

  /// Coalesced parameters whose fallbacks match their target slots.
  final Set<String> validatedCoalesceParams;

  /// Structural scope awaiting the next widget construction.
  final MeasurementOccurrenceScope? measurementScope;

  /// Exact widget occurrence whose arguments are being translated.
  final MeasurementWidgetOccurrence? measurementWidget;

  /// Exact widget-list slot whose elements are being translated.
  final MeasurementWidgetListOccurrence? measurementWidgetList;

  /// Helper calls and unrolled iterations from the surface's build.
  final List<String> islandScope;

  /// The earlier element of an enclosing emitted list whose number of
  /// widgets can change, moving everything after it.
  final _StateShift? stateShift;

  /// The branches of emitted switches being translated, outermost first.
  final List<_ArmSite> armSites;

  /// The `&&` or `||` condition guarding this element, whose emitted guard
  /// rebinds the element when its first part changes.
  final Expression? stateGuard;

  /// Returns a copy with the named fields replaced. Omitted fields keep their
  /// current value (shared by reference). The four nullable fields use the
  /// [_kWalkUnset] sentinel so a caller can set them to null.
  _WalkContext copyWith({
    Map<String, String>? argNames,
    Object? stateFields = _kWalkUnset,
    Map<String, RecognisedSetState>? eventHandlers,
    bool? rootStateContext,
    InlinedDefinitions? inlined,
    Map<String, CustomWidgetParam>? params,
    Map<String, RootContextParam>? rootParams,
    Object? classKey = _kWalkUnset,
    Map<Element, Expression>? paramBindings,
    List<_RuntimeLoopBinding>? runtimeLoops,
    Object? modalSheet = _kWalkUnset,
    Object? modalSheetCloseFlag = _kWalkUnset,
    Set<String>? validatedCoalesceParams,
    Object? measurementScope = _kWalkUnset,
    Object? measurementWidget = _kWalkUnset,
    Object? measurementWidgetList = _kWalkUnset,
    List<String>? islandScope,
    Object? stateShift = _kWalkUnset,
    List<_ArmSite>? armSites,
    Object? stateGuard = _kWalkUnset,
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
      rootParams: rootParams ?? this.rootParams,
      classKey: identical(classKey, _kWalkUnset)
          ? this.classKey
          : classKey as String?,
      paramBindings: paramBindings ?? this.paramBindings,
      runtimeLoops: runtimeLoops ?? this.runtimeLoops,
      modalSheet: identical(modalSheet, _kWalkUnset)
          ? this.modalSheet
          : modalSheet as _ModalSheetEmitContext?,
      modalSheetCloseFlag: identical(modalSheetCloseFlag, _kWalkUnset)
          ? this.modalSheetCloseFlag
          : modalSheetCloseFlag as String?,
      validatedCoalesceParams:
          validatedCoalesceParams ?? this.validatedCoalesceParams,
      measurementScope: identical(measurementScope, _kWalkUnset)
          ? this.measurementScope
          : measurementScope as MeasurementOccurrenceScope?,
      measurementWidget: identical(measurementWidget, _kWalkUnset)
          ? this.measurementWidget
          : measurementWidget as MeasurementWidgetOccurrence?,
      measurementWidgetList: identical(measurementWidgetList, _kWalkUnset)
          ? this.measurementWidgetList
          : measurementWidgetList as MeasurementWidgetListOccurrence?,
      islandScope: islandScope ?? this.islandScope,
      stateShift: identical(stateShift, _kWalkUnset)
          ? this.stateShift
          : stateShift as _StateShift?,
      armSites: armSites ?? this.armSites,
      stateGuard: identical(stateGuard, _kWalkUnset)
          ? this.stateGuard
          : stateGuard as Expression?,
    );
  }

  /// This walk one step further into each enclosing branch.
  _WalkContext armStep(String step) => armSites.isEmpty
      ? this
      : copyWith(armSites: [for (final site in armSites) site.at(step)]);
}

/// A list element whose number of widgets changes at run time.
final class _StateShift {
  const _StateShift(this.node, this.kind);

  final AstNode node;

  /// 'loop', 'spread' or 'condition'.
  final String kind;
}

/// One branch of an emitted switch, and the slot reached inside it.
final class _ArmSite {
  const _ArmSite(this.id, this.arm, [this.slot = '', this.skip = 0]);

  final Object id;
  final int arm;
  final String slot;

  /// Steps still to pass before this slot path grows: the steps into an
  /// argument a declaration body places.
  final int skip;

  _ArmSite at(String step) => skip > 0
      ? _ArmSite(id, arm, slot, skip - 1)
      : _ArmSite(id, arm, '$slot/$step');
}

final class _RuntimeLoopBinding {
  const _RuntimeLoopBinding(
    this.element,
    this.identifier,
    this.shape, {
    this.root,
    this.items,
    this.elements = const [],
  });

  final Element element;
  final String identifier;
  final HostDataShape shape;

  /// The screen input this loop walks directly, if it walks one.
  final RootContextParam? root;

  /// The mount-computed item list this loop walks, if it walks one.
  final String? items;

  /// The variables a destructuring loop declares.
  final List<Element> elements;

  /// The context value whose items this loop walks.
  String? get item => items ?? root?.name;

  bool binds(Element? candidate) =>
      identical(element, candidate) || elements.contains(candidate);
}

final class _RuntimeLoopReference {
  const _RuntimeLoopReference(
    this.binding,
    this.parts, {
    required this.shape,
    required this.indexed,
  });

  final _RuntimeLoopBinding binding;
  final List<String> parts;
  final HostDataShape? shape;
  final bool indexed;

  bool get isRefused => shape == null;

  _RuntimeLoopReference append(Element? element) {
    final current = shape;
    final field = current is HostDataObjectShape
        ? current.fieldFor(element)
        : null;
    return _RuntimeLoopReference(
      binding,
      field == null ? parts : [...parts, field.wireKey],
      shape: field?.shape,
      indexed: indexed,
    );
  }

  _RuntimeLoopReference withIndex() => _RuntimeLoopReference(
    binding,
    parts,
    shape: null,
    indexed: true,
  );

  String dsl(String Function(String) pathPart) =>
      '${binding.identifier}${parts.map(pathPart).join()}';
}

/// RFW's spelling of an absent value where an argument or map value is read.
const String _kNoValue = 'null';

/// A switch that matches nothing, which resolves to no value inside a switch.
const String _kNoValueSwitch = 'switch false {}';

/// A conditional element loops over one entry when its condition holds and
/// none when it does not.
const String _kPresentSelector = '[0]';
const String _kAbsentSelector = '[]';

/// The loop name for a conditional element. The template never reads it.
const String _kAbsentLoopIdentifier = 'presence';

String _unguarded(String whenPresent, String whenAbsent) => whenPresent;

/// Builds the RFW switch that selects between two already-rendered arms.
final class _ConditionLowering {
  const _ConditionLowering(this._build);

  final String Function(String whenTrue, String whenFalse) _build;

  String call(String whenTrue, String whenFalse) => _build(whenTrue, whenFalse);
}

/// The public analyzer interface name of [node], for diagnostics.
String _nodeKind(AstNode node) =>
    '${node.runtimeType}'.replaceFirst(RegExp(r'Impl$'), '');

/// Finds a non-constant installed native construction, through locals; those
/// need the surface's ordered evaluation frame, so the mount cannot compute them.
final class _InstalledNativeConstruction extends RecursiveAstVisitor<void> {
  _InstalledNativeConstruction(this._resolve);
  final Expression Function(Expression) _resolve;
  final _seen = <AstNode>{};
  var found = false;

  void visit(Expression expression) => expression.accept(this);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!node.isConst && installedNativeConstructorType(node) != null) {
      found = true;
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final resolved = _resolve(node);
    if (!identical(resolved, node) && _seen.add(resolved))
      resolved.accept(this);
  }
}

/// Calls [onFound] for each reference to [element], or to any element
/// [matches] accepts.
typedef _AheadDeclarations = ({
  List<(VariableDeclarationStatement, bool)> locals,
  List<(Statement, DeclaredVariablePattern)> patterns,
  List<(PatternVariableDeclarationStatement, DeclaredVariablePattern)>
  destructured,
  List<(ForStatement, Element)> loopVariables,
  List<(CatchClause, Element)> caught,
});

final class _ElementReferenceVisitor extends RecursiveAstVisitor<void> {
  _ElementReferenceVisitor(Element element, void Function() onFound)
    : this.at((candidate) => candidate == element, (_) => onFound());
  _ElementReferenceVisitor.at(this.matches, this.onFound);

  final bool Function(Element? element) matches;
  final void Function(SimpleIdentifier node) onFound;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (matches(node.element)) onFound(node);
  }
}

/// The nodes down a surface's root shell, their steps, and the index of the
/// last one that does not lower.
typedef _RootChain = ({
  List<InstanceCreationExpression> nodes,
  List<_ShellStep> steps,
  List<bool> lowers,
  int end,
});

/// One step down a root shell: the next node, and for a builder its
/// closure, prelude locals and parameters.
typedef _ShellStep = ({
  Expression next,
  FunctionExpression? builder,
  Map<Element, Expression> bindings,
  Set<Element> scope,
});

// Whether [type] is the type of a parameter that is covariant, written so or
// inherited, as `didUpdateWidget`'s is.
bool _isCovariantParameterType(NamedType type) {
  final parameter = type.parent;
  return parameter is FormalParameter &&
      (parameter.declaredFragment?.element.isCovariant ?? false);
}

/// Collects the type names that refer to [element].
final class _TypeReferences extends RecursiveAstVisitor<void> {
  _TypeReferences(this.element, this.edits, {required this.header});

  final Element element;
  final List<(int, int, String)> edits;

  /// Whether every reference counts; in members only `covariant` parameter
  /// types do.
  final bool header;

  @override
  void visitNamedType(NamedType node) {
    if (node.element == element &&
        (header || _isCovariantParameterType(node))) {
      edits.add((
        node.importPrefix?.offset ?? node.name.offset,
        node.name.end,
        kMountNameMarker,
      ));
    }
    super.visitNamedType(node);
  }
}

// Every `super.didUpdateWidget(...)` call: its argument becomes the mount's
// old widget.
final class _SuperUpdates extends RecursiveAstVisitor<void> {
  _SuperUpdates(this.edits);

  final List<(int, int, String)> edits;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target is SuperExpression &&
        node.methodName.name == 'didUpdateWidget') {
      final arguments = node.argumentList;
      edits.add((
        arguments.leftParenthesis.end,
        arguments.rightParenthesis.offset,
        '_restageOldWidget',
      ));
      return;
    }
    super.visitMethodInvocation(node);
  }
}

// The declaration of one local variable.
final class _DeclarationOf extends RecursiveAstVisitor<void> {
  _DeclarationOf(this.element, this.found);

  final Element element;
  final void Function(VariableDeclaration declaration) found;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (identical(node.declaredFragment?.element, element)) found(node);
    super.visitVariableDeclaration(node);
  }
}

// Whether a node calls code: an invocation or a non-constant construction.
final class _Invocations extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitMethodInvocation(MethodInvocation node) => found = true;

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) =>
      found = true;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!node.isConst) found = true;
    super.visitInstanceCreationExpression(node);
  }
}

final class _EvaluatesCode extends RecursiveAstVisitor<void> {
  _EvaluatesCode(this.helperFor, {this.appCode = false});

  final HelperDef? Function(Element? element) helperFor;

  /// Whether a framework constructor counts only by what its arguments run.
  final bool appCode;
  final Set<HelperDef> _entered = {};
  bool found = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final helper = helperFor(node.methodName.element);
    if (helper == null || !_entered.add(helper)) {
      found = true;
      return;
    }
    node.argumentList.accept(this);
    for (final root in helper.roots) {
      root.accept(this);
    }
    _entered.remove(helper);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) =>
      found = true;

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  // A getter, operator or index the app declares is code too.
  static bool _appDeclared(Element? element) {
    final uri = element?.library?.uri;
    return uri != null &&
        !uri.isScheme('dart') &&
        !uri.toString().startsWith('package:flutter/');
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element case final PropertyAccessorElement getter
        when !getter.isOriginVariable && _appDeclared(getter)) {
      found = true;
    }
  }

  // Types whose members the app can't override: String, int, double, num,
  // bool and Null.
  static bool _closedType(DartType? type) =>
      type is InterfaceType &&
          type.element.library.isDartCore &&
          const {
            'String',
            'int',
            'double',
            'num',
            'bool',
            'Null',
          }.contains(type.element.name) ||
      type != null && type.isDartCoreNull;

  // Anything iterated but a literal may run the app's iterator.
  static bool _literal(Expression expression) =>
      expression.unParenthesized is TypedLiteral;

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final operator = node.operator.type;
    final logical =
        operator == TokenType.AMPERSAND_AMPERSAND ||
        operator == TokenType.BAR_BAR ||
        operator == TokenType.QUESTION_QUESTION;
    if (!logical &&
        (node.element == null && !_closedType(node.leftOperand.staticType) ||
            _appDeclared(node.element) ||
            !_closedType(node.leftOperand.staticType) &&
                // An enum's == is its identity.
                node.leftOperand.staticType?.element is! EnumElement &&
                (operator == TokenType.EQ_EQ ||
                    operator == TokenType.BANG_EQ))) {
      found = true;
    }
    super.visitBinaryExpression(node);
  }

  // Interpolating anything but a closed type calls its `toString`.
  @override
  void visitInterpolationExpression(InterpolationExpression node) {
    if (!_closedType(node.expression.staticType)) found = true;
    super.visitInterpolationExpression(node);
  }

  @override
  void visitSpreadElement(SpreadElement node) {
    if (!_literal(node.expression)) found = true;
    super.visitSpreadElement(node);
  }

  @override
  void visitForEachPartsWithDeclaration(ForEachPartsWithDeclaration node) {
    if (!_literal(node.iterable)) found = true;
    super.visitForEachPartsWithDeclaration(node);
  }

  @override
  void visitForEachPartsWithIdentifier(ForEachPartsWithIdentifier node) {
    if (!_literal(node.iterable)) found = true;
    super.visitForEachPartsWithIdentifier(node);
  }

  @override
  void visitForEachPartsWithPattern(ForEachPartsWithPattern node) {
    if (!_literal(node.iterable)) found = true;
    super.visitForEachPartsWithPattern(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    if (_appDeclared(node.element) || node.operator.type.isIncrementOperator) {
      found = true;
    }
    super.visitPrefixExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    if (_appDeclared(node.element) || node.operator.type.isIncrementOperator) {
      found = true;
    }
    super.visitPostfixExpression(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) => found = true;

  @override
  void visitIndexExpression(IndexExpression node) {
    if (_appDeclared(node.element)) found = true;
    super.visitIndexExpression(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final library = node.constructorName.element?.library.uri;
    if (!node.isConst &&
        node.constructorName.element?.isConst != true &&
        !(appCode &&
            library != null &&
            (library.isScheme('dart') ||
                library.toString().startsWith('package:flutter/')))) {
      found = true;
    }
    super.visitInstanceCreationExpression(node);
  }
}

// Each name [onName] meets, declared or read, with where it is written.
final class _Names extends RecursiveAstVisitor<void> {
  _Names(this.onName);

  final void Function(String name, AstNode node) onName;

  // A member after a target, a label or a constructor's name is not one
  // the scope resolves.
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final member = switch (node.parent) {
      PropertyAccess(:final propertyName) => identical(propertyName, node),
      PrefixedIdentifier(:final identifier) => identical(identifier, node),
      MethodInvocation(:final methodName, :final target) =>
        identical(methodName, node) && target != null,
      Label() || ConstructorName() => true,
      _ => false,
    };
    if (!member) onName(node.name, node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    onName(node.name.lexeme, node);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    onName(node.name.lexeme, node);
    super.visitDeclaredVariablePattern(node);
  }

  @override
  void visitDeclaredIdentifier(DeclaredIdentifier node) {
    onName(node.name.lexeme, node);
    super.visitDeclaredIdentifier(node);
  }

  @override
  void visitRegularFormalParameter(RegularFormalParameter node) {
    if (node.name case final name?) onName(name.lexeme, node);
    super.visitRegularFormalParameter(node);
  }

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {
    onName(node.functionDeclaration.name.lexeme, node);
    super.visitFunctionDeclarationStatement(node);
  }
}

final class _Writes extends RecursiveAstVisitor<void> {
  _Writes(this.onWrite);

  final void Function(Element? element) onWrite;

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    onWrite(node.writeElement);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    onWrite(node.writeElement);
    super.visitPostfixExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    onWrite(node.writeElement);
    super.visitPrefixExpression(node);
  }
}

final class _PatternVariables extends RecursiveAstVisitor<void> {
  _PatternVariables(this.onPattern);

  final void Function(DeclaredVariablePattern pattern) onPattern;

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    onPattern(node);
    super.visitDeclaredVariablePattern(node);
  }
}

// The identifier reads and `this` in a node, outside [skipped] nodes.
final class _MountReads extends GeneralizingAstVisitor<void> {
  _MountReads(this.skipped, this.onRead, {required this.onThis});

  final Set<AstNode> skipped;
  final void Function(SimpleIdentifier identifier) onRead;
  final void Function() onThis;

  @override
  void visitNode(AstNode node) {
    if (!skipped.contains(node)) super.visitNode(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!skipped.contains(node) &&
        !node.inDeclarationContext() &&
        node.parent is! Label) {
      onRead(node);
    }
  }

  @override
  void visitThisExpression(ThisExpression node) => onThis();
}

/// One translation's islands.
final class _IslandSession {
  _IslandSession(
    this.namespace,
    this.library,
    this.liftedState,
    this.surface, {
    required this.contentFree,
    this.stateless,
    this.designOwnsState = false,
  });

  /// Whether the design keeps the State, so only the recorded copy reads it.
  final bool designOwnsState;

  /// Whether the recorded copy is being written.
  bool recording = false;

  /// Whether an analysis asks what the mount can compute without the State
  /// the design owns.
  bool probing = false;

  /// Why the mount would depend on design state, which keeps State in the app.
  Issue? designMiss;

  /// Whether [element] is a member of the lifted State that the app declares,
  /// which the design owns while it keeps the State.
  bool isDesignStateMember(Element element) =>
      liftedState != null && isDesignStateMemberOf(liftedState!, element);

  /// Which root builders run once per build, so the mount can keep them.
  final ContentFreeBuilders contentFree;

  /// Warnings and refusals the recorded build raises.
  final List<Issue> recordIssues = [];

  /// The `SurfaceEvent` constants the recorded build fires.
  final Set<PropertyInducingElement> firedEvents = {};

  final String namespace;

  /// The library the mount's part belongs to.
  final LibraryElement library;

  /// The surface every island name starts with, and its root method.
  final ({String name, String method, String screen}) surface;

  /// The surface's `State`, when the mount takes it over.
  final ClassElement? liftedState;

  /// The surface's class when it has no `State`.
  final ClassElement? stateless;

  /// Builder parameters and locals the mount declares.
  final Set<Element> scope = {};

  /// Child arguments a shell probe stands in for.
  final Set<Expression> stubs = HashSet.identity();

  MountSplit? split;

  /// The build's locals the mount declares once, for values it computes.
  final Set<Element> preludeLocals = {};

  /// The names the mount declares locals under, by element, where a name
  /// differs from its source name or the local is declared ahead of its block.
  final Map<Element, String> mountNames = {};

  /// The locals among [mountNames] a block, pattern or loop declares.
  final Set<Element> innerLocals = {};

  /// The slot of the local [element] the mount declares ahead.
  String heldSlot(Element element) =>
      heldLocalSlot(mountNames[element]!, inner: innerLocals.contains(element));

  /// The widget [preludeLocals] each placement reads as an island.
  final Set<Element> sharedLocals = {};

  /// The build's returns, when it has several.
  List<ReturnStatement> returns = const [];

  /// The arms of the switch a build returns, when the mount takes its case.
  List<SwitchExpressionCase> arms = const [];

  /// The body of the build the surface renders.
  FunctionBody? buildBody;

  /// Why the build can't be recorded, when it can't.
  Issue? recordProblem;

  /// The root builders the mount keeps, outermost first.
  final List<FunctionExpression> keptBuilders = [];

  /// What the recorded build writes, once it is written.
  RecordedBuild? recordedFacts;

  /// Each island as the recorded build writes it.
  final List<
    ({
      String name,
      AstNode node,
      bool shared,
      ({AstNode at, List<SimpleIdentifier> spots}) placement,
      Map<AstNode, ({String marker, bool property})> holes,
      List<AstNode> calls,
      String? items,
    })
  >
  recordIslands = [];

  /// Each app widget the design builds that the build places, by the name
  /// its placement is keyed under, and the function that places it: a split
  /// widget's wrapper, null where the mount's imports don't show it (the
  /// mount install refuses then).
  final List<
    ({
      String name,
      AstNode node,
      List<AstNode> calls,
      String? items,
      String widget,
      bool split,
      String? place,
    })
  >
  recordPlacements = [];

  /// The walk the build's root is translated in.
  _WalkContext? rootWalk;

  /// Why the mount cannot take over the surface's `State`.
  Issue? problem;

  // A lifted State's members, inherited ones too.
  bool inMountScope(Element element) =>
      scope.contains(element.baseElement) ||
      isStateMember(element) && !(probing && isDesignStateMember(element));

  /// Whether [element] is an instance member of the lifted State or of one
  /// of its supertypes.
  bool isStateMember(Element element) =>
      liftedState != null && isInstanceMemberOf(liftedState!, element);

  /// The mount's spelling of `this` of [type]: the mount State itself, or the
  /// stateless surface's instance.
  String? thisFor(DartType? type) {
    final element = type?.element;
    if (element == null) return null;
    if (element == liftedState) return 'this';
    if (element == stateless) return '\u0000$kSurfaceInstance\u0000';
    return null;
  }

  bool isSurfaceMember(Element element) =>
      stateless != null &&
      element.enclosingElement == stateless &&
      isInstanceMember(element);

  /// Islands by structural ID.
  final Map<String, Island> islands = {};

  /// Surface declarations islands needed but the mount could not see.
  final Set<Element> blocked = {};

  /// Why the mount could not write an island, by its node.
  final Map<Expression, HoistNeedsSurfaceValue> blockedBy = HashMap.identity();

  /// Island candidates by scope and widget type, in the order reached.
  final List<({String key, Expression node})> order = [];

  /// Candidates under translation, so a nested call does not re-enter.
  final Set<Expression> attempting = HashSet.identity();
}

// The returns of [body] itself, not of a function nested in it.
const _routeTypes = {
  'MaterialPageRoute',
  'CupertinoPageRoute',
  'PageRouteBuilder',
  'DialogRoute',
  'RawDialogRoute',
  'CupertinoDialogRoute',
  'CupertinoModalPopupRoute',
  'ModalBottomSheetRoute',
};

const _routeFunctions = {
  'showDialog',
  'showAdaptiveDialog',
  'showGeneralDialog',
  'showModalBottomSheet',
  'showCupertinoDialog',
  'showCupertinoModalPopup',
};

/// The expressions each route or dialog builder in [node] returns: the
/// content a pushed route shows. With [pushesOnly], page routes only: a
/// dialog or sheet carries the scopes of the context that opens it.
List<Expression> routeContents(AstNode node, {bool pushesOnly = false}) {
  final found = <Expression>[];
  void contentOf(NodeList<Argument> arguments) {
    for (final argument in arguments.whereType<NamedArgument>()) {
      if (!const {'builder', 'pageBuilder'}.contains(argument.name.lexeme)) {
        continue;
      }
      final value = argument.argumentExpression;
      if (value is! FunctionExpression) continue;
      switch (value.body) {
        case ExpressionFunctionBody(:final expression):
          found.add(expression);
        case final BlockFunctionBody body:
          final returns = <ReturnStatement>[];
          body.accept(_OwnReturns(body, returns));
          found.addAll([for (final r in returns) ?r.expression]);
        default:
      }
    }
  }

  bool fromFlutter(Element? element) =>
      element?.library?.identifier.startsWith('package:flutter/') ?? false;
  node.accept(
    _RouteRoots(
      onRoute: (creation) {
        final type = creation.constructorName.type.element;
        if (_routeTypes.contains(type?.name) && fromFlutter(type)) {
          contentOf(creation.argumentList.arguments);
        }
      },
      onCall: (call) {
        if (!pushesOnly &&
            _routeFunctions.contains(call.methodName.name) &&
            fromFlutter(call.methodName.element)) {
          contentOf(call.argumentList.arguments);
        }
      },
    ),
  );
  return found;
}

final class _RouteRoots extends RecursiveAstVisitor<void> {
  _RouteRoots({required this.onRoute, required this.onCall});

  final void Function(InstanceCreationExpression creation) onRoute;
  final void Function(MethodInvocation call) onCall;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    onRoute(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    onCall(node);
    super.visitMethodInvocation(node);
  }
}

final class _OwnReturns extends RecursiveAstVisitor<void> {
  _OwnReturns(this.body, this.found);

  final FunctionBody body;
  final List<ReturnStatement> found;

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (identical(node.body, body)) super.visitFunctionExpression(node);
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    found.add(node);
    super.visitReturnStatement(node);
  }
}

// Every expression in a node, outermost first.
final class _Expressions extends GeneralizingAstVisitor<void> {
  _Expressions(this.found);

  final List<Expression> found;

  @override
  void visitExpression(Expression node) {
    found.add(node);
    super.visitExpression(node);
  }
}

/// One translation's mount-computed values.
final class _HoistSession {
  _HoistSession(this.analyzer);

  final HoistAnalyzer analyzer;
  final Map<String, HoistedValue> values = {};

  /// Set while a candidate is translated to see whether it lowers.
  bool speculating = false;

  /// Set while a kept builder's parameters are published.
  bool exposing = false;

  /// Strings whose parts are being translated before the whole is hoisted.
  final Set<Expression> inParts = HashSet.identity();

  /// Each node a value is computed at, with the helper calls around it.
  final List<
    ({
      String key,
      AstNode site,
      List<AstNode> calls,
      List<({ForElement loop, int ordinal})> unrolled,
      bool slot,
    })
  >
  records = [];

  /// Values computed in a widget closure the design path doesn't run.
  final List<AstNode> closureMisses = [];

  /// Each builder parameter value a kept builder publishes when it runs.
  final List<({String key, String source, FunctionExpression builder})>
  exposes = [];

  /// The body each inlined helper call runs.
  final Map<AstNode, Expression> helperBodies = Map.identity();

  /// Records where each added value is read.
  void Function(HoistedValue value)? onAdd;

  HoistedValue add(HoistedValue value) {
    final keyed = occurrence?.call(value) ?? value;
    final added = values.putIfAbsent(keyed.key, () => keyed);
    onAdd?.call(keyed);
    return added;
  }

  /// The key each occurrence of a value's text is recorded under.
  HoistedValue Function(HoistedValue value)? occurrence;

  /// Each occurrence's key, by base key and [occurrenceOf] identity.
  final Map<String, String> occurrenceKeys = {};

  /// How many occurrences of each base key have a key.
  final Map<String, int> occurrenceCounts = {};
}

/// The identity of one occurrence in a build: the node, and the helper calls
/// it is reached through.
String occurrenceOf(AstNode node, Iterable<AstNode> calls) =>
    [node, ...calls].map(identityHashCode).join(',');

// Whether a statement calls code the app declares, which the mount must run
// as the app does even when nothing reads its result.
// Each `super` in a node.
final class _Supers extends RecursiveAstVisitor<void> {
  _Supers(this.found);

  final List<SuperExpression> found;

  @override
  void visitSuperExpression(SuperExpression node) => found.add(node);
}

final class _RunsAppCode extends RecursiveAstVisitor<void> {
  bool found = false;

  static bool inside(AstNode node) {
    final visitor = _RunsAppCode();
    node.accept(visitor);
    return visitor.found;
  }

  static bool _app(Element? element) {
    final uri = element?.library?.uri;
    return uri == null ||
        !uri.isScheme('dart') && !uri.toString().startsWith('package:flutter/');
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_app(node.methodName.element)) found = true;
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (_app(node.element)) found = true;
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!node.isConst && _app(node.constructorName.element)) found = true;
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) => found = true;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element case final PropertyAccessorElement getter
        when !getter.isOriginVariable && _app(getter)) {
      found = true;
    }
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {}
}

// Calls [onIdentifier] with each simple identifier it visits.
final class _IdentifierVisitor extends RecursiveAstVisitor<void> {
  _IdentifierVisitor(this.onIdentifier);

  final void Function(SimpleIdentifier identifier) onIdentifier;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) => onIdentifier(node);
}

/// What the mount records at a site: a value, an app widget, a wrapper, or
/// which widget a build returns.
enum _Recorded { value, widget, wrapper, branch }
