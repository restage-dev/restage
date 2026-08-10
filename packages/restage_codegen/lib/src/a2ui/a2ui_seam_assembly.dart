import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart'
    show A2uiRichShapes, a2uiCatalogDataNodeForProperty;
import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:restage_codegen/src/a2ui/a2ui_shape_reflector.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// One authored A2UI component paired with its resolved class element. The
/// `entry` carries catalog property names + types; the `element` carries the
/// constructor parameter types + field annotations the analyzer-fed seams
/// read.
typedef A2uiWidgetElement = ({WidgetEntry entry, ClassElement element});

/// The three analyzer-fed A2UI seams produced from resolved customer-widget
/// and native-screen elements — the inputs the production A2UI emitter
/// (`emitA2uiCatalogDart` / `emitA2uiCatalog`) threads alongside the catalog.
typedef A2uiSeams = ({
  A2uiRichShapes richShapes,
  A2uiEventSeam eventSeam,
  A2uiPairingSeam pairingSeam,
  List<Issue> issues,
});

/// Assembles the three A2UI read legs from resolved authored components,
/// closing the build-phase auto-wiring: for each catalog property of each
/// component,
///
///  * an `event` property reflects its constructor parameter into the EVENT
///    seam (the same `reflectType` leg the rich-shape path uses), and reads the
///    resolved target configuration into the PAIRING seam when present
///    (auto-pair / dispatch callbacks carry none);
///  * a `structured` property reflects its constructor parameter into the
///    analyzer-fed shape seam. This includes A2UI-targeted direct scalar lists,
///    which use `structured` only as a target-local carrier;
///  * ordinary enum leaves reflect their analyzer-resolved member set and
///    identity, while other data leaves retain their catalog-fed scalar kind
///    and add analyzer-known nullability;
///  * `Widget` / `List<Widget>` child slots carry analyzer-known nullability on
///    an id-shaped seam node so schema and construction agree.
///
/// Seam keys are `(widget catalog name, property name)`, matching what the
/// emitter consumes. The constructor parameter / field is matched to the
/// catalog property by name. This is the production unification of the proof
/// harnesses' inline event/pairing/rich-shape legs, driven off
/// `buildStep.resolver` instead of a hand-resolved fixture.
A2uiSeams assembleA2uiSeams(
  Iterable<A2uiWidgetElement> widgets, {
  Map<String, Map<String, String>> writeBackValuesByWidget = const {},
}) {
  final richShapes = <(String, String), A2uiSchemaNode>{};
  final eventSeam = <(String, String), A2uiCallbackSignature>{};
  final pairingSeam = <(String, String), String>{};
  final issues = <Issue>[];

  for (final widget in widgets) {
    final name = widget.entry.name;
    final ctor = _defaultConstructor(widget.element);
    for (final property in widget.entry.properties) {
      // Theme/synthetic values stay on their existing classifier paths; they
      // are not ordinary constructor-bound A2UI leaves.
      if (property.defaultSource is ThemeBindingDefault ||
          property.synthetic != null) {
        continue;
      }

      // Every A2UI-emitted property MUST bind a default-constructor parameter.
      // A missing one is a catalog/constructor inconsistency (the emitter could
      // not construct the widget faithfully), so fail LOUD rather than silently
      // lose its source shape.
      final formal = _requireFormal(ctor, name, property);
      final formalType =
          effectiveWidgetConstructorFormalType(widget.element, formal);
      if (property.type == PropertyType.event) {
        final result = reflectType(formalType);
        // The value pairing is meaningful only for a lowered callback — read it
        // inside the event-surface branch so a non-lowered callback never
        // leaves an orphan pairing entry.
        if (result is A2uiShapeEventSurface) {
          eventSeam[(name, property.name)] = result.signature;
          final writeBack = writeBackValuesByWidget[name]?[property.name];
          if (writeBack != null) {
            pairingSeam[(name, property.name)] = writeBack;
          }
        }
        continue;
      }

      if (property.type == PropertyType.structured) {
        final result = reflectType(formalType);
        // A structured property is reflected into the analyzer-fed shape seam.
        // Exhaustive over the reflector result so a non-Resolved shape can
        // NEVER be silently dropped — the governing fail-closed-LOUD invariant
        // carried into the seam. A scoped-out shape (a data class with an
        // A2UI-unrepresentable field) or an event surface at a structured
        // property surfaces a LOUD issue the builder fails on, rather than the
        // widget silently vanishing from the emitted catalog. (The 11
        // unconstructable built-ins are scoped out at the emitter, not here —
        // that is a built-in-only, intentional drop, distinct from a customer
        // structured shape the emitter cannot represent.)
        switch (result) {
          case A2uiShapeResolved():
            richShapes[(name, property.name)] = result.node;
          case A2uiShapeScopedOut():
            issues.add(
              Issue(
                code: IssueCode.unsupportedPropertyType,
                message: 'The structured property "${property.name}" on widget '
                    '"$name" cannot be represented in A2UI: '
                    '${result.typeDescription} (${result.reason.name}). It '
                    'would be silently dropped from the catalog — fix or '
                    'remove the property.',
                location: '${widget.element.library.identifier}'
                    '#$name.${property.name}',
              ),
            );
          case A2uiShapeEventSurface():
            issues.add(
              Issue(
                code: IssueCode.unsupportedPropertyType,
                message: 'The structured property "${property.name}" on widget '
                    '"$name" resolves to a callback/event surface, not a data '
                    'shape — a catalog/constructor inconsistency.',
                location: '${widget.element.library.identifier}'
                    '#$name.${property.name}',
              ),
            );
        }
        continue;
      }

      final nullable =
          formalType.nullabilitySuffix == NullabilitySuffix.question;
      if (property.type == PropertyType.enumValue) {
        final result = reflectType(formalType);
        if (result is A2uiShapeResolved && result.node is EnumNode) {
          richShapes[(name, property.name)] = result.node;
          continue;
        }
        throw StateError(
          'A2UI seam assembly: the catalog enumValue property '
          '"${property.name}" on widget "$name" does not resolve to an '
          'importable Dart enum: $result.',
        );
      } else if (property.type == PropertyType.widget) {
        richShapes[(name, property.name)] =
            ScalarNode(A2uiScalarType.string, nullable: nullable);
      } else if (property.type == PropertyType.widgetList) {
        richShapes[(name, property.name)] = ListNode(
          element: const ScalarNode(A2uiScalarType.string),
          nullable: nullable,
        );
      } else {
        final node = a2uiCatalogDataNodeForProperty(
          property,
          nullable: nullable,
        );
        if (node != null) richShapes[(name, property.name)] = node;
      }
    }
  }

  return (
    richShapes: richShapes,
    eventSeam: eventSeam,
    pairingSeam: pairingSeam,
    issues: issues,
  );
}

/// The unnamed/default generative constructor — the same canonical choice the
/// proof harnesses make. Returns `null` when absent so [_requireFormal] can
/// fail loud for any constructor-bound property.
ConstructorElement? _defaultConstructor(ClassElement element) =>
    element.constructors
        .where((c) => c.name == null || c.name!.isEmpty || c.name == 'new')
        .firstOrNull;

/// The default-constructor formal that binds [property], or a LOUD failure when
/// it is absent — a catalog/constructor inconsistency (the catalog declares a
/// property the widget's default constructor cannot receive).
FormalParameterElement _requireFormal(
  ConstructorElement? ctor,
  String widgetName,
  PropertyEntry property,
) {
  if (ctor == null) {
    throw StateError(
      'A2UI seam assembly: widget "$widgetName" has no default constructor to '
      'bind its "${property.name}" ${property.type.name} property — a '
      'catalog/constructor inconsistency.',
    );
  }
  final formal =
      ctor.formalParameters.where((p) => p.name == property.name).firstOrNull;
  if (formal == null) {
    throw StateError(
      'A2UI seam assembly: the catalog ${property.type.name} property '
      '"${property.name}" on widget "$widgetName" has no matching '
      'default-constructor parameter — a catalog/constructor inconsistency.',
    );
  }
  return formal;
}
