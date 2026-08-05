// End-to-end admission for a customer map slot, driven through the REAL
// whole-widget emittability callback rather than past it.
//
// Admission gates on `isWholeWidgetEmittable` -> `isFactoryEmittable`, and a
// test that leaves that callback null asserts admission while bypassing the
// one mechanism that decides it. The callback is therefore built here exactly
// as the walker builds it, from the visitor's own result.
//
// The two cases below are deliberately SEPARATE tests with separate names.
// They exercise different mechanisms: a map at a WIDGET PROPERTY is decided by
// the slot's own reconstruction plan, while a map on a DATA-CLASS FIELD is
// reached through the owning type's renderability walk, which does not consult
// the property-slot path at all. A single "a map-carrying widget is admitted"
// test would pass on either mechanism alone and so would prove neither.
import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The inline reconstruction context, assembled from [result] the same way the
/// walker assembles it before handing it to the emittability check.
CustomerReconstruction _reconstructionContext(WidgetVisitorResult result) => (
      structuredBySourceType: {
        for (final structured in result.structuredTypes)
          structured.sourceType: structured,
      },
      plansBySourceType: result.reconstructionPlans,
      mapPlans: result.mapPlans,
      recordPlans: result.recordPlans,
      slotTargets: result.slotTargets,
      nullableStructuredSlots: result.nullableStructuredSlots,
      aliases: const <String, String>{},
    );

Future<
    ({
      CustomerStructuredAdmission admission,
      WidgetVisitorResult result,
    })> _admitThroughFactoryEmittability(Map<String, String> sources) async {
  final result = await runWidgetVisitorOn(sources);
  final context = _reconstructionContext(result);
  return (
    admission: computeAdmission(
      widgets: result.widgets,
      structuredTypes: result.structuredTypes,
      slotTargets: result.slotTargets,
      localUnrenderable: result.localUnrenderable,
      widgetUnrenderable: result.widgetUnrenderable,
      mapPlans: result.mapPlans,
      isWholeWidgetEmittable: (widget) =>
          isFactoryEmittable(widget, customer: context),
    ),
    result: result,
  );
}

void main() {
  test(
    'a map WIDGET PROPERTY is admitted through the real factory '
    'emittability check',
    () async {
      final r = await _admitThroughFactoryEmittability({
        'lib/field_notes.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          @RestageWidget(name: 'FieldNotes',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'f')
          class FieldNotes {
            const FieldNotes({required this.glossary});
            @RestageProperty(description: 'g')
            final Map<String, String> glossary;
          }
        ''',
      });

      expect(
        r.admission.excluded,
        isEmpty,
        reason: 'the widget must not be excluded; got '
            '${r.admission.excluded.map((e) => e.reason).toList()}',
      );
      expect(r.admission.admitted.map((w) => w.name), ['FieldNotes']);

      // Assert the SLOT SURVIVED carrying the map contract, not merely that
      // the widget was admitted: a dropped property leaves a widget with no
      // slot to object to, which is admitted for the wrong reason.
      final prop = r.admission.admitted.single.properties
          .singleWhere((p) => p.name == 'glossary');
      expect(prop.type, PropertyType.unknown);
      expect((prop.valueShape! as ScalarShape).isOpaqueStringKeyedMap, isTrue);
    },
  );

  test(
    'a map DATA-CLASS FIELD is admitted through the real factory '
    'emittability check',
    () async {
      final r = await _admitThroughFactoryEmittability({
        'lib/field_notes.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          class Section {
            const Section({required this.heading, required this.glossary});
            final String heading;
            final Map<String, String> glossary;
          }
          @RestageWidget(name: 'FieldNotes',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'f')
          class FieldNotes {
            const FieldNotes({required this.section});
            @RestageProperty(description: 's')
            final Section section;
          }
        ''',
      });

      expect(
        r.admission.excluded,
        isEmpty,
        reason: 'the widget must not be excluded; got '
            '${r.admission.excluded.map((e) => e.reason).toList()}',
      );
      expect(r.admission.admitted.map((w) => w.name), ['FieldNotes']);

      // The map field must have MATERIALIZED on the owning type carrying the
      // map contract. Asserting only that nothing was marked unrenderable
      // would also pass if the field had vanished silently.
      final section = r.result.structuredTypes
          .singleWhere((entry) => entry.sourceType.endsWith('#Section'));
      final field =
          section.fields.singleWhere((field) => field.name == 'glossary');
      expect(field.type, PropertyType.unknown);
      expect((field.valueShape! as ScalarShape).isOpaqueStringKeyedMap, isTrue);
    },
  );
}
