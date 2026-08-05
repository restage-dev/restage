// A customer data class as a map VALUE at a widget property — the shape the
// map contract exists for.
//
// Four mechanisms meet here and none of them was exercised until the value
// path became reachable:
//
//   * the renderability walk reaches a map's VALUE. A map slot is skipped by
//     the nominal structured-slot checks, so without its own arm the recursive
//     gate never inspects what the map carries, and a widget would be admitted
//     holding a value the reconstructor cannot build.
//   * an admitted map value joins the admitted structured closure, so its type
//     is emitted rather than dangling.
//   * the generated factory rebuilds the real customer value inside the map.
//   * framework recipe types are NOT customer data classes and must keep
//     resolving as ordinary scalar values.
//
// Every assertion below is written from output captured from the real walker
// and the real emitter.
import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/user_factory_emitter.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String _header =
    "import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';";

String _widget(String declarations, String valueType) => '''
$_header
$declarations
@RestageWidget(name: 'FieldNotes', library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.decoration, description: 'f')
class FieldNotes {
  const FieldNotes({required this.glossary});
  @RestageProperty(description: 'g') final Map<String, $valueType> glossary;
}
''';

const String _renderablePlan = '''
class Plan {
  const Plan({required this.name, required this.seats});
  final String name;
  final int seats;
}
''';

/// A value type carrying a field the walker drops, which makes the type itself
/// unrenderable — the obstruction the map arm must reach.
const String _droppedFieldPlan = '''
class Plan {
  const Plan({required this.name, required this.bad});
  final String name;
  final Map<int, String> bad;
}
''';

const String _cyclicNode = '''
class Node {
  const Node({required this.label, required this.next});
  final String label;
  final Node next;
}
''';

Future<
    ({
      CustomerStructuredAdmission admission,
      WidgetVisitorResult result,
      String? source,
    })> _run(String declarations, String valueType) async {
  final result = await runWidgetVisitorOn({
    'lib/field_notes.dart': _widget(declarations, valueType),
  });
  final context = (
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
  final admission = computeAdmission(
    widgets: result.widgets,
    structuredTypes: result.structuredTypes,
    slotTargets: result.slotTargets,
    localUnrenderable: result.localUnrenderable,
    widgetUnrenderable: result.widgetUnrenderable,
    mapPlans: result.mapPlans,
    isWholeWidgetEmittable: (widget) =>
        isFactoryEmittable(widget, customer: context),
  );
  return (
    admission: admission,
    result: result,
    source: admission.admitted.isEmpty
        ? null
        : emitUserFactoriesDart(
            admission.admitted,
            structuredTypes: result.structuredTypes,
            slotTargets: result.slotTargets,
            nullableStructuredSlots: result.nullableStructuredSlots,
            reconstructionPlans: result.reconstructionPlans,
            mapPlans: result.mapPlans,
            recordPlans: result.recordPlans,
          ),
  );
}

void main() {
  group('the renderability walk reaches a map value', () {
    test('a dropped field inside the value type excludes the widget', () async {
      final r = await _run(_droppedFieldPlan, 'Plan');

      expect(r.admission.admitted, isEmpty);
      expect(r.admission.excluded, hasLength(1));
      final reason = r.admission.excluded.single.reason;
      expect(
        reason,
        contains("has a map value targeting 'Plan' whose closure is not "
            'fully renderable'),
      );
      // The inner cause travels out with it, so the author is told WHICH field
      // inside the value type is the problem rather than only that one is.
      expect(reason, contains('map key type int is unsupported'));
      // Paired absence: excluded for the closure walk, not for the earlier
      // missing-plan guard, which would also produce an exclusion here and
      // would mean the walk never ran.
      expect(reason, isNot(contains('has no map reconstruction plan')));
    });

    test('a cyclic value type excludes the widget and names the cycle',
        () async {
      // A second obstruction through the same arm. One shape passing would not
      // show the arm reaches the value generally — this one is refused deeper
      // in, by the cycle check rather than by a dropped field.
      final r = await _run(_cyclicNode, 'Node');

      expect(r.admission.admitted, isEmpty);
      final reason = r.admission.excluded.single.reason;
      expect(
        reason,
        contains("has a map value targeting 'Node' whose closure is not "
            'fully renderable'),
      );
      expect(reason, contains('cyclic structured type'));
    });
  });

  test('an admitted map value joins the admitted structured closure', () async {
    final r = await _run(_renderablePlan, 'Plan');

    expect(r.admission.admitted.map((w) => w.name), ['FieldNotes']);
    expect(
      r.admission.admittedSourceTypes.map((s) => s.split('#').last),
      contains('Plan'),
      reason: 'the map value type must be collected, or it would be emitted '
          'as a dangling reference',
    );
    // The plan carries the value identity that the closure walk followed.
    final plan = r.result.mapPlans.values.single;
    expect(plan.valueSourceType, endsWith('#Plan'));
  });

  test('the factory reconstructs the customer value inside the map', () async {
    final r = await _run(_renderablePlan, 'Plan');
    final src = r.source!;

    // The map is typed by the real customer class, not by a scalar.
    expect(src, contains('final m0 = <String, s0.Plan>{};'));
    // Each entry's VALUE is reconstructed from the entry's own value path.
    // Asserted as a path fragment: the emitted source is formatted, so the
    // whole read wraps across lines.
    expect(src, contains("<Object>['glossary', i0, 'value', 'name']"));
    expect(src, contains("<Object>['glossary', i0, 'value', 'seats']"));
    expect(src, contains('s0.Plan('));
    // Paired absence: the value must not be read as an opaque scalar, which is
    // what the terminal path emits when no value type is carried.
    const opaqueScalarRead =
        "source.v<String>(<Object>['glossary', i0, 'value'])";
    expect(src, isNot(contains(opaqueScalarRead)));
  });

  test('a framework recipe value is not treated as a customer data class',
      () async {
    // The customer-authored gate. The walk policy reports framework recipe
    // types as concrete too, so without it a map of one is captured by the
    // customer-value branch and excluded as an unresolvable structured target.
    // This pins the shapes that must keep working; no test can pin WHICH form
    // of the gate is in place, because every candidate agrees on every shape.
    final r = await _run('', 'Duration');

    expect(r.admission.admitted.map((w) => w.name), ['FieldNotes']);
    expect(r.result.mapPlans.values.single.valueSourceType, isNull);
    expect(r.source, contains('final m0 = <String, Duration>{};'));
    expect(r.source, contains('RestageDecoders.duration('));
    // Paired absence: the shape must not acquire the structured-value
    // treatment, whose failure surfaces as this exclusion wording.
    expect(
      r.admission.excluded,
      isEmpty,
      reason: 'a framework recipe value must stay admitted; got '
          '${r.admission.excluded.map((e) => e.reason).toList()}',
    );
  });
}
