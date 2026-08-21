import 'dart:collection';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/measurement/measurement_resolved_event.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
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
  }) : inlinedCustomWidgetBlueprints = Map.unmodifiable(
          inlinedCustomWidgetBlueprints,
        );

  /// Exact source-root annotation authority.
  final MeasurementSourceAuthority authority;

  /// Resolved class carrying the source-root annotation.
  final ClassElement sourceClass;

  /// Resolved expression returned by the source root's effective `build()`.
  final Expression rootExpression;

  /// Exact merged catalog used by the same compiler pass.
  final Catalog catalog;

  /// Compiler-captured bodies for custom widgets that actually inline.
  ///
  /// A strict custom-widget occurrence without an entry here is opaque to this
  /// lane only when it has one exact customer catalog entry. It then remains a
  /// static boundary and its private descendants are not discovered.
  final Map<String, CustomWidgetBlueprint> inlinedCustomWidgetBlueprints;
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
/// A node is static discovery material, not a synthetic presentation point.
/// The separately owned first-paint path decides whether and when a resolved
/// node receives a `presented` capability.
final class MeasurementDiscoveredNode {
  MeasurementDiscoveredNode._({
    required this.sourceProvenance,
    required this.structuralOccurrenceKey,
    required this.parentStructuralOccurrenceKey,
    required this.resolvedWidgetIdentity,
    required List<String> inlinedCustomWidgetIdentities,
  }) : inlinedCustomWidgetIdentities = List.unmodifiable(
          inlinedCustomWidgetIdentities,
        );

  /// Root source and compiler authority that owns the node.
  final MeasurementSourceProvenance sourceProvenance;

  /// Deterministic static occurrence locator for ledger reconciliation.
  final String structuralOccurrenceKey;

  /// Direct static Flutter-parent locator, absent for a root node.
  final String? parentStructuralOccurrenceKey;

  /// Exact resolved Flutter widget declaration identity.
  final String resolvedWidgetIdentity;

  /// Resolved custom definitions crossed while statically inlining this node.
  final List<String> inlinedCustomWidgetIdentities;
}

/// One strict compiler-known event slot discovered in source.
final class MeasurementDiscoveredEvent {
  MeasurementDiscoveredEvent._({
    required this.node,
    required this.resolvedEvent,
    required this.sourceExpression,
  });

  /// Static node owning the exact callback slot.
  final MeasurementDiscoveredNode node;

  /// Strict Flutter or opaque-catalog identity derived from analyzer elements.
  final MeasurementResolvedEvent resolvedEvent;

  /// The exact analyzer expression supplying this callback slot.
  ///
  /// This is an internal compiler handoff, not a source-path or ordinal
  /// identity. Carrier emission binds to this object while the same resolved
  /// AST is translated; no later pass reconstructs a callback from labels,
  /// event names, or collection order.
  final Expression sourceExpression;
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

  MeasurementSourceDiscoveryResult discover() {
    final provenance = _sourceProvenance();
    _visitWidgetExpression(
      input.rootExpression,
      _WidgetVisitContext.root(provenance),
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
    final expression = _withoutParentheses(source);
    final binding = _boundWidgetExpression(expression, context);
    if (binding != null) {
      _visitWidgetExpression(binding, context);
      return;
    }
    final helper = _resolvedInlinedHelper(expression, context);
    if (helper != null) {
      _visitWidgetExpression(
        helper.definition.body,
        context.enterHelper(
          helperIdentity: helper.identity,
          parameterBindings: helper.parameterBindings,
        ),
      );
      return;
    }
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
      _visitFlutterWidget(expression, classElement, context);
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
    _visitCustomWidget(expression, classElement, context);
  }

  void _visitFlutterWidget(
    InstanceCreationExpression expression,
    InterfaceElement widgetClass,
    _WidgetVisitContext context,
  ) {
    final catalogEntry = _catalogEntryFor(expression, widgetClass);
    final widgetIdentity = _classIdentity(widgetClass);
    final node = _recordNode(
      context: context,
      widgetIdentity: widgetIdentity,
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
      final slotIdentity = '$widgetIdentity.$parameterName';
      if (_isWidgetType(parameter.type)) {
        final ordinal = childOrdinals.update(
          slotIdentity,
          (value) => value + 1,
          ifAbsent: () => 0,
        );
        _visitWidgetExpression(
          value,
          context.child(
            parentNodeKey: node.structuralOccurrenceKey,
            parentWidgetIdentity: widgetIdentity,
            slotIdentity: slotIdentity,
            ordinal: ordinal,
          ),
        );
        continue;
      }
      if (_isWidgetListType(parameter.type)) {
        _visitWidgetList(
          value,
          context: context,
          parentNodeKey: node.structuralOccurrenceKey,
          parentWidgetIdentity: widgetIdentity,
          slotIdentity: slotIdentity,
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
    required String parentNodeKey,
    required String parentWidgetIdentity,
    required String slotIdentity,
  }) {
    final expression = _withoutParentheses(source);
    if (expression is! ListLiteral) {
      throw ArgumentError(
        'A measurement widget list must be a static literal list',
      );
    }
    var ordinal = 0;
    for (final element in expression.elements) {
      if (element is! Expression) {
        throw ArgumentError(
          'Conditional, spread, and loop widget-list elements are not a '
          'static measurement closure',
        );
      }
      _visitWidgetExpression(
        element,
        context.child(
          parentNodeKey: parentNodeKey,
          parentWidgetIdentity: parentWidgetIdentity,
          slotIdentity: slotIdentity,
          ordinal: ordinal,
        ),
      );
      ordinal++;
    }
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
      _requireRegisteredOpaqueCustomWidget(expression, customClass);
      final node = _recordNode(
        context: context,
        widgetIdentity: customIdentity,
      );
      final slots = MeasurementResolvedOpaqueCustomWidgetEvent.discoverSlots(
        sourceRoot: input.sourceClass,
        occurrence: expression,
        catalog: input.catalog,
      );
      for (final slot in slots) {
        _recordResolvedEvent(
          node: node,
          resolvedEvent: slot,
          sourceExpression: _opaqueEventExpression(
            expression,
            slot.sourceEventIdentity,
          ),
        );
      }
      // The occurrence and its declared slots are in the emitted graph. Its
      // private Flutter implementation remains a terminal compiler boundary.
      return;
    }
    final bindings = _customWidgetBindings(expression, customClass);
    _visitWidgetExpression(
      blueprint.buildExpression,
      context.enterInline(
        customIdentity: customIdentity,
        fieldBindings: bindings,
        inlinedDefinitions: blueprint.inlined,
      ),
    );
  }

  MeasurementDiscoveredNode _recordNode({
    required _WidgetVisitContext context,
    required String widgetIdentity,
  }) {
    final segments = [
      ...context.pathSegments,
      _StructuralPathSegment.widget(widgetIdentity),
    ];
    final structuralOccurrenceKey = _structuralOccurrenceKey(
      context.sourceProvenance,
      segments,
    );
    if (!_nodeKeys.add(structuralOccurrenceKey)) {
      throw ArgumentError('A static measurement node occurrence is duplicated');
    }
    final node = MeasurementDiscoveredNode._(
      sourceProvenance: context.sourceProvenance,
      structuralOccurrenceKey: structuralOccurrenceKey,
      parentStructuralOccurrenceKey: context.parentNodeKey,
      resolvedWidgetIdentity: widgetIdentity,
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
    var sourceExpression = value;
    while (true) {
      final binding = _boundWidgetExpression(sourceExpression, context);
      if (binding == null) break;
      sourceExpression = binding;
    }
    if (_withoutParentheses(sourceExpression) is NullLiteral) return;
    if (!_isFunctionType(sourceExpression.staticType)) {
      throw ArgumentError(
        'A compiler-known Flutter event slot requires a statically resolved '
        'function value',
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
    );
  }

  void _recordResolvedEvent({
    required MeasurementDiscoveredNode node,
    required MeasurementResolvedEvent resolvedEvent,
    required Expression sourceExpression,
  }) {
    final event = MeasurementDiscoveredEvent._(
      node: node,
      resolvedEvent: resolvedEvent,
      sourceExpression: sourceExpression,
    );
    if (!_eventKeys.add(_eventKey(event))) {
      throw ArgumentError(
        'A static measurement callback slot is duplicated',
      );
    }
    _events.add(event);
  }

  Expression _opaqueEventExpression(
    InstanceCreationExpression occurrence,
    SourceEventIdentity sourceEventIdentity,
  ) {
    for (final argument in occurrence.argumentList.arguments) {
      if (argument is NamedExpression &&
          argument.name.label.name == sourceEventIdentity.value) {
        return argument.expression;
      }
    }
    throw ArgumentError(
      'An opaque measurement event must retain its exact source expression',
    );
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
        'customer catalog entry for $flutterType',
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

  Map<FieldElement, Expression> _customWidgetBindings(
    InstanceCreationExpression expression,
    InterfaceElement customClass,
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
    final bindings = <FieldElement, Expression>{};
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
        final previous = bindings[field];
        if (previous != null && !identical(previous, value)) {
          throw ArgumentError(
            'A statically inlined custom-widget field was bound twice',
          );
        }
        bindings[field] = value;
      }
    }
    return UnmodifiableMapView(bindings);
  }

  Expression? _boundWidgetExpression(
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
      identity: helperIdentity,
      definition: definition,
      parameterBindings: parameterBindings,
    );
  }
}

final class _WidgetVisitContext {
  const _WidgetVisitContext._({
    required this.sourceProvenance,
    required this.pathSegments,
    required this.parentNodeKey,
    required this.inlinedCustomWidgetIdentities,
    required this.expressionBindings,
    required this.helperDefinitions,
    required this.inlinedHelperIdentities,
  });

  factory _WidgetVisitContext.root(MeasurementSourceProvenance provenance) =>
      _WidgetVisitContext._(
        sourceProvenance: provenance,
        pathSegments: const [],
        parentNodeKey: null,
        inlinedCustomWidgetIdentities: const [],
        expressionBindings: const {},
        helperDefinitions: const {},
        inlinedHelperIdentities: const [],
      );

  final MeasurementSourceProvenance sourceProvenance;
  final List<_StructuralPathSegment> pathSegments;
  final String? parentNodeKey;
  final List<String> inlinedCustomWidgetIdentities;
  final Map<Element, Expression> expressionBindings;
  final Map<Element, HelperDef> helperDefinitions;
  final List<String> inlinedHelperIdentities;

  _WidgetVisitContext child({
    required String parentNodeKey,
    required String parentWidgetIdentity,
    required String slotIdentity,
    required int ordinal,
  }) =>
      _WidgetVisitContext._(
        sourceProvenance: sourceProvenance,
        pathSegments: [
          ...pathSegments,
          _StructuralPathSegment.child(
            parentWidgetIdentity: parentWidgetIdentity,
            slotIdentity: slotIdentity,
            ordinal: ordinal,
          ),
        ],
        parentNodeKey: parentNodeKey,
        inlinedCustomWidgetIdentities: inlinedCustomWidgetIdentities,
        expressionBindings: expressionBindings,
        helperDefinitions: helperDefinitions,
        inlinedHelperIdentities: inlinedHelperIdentities,
      );

  _WidgetVisitContext enterInline({
    required String customIdentity,
    required Map<FieldElement, Expression> fieldBindings,
    required InlinedDefinitions inlinedDefinitions,
  }) =>
      _WidgetVisitContext._(
        sourceProvenance: sourceProvenance,
        pathSegments: [
          ...pathSegments,
          _StructuralPathSegment.inline(customIdentity),
          _StructuralPathSegment.inlinedBody(customIdentity),
        ],
        parentNodeKey: parentNodeKey,
        inlinedCustomWidgetIdentities: [
          ...inlinedCustomWidgetIdentities,
          customIdentity,
        ],
        // A nested custom body can pass one of its own fields through to a
        // descendant custom widget. Retaining the outer bindings lets the
        // resolved field reference continue to its exact source call-site.
        expressionBindings: Map.unmodifiable({
          ...expressionBindings,
          ...fieldBindings,
          ...inlinedDefinitions.localBindings,
        }),
        helperDefinitions: Map.unmodifiable({
          ...helperDefinitions,
          ...inlinedDefinitions.helpers,
        }),
        inlinedHelperIdentities: inlinedHelperIdentities,
      );

  _WidgetVisitContext enterHelper({
    required String helperIdentity,
    required Map<Element, Expression> parameterBindings,
  }) =>
      _WidgetVisitContext._(
        sourceProvenance: sourceProvenance,
        pathSegments: [
          ...pathSegments,
          _StructuralPathSegment.helper(helperIdentity),
        ],
        parentNodeKey: parentNodeKey,
        inlinedCustomWidgetIdentities: inlinedCustomWidgetIdentities,
        expressionBindings: Map.unmodifiable({
          ...expressionBindings,
          ...parameterBindings,
        }),
        helperDefinitions: helperDefinitions,
        inlinedHelperIdentities: [
          ...inlinedHelperIdentities,
          helperIdentity,
        ],
      );
}

final class _StructuralPathSegment {
  const _StructuralPathSegment._(this.value);

  factory _StructuralPathSegment.widget(String widgetIdentity) =>
      _StructuralPathSegment._('widget:$widgetIdentity');

  factory _StructuralPathSegment.child({
    required String parentWidgetIdentity,
    required String slotIdentity,
    required int ordinal,
  }) =>
      _StructuralPathSegment._(
        'child:$parentWidgetIdentity:$slotIdentity[$ordinal]',
      );

  factory _StructuralPathSegment.inline(String customIdentity) =>
      _StructuralPathSegment._('inline:$customIdentity');

  factory _StructuralPathSegment.inlinedBody(String customIdentity) =>
      _StructuralPathSegment._('inlinedBody:$customIdentity');

  factory _StructuralPathSegment.helper(String helperIdentity) =>
      _StructuralPathSegment._('helper:$helperIdentity');

  final String value;
}

final class _ResolvedArgument {
  const _ResolvedArgument({required this.parameter, required this.value});

  final FormalParameterElement parameter;
  final Expression value;
}

final class _ResolvedInlinedHelper {
  const _ResolvedInlinedHelper({
    required this.identity,
    required this.definition,
    required this.parameterBindings,
  });

  final String identity;
  final HelperDef definition;
  final Map<Element, Expression> parameterBindings;
}

String _structuralOccurrenceKey(
  MeasurementSourceProvenance provenance,
  Iterable<_StructuralPathSegment> segments,
) =>
    '${provenance.resolvedSourceIdentity}|'
    '${segments.map((segment) => segment.value).join('|')}';

String _eventKey(MeasurementDiscoveredEvent event) =>
    '${event.node.structuralOccurrenceKey}\u0000'
    '${event.resolvedEvent.resolvedSemanticIdentity}';

String _classIdentity(InterfaceElement element) {
  final name = element.name;
  final libraryUri = element.library.identifier;
  if (name == null || name.isEmpty || libraryUri.isEmpty) {
    throw ArgumentError('Resolved class identities must be stable');
  }
  return '$libraryUri#$name';
}

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

String _helperIdentity(ExecutableElement executable) {
  final libraryUri = executable.library.identifier;
  final executableName = executable.name;
  final owner = executable.enclosingElement;
  final ownerName = owner is InterfaceElement ? owner.name : null;
  if (libraryUri.isEmpty ||
      executableName == null ||
      executableName.isEmpty ||
      (ownerName != null && ownerName.isEmpty)) {
    throw ArgumentError('Resolved helper identities must be stable');
  }
  final ownerIdentity = ownerName ?? 'topLevel';
  return '$libraryUri#$ownerIdentity.$executableName';
}

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
