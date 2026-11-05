import 'dart:collection';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/const_folding.dart';
import 'package:restage_codegen/src/islands/islands.dart' show readableSource;
import 'package:restage_codegen/src/hoisting.dart'
    show HoistIsWidget, classifyHoistType;

/// The largest number of elements one list with collection flow may emit.
const int kCollectionUnrollCeiling = 1000;

/// The largest amount of static traversal one collection-flow list may use.
const int kCollectionUnrollWorkCeiling = kCollectionUnrollCeiling * 8;

/// Why a collection element could not be expanded into static elements.
enum CollectionUnrollRefusal {
  /// The iterable or condition is a value known only at run time.
  runtimeValue,

  /// The construct is not a supported static collection shape.
  unsupportedShape,

  /// The expansion exceeds [kCollectionUnrollCeiling].
  ceilingExceeded,

  /// Static expansion exceeds [kCollectionUnrollWorkCeiling].
  workLimitExceeded,

  /// A callback-bearing semantic source reached two structural occurrences.
  callbackSourceReused,

  /// The element renders from the app's own code, so it is not expanded.
  appRendered,
}

/// The result of searching a semantically reachable expression graph.
enum CollectionCallbackProbeResult {
  /// No callback was reachable.
  absent,

  /// A callback was reachable.
  present,

  /// The bounded search could not finish.
  workLimitExceeded,
}

/// One helper body and the parameter bindings active while visiting it.
final class CollectionResolvedHelper {
  /// Creates a resolved helper invocation.
  const CollectionResolvedHelper({
    required this.body,
    required this.parameterBindings,
  });

  /// The helper expression translation can inline.
  final Expression body;

  /// The call arguments keyed by their resolved parameter elements.
  final Map<Element, Expression> parameterBindings;
}

/// Resolves a named intermediate visible to collection-flow translation.
typedef CollectionBindingResolver =
    Expression? Function(
      SimpleIdentifier identifier,
    );

/// Resolves a transparent authored source for typed-list inspection.
typedef CollectionSourceResolver = Expression? Function(Expression expression);

/// Resolves an inlinable helper invocation visible to translation.
typedef CollectionHelperResolver =
    CollectionResolvedHelper? Function(
      MethodInvocation invocation,
    );

/// A bounded semantic view of every transparent expression translation can
/// reach.
final class CollectionSemanticProbe {
  /// Creates a probe over injected binding and helper resolvers.
  CollectionSemanticProbe({
    CollectionBindingResolver? bindingFor,
    CollectionHelperResolver? helperFor,
    CollectionSourceResolver? sourceFor,
  }) : _bindingFor = bindingFor ?? _noBinding,
       _helperFor = helperFor ?? _noHelper,
       _sourceFor = sourceFor ?? _noSource;

  final CollectionBindingResolver _bindingFor;
  final CollectionHelperResolver _helperFor;
  final CollectionSourceResolver _sourceFor;

  /// Resolves one unambiguous path through the transparent semantic graph.
  /// [stopAtConditionals] retains runtime branches for their caller to lower.
  /// [preserveHelpers] retains calls so the caller can stage eager arguments.
  CollectionExpressionResolution resolve(
    Expression expression,
    Map<Element, Expression> bindings,
    CollectionUnrollBudget budget, {
    bool stopAtConditionals = false,
    bool preserveHelpers = false,
  }) {
    final walk = _walk(
      expression,
      bindings,
      budget,
      stopAtConditionals: stopAtConditionals,
      preserveHelpers: preserveHelpers,
    );
    if (walk.workLimitExceeded) {
      return CollectionExpressionResolution(
        expression: expression,
        bindings: bindings,
        sourceProvenance: const [],
        workLimitExceeded: true,
      );
    }
    if (walk.terminals.length != 1) {
      return CollectionExpressionResolution(
        expression: expression,
        bindings: bindings,
        sourceProvenance: const [],
        cycleDetected: walk.cycleDetected,
      );
    }
    final terminal = walk.terminals.single;
    return CollectionExpressionResolution(
      expression: terminal.expression,
      bindings: terminal.bindings,
      sourceProvenance: terminal.sourceProvenance,
      cycleDetected: walk.cycleDetected,
    );
  }

  /// Finds callbacks through the same transparent graph used by controls.
  CollectionCallbackProbeResult callbacksIn(
    AstNode node, {
    required CollectionUnrollBudget budget,
    Map<Element, Expression> bindings = const {},
  }) => _callbackSourcesIn(
    node,
    budget: budget,
    bindings: bindings,
  ).result;

  /// Finds every exact callback expression reached through transparent edges.
  _CollectionCallbackSources _callbackSourcesIn(
    AstNode node, {
    required CollectionUnrollBudget budget,
    Map<Element, Expression> bindings = const {},
    bool rootWorkAlreadyCharged = false,
    bool stopAtNestedLists = false,
  }) {
    final state = _SemanticCallbackState(
      this,
      budget,
      root: node,
      unchargedRoot: rootWorkAlreadyCharged ? node : null,
      stopAtNestedLists: stopAtNestedLists,
    )..inspect(node, bindings);
    if (state.occurrences.isNotEmpty) {
      return _CollectionCallbackSources(
        result: CollectionCallbackProbeResult.present,
        occurrences: List.unmodifiable(state.occurrences),
      );
    }
    return _CollectionCallbackSources(
      result: state.exhausted
          ? CollectionCallbackProbeResult.workLimitExceeded
          : CollectionCallbackProbeResult.absent,
    );
  }

  /// Inspects a typed-list boundary through the shared semantic graph.
  CollectionTypedListProbeResult typedListCollectionElement(
    Expression expression, {
    required CollectionUnrollBudget budget,
    Map<Element, Expression> bindings = const {},
  }) {
    final walk = _walk(expression, bindings, budget);
    if (walk.workLimitExceeded) {
      return const CollectionTypedListWorkLimitExceeded();
    }
    for (final terminal in walk.terminals) {
      final resolved = terminal.expression;
      if (resolved is! ListLiteral) continue;
      for (final element in resolved.elements) {
        if (element is! Expression) {
          if (!budget.tryChargeWork()) {
            return const CollectionTypedListWorkLimitExceeded();
          }
          return CollectionTypedListElement(
            element,
            resolution: !walk.cycleDetected && walk.terminals.length == 1
                ? CollectionExpressionResolution(
                    expression: resolved,
                    bindings: terminal.bindings,
                    sourceProvenance: terminal.sourceProvenance,
                  )
                : null,
          );
        }
      }
    }
    if (!walk.cycleDetected && walk.terminals.length == 1) {
      final terminal = walk.terminals.single;
      final resolved = terminal.expression;
      if (resolved is ListLiteral) {
        return CollectionTypedListPlain(
          source: expression,
          list: resolved,
          bindings: terminal.bindings,
          sourceProvenance: terminal.sourceProvenance,
        );
      }
    }
    return CollectionTypedListTerminal(
      expression,
      cycleDetected: walk.cycleDetected,
    );
  }

  _CollectionSemanticWalk _walk(
    Expression expression,
    Map<Element, Expression> bindings,
    CollectionUnrollBudget budget, {
    bool stopAtConditionals = false,
    bool preserveHelpers = false,
  }) {
    final active = HashSet<Expression>.identity();
    var cycleDetected = false;
    var workLimitExceeded = false;

    bool chargeEdge() {
      if (budget.tryChargeWork()) return true;
      workLimitExceeded = true;
      return false;
    }

    List<_CollectionSemanticTerminal> inspect(
      Expression current,
      Map<Element, Expression> activeBindings,
      List<CollectionSemanticSourceStep> sourceProvenance,
    ) {
      if (workLimitExceeded) return const [];
      if (!active.add(current)) {
        cycleDetected = true;
        return [
          _CollectionSemanticTerminal(
            current,
            activeBindings,
            sourceProvenance,
          ),
        ];
      }
      try {
        if (current is ParenthesizedExpression) {
          if (chargeEdge()) {
            return inspect(
              current.expression,
              activeBindings,
              [
                ...sourceProvenance,
                CollectionSemanticSourceStep(
                  kind: CollectionSemanticSourceKind.parentheses,
                  source: current,
                  target: current.expression,
                ),
              ],
            );
          }
          return const [];
        }
        if (current is SimpleIdentifier) {
          final element = current.element;
          final bound =
              (element == null ? null : activeBindings[element]) ??
              _bindingFor(current);
          if (bound != null) {
            if (chargeEdge()) {
              return inspect(
                bound,
                {
                  ...activeBindings,
                  if (element != null) element: bound,
                },
                [
                  ...sourceProvenance,
                  CollectionSemanticSourceStep(
                    kind: CollectionSemanticSourceKind.binding,
                    source: current,
                    target: bound,
                    element: element,
                  ),
                ],
              );
            }
            return const [];
          }
        }
        final receiver = _fieldAccessReceiver(current);
        if (receiver != null &&
            canResolveConstObjectFieldReceiver(current) &&
            chargeEdge()) {
          final receiverProvenance = [
            ...sourceProvenance,
            CollectionSemanticSourceStep(
              kind: CollectionSemanticSourceKind.receiver,
              source: current,
              target: receiver,
              element: _referencedElement(current),
            ),
          ];
          final receiverSourceStart = receiverProvenance.length;
          final receiverTerminals = inspect(
            receiver,
            activeBindings,
            receiverProvenance,
          );
          final fieldTerminals = <_CollectionSemanticTerminal>[];
          var everyReceiverResolved = receiverTerminals.isNotEmpty;
          for (final terminal in receiverTerminals) {
            final receiverExpression = terminal.expression;
            final receiverIsConstValue = _hasConstValueProvenance(
              receiverExpression,
              terminal.sourceProvenance.skip(receiverSourceStart),
            );
            final fieldSource = resolveConstObjectFieldInitializerFromReceiver(
              current,
              receiverExpression,
              receiverIsConstValue: receiverIsConstValue,
            );
            if (fieldSource == null) {
              everyReceiverResolved = false;
              break;
            }
            if (!chargeEdge()) break;
            fieldTerminals.addAll(
              inspect(
                fieldSource,
                terminal.bindings,
                [
                  ...terminal.sourceProvenance,
                  CollectionSemanticSourceStep(
                    kind: CollectionSemanticSourceKind.constObjectField,
                    source: current,
                    target: fieldSource,
                    element: _referencedElement(current),
                  ),
                ],
              ),
            );
          }
          if (everyReceiverResolved || workLimitExceeded) {
            return fieldTerminals;
          }
        }
        final source =
            _sourceFor(current) ??
            resolveConstDeclarationInitializer(current) ??
            resolveConstObjectFieldInitializer(current);
        if (source != null && !identical(source, current)) {
          if (chargeEdge()) {
            return inspect(
              source,
              activeBindings,
              [
                ...sourceProvenance,
                CollectionSemanticSourceStep(
                  kind: isConstObjectFieldAccess(current)
                      ? CollectionSemanticSourceKind.constObjectField
                      : constDeclarationElement(current) != null
                      ? CollectionSemanticSourceKind.constDeclaration
                      : CollectionSemanticSourceKind.source,
                  source: current,
                  target: source,
                  element: _referencedElement(current),
                ),
              ],
            );
          }
          return const [];
        }
        if (current is MethodInvocation && !preserveHelpers) {
          final helper = _helperFor(current);
          if (helper != null) {
            if (chargeEdge()) {
              return inspect(
                helper.body,
                {...activeBindings, ...helper.parameterBindings},
                [
                  ...sourceProvenance,
                  CollectionSemanticSourceStep(
                    kind: CollectionSemanticSourceKind.helper,
                    source: current,
                    target: helper.body,
                    element: current.methodName.element,
                  ),
                ],
              );
            }
            return const [];
          }
        }
        if (current is ConditionalExpression && !stopAtConditionals) {
          final terminals = <_CollectionSemanticTerminal>[];
          if (chargeEdge()) {
            terminals.addAll(
              inspect(
                current.thenExpression,
                activeBindings,
                [
                  ...sourceProvenance,
                  CollectionSemanticSourceStep(
                    kind: CollectionSemanticSourceKind.conditionalThen,
                    source: current,
                    target: current.thenExpression,
                  ),
                ],
              ),
            );
          }
          if (chargeEdge()) {
            terminals.addAll(
              inspect(
                current.elseExpression,
                activeBindings,
                [
                  ...sourceProvenance,
                  CollectionSemanticSourceStep(
                    kind: CollectionSemanticSourceKind.conditionalElse,
                    source: current,
                    target: current.elseExpression,
                  ),
                ],
              ),
            );
          }
          return terminals;
        }
        return [
          _CollectionSemanticTerminal(
            current,
            activeBindings,
            sourceProvenance,
          ),
        ];
      } finally {
        active.remove(current);
      }
    }

    final terminals = inspect(expression, bindings, const []);
    return _CollectionSemanticWalk(
      terminals: terminals,
      cycleDetected: cycleDetected,
      workLimitExceeded: workLimitExceeded,
    );
  }
}

/// One bounded typed-list boundary result.
sealed class CollectionTypedListProbeResult {
  const CollectionTypedListProbeResult();
}

/// A resolved plain list that can be inspected element by element.
final class CollectionTypedListPlain extends CollectionTypedListProbeResult {
  /// Creates a successful plain-list result.
  const CollectionTypedListPlain({
    required this.source,
    required this.list,
    required this.bindings,
    required this.sourceProvenance,
  });

  /// The expression authored at the typed-list boundary.
  final Expression source;

  /// The resolved list literal.
  final ListLiteral list;

  /// Bindings required to translate [list] in its terminal context.
  final Map<Element, Expression> bindings;

  /// Transparent semantic edges crossed to reach [list].
  final List<CollectionSemanticSourceStep> sourceProvenance;
}

/// A genuine collection element found at a typed-list boundary.
final class CollectionTypedListElement extends CollectionTypedListProbeResult {
  /// Creates a result for a genuine collection element.
  const CollectionTypedListElement(
    this.offending, {
    this.resolution,
  });

  /// The first collection element found at the typed-list boundary.
  final AstNode offending;

  /// The unique terminal list and its bindings, when resolution is unambiguous.
  final CollectionExpressionResolution? resolution;
}

/// A static terminal or cycle that generic translation must classify.
final class CollectionTypedListTerminal extends CollectionTypedListProbeResult {
  /// Creates a terminal result that generic translation must classify.
  const CollectionTypedListTerminal(
    this.expression, {
    required this.cycleDetected,
  });

  /// The authored expression at the inspection boundary.
  final Expression expression;

  /// Whether identity-cycle protection ended inspection.
  final bool cycleDetected;
}

/// Semantic inspection exhausted its exact work budget.
final class CollectionTypedListWorkLimitExceeded
    extends CollectionTypedListProbeResult {
  /// Creates a bounded-inspection exhaustion result.
  const CollectionTypedListWorkLimitExceeded();
}

/// One bounded binding-resolution result.
final class CollectionExpressionResolution {
  /// Creates a resolution result.
  const CollectionExpressionResolution({
    required this.expression,
    required this.bindings,
    required this.sourceProvenance,
    this.workLimitExceeded = false,
    this.cycleDetected = false,
  });

  /// The deepest expression reached.
  final Expression expression;

  /// Bindings active at [expression].
  final Map<Element, Expression> bindings;

  /// Transparent semantic edges crossed to reach [expression].
  final List<CollectionSemanticSourceStep> sourceProvenance;

  /// Whether resolution exhausted its traversal bound.
  final bool workLimitExceeded;

  /// Whether the transparent graph terminated at an identity cycle.
  final bool cycleDetected;
}

final class _CollectionSemanticTerminal {
  const _CollectionSemanticTerminal(
    this.expression,
    this.bindings,
    this.sourceProvenance,
  );

  final Expression expression;
  final Map<Element, Expression> bindings;
  final List<CollectionSemanticSourceStep> sourceProvenance;
}

/// The kind of transparent edge crossed during semantic resolution.
enum CollectionSemanticSourceKind {
  /// A parenthesized expression.
  parentheses,

  /// The receiver of an instance-field access.
  receiver,

  /// An element-keyed local or parameter binding.
  binding,

  /// An inlinable helper body.
  helper,

  /// A source supplied by the semantic resolver.
  source,

  /// A const declaration initializer.
  constDeclaration,

  /// A field initializer reached through a const object.
  constObjectField,

  /// The selected true branch of a conditional expression.
  conditionalThen,

  /// The selected false branch of a conditional expression.
  conditionalElse;

  /// Whether this entrance distinguishes a directly authored occurrence.
  bool get distinguishesDirectOccurrence => switch (this) {
    CollectionSemanticSourceKind.helper => true,
    CollectionSemanticSourceKind.parentheses ||
    CollectionSemanticSourceKind.receiver ||
    CollectionSemanticSourceKind.binding ||
    CollectionSemanticSourceKind.source ||
    CollectionSemanticSourceKind.constDeclaration ||
    CollectionSemanticSourceKind.constObjectField ||
    CollectionSemanticSourceKind.conditionalThen ||
    CollectionSemanticSourceKind.conditionalElse => false,
  };
}

/// One exact transparent edge in an occurrence's source provenance.
final class CollectionSemanticSourceStep {
  /// Creates one source-provenance edge.
  const CollectionSemanticSourceStep({
    required this.kind,
    required this.source,
    required this.target,
    this.element,
  });

  /// The semantic edge kind.
  final CollectionSemanticSourceKind kind;

  /// The expression at the edge entrance.
  final Expression source;

  /// The expression reached through the edge.
  final Expression target;

  /// The exact declaration crossed when the edge is element-backed.
  final Element? element;
}

final class _CollectionSemanticWalk {
  const _CollectionSemanticWalk({
    required this.terminals,
    required this.cycleDetected,
    required this.workLimitExceeded,
  });

  final List<_CollectionSemanticTerminal> terminals;
  final bool cycleDetected;
  final bool workLimitExceeded;
}

/// Callback identity shared by every semantic leaf in one source artifact.
final class CollectionSemanticTraversalSession {
  final Map<Expression, CollectionSemanticOccurrence>
  _firstOccurrenceByCallbackSource =
      HashMap<Expression, CollectionSemanticOccurrence>.identity();
  final Map<Expression, ForElement> _repeatingLoopByCallbackSource =
      HashMap<Expression, ForElement>.identity();
  final Set<Expression> _convergentCallbackSources =
      HashSet<Expression>.identity();

  /// A copy that later admissions on this session do not change.
  CollectionSemanticTraversalSession copy() =>
      CollectionSemanticTraversalSession()
        .._firstOccurrenceByCallbackSource.addAll(
          _firstOccurrenceByCallbackSource,
        )
        .._repeatingLoopByCallbackSource.addAll(_repeatingLoopByCallbackSource)
        .._convergentCallbackSources.addAll(_convergentCallbackSources);

  /// Admits callbacks reachable from one ordinary semantic leaf.
  CollectionUnrollRefused? admitOrdinaryLeaf(
    Expression expression,
    CollectionSemanticProbe semantics, {
    Map<Element, Expression> bindings = const {},
    Iterable<Expression> convergentSources = const [],
  }) {
    if (expression is ListLiteral) return null;
    final budget = CollectionUnrollBudget();
    final convergentCallbacks = HashSet<Expression>.identity();
    for (final source in convergentSources) {
      final callbacks = semantics._callbackSourcesIn(
        source,
        bindings: bindings,
        budget: budget,
        stopAtNestedLists: true,
      );
      if (callbacks.result == CollectionCallbackProbeResult.workLimitExceeded) {
        return budget.workRefusal(source);
      }
      for (final callback in callbacks.occurrences) {
        if (_firstOccurrenceByCallbackSource.containsKey(callback.source)) {
          convergentCallbacks.add(callback.source);
        }
      }
    }
    _convergentCallbackSources.addAll(convergentCallbacks);
    return _admitCallbacks(
      CollectionSemanticOccurrence(
        authoredExpression: expression,
        terminalExpression: expression,
        bindings: bindings,
        sourceProvenance: const [],
        structuralPath: const [],
      ),
      semantics,
      budget,
      repeatedBy: null,
      rootWorkAlreadyCharged: false,
    );
  }

  CollectionUnrollRefused? _admitCallbacks(
    CollectionSemanticOccurrence occurrence,
    CollectionSemanticProbe semantics,
    CollectionUnrollBudget budget, {
    required ForElement? repeatedBy,
    required bool rootWorkAlreadyCharged,
  }) {
    final callbacks = semantics._callbackSourcesIn(
      occurrence.terminalExpression,
      bindings: occurrence.bindings,
      budget: budget,
      rootWorkAlreadyCharged: rootWorkAlreadyCharged,
      stopAtNestedLists: repeatedBy == null,
    );
    switch (callbacks.result) {
      case CollectionCallbackProbeResult.present:
        for (final callback in callbacks.occurrences) {
          final duplicate = _admitCallbackSource(
            callback,
            occurrence,
            repeatedBy: repeatedBy,
          );
          if (duplicate != null) return duplicate;
        }
      case CollectionCallbackProbeResult.workLimitExceeded:
        return budget.workRefusal(
          repeatedBy ?? occurrence.authoredExpression,
        );
      case CollectionCallbackProbeResult.absent:
        break;
    }
    return null;
  }

  CollectionUnrollRefused? _admitCallbackSource(
    _CollectionCallbackOccurrence callback,
    CollectionSemanticOccurrence occurrence, {
    required ForElement? repeatedBy,
  }) {
    final priorOccurrence = _firstOccurrenceByCallbackSource[callback.source];
    if (priorOccurrence == null) {
      _firstOccurrenceByCallbackSource[callback.source] = occurrence;
      if (repeatedBy != null) {
        _repeatingLoopByCallbackSource[callback.source] = repeatedBy;
      }
      return null;
    }
    // Every iteration of a static loop reuses its body's callbacks, including
    // those in lists nested inside that body; a use outside the loop refuses.
    final loop = _repeatingLoopByCallbackSource[callback.source];
    if (loop != null &&
        (identical(loop, repeatedBy) ||
            _isWithin(occurrence.authoredExpression, loop))) {
      return null;
    }
    if (_convergentCallbackSources.remove(callback.source)) {
      _firstOccurrenceByCallbackSource[callback.source] = occurrence;
      return null;
    }
    return CollectionUnrollRefused(
      reason: CollectionUnrollRefusal.callbackSourceReused,
      detail: _kCallbackSourceReusedDetail,
      location: identical(priorOccurrence, occurrence)
          ? callback.authoredExpression
          : occurrence.structuralPath.isEmpty
          ? occurrence.authoredExpression
          : occurrence.structuralPath.first.node,
    );
  }
}

bool _isWithin(AstNode node, AstNode ancestor) {
  for (AstNode? current = node; current != null; current = current.parent) {
    if (identical(current, ancestor)) return true;
  }
  return false;
}

/// Shared emitted-child and traversal-work accounting for one list literal.
final class CollectionUnrollBudget {
  /// Creates a fresh per-list budget.
  CollectionUnrollBudget({
    this.emittedCeiling = kCollectionUnrollCeiling,
    this.workCeiling = kCollectionUnrollWorkCeiling,
  });

  /// Maximum emitted children for this list.
  final int emittedCeiling;

  /// Maximum static traversal work for this list.
  final int workCeiling;

  int _emittedCount = 0;
  int _workCount = 0;

  /// Charges one emitted child, or returns the ceiling refusal.
  CollectionUnrollRefused? chargeEmission(AstNode location) {
    if (_emittedCount >= emittedCeiling) {
      return CollectionUnrollRefused(
        reason: CollectionUnrollRefusal.ceilingExceeded,
        detail:
            'A list with collection flow exceeds the supported maximum of '
            '$emittedCeiling emitted elements. Use a shorter list.',
        location: location,
      );
    }
    _emittedCount++;
    return null;
  }

  /// Charges one static traversal step, or returns the work-limit refusal.
  CollectionUnrollRefused? chargeWork(AstNode location) {
    return tryChargeWork() ? null : workRefusal(location);
  }

  /// Charges one semantic edge or callback node.
  bool tryChargeWork() {
    if (_workCount >= workCeiling) return false;
    _workCount++;
    return true;
  }

  /// Returns the refusal used when another bounded semantic walk exhausts.
  CollectionUnrollRefused workRefusal(AstNode location) =>
      CollectionUnrollRefused(
        reason: CollectionUnrollRefusal.workLimitExceeded,
        detail:
            'A collection-flow list exceeds the supported limit of '
            '$workCeiling static expansion steps. Use a smaller static '
            'collection.',
        location: location,
      );
}

/// The kind of structural step that produced a semantic occurrence.
enum CollectionStructuralOccurrenceKind {
  /// An authored element in a list literal.
  listElement,

  /// One statically expanded loop iteration.
  loopIteration,

  /// The single authored template of a run-time loop.
  loopTemplate,

  /// The selected true branch of a collection condition.
  selectedThen,

  /// The selected false branch of a collection condition.
  selectedElse,
}

/// One exact structural step from a collection list to an admitted leaf.
final class CollectionStructuralOccurrenceStep {
  /// Creates one structural occurrence step.
  const CollectionStructuralOccurrenceStep({
    required this.kind,
    required this.node,
    required this.ordinal,
    this.iterableSteps = 0,
  });

  /// The collection construct represented by this step.
  final CollectionStructuralOccurrenceKind kind;

  /// The exact authored node that owns this step.
  final AstNode node;

  /// The authored or expansion ordinal within that construct.
  final int ordinal;

  /// For a loop iteration, how many steps just before it walk the iterable.
  final int iterableSteps;
}

/// One admitted collection leaf resolved to its complete semantic context.
final class CollectionSemanticOccurrence {
  /// Creates one complete semantic occurrence.
  const CollectionSemanticOccurrence({
    required this.authoredExpression,
    required this.terminalExpression,
    required this.bindings,
    required this.sourceProvenance,
    required this.structuralPath,
    this.spreadProvenance = const [],
  });

  /// The expression authored at this leaf.
  final Expression authoredExpression;

  /// The canonical terminal expression reached through transparent sources.
  final Expression terminalExpression;

  /// Exact element-keyed bindings active at [terminalExpression].
  final Map<Element, Expression> bindings;

  /// Transparent source edges crossed to reach [terminalExpression].
  final List<CollectionSemanticSourceStep> sourceProvenance;

  /// The source edges of each spread this occurrence was reached through,
  /// outermost first; not part of its identity.
  final List<CollectionSemanticSourceStep> spreadProvenance;

  /// Source entrances that distinguish this persistent occurrence.
  Iterable<CollectionSemanticSourceStep> get identitySourceProvenance =>
      isDirectListElement
      ? sourceProvenance.where(
          (step) => step.kind.distinguishesDirectOccurrence,
        )
      : sourceProvenance;

  /// Exact structural path that produced this occurrence.
  final List<CollectionStructuralOccurrenceStep> structuralPath;

  /// Whether this is one directly authored element of the traversed list.
  bool get isDirectListElement {
    if (structuralPath case [final root]) {
      return root.kind == CollectionStructuralOccurrenceKind.listElement &&
          identical(root.node, authoredExpression);
    }
    return false;
  }
}

/// One ordered result from traversing a list literal.
sealed class CollectionListTraversalEntry {
  const CollectionListTraversalEntry();
}

/// One expression admitted by static collection traversal.
final class CollectionListElement extends CollectionListTraversalEntry {
  /// Creates an admitted list element.
  const CollectionListElement(this.occurrence);

  /// The complete resolved semantic occurrence.
  final CollectionSemanticOccurrence occurrence;
}

/// One run-time collection loop that static traversal deliberately refused.
final class CollectionRuntimeLoopCandidate {
  /// Creates a resolved candidate for strict downstream admission.
  const CollectionRuntimeLoopCandidate({
    required this.iterable,
    required this.binding,
    required this.identifier,
    required this.template,
    this.bindings = const {},
    this.pattern,
    this.patternVariables = const [],
    this.spreadProvenance = const [],
    this.loop,
  });

  /// The helper calls and locals a spread reached this loop through,
  /// outermost first.
  final List<CollectionSemanticSourceStep> spreadProvenance;

  /// The loop as the source writes it.
  final ForElement? loop;

  /// This loop reached through [steps] first.
  CollectionRuntimeLoopCandidate through(
    List<CollectionSemanticSourceStep> steps,
  ) => CollectionRuntimeLoopCandidate(
    iterable: iterable,
    binding: binding,
    identifier: identifier,
    template: template,
    bindings: bindings,
    pattern: pattern,
    patternVariables: patternVariables,
    spreadProvenance: [...steps, ...spreadProvenance],
    loop: loop,
  );

  /// The pattern each item is destructured with, when there is one.
  final DartPattern? pattern;

  /// The variables [pattern] declares.
  final List<Element> patternVariables;

  /// Bindings active while resolving the iterable and its template.
  final Map<Element, Expression> bindings;

  /// The resolved iterable expression.
  final Expression iterable;

  /// The resolved loop-variable element.
  final Element binding;

  /// The identifier authored for the loop variable.
  final String identifier;

  /// The resolved loop body and its structural occurrences.
  final CollectionRuntimeBranch template;
}

/// One collection condition resolved for a downstream consumer to lower.
final class CollectionRuntimeIfCandidate {
  /// Creates a resolved candidate.
  const CollectionRuntimeIfCandidate({
    required this.condition,
    required this.thenBranch,
    this.elseBranch,
    this.bindings = const {},
  });

  /// Bindings active while resolving the condition and its branches.
  final Map<Element, Expression> bindings;

  /// The resolved condition expression.
  final Expression condition;

  /// The branch selected when the condition holds.
  final CollectionRuntimeBranch thenBranch;

  /// The branch selected otherwise, when one is authored.
  final CollectionRuntimeBranch? elseBranch;

  /// Every element this condition can contribute, in authored order.
  Iterable<CollectionSemanticOccurrence> get leafOccurrences sync* {
    yield* thenBranch.leafOccurrences;
    final otherwise = elseBranch;
    if (otherwise != null) yield* otherwise.leafOccurrences;
  }
}

/// One resolved branch of a collection condition or loop template.
sealed class CollectionRuntimeBranch {
  /// Creates a branch.
  const CollectionRuntimeBranch();

  /// Every element this branch can contribute.
  Iterable<CollectionSemanticOccurrence> get leafOccurrences;
}

/// A branch holding one resolved element.
final class CollectionRuntimeLeaf extends CollectionRuntimeBranch {
  /// Creates a leaf branch.
  const CollectionRuntimeLeaf(this.occurrence);

  /// The element and its structural occurrence.
  final CollectionSemanticOccurrence occurrence;

  @override
  Iterable<CollectionSemanticOccurrence> get leafOccurrences => [occurrence];
}

/// A branch holding a further condition.
final class CollectionRuntimeConditional extends CollectionRuntimeBranch {
  /// Creates a nested branch.
  const CollectionRuntimeConditional(this.candidate);

  /// The nested condition.
  final CollectionRuntimeIfCandidate candidate;

  @override
  Iterable<CollectionSemanticOccurrence> get leafOccurrences =>
      candidate.leafOccurrences;
}

/// A nested bounded loop contributing collection fragments.
final class CollectionRuntimeIteration extends CollectionRuntimeBranch {
  /// Creates a loop from its validated runtime candidate.
  const CollectionRuntimeIteration(this.candidate, this.refusal);

  /// The resolved nested loop.
  final CollectionRuntimeLoopCandidate candidate;

  /// Original source diagnostic for consumers that cannot lower the loop.
  final CollectionUnrollRefused refusal;

  @override
  Iterable<CollectionSemanticOccurrence> get leafOccurrences =>
      candidate.template.leafOccurrences;
}

/// A branch spreading a list literal, each element its own branch.
final class CollectionRuntimeGroup extends CollectionRuntimeBranch {
  /// Creates a spread branch.
  const CollectionRuntimeGroup(this.members);

  /// The spread elements in authored order.
  final List<CollectionRuntimeBranch> members;

  @override
  Iterable<CollectionSemanticOccurrence> get leafOccurrences =>
      members.expand((member) => member.leafOccurrences);
}

/// One refusal produced while traversing a list literal.
final class CollectionListRefusal extends CollectionListTraversalEntry {
  /// Creates a refused list entry.
  const CollectionListRefusal(this.refusal);

  /// The exact static-traversal refusal.
  final CollectionUnrollRefused refusal;
}

/// Ordered static-traversal results for one list literal.
final class CollectionListTraversal {
  /// Creates a completed list traversal.
  const CollectionListTraversal(this.entries);

  /// Admitted expressions and refusals in authored order.
  final List<CollectionListTraversalEntry> entries;
}

/// The outcome of expanding one collection element.
sealed class CollectionUnrollResult {
  /// Creates a collection-element expansion outcome.
  const CollectionUnrollResult();
}

/// A successful expansion.
final class CollectionUnrollExpansion extends CollectionUnrollResult {
  /// Creates a successful expansion containing [occurrences].
  const CollectionUnrollExpansion(this.occurrences, {this.entries});

  /// Ordered static leaves and runtime branches of a composed collection.
  final List<CollectionListTraversalEntry>? entries;

  /// Semantic occurrences in emission order.
  final List<CollectionSemanticOccurrence> occurrences;
}

/// A refusal carrying the developer-facing [detail] and offending [location].
final class CollectionUnrollRefused extends CollectionUnrollResult {
  /// Creates a refusal with its reason, developer-facing detail, and location.
  const CollectionUnrollRefused({
    required this.reason,
    required this.detail,
    required this.location,
    this.runtimeLoop,
    this.runtimeIf,
  });

  /// The category of the refusal.
  final CollectionUnrollRefusal reason;

  /// The developer-facing explanation.
  final String detail;

  /// The AST node that should anchor the diagnostic.
  final AstNode location;

  /// A resolved run-time loop available to strict downstream consumers.
  final CollectionRuntimeLoopCandidate? runtimeLoop;

  /// A resolved run-time condition available to downstream consumers.
  final CollectionRuntimeIfCandidate? runtimeIf;
}

/// Expands a spread, collection-`if`, or collection-`for` over static values
/// into the elements it contributes.
CollectionUnrollResult expandCollectionElement(
  CollectionElement element, {
  CollectionSemanticProbe? semantics,
  CollectionUnrollBudget? budget,
  CollectionSemanticTraversalSession? session,
  Map<Element, Expression> bindings = const {},
}) {
  return _CollectionUnroller(
    element,
    semantics ?? CollectionSemanticProbe(),
    budget ?? CollectionUnrollBudget(),
    session ?? CollectionSemanticTraversalSession(),
    bindings,
    [
      CollectionStructuralOccurrenceStep(
        kind: CollectionStructuralOccurrenceKind.listElement,
        node: element,
        ordinal: 0,
      ),
    ],
  ).expand();
}

/// Traverses one list through the same static expansion contract.
CollectionListTraversal traverseCollectionList(
  ListLiteral list, {
  CollectionSemanticProbe? semantics,
  CollectionUnrollBudget? budget,
  CollectionSemanticTraversalSession? session,
  Map<Element, Expression> bindings = const {},
  bool Function(CollectionElement element)? rendersFromApp,
}) {
  final sharedSemantics = semantics ?? CollectionSemanticProbe();
  final sharedSession = session ?? CollectionSemanticTraversalSession();
  // A spread, `if` or `for` the app renders itself takes its place
  // unexpanded; a widget expression is walked where it is.
  CollectionListRefusal? fromApp(CollectionElement element) =>
      element is! Expression && (rendersFromApp?.call(element) ?? false)
      ? CollectionListRefusal(
          CollectionUnrollRefused(
            reason: CollectionUnrollRefusal.appRendered,
            detail: 'The element renders from the app.',
            location: element,
          ),
        )
      : null;
  if (list.elements.every((element) => element is Expression)) {
    final entries = <CollectionListTraversalEntry>[];
    for (final (index, element) in list.elements.cast<Expression>().indexed) {
      final occurrence = CollectionSemanticOccurrence(
        authoredExpression: element,
        terminalExpression: element,
        bindings: bindings,
        sourceProvenance: const [],
        structuralPath: [
          CollectionStructuralOccurrenceStep(
            kind: CollectionStructuralOccurrenceKind.listElement,
            node: element,
            ordinal: index,
          ),
        ],
      );
      final refusal = sharedSession._admitCallbacks(
        occurrence,
        sharedSemantics,
        CollectionUnrollBudget(),
        repeatedBy: null,
        rootWorkAlreadyCharged: false,
      );
      entries.add(
        refusal == null
            ? CollectionListElement(occurrence)
            : CollectionListRefusal(refusal),
      );
    }
    return CollectionListTraversal(List.unmodifiable(entries));
  }
  final sharedBudget = budget ?? CollectionUnrollBudget();
  final entries = <CollectionListTraversalEntry>[];
  for (final (index, element) in list.elements.indexed) {
    if (fromApp(element) case final entry?) {
      entries.add(entry);
      continue;
    }
    final result = _CollectionUnroller(
      element,
      sharedSemantics,
      sharedBudget,
      sharedSession,
      bindings,
      [
        CollectionStructuralOccurrenceStep(
          kind: CollectionStructuralOccurrenceKind.listElement,
          node: element,
          ordinal: index,
        ),
      ],
    ).expand();
    switch (result) {
      case CollectionUnrollExpansion(
        :final occurrences,
        entries: final expanded,
      ):
        entries.addAll(expanded ?? occurrences.map(CollectionListElement.new));
      case CollectionUnrollRefused():
        entries.add(CollectionListRefusal(result));
        if (result.reason == CollectionUnrollRefusal.ceilingExceeded ||
            result.reason == CollectionUnrollRefusal.workLimitExceeded) {
          return CollectionListTraversal(List.unmodifiable(entries));
        }
    }
  }
  return CollectionListTraversal(List.unmodifiable(entries));
}

bool _isCallback(Expression expression) {
  if (expression is NamedArgument) return false;
  if (expression is FunctionExpression) return true;
  if (expression.staticType is! FunctionType) return false;
  final parent = expression.parent;
  if (parent is MethodInvocation && identical(parent.methodName, expression)) {
    return false;
  }
  if (parent is FunctionExpressionInvocation &&
      identical(parent.function, expression)) {
    return false;
  }
  return true;
}

Element? _referencedElement(Expression expression) {
  Element? element;
  switch (expression) {
    case SimpleIdentifier():
      element = expression.element;
    case PrefixedIdentifier():
      element = expression.identifier.element;
    case PropertyAccess():
      element = expression.propertyName.element;
    default:
      return null;
  }
  return element is PropertyAccessorElement ? element.variable : element;
}

Expression? _fieldAccessReceiver(Expression expression) => switch (expression) {
  PrefixedIdentifier(:final prefix) => prefix,
  PropertyAccess(:final target) => target,
  _ => null,
};

bool _hasConstValueProvenance(
  Expression expression,
  Iterable<CollectionSemanticSourceStep> provenance,
) {
  if (expression is! InstanceCreationExpression) return false;
  if (expression.isConst) return true;
  return provenance.any(
    (step) =>
        step.kind == CollectionSemanticSourceKind.constDeclaration ||
        step.kind == CollectionSemanticSourceKind.constObjectField,
  );
}

Expression? _noBinding(SimpleIdentifier identifier) => null;

CollectionResolvedHelper? _noHelper(MethodInvocation invocation) => null;

Expression? _noSource(Expression expression) => null;

const String _kRuntimeForDetail =
    "Restage can't loop over a list that is only known when the app runs. "
    'Try looping over a list literal or computing the list in the '
    "screen's build method and passing it in.";
const String _kRuntimeSpreadDetail =
    "Restage can't spread a list that is only known when the app runs. "
    'Try spreading a list literal or computing the list in the screen\'s '
    'build method and passing it in.';
const String _kRuntimeIfDetail =
    "Restage can't evaluate this condition because it is only known when the "
    "app runs. Try computing it in the screen's build method and passing it "
    'in as a `bool`.';
const String _kRuntimeIfBodyDetail =
    "Restage can't show this element under a condition that is only known "
    'when the app runs. Try using a widget, a spread of a list literal or '
    'another `if` in each branch.';

/// [refusal]'s message, naming what it refuses and where, at [location].
String collectionRefusalMessage(
  CollectionUnrollRefused refusal,
  String location,
) =>
    '`${readableSource(refusal.location.toSource())}` ($location): '
    '${refusal.detail}';
const String _kStaticForDetail =
    'A collection-for requires a list literal, but this iterable is a '
    'statically known non-list value.';
const String _kStaticSpreadDetail =
    'A spread requires a list literal, but this value is a statically known '
    'non-list value.';
const String _kCStyleForDetail =
    'A C-style collection-for is unsupported. Write a for-each over a list '
    'literal, as in '
    '`for (final item in [a, b])`.';
const String _kUndeclaredForDetail =
    'A collection-for must declare its loop variable. Write '
    '`for (final item in [a, b])`.';
const String _kAwaitForDetail =
    'An await collection-for is unsupported. Write a for-each over a list '
    'literal.';
const String _kUnresolvedLoopVariableDetail =
    'The collection-for loop variable could not be resolved.';
const String _kMethodCallIterableDetail =
    'An iterable built by a method call, such as a .map(...) chain, is '
    'unsupported. Iterate a list literal.';
const String _kCaseIfDetail =
    'A collection-if with a case pattern is unsupported. Use a condition that '
    'folds to a constant.';
const String _kUnsupportedCollectionElementDetail =
    'This collection element is unsupported. Use a list literal element, a '
    'spread of a list literal, a constant collection-if, or a for-each over a '
    'list literal.';
const String _kCallbackSourceReusedDetail =
    'A callback-bearing static collection source is reused, so its '
    'occurrences would share one callback identity. Write distinct elements, '
    'or bind the list to host-supplied data where supported.';

typedef _SemanticOccurrenceConsumer =
    CollectionUnrollRefused? Function(
      CollectionSemanticOccurrence occurrence,
    );

final class _CollectionUnroller {
  _CollectionUnroller(
    this._outermost,
    this._semantics,
    this._budget,
    this._session,
    this._initialBindings,
    this._initialPath,
  );

  final CollectionElement _outermost;
  final CollectionSemanticProbe _semantics;
  final CollectionUnrollBudget _budget;
  final CollectionSemanticTraversalSession _session;
  final Map<Element, Expression> _initialBindings;
  final List<CollectionStructuralOccurrenceStep> _initialPath;

  var _entries = <CollectionListTraversalEntry>[];
  ForElement? _activeRepeatedBy;

  // The sources the spreads around the element being expanded crossed.
  List<CollectionSemanticSourceStep> _activeSpread = const [];

  CollectionUnrollResult expand() {
    final occurrences = <CollectionSemanticOccurrence>[];
    final refusal = _expandElement(
      _outermost,
      _initialBindings,
      _initialPath,
      (occurrence) {
        final refusal = _budget.chargeEmission(_outermost);
        if (refusal != null) return refusal;
        occurrences.add(occurrence);
        _entries.add(CollectionListElement(occurrence));
        return null;
      },
      repeatedBy: null,
      ledgerCallbacks: true,
    );
    if (refusal != null) return refusal;
    if (_entries case [CollectionListRefusal(:final refusal)]) return refusal;
    return CollectionUnrollExpansion(
      occurrences,
      entries: List.unmodifiable(_entries),
    );
  }

  CollectionUnrollRefused? _expandElement(
    CollectionElement element,
    Map<Element, Expression> bindings,
    List<CollectionStructuralOccurrenceStep> structuralPath,
    _SemanticOccurrenceConsumer emit, {
    required ForElement? repeatedBy,
    required bool ledgerCallbacks,
  }) {
    final saved = _activeRepeatedBy;
    _activeRepeatedBy = repeatedBy;
    try {
      final refusal = _expandRawElement(
        element,
        bindings,
        structuralPath,
        emit,
        repeatedBy: repeatedBy,
        ledgerCallbacks: ledgerCallbacks,
      );
      if (ledgerCallbacks &&
          refusal != null &&
          (refusal.runtimeIf != null || refusal.runtimeLoop != null)) {
        _entries.add(
          CollectionListRefusal(
            refusal.runtimeLoop == null || _activeSpread.isEmpty
                ? refusal
                : CollectionUnrollRefused(
                    reason: refusal.reason,
                    detail: refusal.detail,
                    location: refusal.location,
                    runtimeLoop: refusal.runtimeLoop!.through(_activeSpread),
                    runtimeIf: refusal.runtimeIf,
                  ),
          ),
        );
        return null;
      }
      return refusal;
    } finally {
      _activeRepeatedBy = saved;
    }
  }

  CollectionUnrollRefused? _expandRawElement(
    CollectionElement element,
    Map<Element, Expression> bindings,
    List<CollectionStructuralOccurrenceStep> structuralPath,
    _SemanticOccurrenceConsumer emit, {
    required ForElement? repeatedBy,
    required bool ledgerCallbacks,
  }) {
    final workRefusal = _budget.chargeWork(element);
    if (workRefusal != null) return workRefusal;
    if (element is Expression) {
      final resolution = _semantics.resolve(element, bindings, _budget);
      if (resolution.workLimitExceeded) {
        return _budget.workRefusal(element);
      }
      final occurrence = CollectionSemanticOccurrence(
        authoredExpression: element,
        terminalExpression: resolution.expression,
        bindings: resolution.bindings,
        sourceProvenance: resolution.sourceProvenance,
        structuralPath: structuralPath,
      );
      if (ledgerCallbacks) {
        if (repeatedBy != null &&
            !identical(
              occurrence.authoredExpression,
              occurrence.terminalExpression,
            ) &&
            !_budget.tryChargeWork()) {
          return _budget.workRefusal(repeatedBy);
        }
        final callbackRefusal = _session._admitCallbacks(
          occurrence,
          _semantics,
          _budget,
          repeatedBy: repeatedBy,
          rootWorkAlreadyCharged:
              repeatedBy == null &&
              identical(
                occurrence.authoredExpression,
                occurrence.terminalExpression,
              ),
        );
        if (callbackRefusal != null) return callbackRefusal;
      }
      return emit(occurrence);
    }
    if (element is ForElement) {
      return _expandForElement(
        element,
        bindings,
        structuralPath,
        emit,
        ledgerCallbacks,
      );
    }
    if (element is IfElement) {
      return _expandIfElement(
        element,
        bindings,
        structuralPath,
        emit,
        repeatedBy,
        ledgerCallbacks,
      );
    }
    if (element is SpreadElement) {
      return _expandSpreadElement(
        element,
        bindings,
        structuralPath,
        emit,
        repeatedBy,
        ledgerCallbacks,
      );
    }
    return _refuse(
      CollectionUnrollRefusal.unsupportedShape,
      _kUnsupportedCollectionElementDetail,
      element,
    );
  }

  CollectionUnrollRefused? _expandForElement(
    ForElement element,
    Map<Element, Expression> bindings,
    List<CollectionStructuralOccurrenceStep> structuralPath,
    _SemanticOccurrenceConsumer emit,
    bool ledgerCallbacks,
  ) {
    if (element.awaitKeyword != null) {
      return _refuse(
        CollectionUnrollRefusal.unsupportedShape,
        _kAwaitForDetail,
        element,
      );
    }
    final parts = element.forLoopParts;
    if (parts is ForEachPartsWithPattern) {
      return _runtimePatternLoop(
        element,
        parts,
        bindings,
        structuralPath,
        ledgerCallbacks,
      );
    }
    if (parts is! ForEachPartsWithDeclaration) {
      return _refuse(
        CollectionUnrollRefusal.unsupportedShape,
        parts is ForEachParts ? _kUndeclaredForDetail : _kCStyleForDetail,
        element,
      );
    }
    final loopVariable = parts.loopVariable.declaredFragment?.element;
    if (loopVariable == null) {
      return _refuse(
        CollectionUnrollRefusal.unsupportedShape,
        _kUnresolvedLoopVariableDetail,
        element,
      );
    }
    final resolution = _semantics.resolve(parts.iterable, bindings, _budget);
    if (resolution.workLimitExceeded) return _budget.workRefusal(element);
    final iterable = resolution.expression;
    if (iterable is! ListLiteral) {
      // A computed iterable stays refused here; a generated mount may walk
      // it at run time.
      final computed =
          iterable is MethodInvocation ||
          iterable is FunctionExpressionInvocation;
      final refusal = computed
          ? _refuse(
              CollectionUnrollRefusal.unsupportedShape,
              _kMethodCallIterableDetail,
              element,
            )
          : _nonListRefusal(
              iterable,
              element,
              staticDetail: _kStaticForDetail,
              runtimeDetail: _kRuntimeForDetail,
            );
      if (!computed && refusal.reason != CollectionUnrollRefusal.runtimeValue) {
        return refusal;
      }
      final template = _runtimeBranchAt(
        element,
        element.body,
        bindings,
        [
          ...structuralPath,
          CollectionStructuralOccurrenceStep(
            kind: CollectionStructuralOccurrenceKind.loopTemplate,
            node: element,
            ordinal: 0,
          ),
        ],
        ledgerCallbacks,
      );
      if (template.refusal != null) return template.refusal;
      return CollectionUnrollRefused(
        reason: refusal.reason,
        detail: refusal.detail,
        location: refusal.location,
        runtimeLoop: CollectionRuntimeLoopCandidate(
          iterable: iterable,
          binding: loopVariable,
          identifier: parts.loopVariable.name.lexeme,
          template: template.branch!,
          bindings: resolution.bindings,
          loop: element,
        ),
      );
    }
    var iterationOrdinal = 0;
    CollectionUnrollRefused? fromBody;
    final refused = _expandList(
      iterable,
      resolution.bindings,
      structuralPath,
      (iteration, _) {
        final currentOrdinal = iterationOrdinal++;
        final bodyBindings = {
          ...iteration.bindings,
          loopVariable: iteration.terminalExpression,
        };
        return fromBody = _expandElement(
          element.body,
          bodyBindings,
          [
            ...iteration.structuralPath,
            CollectionStructuralOccurrenceStep(
              kind: CollectionStructuralOccurrenceKind.loopIteration,
              node: element,
              ordinal: currentOrdinal,
              iterableSteps:
                  iteration.structuralPath.length - structuralPath.length,
            ),
          ],
          emit,
          repeatedBy: element,
          ledgerCallbacks: ledgerCallbacks,
        );
      },
      repeatedBy: null,
      ledgerCallbacks: false,
    );
    // A run-time part of the list this loop walks can't stand for the loop:
    // its body would be lost.
    if (refused != null &&
        !identical(refused, fromBody) &&
        (refused.runtimeLoop != null || refused.runtimeIf != null)) {
      return _refuse(
        CollectionUnrollRefusal.unsupportedShape,
        _kMethodCallIterableDetail,
        element,
      );
    }
    return refused;
  }

  CollectionUnrollRefused? _expandIfElement(
    IfElement element,
    Map<Element, Expression> bindings,
    List<CollectionStructuralOccurrenceStep> structuralPath,
    _SemanticOccurrenceConsumer emit,
    ForElement? repeatedBy,
    bool ledgerCallbacks,
  ) {
    if (element.caseClause != null) {
      return _refuse(
        CollectionUnrollRefusal.unsupportedShape,
        _kCaseIfDetail,
        element,
      );
    }
    final resolution = _semantics.resolve(
      element.expression,
      bindings,
      _budget,
    );
    if (resolution.workLimitExceeded) return _budget.workRefusal(element);
    final condition = tryFoldConstant(resolution.expression);
    if (condition is! bool) {
      return _runtimeIfRefusal(
        element,
        resolution.expression,
        resolution.bindings,
        structuralPath,
        ledgerCallbacks,
      );
    }
    final branch = condition ? element.thenElement : element.elseElement;
    if (branch == null) return null;
    return _expandElement(
      branch,
      bindings,
      [
        ...structuralPath,
        CollectionStructuralOccurrenceStep(
          kind: condition
              ? CollectionStructuralOccurrenceKind.selectedThen
              : CollectionStructuralOccurrenceKind.selectedElse,
          node: element,
          ordinal: condition ? 0 : 1,
        ),
      ],
      emit,
      repeatedBy: repeatedBy,
      ledgerCallbacks: ledgerCallbacks,
    );
  }

  /// Resolves the branches of a run-time collection-`if`.
  CollectionUnrollRefused _runtimeIfRefusal(
    IfElement element,
    Expression condition,
    Map<Element, Expression> bindings,
    List<CollectionStructuralOccurrenceStep> structuralPath,
    bool ledgerCallbacks,
  ) {
    final resolved = _runtimeIfCandidate(
      element,
      condition,
      bindings,
      structuralPath,
      ledgerCallbacks,
    );
    if (resolved.refusal != null) return resolved.refusal!;
    return CollectionUnrollRefused(
      reason: CollectionUnrollRefusal.runtimeValue,
      detail: _kRuntimeIfDetail,
      location: element,
      runtimeIf: resolved.candidate,
    );
  }

  ({CollectionRuntimeIfCandidate? candidate, CollectionUnrollRefused? refusal})
  _runtimeIfCandidate(
    IfElement element,
    Expression condition,
    Map<Element, Expression> bindings,
    List<CollectionStructuralOccurrenceStep> structuralPath,
    bool ledgerCallbacks,
  ) {
    final thenResult = _runtimeIfBranch(
      element,
      element.thenElement,
      bindings,
      structuralPath,
      ledgerCallbacks,
      CollectionStructuralOccurrenceKind.selectedThen,
      0,
    );
    if (thenResult.refusal != null) {
      return (candidate: null, refusal: thenResult.refusal);
    }
    CollectionRuntimeBranch? elseBranch;
    final elseElement = element.elseElement;
    if (elseElement != null) {
      final elseResult = _runtimeIfBranch(
        element,
        elseElement,
        bindings,
        structuralPath,
        ledgerCallbacks,
        CollectionStructuralOccurrenceKind.selectedElse,
        1,
      );
      if (elseResult.refusal != null) {
        return (candidate: null, refusal: elseResult.refusal);
      }
      elseBranch = elseResult.branch;
    }
    return (
      candidate: CollectionRuntimeIfCandidate(
        condition: condition,
        bindings: bindings,
        thenBranch: thenResult.branch!,
        elseBranch: elseBranch,
      ),
      refusal: null,
    );
  }

  ({CollectionRuntimeBranch? branch, CollectionUnrollRefused? refusal})
  _runtimeIfBranch(
    IfElement element,
    CollectionElement branch,
    Map<Element, Expression> bindings,
    List<CollectionStructuralOccurrenceStep> structuralPath,
    bool ledgerCallbacks,
    CollectionStructuralOccurrenceKind kind,
    int ordinal,
  ) {
    final branchPath = [
      ...structuralPath,
      CollectionStructuralOccurrenceStep(
        kind: kind,
        node: element,
        ordinal: ordinal,
      ),
    ];
    return _runtimeBranchAt(
      element,
      branch,
      bindings,
      branchPath,
      ledgerCallbacks,
    );
  }

  ({CollectionRuntimeBranch? branch, CollectionUnrollRefused? refusal})
  _runtimeBranchAt(
    CollectionElement element,
    CollectionElement branch,
    Map<Element, Expression> bindings,
    List<CollectionStructuralOccurrenceStep> branchPath,
    bool ledgerCallbacks,
  ) {
    if (branch is ForElement) {
      final saved = _entries;
      final nested = <CollectionListTraversalEntry>[];
      _entries = nested;
      CollectionUnrollRefused? refusal;
      try {
        refusal = _expandForElement(branch, bindings, branchPath, (occurrence) {
          final refused = _budget.chargeEmission(branch);
          if (refused != null) return refused;
          nested.add(CollectionListElement(occurrence));
          return null;
        }, ledgerCallbacks);
      } finally {
        _entries = saved;
      }
      if (refusal != null) {
        final candidate = refusal.runtimeLoop;
        return candidate == null
            ? (branch: null, refusal: refusal)
            : (
                branch: CollectionRuntimeIteration(candidate, refusal),
                refusal: null,
              );
      }
      final members = <CollectionRuntimeBranch>[];
      for (final entry in nested) {
        switch (entry) {
          case CollectionListElement(:final occurrence):
            members.add(CollectionRuntimeLeaf(occurrence));
          case CollectionListRefusal(:final refusal):
            if (refusal.runtimeIf case final candidate?) {
              members.add(CollectionRuntimeConditional(candidate));
            } else if (refusal.runtimeLoop case final candidate?) {
              members.add(CollectionRuntimeIteration(candidate, refusal));
            } else {
              return (branch: null, refusal: refusal);
            }
        }
      }
      return (branch: CollectionRuntimeGroup(members), refusal: null);
    }
    if (branch is SpreadElement) {
      return _runtimeSpreadBranch(
        element,
        branch,
        branch.expression,
        bindings,
        branchPath,
        ledgerCallbacks,
      );
    }
    if (branch is IfElement && branch.caseClause == null) {
      final resolution = _semantics.resolve(
        branch.expression,
        bindings,
        _budget,
      );
      if (resolution.workLimitExceeded) {
        return (branch: null, refusal: _budget.workRefusal(branch));
      }
      final constant = tryFoldConstant(resolution.expression);
      if (constant is bool) {
        final selected = constant ? branch.thenElement : branch.elseElement;
        if (selected == null) {
          return (branch: const CollectionRuntimeGroup([]), refusal: null);
        }
        return _runtimeBranchAt(
          element,
          selected,
          bindings,
          [
            ...branchPath,
            CollectionStructuralOccurrenceStep(
              kind: constant
                  ? CollectionStructuralOccurrenceKind.selectedThen
                  : CollectionStructuralOccurrenceKind.selectedElse,
              node: branch,
              ordinal: constant ? 0 : 1,
            ),
          ],
          ledgerCallbacks,
        );
      }
      final nested = _runtimeIfCandidate(
        branch,
        resolution.expression,
        resolution.bindings,
        branchPath,
        ledgerCallbacks,
      );
      if (nested.refusal != null) {
        return (branch: null, refusal: nested.refusal);
      }
      return (
        branch: CollectionRuntimeConditional(nested.candidate!),
        refusal: null,
      );
    }
    if (branch is! Expression) {
      return (
        branch: null,
        refusal: _refuse(
          CollectionUnrollRefusal.runtimeValue,
          _kRuntimeIfBodyDetail,
          branch,
        ),
      );
    }
    final emissionRefusal = _budget.chargeEmission(branch);
    if (emissionRefusal != null)
      return (branch: null, refusal: emissionRefusal);
    final resolution = _semantics.resolve(branch, bindings, _budget);
    if (resolution.workLimitExceeded) {
      return (branch: null, refusal: _budget.workRefusal(element));
    }
    final occurrence = CollectionSemanticOccurrence(
      authoredExpression: branch,
      terminalExpression: resolution.expression,
      bindings: resolution.bindings,
      sourceProvenance: resolution.sourceProvenance,
      structuralPath: branchPath,
    );
    if (ledgerCallbacks) {
      final callbackRefusal = _session._admitCallbacks(
        occurrence,
        _semantics,
        _budget,
        repeatedBy: _activeRepeatedBy,
        rootWorkAlreadyCharged: false,
      );
      if (callbackRefusal != null) {
        return (branch: null, refusal: callbackRefusal);
      }
    }
    return (branch: CollectionRuntimeLeaf(occurrence), refusal: null);
  }

  ({CollectionRuntimeBranch? branch, CollectionUnrollRefused? refusal})
  _runtimeSpreadBranch(
    CollectionElement element,
    SpreadElement spread,
    Expression expression,
    Map<Element, Expression> bindings,
    List<CollectionStructuralOccurrenceStep> path,
    bool ledgerCallbacks,
  ) {
    final resolution = _semantics.resolve(
      expression,
      bindings,
      _budget,
      stopAtConditionals: true,
    );
    if (resolution.workLimitExceeded) {
      return (branch: null, refusal: _budget.workRefusal(spread));
    }
    final value = resolution.expression;
    if (spread.isNullAware && value is NullLiteral) {
      return (branch: const CollectionRuntimeGroup([]), refusal: null);
    }
    if (value is ConditionalExpression) {
      final condition = _semantics.resolve(
        value.condition,
        resolution.bindings,
        _budget,
      );
      if (condition.workLimitExceeded) {
        return (branch: null, refusal: _budget.workRefusal(spread));
      }
      final folded = tryFoldConstant(condition.expression);
      final branches = <CollectionRuntimeBranch>[];
      for (final (then, arm) in [
        (true, value.thenExpression),
        (false, value.elseExpression),
      ]) {
        if (folded is bool && folded != then) continue;
        final result = _runtimeSpreadBranch(
          element,
          spread,
          arm,
          resolution.bindings,
          [
            ...path,
            CollectionStructuralOccurrenceStep(
              kind: then
                  ? CollectionStructuralOccurrenceKind.selectedThen
                  : CollectionStructuralOccurrenceKind.selectedElse,
              node: value,
              ordinal: then ? 0 : 1,
            ),
          ],
          ledgerCallbacks,
        );
        if (result.refusal != null) return result;
        branches.add(result.branch!);
      }
      return (
        branch: folded is bool
            ? branches.single
            : CollectionRuntimeConditional(
                CollectionRuntimeIfCandidate(
                  condition: condition.expression,
                  bindings: condition.bindings,
                  thenBranch: branches[0],
                  elseBranch: branches[1],
                ),
              ),
        refusal: null,
      );
    }
    if (value is! ListLiteral) {
      return (
        branch: null,
        refusal: _nonListRefusal(
          value,
          spread,
          staticDetail: _kStaticSpreadDetail,
          runtimeDetail: _kRuntimeSpreadDetail,
        ),
      );
    }
    final members = <CollectionRuntimeBranch>[];
    for (final (index, member) in value.elements.indexed) {
      final charged = _budget.chargeWork(member);
      if (charged != null) return (branch: null, refusal: charged);
      final result = _runtimeBranchAt(element, member, resolution.bindings, [
        ...path,
        CollectionStructuralOccurrenceStep(
          kind: CollectionStructuralOccurrenceKind.listElement,
          node: member,
          ordinal: index,
        ),
      ], ledgerCallbacks);
      if (result.refusal != null) return result;
      members.add(result.branch!);
    }
    return (branch: CollectionRuntimeGroup(members), refusal: null);
  }

  CollectionUnrollRefused? _expandSpreadElement(
    SpreadElement element,
    Map<Element, Expression> bindings,
    List<CollectionStructuralOccurrenceStep> structuralPath,
    _SemanticOccurrenceConsumer emit,
    ForElement? repeatedBy,
    bool ledgerCallbacks,
  ) {
    return _expandSpreadValue(
      element,
      element.expression,
      bindings,
      structuralPath,
      emit,
      repeatedBy,
      ledgerCallbacks,
    );
  }

  CollectionUnrollRefused? _expandSpreadValue(
    SpreadElement element,
    Expression expression,
    Map<Element, Expression> bindings,
    List<CollectionStructuralOccurrenceStep> structuralPath,
    _SemanticOccurrenceConsumer emit,
    ForElement? repeatedBy,
    bool ledgerCallbacks,
  ) {
    final resolution = _semantics.resolve(
      expression,
      bindings,
      _budget,
      stopAtConditionals: true,
    );
    if (resolution.workLimitExceeded) return _budget.workRefusal(element);
    final iterable = resolution.expression;
    if (element.isNullAware && iterable is NullLiteral) return null;
    if (iterable is ConditionalExpression) {
      final condition = _semantics.resolve(
        iterable.condition,
        resolution.bindings,
        _budget,
      );
      if (condition.workLimitExceeded) return _budget.workRefusal(element);
      final selected = tryFoldConstant(condition.expression);
      if (selected is bool) {
        return _expandSpreadValue(
          element,
          selected ? iterable.thenExpression : iterable.elseExpression,
          resolution.bindings,
          [
            ...structuralPath,
            CollectionStructuralOccurrenceStep(
              kind: selected
                  ? CollectionStructuralOccurrenceKind.selectedThen
                  : CollectionStructuralOccurrenceKind.selectedElse,
              node: iterable,
              ordinal: selected ? 0 : 1,
            ),
          ],
          emit,
          repeatedBy,
          ledgerCallbacks,
        );
      }
      final branch = _runtimeSpreadBranch(
        element,
        element,
        iterable,
        resolution.bindings,
        structuralPath,
        ledgerCallbacks,
      );
      if (branch.refusal != null) return branch.refusal;
      if (branch.branch case CollectionRuntimeConditional(:final candidate)) {
        return CollectionUnrollRefused(
          reason: CollectionUnrollRefusal.runtimeValue,
          detail: _kRuntimeSpreadDetail,
          location: element,
          runtimeIf: candidate,
        );
      }
      return _refuse(
        CollectionUnrollRefusal.unsupportedShape,
        _kRuntimeSpreadDetail,
        element,
      );
    }

    if (iterable is MethodInvocation ||
        iterable is FunctionExpressionInvocation) {
      return _refuse(
        CollectionUnrollRefusal.unsupportedShape,
        _kMethodCallIterableDetail,
        element,
      );
    }
    if (iterable is! ListLiteral) {
      return _nonListRefusal(
        iterable,
        element,
        staticDetail: _kStaticSpreadDetail,
        runtimeDetail: _kRuntimeSpreadDetail,
      );
    }
    final outerSpread = _activeSpread;
    _activeSpread = [...outerSpread, ...resolution.sourceProvenance];
    final CollectionUnrollRefused? refused;
    try {
      refused = _expandList(
        iterable,
        resolution.bindings,
        structuralPath,
        // Each element is read through the spread's own sources too.
        (occurrence, _) => emit(
          CollectionSemanticOccurrence(
            authoredExpression: occurrence.authoredExpression,
            terminalExpression: occurrence.terminalExpression,
            bindings: occurrence.bindings,
            sourceProvenance: occurrence.sourceProvenance,
            structuralPath: occurrence.structuralPath,
            spreadProvenance: [
              ...resolution.sourceProvenance,
              ...occurrence.spreadProvenance,
            ],
          ),
        ),
        repeatedBy: repeatedBy,
        ledgerCallbacks: ledgerCallbacks,
      );
    } finally {
      _activeSpread = outerSpread;
    }
    // A run-time loop is read through the spread's sources as well.
    if (refused?.runtimeLoop case final loop?) {
      return CollectionUnrollRefused(
        reason: refused!.reason,
        detail: refused.detail,
        location: refused.location,
        runtimeLoop: loop.through(resolution.sourceProvenance),
        runtimeIf: refused.runtimeIf,
      );
    }
    return refused;
  }

  CollectionUnrollRefused? _expandList(
    ListLiteral literal,
    Map<Element, Expression> bindings,
    List<CollectionStructuralOccurrenceStep> structuralPath,
    CollectionUnrollRefused? Function(
      CollectionSemanticOccurrence occurrence,
      int index,
    )
    emit, {
    required ForElement? repeatedBy,
    required bool ledgerCallbacks,
  }) {
    for (final (index, element) in literal.elements.indexed) {
      final refusal = _expandElement(
        element,
        bindings,
        [
          ...structuralPath,
          CollectionStructuralOccurrenceStep(
            kind: CollectionStructuralOccurrenceKind.listElement,
            node: element,
            ordinal: index,
          ),
        ],
        (occurrence) => emit(occurrence, index),
        repeatedBy: repeatedBy,
        ledgerCallbacks: ledgerCallbacks,
      );
      if (refusal != null) return refusal;
    }
    return null;
  }

  CollectionUnrollRefused _refuse(
    CollectionUnrollRefusal reason,
    String detail,
    AstNode location,
  ) => CollectionUnrollRefused(
    reason: reason,
    detail: detail,
    location: location,
  );

  /// A loop that destructures each item is admitted only at run time.
  CollectionUnrollRefused _runtimePatternLoop(
    ForElement element,
    ForEachPartsWithPattern parts,
    Map<Element, Expression> bindings,
    List<CollectionStructuralOccurrenceStep> structuralPath,
    bool ledgerCallbacks,
  ) {
    final variables = <Element>[];
    parts.pattern.accept(_PatternVariables(variables));
    final resolution = _semantics.resolve(parts.iterable, bindings, _budget);
    if (resolution.workLimitExceeded) return _budget.workRefusal(element);
    final iterable = resolution.expression;
    if (variables.isEmpty ||
        iterable is ListLiteral ||
        _isStaticallyKnownNonList(iterable)) {
      return _refuse(
        CollectionUnrollRefusal.unsupportedShape,
        _kUndeclaredForDetail,
        element,
      );
    }
    final template = _runtimeBranchAt(
      element,
      element.body,
      bindings,
      [
        ...structuralPath,
        CollectionStructuralOccurrenceStep(
          kind: CollectionStructuralOccurrenceKind.loopTemplate,
          node: element,
          ordinal: 0,
        ),
      ],
      ledgerCallbacks,
    );
    if (template.refusal != null) return template.refusal!;
    return CollectionUnrollRefused(
      reason: CollectionUnrollRefusal.runtimeValue,
      detail: _kRuntimeForDetail,
      location: element,
      runtimeLoop: CollectionRuntimeLoopCandidate(
        iterable: iterable,
        binding: variables.first,
        identifier: 'item',
        template: template.branch!,
        bindings: resolution.bindings,
        pattern: parts.pattern,
        patternVariables: variables,
        loop: element,
      ),
    );
  }

  CollectionUnrollRefused _nonListRefusal(
    Expression expression,
    AstNode location, {
    required String staticDetail,
    required String runtimeDetail,
  }) {
    final staticShape = _isStaticallyKnownNonList(expression);
    return _refuse(
      staticShape
          ? CollectionUnrollRefusal.unsupportedShape
          : CollectionUnrollRefusal.runtimeValue,
      staticShape ? staticDetail : runtimeDetail,
      location,
    );
  }
}

bool _isStaticallyKnownNonList(Expression expression) {
  if (expression is SetOrMapLiteral ||
      (expression is Literal && expression is! ListLiteral)) {
    return true;
  }
  if (expression is! InstanceCreationExpression) return false;
  final constructor = expression.constructorName.element;
  final type = expression.staticType;
  if (constructor == null ||
      constructor.isFactory ||
      type is! InterfaceType ||
      type.isDartCoreObject) {
    return false;
  }
  return !type.isDartCoreList &&
      !type.allSupertypes.any((supertype) => supertype.isDartCoreList);
}

final class _SemanticCallbackState {
  _SemanticCallbackState(
    this.probe,
    this.budget, {
    required this.root,
    required this.unchargedRoot,
    required this.stopAtNestedLists,
  });

  final CollectionSemanticProbe probe;
  final CollectionUnrollBudget budget;
  final AstNode root;
  final AstNode? unchargedRoot;
  final bool stopAtNestedLists;
  final Set<AstNode> active = HashSet<AstNode>.identity();
  final Map<Expression, Set<Expression>> _sourcesByAuthoredCallback =
      HashMap<Expression, Set<Expression>>.identity();
  final List<_CollectionCallbackOccurrence> occurrences = [];
  bool exhausted = false;

  void inspect(
    AstNode node,
    Map<Element, Expression> bindings, {
    Expression? callbackOccurrence,
  }) {
    if (exhausted || active.contains(node)) return;
    node.accept(
      _SemanticCallbackVisitor(this, bindings, callbackOccurrence),
    );
  }

  void record(Expression source, Expression authoredExpression) {
    final sources = _sourcesByAuthoredCallback.putIfAbsent(
      authoredExpression,
      HashSet<Expression>.identity,
    );
    if (!sources.add(source)) return;
    occurrences.add(
      _CollectionCallbackOccurrence(
        source: source,
        authoredExpression: authoredExpression,
      ),
    );
  }
}

final class _SemanticCallbackVisitor extends UnifyingAstVisitor<void> {
  _SemanticCallbackVisitor(
    this.state,
    this.bindings,
    this.callbackOccurrence,
  );

  final _SemanticCallbackState state;
  final Map<Element, Expression> bindings;
  final Expression? callbackOccurrence;

  @override
  void visitNode(AstNode node) {
    if (state.stopAtNestedLists &&
        node is ListLiteral &&
        !identical(node, state.root)) {
      return;
    }
    if (state.exhausted || !state.active.add(node)) return;
    try {
      if (!identical(node, state.unchargedRoot) &&
          !state.budget.tryChargeWork()) {
        state.exhausted = true;
        return;
      }
      if (node is Expression) {
        final walk = state.probe._walk(node, bindings, state.budget);
        if (walk.workLimitExceeded) {
          state.exhausted = true;
          return;
        }
        final unchanged =
            walk.terminals.length == 1 &&
            identical(walk.terminals.single.expression, node) &&
            identical(walk.terminals.single.bindings, bindings);
        if (!unchanged) {
          for (final terminal in walk.terminals) {
            state.inspect(
              terminal.expression,
              terminal.bindings,
              callbackOccurrence: _isCallback(terminal.expression)
                  ? callbackOccurrence ?? node
                  : null,
            );
          }
          return;
        }
        if (_isCallback(node)) {
          state.record(node, callbackOccurrence ?? node);
          return;
        }
        // A call computing a plain value consumes its callbacks itself.
        if (node is MethodInvocation && _computesPlainValue(node.staticType)) {
          node.target?.accept(this);
          return;
        }
      }
      super.visitNode(node);
    } finally {
      state.active.remove(node);
    }
  }
}

/// The callback probe result and its exact source expressions when present.
final class _CollectionCallbackSources {
  /// Creates a callback source probe result.
  const _CollectionCallbackSources({
    required this.result,
    this.occurrences = const [],
  });

  /// Whether a callback was found or the bounded walk was exhausted.
  final CollectionCallbackProbeResult result;

  /// Every authored callback occurrence and its exact source.
  final List<_CollectionCallbackOccurrence> occurrences;
}

final class _CollectionCallbackOccurrence {
  const _CollectionCallbackOccurrence({
    required this.source,
    required this.authoredExpression,
  });

  final Expression source;
  final Expression authoredExpression;
}

final class _PatternVariables extends RecursiveAstVisitor<void> {
  _PatternVariables(this.variables);

  final List<Element> variables;

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    if (node.declaredFragment?.element case final element?) {
      variables.add(element);
    }
  }
}

bool _computesPlainValue(DartType? type) =>
    type is InterfaceType &&
    classifyHoistType(type) is! HoistIsWidget &&
    ![type, ...type.allSupertypes].any(
      (candidate) => candidate.isDartCoreIterable || candidate.isDartCoreMap,
    );
