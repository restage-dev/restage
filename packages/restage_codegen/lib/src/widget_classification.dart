import 'package:meta/meta.dart';
import 'package:restage_codegen/src/issue.dart';

/// An inlining mechanism a class-4a custom widget's `build()` / `State`
/// depends on, beyond plain catalog-widget composition.
///
/// A [ComposableWidget] is inlinable by a given codegen increment exactly
/// when its [ComposableWidget.requiredMechanisms] is a subset of the
/// mechanisms that increment implements. Plain composition is the
/// always-present baseline and is therefore not a member.
enum InliningMechanism {
  /// Build-time-constant compute folded to a literal — e.g.
  /// `EdgeInsets.all(_kGap)` where `_kGap` is a `const`.
  constantFolding,

  /// A `Theme.of(context).<role>` read, rewritten to a `data.theme.*`
  /// reference.
  themeAsData,

  /// A `StatefulWidget` with plain bool / int / enum state, emitted as an
  /// RFW `state` block.
  declarativeState,

  /// A catalog-widget callback that opens a modal sheet through a synthetic
  /// declarative state flag.
  modalSheet,
}

/// The kind of construct that makes a custom widget imperative (class 4b) —
/// not expressible in RFW's declarative blob format.
enum BlockerKind {
  /// `CustomPaint` / a `CustomPainter` subclass / canvas / shaders.
  customPainter,

  /// A value computed at runtime from constructor args or state —
  /// `width * 0.8`, `.withOpacity(...)`, string logic.
  runtimeComputedValue,

  /// A call into a Dart function or package (date formatting, helpers) —
  /// neither a catalog-widget construction, a recognised structured-value
  /// expression, nor a registered paywall helper.
  dartCall,

  /// `await`, `Future`, `Timer`, streams, `AnimationController`, or a
  /// lifecycle method (`initState` / `dispose` / `didChangeDependencies`).
  asyncOrLifecycle,

  /// `build()` composes a widget that is neither a catalog widget nor an
  /// `@RestageWidget`-annotated custom widget.
  unrecognisedComposedWidget,

  /// `build()` composes another custom widget that is itself class 4b.
  composesImperativeWidget,

  /// A `StatefulWidget` whose `State` holds non-primitive / computed /
  /// controller-driven state RFW's `state` block cannot express.
  nonSimpleState,
}

/// Maps a custom-widget diagnostic [code] to its disposition, so a consumer or
/// telemetry can group the four custom-widget codes into three dispositions
/// WITHOUT parsing message strings. Returns `null` for any code that is not a
/// custom-widget-classification diagnostic.
///
/// The grouping:
///   * **reducible / backlog** — [IssueCode.customWidgetInliningDeferred]
///     (recognised composition, mechanism not built yet) +
///     [IssueCode.customWidgetUnsupportedReducible] (an imperative-walk blocker
///     that is reducible in principle);
///   * **dead end** — [IssueCode.customWidgetImperative];
///   * **indeterminate** — [IssueCode.customWidgetUnclassified].
CustomWidgetDisposition? customWidgetDispositionFor(IssueCode code) =>
    switch (code) {
      IssueCode.customWidgetInliningDeferred ||
      IssueCode.customWidgetUnsupportedReducible =>
        CustomWidgetDisposition.reducible,
      IssueCode.customWidgetImperative => CustomWidgetDisposition.deadEnd,
      IssueCode.customWidgetUnclassified =>
        CustomWidgetDisposition.indeterminate,
      _ => null,
    };

/// The disposition of a non-transpilable custom widget — the triage label
/// that distinguishes a genuine capability boundary from a not-yet-built one.
/// It governs the diagnostic message + backlog narrative, never the blob
/// behaviour (every non-transpilable widget is deferred identically).
enum CustomWidgetDisposition {
  /// The construct is **not supported by this transpiler increment yet** but is
  /// reducible in principle — a future catalog / recipe / state-authoring
  /// increment could express it. A backlog candidate, not a dead end.
  reducible,

  /// The construct is **fundamentally outside RFW's declarative envelope**
  /// (rule 4 / primitive-only state) — no future increment will bring it in.
  /// A genuine dead end; the author must redesign.
  deadEnd,

  /// The classifier recognised the widget but could not reach a 4a/4b verdict
  /// — it may well be transpilable; the transpiler simply cannot tell.
  indeterminate,
}

/// The default disposition of each [BlockerKind]. `composesImperativeWidget`
/// is `deadEnd` by default but is overridden per-instance to the composed
/// child's disposition (a parent that composes a merely-reducible child is
/// itself reducible-not-yet, not a dead end) — see [Blocker.disposition].
extension BlockerKindDisposition on BlockerKind {
  /// Whether this kind is, on its own, a genuine RFW capability boundary
  /// (`deadEnd`) vs a not-yet-supported-but-reducible construct (`reducible`).
  CustomWidgetDisposition get disposition => switch (this) {
        // Genuine RFW boundaries — declarative-only (rule 4) + primitive-only
        // state. No future increment expresses these.
        BlockerKind.customPainter => CustomWidgetDisposition.deadEnd,
        BlockerKind.runtimeComputedValue => CustomWidgetDisposition.deadEnd,
        BlockerKind.asyncOrLifecycle => CustomWidgetDisposition.deadEnd,
        BlockerKind.nonSimpleState => CustomWidgetDisposition.deadEnd,
        // Default deadEnd, but per-instance overridden to the child's
        // disposition at construction (see `Blocker.disposition`).
        BlockerKind.composesImperativeWidget => CustomWidgetDisposition.deadEnd,
        // Not supported yet but reducible: a dart call could become a recipe /
        // registered helper / auto-substitution; an unrecognised composed
        // widget could be added to the catalog.
        BlockerKind.dartCall => CustomWidgetDisposition.reducible,
        BlockerKind.unrecognisedComposedWidget =>
          CustomWidgetDisposition.reducible,
      };
}

/// One construct that disqualifies a custom widget from transpilation,
/// with the source location the diagnostic points the author at.
@immutable
final class Blocker {
  /// Creates a blocker. [dispositionOverride] is set only for
  /// `composesImperativeWidget`, to the composed child's disposition; every
  /// other kind takes its `BlockerKind.disposition` default. [idiomSubject] is
  /// the structured aggregation subject (see [idiomSubject]).
  const Blocker({
    required this.kind,
    required this.location,
    required this.detail,
    this.idiomSubject,
    CustomWidgetDisposition? dispositionOverride,
  }) : _dispositionOverride = dispositionOverride;

  /// What kind of imperative construct this is.
  final BlockerKind kind;

  /// Source location inside the custom widget —
  /// `'<library URI>#<Class>@line:col'`.
  final String location;

  /// The offending construct, quoted into the diagnostic message.
  final String detail;

  /// The structured aggregation subject — the AST-resolved identifier the
  /// coverage idiom histogram keys on, so constructs of the same kind aggregate
  /// regardless of their arguments (a `CustomPaint(...)` blocker carries
  /// `CustomPaint`; a `ButtonStyle.styleFrom(...)` dart call carries
  /// `ButtonStyle.styleFrom`; a non-primitive state field carries its name).
  /// Threaded from the producer's AST node so the histogram needs no
  /// string-parse of [detail]. `null` only when a blocker is constructed
  /// without one (the histogram then falls back to [detail]).
  final String? idiomSubject;

  final CustomWidgetDisposition? _dispositionOverride;

  /// This blocker's disposition — its `BlockerKind.disposition` default, unless
  /// a per-instance override was supplied (the `composesImperativeWidget` case,
  /// which inherits the composed child's disposition: composing a merely
  /// reducible child is itself reducible-not-yet, not a dead end).
  CustomWidgetDisposition get disposition =>
      _dispositionOverride ?? kind.disposition;
}

/// The class-4a / class-4b classification of one custom (`@RestageWidget`)
/// widget, produced by the classifier and consumed by the translator.
///
/// The classification is *sound*: [ComposableWidget] and [ImperativeWidget]
/// are produced only when the classifier is certain; any construct it does
/// not recognise yields [UnclassifiableWidget] rather than a guessed verdict.
sealed class WidgetClassification {
  /// Base constructor — records the [classKey].
  const WidgetClassification(this.classKey);

  /// Canonical key of the classified widget class —
  /// `'<library URI>#<ClassName>'`, constructor suffix stripped.
  final String classKey;
}

/// Class 4a — pure composition: `build()` (and `State`) reduce to catalog
/// widgets, literals, references, branches, loops, and simple declarative
/// state. Transpilable to an RFW remote-widget definition.
final class ComposableWidget extends WidgetClassification {
  /// Creates a class-4a classification.
  ComposableWidget(
    super.classKey, {
    required Set<InliningMechanism> requiredMechanisms,
    required List<String> composedCustomWidgets,
  })  : requiredMechanisms = Set.unmodifiable(requiredMechanisms),
        composedCustomWidgets = List.unmodifiable(composedCustomWidgets);

  /// Inlining mechanisms this widget needs, **rolled up transitively** across
  /// its whole composition closure: if it composes another custom widget
  /// that needs [InliningMechanism.themeAsData], that mechanism appears here
  /// too. An increment can therefore inline this widget iff
  /// [requiredMechanisms] is a subset of the mechanisms it implements — with
  /// no traversal of [composedCustomWidgets].
  final Set<InliningMechanism> requiredMechanisms;

  /// [classKey]s of the custom widgets this widget composes **directly**.
  /// The transitive closure is reachable by walking the classifier's result
  /// map; emitters use this to output each composed widget's definition.
  final List<String> composedCustomWidgets;
}

/// Class 4b — imperative: `build()` or `State` contains a construct RFW's
/// declarative blob format cannot express. Not transpilable; referencing it
/// in a transpiled paywall is an error.
final class ImperativeWidget extends WidgetClassification {
  /// Creates a class-4b classification. [blockers] must be non-empty;
  /// `blockers.first` is the construct the diagnostic names.
  ImperativeWidget(super.classKey, {required List<Blocker> blockers})
      : assert(blockers.isNotEmpty, 'an ImperativeWidget needs a blocker'),
        blockers = List.unmodifiable(blockers);

  /// The disqualifying construct(s).
  final List<Blocker> blockers;

  /// The widget's disposition: `deadEnd` if ANY blocker is a genuine RFW
  /// boundary, else `reducible` (every blocker is a not-yet-supported but
  /// reducible construct). A single dead-end construct makes the whole widget
  /// a dead end; an all-reducible-blocker widget is a backlog candidate.
  CustomWidgetDisposition get disposition =>
      blockers.any((b) => b.disposition == CustomWidgetDisposition.deadEnd)
          ? CustomWidgetDisposition.deadEnd
          : CustomWidgetDisposition.reducible;
}

/// The widget is a recognised `@RestageWidget` but the classifier could not
/// give it a 4a / 4b verdict — its `build()` body is not a single returned
/// expression, it uses a construct the transpiler does not yet analyse, or
/// its source AST was unreachable. **Not** a class-4b verdict: the widget
/// may well be transpilable; the transpiler simply cannot tell.
final class UnclassifiableWidget extends WidgetClassification {
  /// Creates an unclassifiable result. [diagnosticCode] overrides the
  /// default [IssueCode.customWidgetUnclassified] when a specific failure
  /// shape is worth a dedicated code (e.g. an intermediate-variable theme
  /// read, surfaced as [IssueCode.themeReadIntermediateVariable]).
  const UnclassifiableWidget(
    super.classKey, {
    required this.reason,
    this.diagnosticCode = IssueCode.customWidgetUnclassified,
  });

  /// Why the classifier could not reach a verdict — surfaced to the author.
  final String reason;

  /// The [IssueCode] the translator surfaces when a paywall references this
  /// widget. Defaults to the generic [IssueCode.customWidgetUnclassified]; a
  /// classifier-side pattern match can override it to point the author at
  /// the specific failure mode.
  final IssueCode diagnosticCode;
}
