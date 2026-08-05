// A nested map whose innermost value is a customer data class.
//
// The classifier decides a map's value shape with the walk LIBRARY and POLICY
// in hand — without them it cannot tell a customer data class from any other
// type, and refuses it. A nested map's inner classification is computed once,
// with both, and carried on the admitted verdict. Deriving the plan by
// re-classifying instead would drop the library and the policy, read the inner
// map as excluded, and leave the OUTER map's own opaque marker as the terminal
// value shape — an unknown property type that the factory emitter has no Dart
// type for.
//
// That failure is not quiet. The plan silently loses a key layer, and emission
// then crashes with an internal `StateError` naming an internal enum, on a
// shape the classifier's own diagnostic lists as admitted ("a scalar, an enum,
// a nested map, or a customer data class"). So the plan is asserted directly,
// not only the absence of a throw: a future change that keeps emission working
// while flattening the plan would otherwise pass.
//
// The flat and scalar-valued cases are controls. They already worked, and the
// risk in a change here is fixing the nested case by disturbing them — the
// nested-scalar and enum-keyed cases in particular travel a path that
// classifies WITHOUT a policy, where the two derivations must agree.
import 'package:restage_codegen/src/customer_map_plan.dart';
import 'package:restage_codegen/src/user_factory_emitter.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String _source = '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  class Tier {
    const Tier({required this.name});
    final String name;
  }

  enum Tone { soft, loud }

  class Holder {
    const Holder({required this.nestedScalar, required this.enumKeyed});
    final Map<String, Map<String, int>> nestedScalar;
    final Map<Tone, Map<String, int>> enumKeyed;
  }

  @RestageWidget(name: 'FieldNotes',
    library: WidgetLibrary.custom('acme.design_system'),
    category: WidgetCategory.decoration, description: 'n')
  class FieldNotes {
    const FieldNotes({
      required this.flat,
      required this.nested,
      required this.nestedEnum,
      required this.holder,
    });
    @RestageProperty(description: 'f') final Map<String, Tier> flat;
    @RestageProperty(description: 'n')
    final Map<String, Map<String, Tier>> nested;
    @RestageProperty(description: 'e')
    final Map<String, Map<String, Tone>> nestedEnum;
    @RestageProperty(description: 'h') final Holder holder;
  }
''';

Future<({Map<String, MapPlan> plans, WidgetVisitorResult result})>
    _walk() async {
  final r = await runWidgetVisitorOn({'lib/field_notes.dart': _source});
  return (
    plans: r.mapPlans.map((k, v) => MapEntry(k.split('#').last, v)),
    result: r,
  );
}

/// The plan for [slot], failing with the slot name rather than a null
/// dereference when the walk did not produce one.
MapPlan _planFor(Map<String, MapPlan> plans, String slot) {
  final plan = plans[slot];
  expect(plan, isNotNull, reason: 'no map plan was produced for $slot');
  return plan!;
}

void main() {
  test('a nested map of a customer data class keeps every key layer', () async {
    final w = await _walk();
    final plan = _planFor(w.plans, 'FieldNotes.nested');

    // Two authored key layers must survive as two. Losing the inner layer is
    // the specific corruption: the outer map's opaque marker becomes the
    // terminal value, and its property type is `unknown`.
    expect(plan.keys, hasLength(2));
    expect(
      plan.valueShape.propertyType,
      PropertyType.structured,
      reason: 'the terminal value is the customer data class, not the outer '
          "map's opaque marker",
    );
    expect(plan.valueSourceType, endsWith('#Tier'));
    // Paired absence: `unknown` is exactly what the outer marker carries, and
    // it is the value the emitter cannot type.
    expect(plan.valueShape.propertyType, isNot(PropertyType.unknown));
  });

  test('the nested slot emits a factory rather than crashing the build',
      () async {
    final w = await _walk();
    final r = w.result;

    // The emitter is called the way the builder calls it; a StateError here is
    // an uncaught build crash, not a diagnosed refusal.
    final source = emitUserFactoriesDart(
      r.widgets,
      structuredTypes: r.structuredTypes,
      slotTargets: r.slotTargets,
      nullableStructuredSlots: r.nullableStructuredSlots,
      reconstructionPlans: r.reconstructionPlans,
      mapPlans: r.mapPlans,
      recordPlans: r.recordPlans,
    );

    expect(source, isNotNull);
    // The inner map must re-apply the list guard. Without it a wrong nested
    // container reads as an empty map, because a non-list length is zero.
    expect(
      source,
      contains("source.isList(<Object>['nested', i0, 'value'])"),
    );
    // The reconstructed Dart type carries both layers.
    expect(source, contains('<String, Map<String, s'));
  });

  group('the shapes that already worked are undisturbed', () {
    test('a flat map of a customer data class', () async {
      final plan = _planFor((await _walk()).plans, 'FieldNotes.flat');

      expect(plan.keys, hasLength(1));
      expect(plan.valueShape.propertyType, PropertyType.structured);
      expect(plan.valueSourceType, endsWith('#Tier'));
    });

    test('a nested scalar map on a data-class field', () async {
      // This travels the field path, which classifies with neither library nor
      // policy. A scalar needs neither, so both derivations of the inner layer
      // must agree — this is where a change here could silently diverge.
      final plan = _planFor((await _walk()).plans, 'Holder.nestedScalar');

      expect(plan.keys, hasLength(2));
      expect(plan.valueShape.propertyType, PropertyType.integer);
      expect(plan.valueSourceType, isNull);
    });

    test('a nested map of an ENUM value — the discriminator', () async {
      // The bug was specific to a value the classifier can only recognise
      // WITH the walk policy. An enum resolves without one, so this nested
      // shape kept working while the customer-data-class one crashed. Pinning
      // it states the boundary: what distinguishes the two is the policy, not
      // the nesting.
      final plan = _planFor((await _walk()).plans, 'FieldNotes.nestedEnum');

      expect(plan.keys, hasLength(2));
      expect(plan.valueShape.propertyType, PropertyType.enumValue);
    });

    test('an enum-keyed nested map on a data-class field', () async {
      final plan = _planFor((await _walk()).plans, 'Holder.enumKeyed');

      expect(plan.keys, hasLength(2));
      // The outer layer is enum-keyed and the inner is string-keyed: the two
      // layers must not be collapsed into one kind.
      expect(plan.keys.first.enumRef?.symbolName, 'Tone');
      expect(plan.keys.last.enumRef, isNull);
      expect(plan.valueShape.propertyType, PropertyType.integer);
    });
  });
}
