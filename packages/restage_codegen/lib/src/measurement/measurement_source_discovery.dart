import 'dart:collection';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/collection_unroll.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/measurement/measurement_event_occurrence.dart';
import 'package:restage_codegen/src/measurement/measurement_resolved_event.dart';
import 'package:restage_codegen/src/modal_sheet_recognition.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The source-root authority that admitted a static widget expression.
enum MeasurementSourceAuthority {
  /// An exact `package:restage` `@PaywallSource` root.
  paywall,

  /// An exact `package:restage` `@ScreenSource` root.
  screen;
}

/// Whether a source expression yielded a complete static discovery closure.
enum MeasurementSourceDiscoveryDisposition {
  /// Every discovered widget node and callback slot is statically resolved.
  accepted,

  /// A source marker, widget, slot, or structural child was ambiguous.
  rejected;
}

/// Analyzer-owned compiler material for one admitted source root.
///
/// This is deliberately an internal build-time input. It contains resolved AST
/// and element facts, never a runtime widget instance, key, source offset, or
/// display copy.
final class MeasurementSourceDiscoveryInput {
  /// Creates one source-discovery input.
  MeasurementSourceDiscoveryInput({
    required this.authority,
    required this.sourceClass,
    required this.rootExpression,
    required this.catalog,
    Map<String, CustomWidgetBlueprint> inlinedCustomWidgetBlueprints = const {},
    Map<String, String> inlinedCustomWidgetCollectionRefusals = const {},
    Map<Element, Expression> rootLocalBindings = const {},
  })  : inlinedCustomWidgetBlueprints = Map.unmodifiable(
          inlinedCustomWidgetBlueprints,
        ),
        inlinedCustomWidgetCollectionRefusals = Map.unmodifiable(
          inlinedCustomWidgetCollectionRefusals,
        ),
        rootLocalBindings = Map.unmodifiable(rootLocalBindings);

  /// Exact source-root annotation authority.
  final MeasurementSourceAuthority authority;

  /// Resolved class carrying the source-root annotation.
  final ClassElement sourceClass;

  /// Resolved expression returned by the source root's effective `build()`.
  final Expression rootExpression;

  /// The root `build()`'s leading `final` locals, keyed by element. A widget
  /// held in one resolves to its initializer at the widget position.
  final Map<Element, Expression> rootLocalBindings;

  /// Exact merged catalog used by the same compiler pass.
  final Catalog catalog;

  /// Compiler-captured bodies for custom widgets that actually inline.
  ///
  /// A strict custom-widget occurrence without an entry here is opaque when it
  /// has one exact registered catalog entry. It remains a static boundary, and
  /// its private descendants are not discovered.
  final Map<String, CustomWidgetBlueprint> inlinedCustomWidgetBlueprints;

  /// Static collection refusals produced with the supplied blueprints.
  final Map<String, String> inlinedCustomWidgetCollectionRefusals;
}

/// Resolved provenance for one source-root closure.
///
/// This is a compiler locator only. It is not a point identity and no
/// canonical byte or hash is derived from it.
final class MeasurementSourceProvenance {
  MeasurementSourceProvenance._({
    required this.authority,
    required this.sourceLibraryUri,
    required this.sourceClassName,
  });

  /// Source-root authority that admitted this closure.
  final MeasurementSourceAuthority authority;

  /// Resolved library of the source root.
  final String sourceLibraryUri;

  /// Resolved source-root class name.
  final String sourceClassName;

  /// Diagnostic-only resolved source identity.
  String get resolvedSourceIdentity => '$sourceLibraryUri#$sourceClassName';
}

/// One statically resolved Flutter node in a compiled source closure.
///
/// [structuralOccurrenceKey] is only a deterministic compiler locator for the
/// external code-identity ledger. It combines resolved source/widget/slot
/// facts; a collection ordinal is never sufficient identity by itself.
///
/// A node is static discovery material used to reconcile strict source events.
final class MeasurementDiscoveredNode {
  MeasurementDiscoveredNode._({
    required this.sourceProvenance,
    required this.occurrence,
    required List<String> inlinedCustomWidgetIdentities,
  }) : inlinedCustomWidgetIdentities = List.unmodifiable(
          inlinedCustomWidgetIdentities,
        );

  /// Root source and compiler authority that owns the node.
  final MeasurementSourceProvenance sourceProvenance;

  /// Exact structural occurrence used during marker emission.
  final MeasurementWidgetOccurrence occurrence;

  /// Deterministic static occurrence locator for ledger reconciliation.
  String get structuralOccurrenceKey => occurrence.structuralOccurrenceKey;

  /// Direct static Flutter-parent locator, absent for a root node.
  String? get parentStructuralOccurrenceKey =>
      occurrence.parentStructuralOccurrenceKey;

  /// Exact resolved Flutter widget declaration identity.
  String get resolvedWidgetIdentity => occurrence.widgetIdentity;

  /// Resolved custom definitions crossed while statically inlining this node.
  final List<String> inlinedCustomWidgetIdentities;
}

/// One strict compiler-known event slot discovered in source.
final class MeasurementDiscoveredEvent {
  MeasurementDiscoveredEvent._({
    required this.node,
    required this.resolvedEvent,
    required this.sourceExpression,
    required this.emissionOccurrence,
  });

  /// Static node owning the exact callback slot.
  final MeasurementDiscoveredNode node;

  /// Strict Flutter or opaque-catalog identity derived from analyzer elements.
  final MeasurementResolvedEvent resolvedEvent;

  /// Exact callback expression selected by semantic source resolution.
  final Expression sourceExpression;

  /// Exact structural callback position that can emit this route marker.
  final MeasurementEventOccurrence emissionOccurrence;
}

/// Complete source-discovery result, empty on rejection.
final class MeasurementSourceDiscoveryResult {
  MeasurementSourceDiscoveryResult._accepted({
    required this.sourceProvenance,
    required List<MeasurementDiscoveredNode> nodes,
    required List<MeasurementDiscoveredEvent> events,
  })  : disposition = MeasurementSourceDiscoveryDisposition.accepted,
        rejectionReason = null,
        nodes = List.unmodifiable(nodes),
        events = List.unmodifiable(events);

  MeasurementSourceDiscoveryResult._rejected({required String reason})
      : disposition = MeasurementSourceDiscoveryDisposition.rejected,
        rejectionReason = reason,
        sourceProvenance = null,
        nodes = const [],
        events = const [];

  /// Whether the complete static source closure was available.
  final MeasurementSourceDiscoveryDisposition disposition;

  /// Resolved root provenance on acceptance.
  final MeasurementSourceProvenance? sourceProvenance;

  /// Static Flutter nodes ordered by their structural occurrence locator.
  final List<MeasurementDiscoveredNode> nodes;

  /// Resolved event slots ordered by node and slot identity.
  final List<MeasurementDiscoveredEvent> events;

  /// Fail-closed reason when static discovery could not be complete.
  final String? rejectionReason;
}

/// Whether a `FlowSource` accepted a supplied static artifact closure.
enum MeasurementFlowSourceClosureDisposition {
  /// The exact resolved flow authority and every supplied artifact succeeded.
  accepted,

  /// The flow authority or one supplied source artifact was ambiguous.
  rejected;
}

/// Existing flow-compiler output made available to Measurement for closure.
///
/// A `FlowSource` is a descriptor graph, not a Flutter widget body. The flow
/// compiler therefore supplies its already-resolved static screen/paywall
/// artifact discoveries here instead of this API guessing a relation from
/// descriptor names or source text.
final class MeasurementFlowSourceClosureInput {
  /// Creates a FlowSource artifact-closure input.
  MeasurementFlowSourceClosureInput({
    required this.flowSourceClass,
    required Iterable<MeasurementSourceDiscoveryResult>
        staticArtifactDiscoveries,
  }) : staticArtifactDiscoveries = List.unmodifiable(staticArtifactDiscoveries);

  /// Resolved class carrying the exact `@FlowSource` annotation.
  final ClassElement flowSourceClass;

  /// Exact statically emitted ScreenSource/PaywallSource artifact closures.
  final List<MeasurementSourceDiscoveryResult> staticArtifactDiscoveries;
}

/// Result of validating FlowSource authority over supplied static artifacts.
final class MeasurementFlowSourceClosureResult {
  MeasurementFlowSourceClosureResult._accepted({
    required this.resolvedFlowIdentity,
    required List<MeasurementDiscoveredNode> nodes,
    required List<MeasurementDiscoveredEvent> events,
  })  : disposition = MeasurementFlowSourceClosureDisposition.accepted,
        rejectionReason = null,
        nodes = List.unmodifiable(nodes),
        events = List.unmodifiable(events);

  MeasurementFlowSourceClosureResult._rejected({required String reason})
      : disposition = MeasurementFlowSourceClosureDisposition.rejected,
        rejectionReason = reason,
        resolvedFlowIdentity = null,
        nodes = const [],
        events = const [];

  /// Whether the complete static artifact closure was admitted.
  final MeasurementFlowSourceClosureDisposition disposition;

  /// Resolved FlowSource class identity on acceptance.
  final String? resolvedFlowIdentity;

  /// Flattened source nodes from the exact supplied artifact closure.
  final List<MeasurementDiscoveredNode> nodes;

  /// Flattened callback slots from the exact supplied artifact closure.
  final List<MeasurementDiscoveredEvent> events;

  /// Fail-closed reason when the closure could not be trusted.
  final String? rejectionReason;
}

/// Discovers ordinary Flutter nodes and callback slots from resolved source.
///
/// It deliberately has no runtime, output-emission, carrier, or host role. A
/// caller reconciles these deterministic locators with the code-identity
/// ledger and then delegates to `MeasurementCompilerBoundary`.
abstract final class MeasurementSourceDiscovery {
  /// Discovers one resolved ScreenSource or PaywallSource widget closure.
  static MeasurementSourceDiscoveryResult discover(
    MeasurementSourceDiscoveryInput input,
  ) {
    try {
      return _MeasurementSourceDiscovery(input).discover();
    } on Object catch (error) {
      return MeasurementSourceDiscoveryResult._rejected(
        reason: error.toString(),
      );
    }
  }

  /// Validates a resolved FlowGraph/FlowSource artifact closure.
  static MeasurementFlowSourceClosureResult closeFlowSourceV1(
    MeasurementFlowSourceClosureInput input,
  ) {
    try {
      final flowClass = input.flowSourceClass;
      if (!_hasResolvedAnnotationFromOriginAny(
        flowClass,
        annotationNames: const {'FlowGraph', 'FlowSource'},
        libraryOrigin: _kRestageOrigin,
      )) {
        throw ArgumentError(
          'Flow measurement authority requires a resolved package:restage '
          '@FlowGraph or @FlowSource annotation',
        );
      }
      if (!_extendsResolvedType(
        flowClass,
        typeName: 'RestageFlow',
        libraryOrigin: _kRestageOrigin,
      )) {
        throw ArgumentError(
          'A Flow measurement authority must resolve to RestageFlow',
        );
      }

      final nodes = <MeasurementDiscoveredNode>[];
      final events = <MeasurementDiscoveredEvent>[];
      final nodeKeys = <String>{};
      final eventKeys = <String>{};
      for (final discovery in input.staticArtifactDiscoveries) {
        if (discovery.disposition !=
            MeasurementSourceDiscoveryDisposition.accepted) {
          throw ArgumentError(
            'A FlowSource static artifact closure contains a rejected source',
          );
        }
        for (final node in discovery.nodes) {
          if (!nodeKeys.add(node.structuralOccurrenceKey)) {
            throw ArgumentError(
              'A FlowSource static artifact closure repeats a node locator',
            );
          }
          nodes.add(node);
        }
        for (final event in discovery.events) {
          final eventKey = _eventKey(event);
          if (!eventKeys.add(eventKey)) {
            throw ArgumentError(
              'A FlowSource static artifact closure repeats a callback slot',
            );
          }
          events.add(event);
        }
      }
      nodes.sort(
        (left, right) => left.structuralOccurrenceKey.compareTo(
          right.structuralOccurrenceKey,
        ),
      );
      events.sort((left, right) => _eventKey(left).compareTo(_eventKey(right)));
      return MeasurementFlowSourceClosureResult._accepted(
        resolvedFlowIdentity: _classIdentity(flowClass),
        nodes: nodes,
        events: events,
      );
    } on Object catch (error) {
      return MeasurementFlowSourceClosureResult._rejected(
        reason: error.toString(),
      );
    }
  }
}

const String _kRestageOrigin = 'package:restage';
const String _kCatalogSchemaOrigin = 'package:rfw_catalog_schema';
const String _kFlutterOrigin = 'package:flutter/';

final class _MeasurementSourceDiscovery {
  _MeasurementSourceDiscovery(this.input);

  final MeasurementSourceDiscoveryInput input;
  final List<MeasurementDiscoveredNode> _nodes = [];
  final List<MeasurementDiscoveredEvent> _events = [];
  final Set<String> _nodeKeys = {};
  final Set<String> _eventKeys = {};
  final CollectionSemanticTraversalSession _collectionSession =
      CollectionSemanticTraversalSession();

  MeasurementSourceDiscoveryResult discover() {
    final provenance = _sourceProvenance();
    final rootContext = _WidgetVisitContext.root(
      provenance,
      input.rootExpression,
      input.rootLocalBindings,
    );
    _admitOrdinaryLeaf(input.rootExpression, rootContext);
    _visitWidgetExpression(
      input.rootExpression,
      rootContext,
    );
    if (_nodes.isEmpty) {
      throw ArgumentError(
        'Measurement source discovery requires one statically resolved '
        'Flutter root widget',
      );
    }
    _nodes.sort(
      (left, right) => left.structuralOccurrenceKey.compareTo(
        right.structuralOccurrenceKey,
      ),
    );
    _events.sort((left, right) => _eventKey(left).compareTo(_eventKey(right)));
    return MeasurementSourceDiscoveryResult._accepted(
      sourceProvenance: provenance,
      nodes: _nodes,
      events: _events,
    );
  }

  MeasurementSourceProvenance _sourceProvenance() {
    final annotationNames = switch (input.authority) {
      MeasurementSourceAuthority.paywall => const {
          'Paywall',
          'PaywallSource',
        },
      MeasurementSourceAuthority.screen => const {
          'Screen',
          'ScreenSource',
        },
    };
    if (!_hasResolvedAnnotationFromOriginAny(
      input.sourceClass,
      annotationNames: annotationNames,
      libraryOrigin: _kRestageOrigin,
    )) {
      throw ArgumentError(
        'Measurement ${input.authority.name} discovery requires a resolved '
        'package:restage annotation from the accepted set '
        '${annotationNames.toList()..sort()}',
      );
    }
    if (!_extendsResolvedType(
          input.sourceClass,
          typeName: 'StatelessWidget',
          libraryOrigin: _kFlutterOrigin,
        ) &&
        !_extendsResolvedType(
          input.sourceClass,
          typeName: 'StatefulWidget',
          libraryOrigin: _kFlutterOrigin,
        )) {
      throw ArgumentError(
        'Measurement source roots must resolve to Flutter StatelessWidget or '
        'StatefulWidget',
      );
    }
    final sourceClassName = input.sourceClass.name;
    final sourceLibraryUri = input.sourceClass.library.identifier;
    if (sourceClassName == null ||
        sourceClassName.isEmpty ||
        sourceLibraryUri.isEmpty) {
      throw ArgumentError('Measurement source roots require stable elements');
    }
    return MeasurementSourceProvenance._(
      authority: input.authority,
      sourceLibraryUri: sourceLibraryUri,
      sourceClassName: sourceClassName,
    );
  }

  void _visitWidgetExpression(
    Expression source,
    _WidgetVisitContext context,
  ) {
    final resolved = _resolvedWidgetSource(source, context);
    final expression = resolved.expression;
    if (expression is! InstanceCreationExpression) {
      throw ArgumentError(
        'A measurement widget occurrence must be a statically resolved '
        'constructor expression',
      );
    }

    final classElement = expression.constructorName.type.element;
    if (classElement is! InterfaceElement) {
      throw ArgumentError(
        'A measurement widget occurrence requires a resolved class element',
      );
    }
    if (_isFlutterWidgetClass(classElement)) {
      _visitFlutterWidget(expression, classElement, resolved.context);
      return;
    }
    if (!_hasResolvedAnnotationFromOrigin(
      classElement,
      annotationName: 'RestageWidget',
      libraryOrigin: _kCatalogSchemaOrigin,
    )) {
      throw ArgumentError(
        'A non-Flutter widget occurrence must resolve to the real '
        '@RestageWidget marker',
      );
    }
    _visitCustomWidget(expression, classElement, resolved.context);
  }

  void _visitFlutterWidget(
    InstanceCreationExpression expression,
    InterfaceElement widgetClass,
    _WidgetVisitContext context,
  ) {
    final catalogEntry = _catalogEntryFor(expression, widgetClass);
    final node = _recordNode(
      context: context,
      widgetClass: widgetClass,
    );
    final arguments = _resolvedArguments(expression, widgetClass);
    final eventPropertyNames = {
      for (final property in catalogEntry.properties)
        if (property.type == PropertyType.event) property.name,
    };
    final childOrdinals = <String, int>{};
    for (final argument in arguments) {
      final parameter = argument.parameter;
      final value = argument.value;
      final parameterName = parameter.name;
      if (parameterName == null || parameterName.isEmpty) {
        throw ArgumentError('A measurement widget slot requires a stable name');
      }
      if (eventPropertyNames.contains(parameterName)) {
        _recordEvent(
          node: node,
          widgetClass: widgetClass,
          parameter: parameter,
          value: value,
          context: context,
        );
        continue;
      }
      if (_isFlutterKeyType(parameter.type)) {
        // Flutter key values are not traversal inputs and never contribute to
        // Measurement identity or source provenance.
        continue;
      }
      if (_isWidgetType(parameter.type)) {
        final ordinal = childOrdinals.update(
          parameterName,
          (value) => value + 1,
          ifAbsent: () => 0,
        );
        _visitWidgetExpression(
          value,
          context.child(
            parent: node.occurrence,
            slot: parameter,
            ordinal: ordinal,
          ),
        );
        continue;
      }
      if (_isWidgetListType(parameter.type)) {
        _visitWidgetList(
          value,
          context: context,
          parent: node.occurrence,
          slot: parameter,
        );
        continue;
      }
      if (_returnsWidget(parameter.type)) {
        throw ArgumentError(
          'Dynamic Flutter widget builders are not a static measurement '
          'closure',
        );
      }
    }
  }

  void _visitWidgetList(
    Expression source, {
    required _WidgetVisitContext context,
    required MeasurementWidgetOccurrence parent,
    required FormalParameterElement slot,
  }) {
    final resolved = _resolvedWidgetSource(source, context);
    final semantics = _collectionSemanticProbe(resolved.context);
    final budget = CollectionUnrollBudget();
    final resolution = semantics.resolve(
      resolved.expression,
      resolved.context.plainExpressionBindings,
      budget,
    );
    if (resolution.workLimitExceeded) {
      throw ArgumentError(budget.workRefusal(resolved.expression).detail);
    }
    final expression = _withoutParentheses(resolution.expression);
    if (expression is! ListLiteral) {
      throw ArgumentError(
        'A measurement widget list must be a static literal list',
      );
    }
    var ordinal = 0;
    final traversal = traverseCollectionList(
      expression,
      semantics: semantics,
      budget: budget,
      session: _collectionSession,
      bindings: resolution.bindings,
    );
    for (final entry in traversal.entries) {
      switch (entry) {
        case CollectionListRefusal(:final refusal):
          throw ArgumentError(refusal.detail);
        case CollectionListElement(:final occurrence):
          _visitWidgetExpression(
            occurrence.terminalExpression,
            resolved.context
                .child(
                  parent: parent,
                  slot: slot,
                  ordinal: ordinal,
                )
                .withCollectionOccurrence(occurrence),
          );
          ordinal++;
      }
    }
  }

  CollectionSemanticProbe _collectionSemanticProbe(
    _WidgetVisitContext context,
  ) =>
      CollectionSemanticProbe(
        bindingFor: (identifier) {
          final element = _referencedElement(identifier);
          return element == null
              ? null
              : context.expressionBindings[element]?.expression;
        },
        helperFor: (invocation) {
          if (!isArtifactHelperInvocation(invocation)) return null;
          final executable = invocation.methodName.element;
          if (executable == null) return null;
          final definition = context.helperDefinitions[executable];
          if (definition == null) return null;
          final bindings = bindHelperArguments(
            definition.params,
            invocation.argumentList.arguments.toList(growable: false),
          );
          if (bindings == null) return null;
          return CollectionResolvedHelper(
            body: definition.body,
            parameterBindings: bindings,
          );
        },
      );

  void _admitOrdinaryLeaf(
    Expression expression,
    _WidgetVisitContext context, {
    Iterable<Expression> convergentSources = const [],
  }) {
    final refusal = _collectionSession.admitOrdinaryLeaf(
      expression,
      _collectionSemanticProbe(context),
      bindings: context.plainExpressionBindings,
      convergentSources: convergentSources,
    );
    if (refusal != null) throw ArgumentError(refusal.detail);
  }

  ({Expression expression, _WidgetVisitContext context}) _resolvedWidgetSource(
    Expression source,
    _WidgetVisitContext context,
  ) {
    final expression = _withoutParentheses(source);
    final binding = _boundWidgetExpression(expression, context);
    if (binding != null) return _resolvedWidgetSource(binding, context);
    final helper = _resolvedInlinedHelper(expression, context);
    if (helper == null) return (expression: expression, context: context);
    return _resolvedWidgetSource(
      helper.definition.body,
      context.enterHelper(
        helper: helper.executable,
        helperIdentity: helper.identity,
        parameterBindings: helper.parameterBindings,
      ),
    );
  }

  void _visitCustomWidget(
    InstanceCreationExpression expression,
    InterfaceElement customClass,
    _WidgetVisitContext context,
  ) {
    final customIdentity = _classIdentity(customClass);
    if (context.inlinedCustomWidgetIdentities.contains(customIdentity)) {
      throw ArgumentError(
        'A statically inlined custom-widget cycle is invalid',
      );
    }
    final blueprint = input.inlinedCustomWidgetBlueprints[customIdentity];
    if (blueprint == null) {
      final collectionRefusal =
          input.inlinedCustomWidgetCollectionRefusals[customIdentity];
      if (collectionRefusal != null) {
        throw ArgumentError(collectionRefusal);
      }
      _requireRegisteredOpaqueCustomWidget(expression, customClass);
      final node = _recordNode(
        context: context,
        widgetClass: customClass,
      );
      final slots = MeasurementResolvedOpaqueCustomWidgetEvent.discoverSlots(
        sourceRoot: input.sourceClass,
        occurrence: expression,
        catalog: input.catalog,
      );
      final arguments = _resolvedArguments(expression, customClass);
      for (final slot in slots) {
        final value = arguments
            .singleWhere((argument) => argument.parameter == slot.eventElement)
            .value;
        final resolvedSource = _resolvedEventSource(
          node: node,
          eventElement: slot.eventElement,
          value: value,
          context: context,
        );
        _recordResolvedEvent(
          node: node,
          resolvedEvent: slot,
          sourceExpression: resolvedSource.expression,
          emissionOccurrence: resolvedSource.emissionOccurrence,
        );
      }
      // The occurrence and its declared slots are in the emitted graph. Its
      // private Flutter implementation remains a terminal compiler boundary.
      return;
    }
    final node = _recordNode(
      context: context,
      widgetClass: customClass,
    );
    final bindings = _customWidgetBindings(
      expression,
      customClass,
      node.occurrence,
    );
    final inlineContext = context.enterInline(
      parent: node.occurrence,
      fieldBindings: bindings,
      inlinedDefinitions: blueprint.inlined,
    );
    _admitOrdinaryLeaf(
      blueprint.buildExpression,
      inlineContext,
      convergentSources: bindings.values.map((binding) => binding.expression),
    );
    _visitWidgetExpression(blueprint.buildExpression, inlineContext);
  }

  MeasurementDiscoveredNode _recordNode({
    required _WidgetVisitContext context,
    required InterfaceElement widgetClass,
  }) {
    final occurrence = context.occurrenceScope.widget(widgetClass);
    if (!_nodeKeys.add(occurrence.structuralOccurrenceKey)) {
      throw ArgumentError('A static measurement node occurrence is duplicated');
    }
    final node = MeasurementDiscoveredNode._(
      sourceProvenance: context.sourceProvenance,
      occurrence: occurrence,
      inlinedCustomWidgetIdentities: context.inlinedCustomWidgetIdentities,
    );
    _nodes.add(node);
    return node;
  }

  void _recordEvent({
    required MeasurementDiscoveredNode node,
    required InterfaceElement widgetClass,
    required FormalParameterElement parameter,
    required Expression value,
    required _WidgetVisitContext context,
  }) {
    final resolvedSource = _resolvedEventSource(
      node: node,
      eventElement: parameter,
      value: value,
      context: context,
    );
    final sourceExpression = resolvedSource.expression;
    if (_withoutParentheses(sourceExpression) is NullLiteral) return;
    if (!_isFunctionType(sourceExpression.staticType)) {
      throw ArgumentError(
        'A compiler-known Flutter event slot requires a statically resolved '
        'function value',
      );
    }
    if (_isFlutterStateMethodTearOff(sourceExpression)) {
      throw ArgumentError(
        'A Flutter State method tear-off lowers to an RFW state update rather '
        'than one host event handler',
      );
    }
    final resolvedEvent = MeasurementResolvedFlutterEvent.fromResolvedElements(
      widgetClass: widgetClass,
      eventElement: parameter,
    );
    _recordResolvedEvent(
      node: node,
      resolvedEvent: resolvedEvent,
      sourceExpression: sourceExpression,
      emissionOccurrence: resolvedSource.emissionOccurrence,
    );
  }

  ({
    Expression expression,
    MeasurementEventOccurrence emissionOccurrence,
  }) _resolvedEventSource({
    required MeasurementDiscoveredNode node,
    required Element eventElement,
    required Expression value,
    required _WidgetVisitContext context,
  }) {
    var sourceExpression = value;
    final directOccurrence = node.occurrence.event(eventElement);
    final forwardingOccurrences = <MeasurementEventOccurrence>[];
    final seenBindings = <Element>{};
    while (true) {
      final binding = _boundExpression(sourceExpression, context);
      if (binding == null) break;
      final element = _referencedElement(_withoutParentheses(sourceExpression));
      if (element == null || !seenBindings.add(element)) {
        throw ArgumentError('A static measurement binding cycle is invalid');
      }
      final forwardingOccurrence = binding.eventOccurrence;
      if (forwardingOccurrence != null &&
          !forwardingOccurrences.contains(forwardingOccurrence)) {
        forwardingOccurrences.add(forwardingOccurrence);
      }
      sourceExpression = binding.expression;
    }
    final emissionOccurrence = forwardingOccurrences.isEmpty
        ? directOccurrence
        : forwardingOccurrences.last;
    return (
      expression: sourceExpression,
      emissionOccurrence: emissionOccurrence,
    );
  }

  void _recordResolvedEvent({
    required MeasurementDiscoveredNode node,
    required MeasurementResolvedEvent resolvedEvent,
    required Expression sourceExpression,
    required MeasurementEventOccurrence emissionOccurrence,
  }) {
    if (recogniseModalSheetTrigger(sourceExpression)
        is! ModalSheetNotRecognised) {
      // The callback becomes a declarative sheet rather than one event
      // handler, so no route can ride on it. Reject the whole surface.
      throw ArgumentError(
        'the modal-sheet lowering carries this callback into a declarative '
        'sheet rather than one event handler',
      );
    }
    final event = MeasurementDiscoveredEvent._(
      node: node,
      resolvedEvent: resolvedEvent,
      sourceExpression: sourceExpression,
      emissionOccurrence: emissionOccurrence,
    );
    if (!_eventKeys.add(_eventKey(event))) {
      throw ArgumentError(
        'A static measurement callback slot is duplicated',
      );
    }
    _events.add(event);
  }

  WidgetEntry _catalogEntryFor(
    InstanceCreationExpression expression,
    InterfaceElement widgetClass,
  ) {
    final widgetIdentity = _classIdentity(widgetClass);
    final constructorName = expression.constructorName.name?.name;
    final suffix = constructorName == null || constructorName.isEmpty
        ? ''
        : '.$constructorName';
    final flutterType = '$widgetIdentity$suffix';
    final matches = input.catalog.widgets
        .where((entry) => entry.flutterType == flutterType)
        .toList(growable: false);
    if (matches.length != 1) {
      throw ArgumentError(
        'A measurement Flutter widget must have one exact catalog entry for '
        '$flutterType',
      );
    }
    return matches.single;
  }

  void _requireRegisteredOpaqueCustomWidget(
    InstanceCreationExpression expression,
    InterfaceElement customClass,
  ) {
    final customIdentity = _classIdentity(customClass);
    final constructorName = expression.constructorName.name?.name;
    final suffix = constructorName == null || constructorName.isEmpty
        ? ''
        : '.$constructorName';
    final flutterType = '$customIdentity$suffix';
    final matches = input.catalog.widgets
        .where((entry) => entry.flutterType == flutterType)
        .toList(growable: false);
    if (matches.length != 1 ||
        WidgetLibrary.builtInByNamespace(matches.single.library.namespace) !=
            null) {
      throw ArgumentError(
        'A non-inlined custom widget must resolve to one exact registered '
        'catalog entry for $flutterType',
      );
    }
  }

  List<_ResolvedArgument> _resolvedArguments(
    InstanceCreationExpression expression,
    InterfaceElement widgetClass,
  ) {
    final constructor = expression.constructorName.element;
    if (constructor is! ConstructorElement ||
        constructor.enclosingElement != widgetClass) {
      throw ArgumentError(
        'A measurement Flutter widget requires a resolved constructor element',
      );
    }
    final positionalParameters = constructor.formalParameters
        .where((parameter) => !parameter.isNamed)
        .toList(growable: false);
    var positionalIndex = 0;
    final arguments = <_ResolvedArgument>[];
    for (final argument in expression.argumentList.arguments) {
      if (argument case final NamedExpression named) {
        final parameter = named.name.label.element;
        if (parameter is! FormalParameterElement) {
          throw ArgumentError(
            'A measurement widget named slot requires a resolved parameter',
          );
        }
        arguments.add(
          _ResolvedArgument(
            parameter: parameter,
            value: named.expression,
          ),
        );
        continue;
      }
      if (positionalIndex >= positionalParameters.length) {
        throw ArgumentError(
          'A measurement widget positional slot exceeds its constructor',
        );
      }
      arguments.add(
        _ResolvedArgument(
          parameter: positionalParameters[positionalIndex],
          value: argument,
        ),
      );
      positionalIndex++;
    }
    return arguments;
  }

  Map<FieldElement, _MeasurementExpressionBinding> _customWidgetBindings(
    InstanceCreationExpression expression,
    InterfaceElement customClass,
    MeasurementWidgetOccurrence occurrence,
  ) {
    final constructor = expression.constructorName.element;
    if (constructor is! ConstructorElement ||
        constructor.enclosingElement != customClass) {
      throw ArgumentError(
        'A statically inlined custom widget requires a resolved constructor',
      );
    }
    final positionalParameters = constructor.formalParameters
        .where((parameter) => !parameter.isNamed)
        .toList(growable: false);
    var positionalIndex = 0;
    final bindings = <FieldElement, _MeasurementExpressionBinding>{};
    for (final argument in expression.argumentList.arguments) {
      FormalParameterElement? parameter;
      Expression value;
      if (argument case final NamedExpression named) {
        final resolved = named.name.label.element;
        if (resolved is! FormalParameterElement) {
          throw ArgumentError(
            'A statically inlined custom-widget slot must resolve',
          );
        }
        parameter = resolved;
        value = named.expression;
      } else {
        if (positionalIndex >= positionalParameters.length) {
          throw ArgumentError(
            'A statically inlined custom widget has too many positional slots',
          );
        }
        parameter = positionalParameters[positionalIndex];
        value = argument;
        positionalIndex++;
      }
      if (parameter is FieldFormalParameterElement) {
        final field = parameter.field;
        if (field == null) {
          throw ArgumentError(
            'A statically inlined custom-widget field parameter must resolve',
          );
        }
        final binding = _MeasurementExpressionBinding(
          expression: value,
          eventOccurrence: occurrence.event(field),
        );
        final previous = bindings[field];
        if (previous != null && !identical(previous.expression, value)) {
          throw ArgumentError(
            'A statically inlined custom-widget field was bound twice',
          );
        }
        bindings[field] = binding;
      }
    }
    return UnmodifiableMapView(bindings);
  }

  Expression? _boundWidgetExpression(
    Expression expression,
    _WidgetVisitContext context,
  ) =>
      _boundExpression(expression, context)?.expression;

  _MeasurementExpressionBinding? _boundExpression(
    Expression expression,
    _WidgetVisitContext context,
  ) {
    final element = _referencedElement(expression);
    if (element == null) return null;
    final binding = context.expressionBindings[element];
    if (binding != null) return binding;
    if (element is FieldElement &&
        context.inlinedCustomWidgetIdentities.isNotEmpty) {
      throw ArgumentError(
        'A statically inlined widget field has no exact call-site binding',
      );
    }
    return null;
  }

  _ResolvedInlinedHelper? _resolvedInlinedHelper(
    Expression expression,
    _WidgetVisitContext context,
  ) {
    if (expression is! MethodInvocation) return null;
    if (!isArtifactHelperInvocation(expression)) return null;
    final executable = expression.methodName.element;
    if (executable is! ExecutableElement) return null;
    final definition = context.helperDefinitions[executable];
    if (definition == null) return null;
    final helperIdentity = _helperIdentity(executable);
    if (context.inlinedHelperIdentities.contains(helperIdentity)) {
      throw ArgumentError('A statically inlined helper cycle is invalid');
    }
    final parameterBindings = bindHelperArguments(
      definition.params,
      expression.argumentList.arguments.toList(growable: false),
    );
    if (parameterBindings == null) {
      throw ArgumentError(
        'A statically inlined helper requires exact argument bindings',
      );
    }
    return _ResolvedInlinedHelper(
      executable: executable,
      identity: helperIdentity,
      definition: definition,
      parameterBindings: parameterBindings,
    );
  }
}

final class _WidgetVisitContext {
  const _WidgetVisitContext._({
    required this.sourceProvenance,
    required this.occurrenceScope,
    required this.inlinedCustomWidgetIdentities,
    required this.expressionBindings,
    required this.helperDefinitions,
    required this.inlinedHelperIdentities,
  });

  factory _WidgetVisitContext.root(
    MeasurementSourceProvenance provenance,
    Expression rootExpression,
    Map<Element, Expression> rootLocalBindings,
  ) =>
      _WidgetVisitContext._(
        sourceProvenance: provenance,
        occurrenceScope: MeasurementOccurrenceScope.root(
          provenance.resolvedSourceIdentity,
        ),
        inlinedCustomWidgetIdentities: const [],
        expressionBindings: _plainExpressionBindings(rootLocalBindings),
        helperDefinitions: Map.unmodifiable(
          inlinableHelperDefinitionsIn(rootExpression),
        ),
        inlinedHelperIdentities: const [],
      );

  final MeasurementSourceProvenance sourceProvenance;
  final MeasurementOccurrenceScope occurrenceScope;
  final List<String> inlinedCustomWidgetIdentities;
  final Map<Element, _MeasurementExpressionBinding> expressionBindings;
  final Map<Element, HelperDef> helperDefinitions;
  final List<String> inlinedHelperIdentities;

  Map<Element, Expression> get plainExpressionBindings => Map.unmodifiable({
        for (final entry in expressionBindings.entries)
          entry.key: entry.value.expression,
      });

  /// The slot scope continues from this context's scope, so a helper entered
  /// before the slot keys the same way it does in the emitted translation.
  _WidgetVisitContext child({
    required MeasurementWidgetOccurrence parent,
    required FormalParameterElement slot,
    required int ordinal,
  }) =>
      _WidgetVisitContext._(
        sourceProvenance: sourceProvenance,
        occurrenceScope:
            parent.withScope(occurrenceScope).child(slot, ordinal: ordinal),
        inlinedCustomWidgetIdentities: inlinedCustomWidgetIdentities,
        expressionBindings: expressionBindings,
        helperDefinitions: helperDefinitions,
        inlinedHelperIdentities: inlinedHelperIdentities,
      );

  _WidgetVisitContext enterInline({
    required MeasurementWidgetOccurrence parent,
    required Map<FieldElement, _MeasurementExpressionBinding> fieldBindings,
    required InlinedDefinitions inlinedDefinitions,
  }) {
    final customIdentity = parent.widgetIdentity;
    return _WidgetVisitContext._(
      sourceProvenance: sourceProvenance,
      occurrenceScope: parent.enterInlinedBody(),
      inlinedCustomWidgetIdentities: [
        ...inlinedCustomWidgetIdentities,
        customIdentity,
      ],
      // Preserve exact outer field bindings through nested custom calls.
      expressionBindings: Map.unmodifiable({
        ...expressionBindings,
        ...fieldBindings,
        ..._plainExpressionBindings(inlinedDefinitions.localBindings),
      }),
      helperDefinitions: Map.unmodifiable({
        ...helperDefinitions,
        ...inlinedDefinitions.helpers,
      }),
      inlinedHelperIdentities: inlinedHelperIdentities,
    );
  }

  _WidgetVisitContext enterHelper({
    required ExecutableElement helper,
    required String helperIdentity,
    required Map<Element, Expression> parameterBindings,
  }) =>
      _WidgetVisitContext._(
        sourceProvenance: sourceProvenance,
        occurrenceScope: occurrenceScope.enterHelper(helper),
        inlinedCustomWidgetIdentities: inlinedCustomWidgetIdentities,
        expressionBindings: Map.unmodifiable({
          ...expressionBindings,
          ..._plainExpressionBindings(parameterBindings),
        }),
        helperDefinitions: helperDefinitions,
        inlinedHelperIdentities: [
          ...inlinedHelperIdentities,
          helperIdentity,
        ],
      );

  _WidgetVisitContext withCollectionOccurrence(
    CollectionSemanticOccurrence occurrence,
  ) =>
      _WidgetVisitContext._(
        sourceProvenance: sourceProvenance,
        occurrenceScope: occurrenceScope.enterCollectionOccurrence(occurrence),
        inlinedCustomWidgetIdentities: inlinedCustomWidgetIdentities,
        // Traversal bindings contribute the occurrence's own elements; an
        // element this context already binds keeps its binding, which carries
        // the forwarding occurrence a collapsed chain drops.
        expressionBindings: Map.unmodifiable({
          ..._plainExpressionBindings(occurrence.bindings),
          ...expressionBindings,
        }),
        helperDefinitions: helperDefinitions,
        inlinedHelperIdentities: inlinedHelperIdentities,
      );
}

final class _ResolvedArgument {
  const _ResolvedArgument({required this.parameter, required this.value});

  final FormalParameterElement parameter;
  final Expression value;
}

final class _MeasurementExpressionBinding {
  const _MeasurementExpressionBinding({
    required this.expression,
    this.eventOccurrence,
  });

  final Expression expression;
  final MeasurementEventOccurrence? eventOccurrence;
}

Map<Element, _MeasurementExpressionBinding> _plainExpressionBindings(
  Map<Element, Expression> bindings,
) =>
    Map<Element, _MeasurementExpressionBinding>.unmodifiable(
      <Element, _MeasurementExpressionBinding>{
        for (final entry in bindings.entries)
          entry.key: _MeasurementExpressionBinding(expression: entry.value),
      },
    );

final class _ResolvedInlinedHelper {
  const _ResolvedInlinedHelper({
    required this.executable,
    required this.identity,
    required this.definition,
    required this.parameterBindings,
  });

  final ExecutableElement executable;
  final String identity;
  final HelperDef definition;
  final Map<Element, Expression> parameterBindings;
}

String _eventKey(MeasurementDiscoveredEvent event) =>
    '${event.node.structuralOccurrenceKey}\u0000'
    '${event.resolvedEvent.resolvedSemanticIdentity}';

String _classIdentity(InterfaceElement element) =>
    measurementClassIdentity(element);

Expression _withoutParentheses(Expression expression) {
  var current = expression;
  while (current is ParenthesizedExpression) {
    current = current.expression;
  }
  return current;
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
  if (element is PropertyAccessorElement) {
    element = element.variable;
  }
  return element;
}

bool _isFlutterStateMethodTearOff(Expression expression) {
  final element = _referencedElement(_withoutParentheses(expression));
  if (element is! MethodElement) return false;
  final owner = element.enclosingElement;
  return owner is InterfaceElement &&
      _extendsResolvedType(
        owner,
        typeName: 'State',
        libraryOrigin: _kFlutterOrigin,
      );
}

String _helperIdentity(ExecutableElement executable) =>
    measurementHelperIdentity(executable);

bool _hasResolvedAnnotationFromOrigin(
  Element element, {
  required String annotationName,
  required String libraryOrigin,
}) =>
    element.metadata.annotations.any((annotation) {
      final annotationClass = _annotationClass(annotation);
      return annotationClass != null &&
          annotationClass.name == annotationName &&
          _libraryMatchesOrigin(
            annotationClass.library.identifier,
            libraryOrigin,
          );
    });

bool _hasResolvedAnnotationFromOriginAny(
  Element element, {
  required Set<String> annotationNames,
  required String libraryOrigin,
}) =>
    element.metadata.annotations.any((annotation) {
      final annotationClass = _annotationClass(annotation);
      return annotationClass != null &&
          annotationNames.contains(annotationClass.name) &&
          _libraryMatchesOrigin(
            annotationClass.library.identifier,
            libraryOrigin,
          );
    });

InterfaceElement? _annotationClass(ElementAnnotation annotation) {
  final element = annotation.element;
  if (element is ConstructorElement) return element.enclosingElement;
  if (element is PropertyAccessorElement) {
    final type = element.variable.type;
    if (type is InterfaceType) return type.element;
  }
  if (element is FieldElement) {
    final type = element.type;
    if (type is InterfaceType) return type.element;
  }
  final type = annotation.computeConstantValue()?.type;
  return type is InterfaceType ? type.element : null;
}

bool _libraryMatchesOrigin(String libraryUri, String origin) =>
    libraryUri == origin ||
    libraryUri.startsWith(origin.endsWith('/') ? origin : '$origin/');

bool _extendsResolvedType(
  InterfaceElement element, {
  required String typeName,
  required String libraryOrigin,
}) =>
    _typeChain(element).any(
      (candidate) =>
          candidate.name == typeName &&
          _libraryMatchesOrigin(candidate.library.identifier, libraryOrigin),
    );

Iterable<InterfaceElement> _typeChain(InterfaceElement element) sync* {
  yield element;
  yield* element.allSupertypes.map((type) => type.element);
}

bool _isFlutterWidgetClass(InterfaceElement element) =>
    _extendsResolvedType(
      element,
      typeName: 'Widget',
      libraryOrigin: _kFlutterOrigin,
    ) &&
    _libraryMatchesOrigin(element.library.identifier, _kFlutterOrigin);

bool _isWidgetType(DartType type) =>
    type is InterfaceType &&
    _extendsResolvedType(
      type.element,
      typeName: 'Widget',
      libraryOrigin: _kFlutterOrigin,
    );

bool _isWidgetListType(DartType type) {
  if (type is! InterfaceType || type.element.name != 'List') return false;
  final typeArguments = type.typeArguments;
  return typeArguments.length == 1 && _isWidgetType(typeArguments.single);
}

bool _returnsWidget(DartType type) =>
    type is FunctionType && _isWidgetType(type.returnType);

bool _isFlutterKeyType(DartType type) =>
    type is InterfaceType &&
    _extendsResolvedType(
      type.element,
      typeName: 'Key',
      libraryOrigin: _kFlutterOrigin,
    );

bool _isFunctionType(DartType? type) => type is FunctionType;
