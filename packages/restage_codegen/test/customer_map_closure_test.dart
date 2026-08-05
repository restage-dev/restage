import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Future<
    ({
      CustomerStructuredAdmission admission,
      WidgetVisitorResult result,
    })> _admit(Map<String, String> sources) async {
  final result = await runWidgetVisitorOn(sources);
  return (
    admission: computeAdmission(
      widgets: result.widgets,
      structuredTypes: result.structuredTypes,
      slotTargets: result.slotTargets,
      localUnrenderable: result.localUnrenderable,
      widgetUnrenderable: result.widgetUnrenderable,
      mapPlans: result.mapPlans,
    ),
    result: result,
  );
}

const _mapValueWidgetSource = '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
  class Plan {
    const Plan({required this.name});
    final String name;
  }
  @RestageWidget(name: 'MapValueWidget',
    library: WidgetLibrary.custom('acme.design_system'),
    category: WidgetCategory.decoration, description: 'm')
  class MapValueWidget {
    const MapValueWidget({required this.tiers});
    @RestageProperty(description: 't')
    final Map<String, Plan> tiers;
  }
''';

void main() {
  test('a widget map value joins the structured closure', () async {
    final result = await runWidgetVisitorOn({
      'lib/map_value_widget.dart': _mapValueWidgetSource,
    });
    final plan = result.structuredTypes.singleWhere(
      (entry) => entry.sourceType.endsWith('#Plan'),
    );

    // Admission also depends on whole-widget emittability, whose
    // reconstruction work is separate from discovery. Pin discovery directly
    // so this test cannot pass or fail for an unrelated admission reason.
    expect(result.structuredTypes, contains(plan));
    expect(result.reconstructionPlans.containsKey(plan.sourceType), isTrue);
  });

  test('a nested data-class map value stays outside the closure', () async {
    const source = '''
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
      class Plan {
        const Plan({required this.name});
        final String name;
      }
      class Holder {
        const Holder({required this.tiers});
        final Map<String, Plan> tiers;
      }
      @RestageWidget(name: 'NestedMapWidget',
        library: WidgetLibrary.custom('acme.design_system'),
        category: WidgetCategory.decoration, description: 'n')
      class NestedMapWidget {
        const NestedMapWidget({required this.holder});
        @RestageProperty(description: 'h') final Holder holder;
      }
    ''';
    final r = await _admit({'lib/nested_map_widget.dart': source});

    expect(
      r.result.structuredTypes.any(
        (entry) => entry.sourceType.endsWith('#Holder'),
      ),
      isTrue,
    );
    expect(
      r.result.structuredTypes.any(
        (entry) => entry.sourceType.endsWith('#Plan'),
      ),
      isFalse,
    );
    expect(r.admission.admitted, isEmpty);
    expect(r.admission.excluded, hasLength(1));
    expect(
      r.admission.excluded.single.reason,
      contains('widget property'),
    );
    expect(
      r.admission.excluded.single.reason,
      isNot(contains('is unsupported')),
    );
  });

  test('an unsupported non-customer map value keeps the generic cause',
      () async {
    // The deferred message tells the author to move the map to a widget
    // property. That advice is only true for a type that would actually be
    // supported there, so a shape which fails for its own reasons must keep
    // the generic wording rather than be sent somewhere it will fail again.
    final result = await runWidgetVisitorOn({
      'lib/cards.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          abstract class AbsPlan { }

          class Holder {
            const Holder({required this.tiers});
            final Map<String, AbsPlan> tiers;
          }

          @RestageWidget(
            name: 'HolderCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration,
            description: 'A card with a holder.',
          )
          class HolderCard {
            const HolderCard({required this.holder});
            @RestageProperty(description: 'The holder.')
            final Holder holder;
          }
        ''',
    });
    final admission = computeAdmission(
      widgets: result.widgets,
      structuredTypes: result.structuredTypes,
      slotTargets: result.slotTargets,
      localUnrenderable: result.localUnrenderable,
      widgetUnrenderable: result.widgetUnrenderable,
      mapPlans: result.mapPlans,
    );
    expect(admission.excluded, hasLength(1));
    final reason = admission.excluded.single.reason;
    expect(reason, contains('is unsupported'));
    expect(reason, isNot(contains('move the map to a widget property')));
  });

  test('map slots do not use nominal slot bookkeeping', () async {
    const source = '''
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
      class Plan {
        const Plan({required this.name});
        final String name;
      }
      @RestageWidget(name: 'MapSlotWidget',
        library: WidgetLibrary.custom('acme.design_system'),
        category: WidgetCategory.decoration, description: 'm')
      class MapSlotWidget {
        const MapSlotWidget({required this.tiers});
        @RestageProperty(description: 't')
        final Map<String, Plan> tiers;
      }
      @RestageWidget(name: 'NominalSlotWidget',
        library: WidgetLibrary.custom('acme.design_system'),
        category: WidgetCategory.decoration, description: 'n')
      class NominalSlotWidget {
        const NominalSlotWidget({required this.plan});
        @RestageProperty(description: 'p') final Plan plan;
      }
    ''';
    final result = await runWidgetVisitorOn({
      'lib/slot_bookkeeping.dart': source,
    });
    final mapWidget = result.widgets.singleWhere(
      (widget) => widget.name == 'MapSlotWidget',
    );
    final nominalWidget = result.widgets.singleWhere(
      (widget) => widget.name == 'NominalSlotWidget',
    );

    expect(
      result.slotTargets.containsKey('${mapWidget.flutterType}.tiers'),
      isFalse,
    );
    expect(
      result.slotTargets.containsKey('${nominalWidget.flutterType}.plan'),
      isTrue,
    );
  });

  test('the complete admission transition set stays enumerated', () async {
    // This is the complete enumeration of shapes whose admission moved. Each
    // assertion is intentionally explicit so adding another shape requires
    // adding another line to this set.
    const mapFieldSource = '''
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
      class MapFieldOwner {
        const MapFieldOwner({required this.values});
        final Map<String, int> values;
      }
      @RestageWidget(name: 'MapFieldWidget',
        library: WidgetLibrary.custom('acme.design_system'),
        category: WidgetCategory.decoration, description: 'm')
      class MapFieldWidget {
        const MapFieldWidget({required this.owner});
        @RestageProperty(description: 'o') final MapFieldOwner owner;
      }
    ''';
    final mapField = await _admit({
      'lib/map_field_widget.dart': mapFieldSource,
    });
    final mapFieldOwner = mapField.result.structuredTypes.singleWhere(
      (entry) => entry.sourceType.endsWith('#MapFieldOwner'),
    );
    expect(
      mapField.result.localUnrenderable.containsKey(
        mapFieldOwner.sourceType,
      ),
      isFalse,
    );

    const recordLabelSource = '''
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
      @RestageWidget(name: 'RecordLabelWidget',
        library: WidgetLibrary.custom('acme.design_system'),
        category: WidgetCategory.decoration, description: 'r')
      class RecordLabelWidget {
        const RecordLabelWidget({required this.config});
        @RestageProperty(description: 'c')
        final ({Map<String, int> values}) config;
      }
    ''';
    final recordLabel = await _admit({
      'lib/record_label_widget.dart': recordLabelSource,
    });
    expect(recordLabel.admission.admitted, isEmpty);
    expect(recordLabel.admission.excluded, hasLength(1));

    const mapRecordSource = '''
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
      @RestageWidget(name: 'MapRecordWidget',
        library: WidgetLibrary.custom('acme.design_system'),
        category: WidgetCategory.decoration, description: 'm')
      class MapRecordWidget {
        const MapRecordWidget({required this.values});
        @RestageProperty(description: 'v')
        final Map<String, ({String title, int step})> values;
      }
    ''';
    final mapRecord = await _admit({
      'lib/map_record_widget.dart': mapRecordSource,
    });
    expect(mapRecord.admission.admitted, isEmpty);
    expect(mapRecord.admission.excluded, hasLength(1));
  });
}
