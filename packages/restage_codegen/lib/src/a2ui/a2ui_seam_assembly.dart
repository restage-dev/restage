import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart'
    show A2uiRichShapes;
import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:restage_codegen/src/a2ui/a2ui_shape_reflector.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A customer `@RestageWidget` paired with its resolved class element — the
/// production build phase discovers these off `buildStep.resolver` and the
/// merged catalog: the `entry` carries the catalog property names + types, the
/// `element` carries the constructor parameter types + field annotations the
/// analyzer-fed seams read.
typedef A2uiWidgetElement = ({WidgetEntry entry, ClassElement element});

/// The three analyzer-fed A2UI seams produced from resolved `@RestageWidget`
/// elements — the inputs the production A2UI emitter (`emitA2uiCatalogDart` /
/// `emitA2uiCatalog`) threads alongside the catalog.
typedef A2uiSeams = ({
  A2uiRichShapes richShapes,
  A2uiEventSeam eventSeam,
  A2uiPairingSeam pairingSeam,
  List<Issue> issues,
});

/// Assembles the three A2UI read legs from resolved customer-widget elements,
/// closing the build-phase auto-wiring: for each catalog property of each
/// widget,
///
///  * an `event` property reflects its constructor parameter into the EVENT
///    seam (the same `reflectType` leg the rich-shape path uses), and reads the
///    field's `@RestageProperty(writeBackValue:)` annotation into the PAIRING
///    seam when present (auto-pair / dispatch callbacks carry none);
///  * a `structured` property reflects its constructor parameter into the
///    RICH-SHAPE seam;
///  * every other property type (scalar / enum / list / widget / theme value
///    props) is carried by the catalog property type itself — no analyzer-fed
///    seam.
///
/// Seam keys are `(widget catalog name, property name)`, matching what the
/// emitter consumes. The constructor parameter / field is matched to the
/// catalog property by name. This is the production unification of the proof
/// harnesses' inline event/pairing/rich-shape legs, driven off
/// `buildStep.resolver` instead of a hand-resolved fixture.
A2uiSeams assembleA2uiSeams(Iterable<A2uiWidgetElement> widgets) {
  final richShapes = <(String, String), A2uiSchemaNode>{};
  final eventSeam = <(String, String), A2uiCallbackSignature>{};
  final pairingSeam = <(String, String), String>{};
  final issues = <Issue>[];

  for (final widget in widgets) {
    final name = widget.entry.name;
    final ctor = _defaultConstructor(widget.element);
    for (final property in widget.entry.properties) {
      // Only `event` and `structured` properties carry an analyzer-fed seam;
      // scalar / enum / list / widget / theme value props are carried by the
      // catalog property type itself.
      if (property.type != PropertyType.event &&
          property.type != PropertyType.structured) {
        continue;
      }
      // A catalog event/structured property MUST bind a default-constructor
      // parameter. A missing one is a catalog/constructor inconsistency (the
      // emitter could not construct the widget faithfully), so fail LOUD rather
      // than silently drop the widget's seam — distinct from a supported-shape
      // that simply reflects to a scope-out below.
      final formal = _requireFormal(ctor, name, property);
      final result = reflectType(formal.type);
      if (property.type == PropertyType.event) {
        // The value pairing is meaningful only for a lowered callback — read it
        // inside the event-surface branch so a non-lowered callback never
        // leaves an orphan pairing entry.
        if (result is A2uiShapeEventSurface) {
          eventSeam[(name, property.name)] = result.signature;
          final writeBack = _writeBackValue(widget.element, property.name);
          if (writeBack != null) {
            pairingSeam[(name, property.name)] = writeBack;
          }
        }
      } else {
        // A structured property is reflected into the RICH-SHAPE seam.
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
/// proof harnesses make. Returns `null` when absent (the caller skips the
/// widget's reflected seams; the catalog path still carries it).
ConstructorElement? _defaultConstructor(ClassElement element) =>
    element.constructors
        .where((c) => c.name == null || c.name!.isEmpty || c.name == 'new')
        .firstOrNull;

/// The default-constructor formal that binds [property], or a LOUD failure when
/// it is absent — a catalog/constructor inconsistency (the catalog declares an
/// event/structured property the widget's default constructor cannot receive).
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

/// Reads the `@RestageProperty(writeBackValue:)` annotation off the field named
/// [name] (the explicit value-pairing leg), or `null` when the field is absent
/// or carries no `writeBackValue` (the same idiom the widget visitor uses for
/// `description`).
String? _writeBackValue(ClassElement element, String name) {
  final field = element.fields.where((f) => f.name == name).firstOrNull;
  if (field == null) return null;
  final annotation = firstAnnotation(field, 'RestageProperty');
  return annotation
      ?.computeConstantValue()
      ?.getField('writeBackValue')
      ?.toStringValue();
}
