import 'dart:convert';

import 'package:meta/meta.dart';

/// Public GitHub repository URL used for one-click capability-gap issue links.
///
/// This intentionally ships empty until the extracted public repository exists.
/// Set it to the repository root URL, for example
/// `https://github.com/restage/restage`, during extraction/publication.
const String kRestageCodegenGapIssueRepositoryUrl = '';

const String _restageSdkVersion = '0.1.0';
const int _capabilityGapDetailLimit = 240;
const JsonEncoder _jsonEncoder = JsonEncoder.withIndent('  ');

/// Categorical codes for codegen diagnostics.
enum IssueCode {
  // Annotation handling
  /// `@PaywallSource` could not be const-evaluated by analyzer.
  annotationEvaluationFailed,

  /// Two `@PaywallSource` classes share the same `id`.
  duplicateId,

  // Class shape
  /// Class doesn't extend `StatelessWidget`.
  unsupportedBaseClass,

  /// Class has no `build()` method.
  buildMethodMissing,

  /// `build()` body has multiple statements / locals / control flow.
  buildMethodTooComplex,

  /// The analyzer couldn't return a resolved library for the input.
  /// Typical causes: missing/unresolved imports, package config gaps,
  /// session disposal mid-build. Distinct from [buildMethodTooComplex]
  /// because the author's code may be well-formed — the failure is in
  /// the analyzer's view of the workspace.
  analyzerResolutionFailed,

  /// Source filename stem doesn't match the `@PaywallSource(id:)` value.
  /// Codegen output paths derive from filename; runtime loads by id; the
  /// two must agree.
  filenameMismatch,

  // Expression-level
  /// Reference to an unknown class, value, or identifier.
  unresolvedIdentifier,

  /// Method call not in the recognized helper / constructor support set.
  unrecognizedMethodCall,

  /// A reference to an instance field of a `const` object — `const _skin =
  /// Skin(...); _skin.headline` — was recognised but could not be folded to its
  /// value: the field is bound cross-file (its declaration is not reachable for
  /// AST substitution) and its value is not a scalar, or it relies on a default
  /// the fold cannot follow. Emitting the bare field NAME here would be a
  /// silent wrong-render in a string slot (and a type mismatch in a structured
  /// one), so the reference is deferred LOUD instead. The remediation is to
  /// inline the value at the use site, or move the const object into the same
  /// file so its initializer can be substituted.
  constObjectFieldUnresolved,

  /// A conditional's condition compares an integer state field but is not the
  /// one shape this transpiler increment lowers to a native `switch` —
  /// `<intStateField> == <intLiteral>`. Equality only this increment: `!=`,
  /// `<`, `>`, a non-literal right-hand side, and the literal-on-the-left form
  /// defer here (a recorded follow-on, not a silently half-built lowering)
  /// rather than emit a degraded blob.
  intStateConditionUnsupported,

  /// Integer literal exceeds int64 range and cannot be represented in
  /// the RFW binary format.
  integerLiteralOverflow,

  /// A numeric value evaluates to a non-finite double — `double.infinity`,
  /// `double.negativeInfinity`, `double.nan`, or an overflowing literal such
  /// as `1e400`. A non-finite double has no representable RFW (or JSON) value,
  /// so emitting it would silently drop to the slot's decode default. The
  /// translator refuses it at the emit layer for every slot — a top-level
  /// scalar or a field inside a structured value (e.g. `BoxShadow.blurRadius`,
  /// `Border.all(width:)`) — so the silent loss becomes a build-time error.
  nonFiniteNumericValue,

  /// `for` / spread / collection-`if` inside a list literal.
  unsupportedCollectionFlow,

  /// Bad expression inside string interpolation.
  unsupportedInterpolation,

  /// Helper used in a position its return type doesn't fit.
  unsupportedHelperPosition,

  // Idiom auto-substitution
  /// Codegen recognised a customer's imperative formatting idiom — e.g.
  /// `Text(NumberFormat.currency(...).format(...))` — and rewrote it to a
  /// semantically-equivalent catalog widget the customer did not name (e.g.
  /// `RestagePrice`). The substitute's rendered output is identical (it runs
  /// the same statically-extracted formatting), so this is **not** an error:
  /// it is the announced-rewrite build notice, surfaced so the customer is
  /// told at build time exactly what was rewritten and why (the source→blob
  /// mapping is no longer 1:1 for the recognised idiom). Informational.
  idiomAutoSubstituted,

  // Catalog validation
  /// Widget name not in merged catalog.
  unknownWidget,

  /// A catalog widget was constructed with a named constructor that this
  /// transpiler increment does not lower to a dedicated catalog entry or a
  /// known implied-default form. Emitting the base widget would silently drop
  /// the named constructor's semantics (e.g. `Positioned.fill`'s implied
  /// zero edges), so the construct defers loud instead. `Positioned.fill` is
  /// the one named constructor lowered faithfully; every other unmatched
  /// named constructor surfaces this diagnostic.
  namedConstructorUnsupported,

  /// A `PageView(...)` construction could not be lowered to the declarative
  /// paged surface. The children-list form maps to it, with an inline
  /// `PageController(initialPage:, viewportFraction:)` flattened onto the
  /// direct properties; any other form — a named constructor (`.builder` /
  /// `.custom`), a positional argument, an argument with no declarative
  /// equivalent, a controller that is not a literal
  /// `PageController(initialPage:, viewportFraction:)`, or an absent / empty
  /// children list — defers the whole widget rather than emit a paged surface
  /// that silently drops the unexpressed behaviour.
  pageViewFormUnsupported,

  /// A modal sheet trigger could not be lowered without dropping observable
  /// behavior, such as the sheet's returned result value. The author must
  /// express that behavior through declarative state instead.
  modalSheetFormUnsupported,

  /// A screen-navigation trigger could not be lowered without dropping
  /// observable behavior, such as a pushed route's returned result value, a
  /// customized route argument, or a pushed screen that is not a
  /// `@PaywallSource`.
  navigationFormUnsupported,

  /// A standalone paywall artifact was intentionally not emitted because the
  /// source uses in-flow back navigation. The flow-screen adapter still emits.
  navigationStandaloneArtifactSkipped,

  /// A `DraggableScrollableSheet(...)` construction could not be lowered to the
  /// declarative draggable surface without changing what it renders. Only the
  /// canonical builder form — `(context, scrollController) =>
  /// SingleChildScrollView(controller: scrollController, child: content)`
  /// with the scroll view carrying nothing beyond `key` / `controller` /
  /// `child` — lowers byte-faithfully (the wrapper reconstitutes exactly that).
  /// A scrollable/flex builder body, a builder that ignores the controller, a
  /// scroll view carrying any other argument, a non-empty `snapSizes`, an
  /// author-supplied `controller`, a `shouldCloseOnMinExtent: true`, a named
  /// constructor, a positional argument, or any argument with no declarative
  /// equivalent defers the whole widget rather than emit a surface that
  /// silently drops or changes the unexpressed behaviour.
  draggableSheetFormUnsupported,

  /// A single-select construction (`RadioGroup` / `DropdownButton`) could not
  /// be lowered to the declarative compiled single-select widget without
  /// dropping or guessing at an option. Only the carrier forms lower — a
  /// `RadioGroup` whose child is a static list of `RadioListTile`s with a
  /// literal `Text` title and a `value`, or a `DropdownButton` whose `items`
  /// is a static list of `DropdownMenuItem`s with a literal `Text` child and a
  /// `value`. Any other shape — a non-list / dynamic / builder child, a leaf
  /// that is not the expected carrier, a non-literal-`Text` label, a missing
  /// `value`, a duplicate value, or a positional / unrecognized argument —
  /// defers the WHOLE widget loud rather than emit a partial or wrong group.
  singleSelectFormUnsupported,

  /// A vanilla-Flutter `ToggleButtons(...)` could not be lowered to the
  /// declarative compiled `RestageToggleButtons` widget without dropping or
  /// misaligning a toggle. Only the carrier form lowers — a `ToggleButtons`
  /// whose `children` is a static list of label widgets and whose `isSelected`
  /// is a static list of `bool` literals of the SAME length. Any other shape —
  /// a non-list / dynamic / builder `children` or `isSelected`, a spread /
  /// `if` / `for` element, a non-`bool`-literal flag, an empty set, a length
  /// mismatch between the two, or a positional / unrecognized argument —
  /// defers the WHOLE widget loud rather than emit a partial or misaligned set.
  toggleButtonsFormUnsupported,

  /// A vanilla-Flutter `SegmentedButton(...)` could not be lowered to the
  /// declarative compiled `RestageSegmentedButton` widget without dropping or
  /// mis-ordering a segment. Only the carrier form lowers — a
  /// `SegmentedButton<String>` whose `segments` is a static list of
  /// `ButtonSegment`s each with a literal `Text` label and a `value`, with a
  /// `selected` set literal and an `onSelectionChanged: ValueChanged<Set>`.
  /// Any other shape — a non-`String` (or inferred non-`String`) generic, a
  /// non-list / dynamic / builder `segments` or `selected`, a spread / `if` /
  /// `for` element, an icon-only / non-literal-`Text` label, a missing
  /// `value`, a behavioral carrier arg (`enabled` / `tooltip`), a duplicate
  /// value, or a positional / unrecognized argument — defers the WHOLE widget
  /// loud rather than emit a partial, reordered, or wrong set.
  segmentedButtonFormUnsupported,

  /// A referenced custom widget is pure composition (transpilable), but
  /// inlining a custom widget into a paywall is not built yet.
  customWidgetInliningDeferred,

  /// A referenced custom widget is imperative — its `build()` or `State`
  /// uses a construct the declarative paywall format **cannot express** (a
  /// genuine RFW capability boundary: a custom painter, runtime-computed value,
  /// async/lifecycle, non-primitive state, or a composition of such). No future
  /// transpiler increment will bring it in; the author must redesign.
  customWidgetImperative,

  /// A referenced custom widget is not transpilable by **this transpiler
  /// increment yet**, but is reducible in principle — its `build()` uses a
  /// construct (an unrecognised Dart call, or a composition of a widget not yet
  /// in the catalog) that a future catalog / recipe / state-authoring increment
  /// could express. Distinct from [customWidgetImperative] (a genuine dead end)
  /// so consumers and telemetry can tell a backlog candidate from a capability
  /// boundary without parsing the message; same deferred blob behaviour.
  customWidgetUnsupportedReducible,

  /// A referenced custom widget was recognised but could not be classified
  /// (its `build()` body shape, or its source, was not analysable).
  customWidgetUnclassified,

  /// Two custom widgets would emit under the same RFW widget name, or a
  /// custom widget's name shadows a catalog widget — either makes a
  /// reference in the emitted blob ambiguous.
  customWidgetNameCollision,

  /// A `Theme.of(context).<x>(.<y>)` read in a transpiled widget resolves
  /// to a path the SDK's `data.theme.*` channel does not publish — e.g. a
  /// `textTheme.*` read, a customer `ThemeExtension`, or a deprecated
  /// `ColorScheme` role. Emitting the reference would silently resolve to
  /// null at render time, so the build surfaces it as an authoring error.
  themeReadOutOfContract,

  /// A transpiled widget binds `Theme.of(context)` (or a sub-tree of it)
  /// to an intermediate variable, then reads through that variable — the
  /// transpiler does not follow intermediate variables, so the read cannot
  /// be emitted directly. The remediation is to inline the read at the use
  /// site: `Theme.of(context).colorScheme.primary`, not
  /// `final cs = …; cs.primary`.
  themeReadIntermediateVariable,

  /// Root-source state or class-4a stateful custom-widget state passed an
  /// earlier coarse shape check, but analysis or emit-time validation found a
  /// State construct it cannot lower to RFW — lifecycle, non-primitive fields,
  /// a non-foldable field initialiser, a setState body outside the recognised
  /// single-assignment shapes, root `widget.<field>` reads, or a ternary whose
  /// condition is not a bool state / args reference. Emit is aborted; no blob
  /// ships with placeholder state.
  stateShapeUnsupported,

  /// A surface references a widget from a custom library whose catalog
  /// metadata declares no capability version, so the delivery-time capability
  /// floor for that library cannot be derived. The author must declare an
  /// explicit monotonic capability version on the library's `@RestageLibrary`
  /// (`capabilityVersion:`) — fail-when-referenced: an unreferenced custom
  /// library that merely omits the version does not fail the build.
  customLibraryMissingCapabilityVersion,

  /// A widget name a surface references resolves to widget entries in more than
  /// one library (a custom library shadowing a built-in name, or two custom
  /// libraries colliding). The delivery-time capability floor cannot be derived
  /// unambiguously — the runtime resolves by import order, but the derivation
  /// resolves by catalog priority, so a wrong-library stamp could fail open
  /// (under-stamp). Fail closed: the author must rename the shadowing widget so
  /// the name resolves to exactly one library.
  ambiguousWidgetName,

  /// Property name not declared on catalog widget.
  unknownProperty,

  /// A value bound to a property has a runtime type the property's declared
  /// catalog type cannot accept — e.g. a string bound to a numeric
  /// (length / real / integer) slot, or a colour-kind theme read bound to a
  /// length slot. The runtime typed decode would silently null such a value
  /// and fall back to the slot's decoder default, dropping the authored
  /// intent, so the build surfaces it as an actionable error rather than
  /// shipping a degraded blob. Checked for literal scalars and for contract
  /// theme reads supplied as slot values (including through the branches of
  /// a conditional); other runtime-resolved values (event handlers, nested
  /// widgets, values routed through a custom widget's parameters) are not.
  propertyValueTypeMismatch,

  /// A property declared `required` in the catalog — a `widget` or
  /// `widgetList` slot — is omitted from a widget instance. A required widget
  /// slot left out decodes to a runtime cast error; a required widgetList slot
  /// silently decodes to an empty list (no error at all), dropping the
  /// authored intent. Surfaced at build time so the author supplies the slot
  /// rather than shipping a degraded blob. (Required scalars are already
  /// enforced by the typed decode; required events are an authoring choice,
  /// by design, and are not checked here.)
  missingRequiredSlot,

  // @RestageWidget / @RestageProperty extraction
  /// A required annotation field (e.g. name, library, description) is
  /// missing or could not be const-evaluated.
  missingAnnotationField,

  /// An annotation enum field carries a name not known to this analyzer's
  /// `restage_shared`. Typical cause: the SDK is older than the analyzer.
  unknownEnumValue,

  /// A `@RestageProperty.defaultValue` literal can't be encoded.
  invalidDefault,

  /// A curation synthetic property is malformed: its name is not a valid Dart
  /// identifier (which would produce uncompilable generated code), or its emit
  /// strategy is not one the factory emitter supports (which silently drops the
  /// whole widget from emission with no other record). Surfaced at curation
  /// time so the curator fixes the synthetic rather than hitting a confusing
  /// downstream failure or a silently-missing widget.
  invalidSynthetic,

  /// A `@RestageProperty` supplies more than one of `defaultValue` /
  /// `defaultBrandToken` / `defaultSource` — they are mutually exclusive
  /// defaulting strategies. Enforced here as a hard build error because the
  /// annotation's const constructor can only `assert` the rule, which is
  /// stripped in release builds.
  conflictingDefaultStrategy,

  /// A constructor parameter's default could not be mechanically resolved
  /// into a catalog default — the catalog records no claim about it.
  /// Informational, not fatal: this is a catalog-completeness gap (a
  /// curation to-do, where surfacing the default in the inspector may be
  /// worthwhile), not a curator error. Contrast [invalidDefault], which
  /// flags a genuinely invalid curator-supplied value and stays fatal.
  unrepresentableCtorDefault,

  /// @StableProperty recognized but property-level stability is deferred
  /// (no schema field).
  ///
  /// Informational, not fatal: the annotation is acknowledged and recorded
  /// in the decision trail, but the catalog schema does not yet carry a
  /// stability field for individual properties. The build succeeds; the
  /// issue surfaces so tooling can audit which properties carry the
  /// annotation ahead of the schema addition.
  stablePropertyDeferred,

  /// A `@RestageProperty` field has a static type the catalog can't represent.
  unsupportedPropertyType,

  /// A parameter's type is on the policy denylist and was excluded from
  /// the catalog entry.
  denylistedPropertyType,

  /// A widget's fully-qualified type name is on the policy denylist.
  /// The entire widget entry is excluded from the catalog.
  denylistedWidget,

  /// A specific widget+property pair is on the per-widget policy denylist.
  denylistedProperty,

  /// A class or field is opted out via @RfwIncompatible.
  rfwIncompatibleAnnotated,

  /// A structured type was encountered again while walking nested fields.
  structuredCycle,

  /// A structured-type walk exceeded its configured recursion depth.
  structuredDepthExceeded,

  /// An abstract structured base type awaits union resolution.
  abstractTypeAwaitingUnion,

  /// A referenced discriminated union resolved with no concrete members.
  /// A union entry with an empty member set — or a structured-field
  /// reference pointing at a union that does not exist — would produce
  /// an incoherent catalog, so this fails the build.
  incoherentUnion,

  /// A registered abstract-union base referenced by the catalog could not
  /// be resolved from the curation library's import closure.
  /// An unresolvable base means the union cannot be emitted at all, which
  /// would produce an incoherent catalog, so this fails the build.
  unresolvedUnionBase,

  /// A structured factory variant has an unsupported parameter type.
  structuredFactoryUnsupportedParam,

  /// A theme-binding policy seed targets a widget curated in this library
  /// but materializes no `ThemeBindingDefault` and is not suppressed by a
  /// competing `defaultBrandToken` — a silently-inert seed. This also
  /// covers a seed that names a property the curated widget does not
  /// surface at all. Either case is an incoherent policy table that would
  /// ship a catalog out of sync with its seeds, so this fails the build.
  inertThemeBindingSeed,

  /// Two `@RestageWidget` classes in the same library declare the same name.
  duplicateWidgetName,

  /// `@RestageWidget` declared on a class shape that codegen can't reach
  /// (e.g. abstract or private — generated factories can't construct them).
  invalidWidgetClass,

  // Internal
  /// Translator emitted DSL that didn't round-trip via parseLibraryFile.
  malformedTranslatorOutput,

  // Raw DSL authoring
  /// Hand-authored `.rfwtxt` file could not be parsed by parseLibraryFile.
  malformedRawDsl,

  /// A Dart paywall / widget source carries a genuine syntactic error (a
  /// scanner or parser error — e.g. an incomplete numeric literal, an
  /// unterminated string). The builder resolves sources tolerantly so a
  /// malformed input does not crash the build with an opaque exception, but
  /// the parser's error recovery can yield a structurally-valid widget tree
  /// that ships a clean blob with the malformed token silently dropped. This
  /// surfaces the syntactic error so the author fixes the source rather than
  /// shipping a degraded blob. Resolution / compile-time errors (an
  /// unresolved import, a not-yet-generated part) are NOT flagged — only
  /// genuine input-syntax errors.
  malformedSourceInput,

  // Onboarding codegen
  /// A source file that requires generated Dart output is missing the
  /// matching `part` directive.
  missingPartDirective,

  /// A user-authored declaration collides with a generated descriptor symbol.
  generatedSymbolCollision,

  /// A flow graph references a generated screen descriptor that codegen cannot
  /// read from the screen builder output.
  missingScreenDescriptor,

  /// The author used a flow DSL feature unsupported by the current runtime.
  unsupportedFlowRuntimeFeature;

  /// Whether this code is a **build notice** — an annotation emitted *alongside
  /// a complete, correct translation*, never a signal that something failed to
  /// translate. The paywall builder partitions on this: a notice is logged but
  /// does not block the emit or fail the build (the blob it annotates is
  /// whole), whereas every other code means an expression could not be lowered
  /// and the paywall must not ship.
  ///
  /// This is deliberately **distinct from [isInformational]** (the
  /// catalog-build disposition): several informational catalog codes — e.g.
  /// [customWidgetInliningDeferred] — mean a widget *did not emit*, which is
  /// fatal in a paywall (a silent drop). Only a true emitted-alongside-success
  /// annotation belongs here.
  bool get isBuildNotice => switch (this) {
        IssueCode.idiomAutoSubstituted ||
        IssueCode.navigationStandaloneArtifactSkipped =>
          true,
        _ => false,
      };

  /// Whether this code records a recognised-but-deferred design decision that
  /// belongs on the build's audit trail rather than failing it.
  ///
  /// Catalog-build consumers split their issue lists on this: an informational
  /// code (a policy exclusion / opt-out, a recognised-but-unbuilt deferral, a
  /// catalog-completeness to-do) stays visible in the decision trail without
  /// blocking the build or strict-mode CI; everything else is a real codegen
  /// error the author must resolve.
  ///
  /// This getter is the single classification point. The switch is exhaustive
  /// with no default arm on purpose: adding a new [IssueCode] is a compile
  /// error here until the author classifies it, so a new code can never
  /// silently default to one disposition and latently break a downstream
  /// consumer's own exhaustive switch.
  bool get isInformational => switch (this) {
        // Policy exclusions / opt-outs — the curation deliberately omitted
        // these; recorded for the audit trail, not a regression.
        IssueCode.denylistedPropertyType ||
        IssueCode.denylistedWidget ||
        IssueCode.denylistedProperty ||
        IssueCode.rfwIncompatibleAnnotated ||
        // A structured-type walk boundary (a cycle or a depth cap) — the walker
        // stops and records, it does not fail.
        IssueCode.structuredCycle ||
        IssueCode.structuredDepthExceeded ||
        // An abstract base awaiting union resolution — a normal mid-walk state.
        IssueCode.abstractTypeAwaitingUnion ||
        // A ctor default the mechanical pass cannot bake, or a per-property
        // stability annotation with no schema field yet — catalog-completeness
        // to-dos (a curation gap), not curator errors.
        IssueCode.unrepresentableCtorDefault ||
        IssueCode.stablePropertyDeferred ||
        // Custom-widget inlining is recognised but the inlining path / this
        // transpiler increment cannot bring the widget in yet — a deferral with
        // a deferred-blob disposition, not a regression.
        IssueCode.customWidgetInliningDeferred ||
        IssueCode.customWidgetUnsupportedReducible ||
        // The announced-rewrite build notice for an auto-substituted idiom —
        // a disclosed, semantically-equivalent rewrite, recorded on the audit
        // trail, never a failure.
        IssueCode.idiomAutoSubstituted ||
        IssueCode.navigationStandaloneArtifactSkipped =>
          true,
        // Everything below is a real codegen error the author must resolve.
        IssueCode.annotationEvaluationFailed ||
        IssueCode.duplicateId ||
        IssueCode.unsupportedBaseClass ||
        IssueCode.buildMethodMissing ||
        IssueCode.buildMethodTooComplex ||
        IssueCode.analyzerResolutionFailed ||
        IssueCode.filenameMismatch ||
        IssueCode.unresolvedIdentifier ||
        IssueCode.unrecognizedMethodCall ||
        IssueCode.constObjectFieldUnresolved ||
        IssueCode.integerLiteralOverflow ||
        IssueCode.nonFiniteNumericValue ||
        IssueCode.unsupportedCollectionFlow ||
        IssueCode.unsupportedInterpolation ||
        IssueCode.unsupportedHelperPosition ||
        IssueCode.unknownWidget ||
        IssueCode.namedConstructorUnsupported ||
        IssueCode.pageViewFormUnsupported ||
        IssueCode.modalSheetFormUnsupported ||
        IssueCode.navigationFormUnsupported ||
        IssueCode.draggableSheetFormUnsupported ||
        IssueCode.singleSelectFormUnsupported ||
        IssueCode.toggleButtonsFormUnsupported ||
        IssueCode.segmentedButtonFormUnsupported ||
        IssueCode.intStateConditionUnsupported ||
        IssueCode.customLibraryMissingCapabilityVersion ||
        IssueCode.ambiguousWidgetName ||
        IssueCode.unknownProperty ||
        // A wrong-typed literal the runtime decode would silently null — a real
        // build error, never informational.
        IssueCode.propertyValueTypeMismatch ||
        IssueCode.missingRequiredSlot ||
        IssueCode.missingAnnotationField ||
        IssueCode.unknownEnumValue ||
        IssueCode.invalidDefault ||
        IssueCode.invalidSynthetic ||
        IssueCode.conflictingDefaultStrategy ||
        IssueCode.unsupportedPropertyType ||
        IssueCode.structuredFactoryUnsupportedParam ||
        IssueCode.duplicateWidgetName ||
        IssueCode.invalidWidgetClass ||
        IssueCode.incoherentUnion ||
        IssueCode.unresolvedUnionBase ||
        IssueCode.inertThemeBindingSeed ||
        IssueCode.malformedTranslatorOutput ||
        IssueCode.malformedRawDsl ||
        IssueCode.malformedSourceInput ||
        IssueCode.missingPartDirective ||
        IssueCode.generatedSymbolCollision ||
        IssueCode.missingScreenDescriptor ||
        IssueCode.unsupportedFlowRuntimeFeature ||
        // A custom widget that cannot be expressed, could not be classified,
        // would emit an ambiguous name, or fails translator-side reconciliation
        // — all real failures the author must resolve.
        IssueCode.customWidgetImperative ||
        IssueCode.customWidgetUnclassified ||
        IssueCode.customWidgetNameCollision ||
        IssueCode.themeReadOutOfContract ||
        IssueCode.themeReadIntermediateVariable ||
        IssueCode.stateShapeUnsupported =>
          false,
      };

  /// Whether this code means the author hit a Restage/codegen capability gap
  /// rather than an author-fixable source error.
  bool get isCapabilityGap => switch (this) {
        // Source shapes the transpiler may learn to lower in a later increment.
        IssueCode.unrecognizedMethodCall ||
        IssueCode.intStateConditionUnsupported ||
        IssueCode.unsupportedCollectionFlow ||
        IssueCode.unsupportedInterpolation ||
        IssueCode.unsupportedHelperPosition ||
        IssueCode.unknownWidget ||
        IssueCode.namedConstructorUnsupported ||
        IssueCode.pageViewFormUnsupported ||
        IssueCode.navigationFormUnsupported ||
        IssueCode.draggableSheetFormUnsupported ||
        IssueCode.unsupportedFlowRuntimeFeature ||
        // Custom-widget diagnostics that are backlog/indeterminate, not the
        // genuine RFW dead-end bucket.
        IssueCode.customWidgetInliningDeferred ||
        IssueCode.customWidgetUnsupportedReducible ||
        IssueCode.customWidgetUnclassified =>
          true,
        _ => false,
      };
}

/// Structured diagnostic emitted during a codegen build pass.
@immutable
final class Issue {
  /// Creates an issue with the given [code], [message], and source
  /// [location]. All three fields are required and must be non-empty.
  const Issue({
    required this.code,
    required this.message,
    required this.location,
    this.capabilityGapSubject,
  })  : assert(message.length > 0, 'Issue.message must not be empty'),
        assert(location.length > 0, 'Issue.location must not be empty'),
        assert(
          capabilityGapSubject != '',
          'Issue.capabilityGapSubject must not be empty',
        );

  /// Categorical code identifying the kind of issue.
  final IssueCode code;

  /// Human-readable message describing the issue and (where possible)
  /// suggesting a remediation.
  final String message;

  /// Source location, e.g. `"package/file.dart#ClassName.build@line:col"`.
  final String location;

  /// Stable, machine-readable subject for a capability gap, such as
  /// `widget:FancyChart` or `constructor:SizedBox.shrink`.
  ///
  /// This is deliberately separate from [message], which is written for humans
  /// and can change wording without breaking demand aggregation.
  final String? capabilityGapSubject;

  /// Formats this issue for build logs, optionally appending a pre-filled
  /// GitHub issue link for capability-gap diagnostics.
  String toLogString({
    String issueRepositoryUrl = kRestageCodegenGapIssueRepositoryUrl,
    String sdkVersion = _restageSdkVersion,
  }) {
    final base = toString();
    final link = _capabilityGapIssueUri(
      issueRepositoryUrl: issueRepositoryUrl,
      sdkVersion: sdkVersion,
    );
    if (link == null) return base;
    return '$base\nRequest support for this Restage gap: $link';
  }

  Uri? _capabilityGapIssueUri({
    required String issueRepositoryUrl,
    required String sdkVersion,
  }) {
    if (!code.isCapabilityGap) return null;

    final trimmed = issueRepositoryUrl.trim();
    if (trimmed.isEmpty) return null;

    final repository = Uri.tryParse(trimmed);
    if (repository == null ||
        !repository.hasScheme ||
        repository.host.isEmpty) {
      return null;
    }

    final path = repository.path.replaceFirst(RegExp(r'/+$'), '');
    final subjectLabel = _capabilityGapSubjectLabel(capabilityGapSubject);
    return repository.replace(
      path: '$path/issues/new',
      queryParameters: {
        'title': '[restage_codegen] Capability gap: ${code.name}',
        'body': _capabilityGapIssueBody(sdkVersion),
        'labels': [
          'codegen-gap',
          'codegen-gap-${code.name}',
          if (subjectLabel != null) subjectLabel,
        ].join(','),
      },
    );
  }

  String _capabilityGapIssueBody(String sdkVersion) {
    const reproductionPrompt = 'Add any minimal reproduction details you are '
        'comfortable sharing before submitting.';
    final detail = _trimCapabilityGapDetail(message);
    final payload = <String, String>{
      'schema': 'restage.codegen.capability_gap.v1',
      'code': code.name,
      if (capabilityGapSubject != null) 'subject': capabilityGapSubject!,
      'sdkVersion': sdkVersion,
    };
    return [
      'Issue code: `${code.name}`',
      if (capabilityGapSubject != null) 'Gap subject: `$capabilityGapSubject`',
      'SDK version: `$sdkVersion`',
      '',
      'Machine-readable:',
      '```json',
      _jsonEncoder.convert(payload),
      '```',
      '',
      'Diagnostic shape:',
      '```text',
      detail,
      '```',
      '',
      reproductionPrompt,
    ].join('\n');
  }

  @override
  String toString() => '[${code.name}] $location: $message';
}

String _trimCapabilityGapDetail(String detail) {
  final normalized =
      detail.replaceAll('```', '` ` `').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= _capabilityGapDetailLimit) return normalized;
  return '${normalized.substring(0, _capabilityGapDetailLimit).trimRight()}...';
}

String? _capabilityGapSubjectLabel(String? subject) {
  if (subject == null) return null;
  final slug = subject
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) return null;
  return 'codegen-gap-subject-$slug';
}
