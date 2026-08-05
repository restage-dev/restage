// The DECODE side of a customer map slot: the generated factory rebuilds a real
// Dart `Map` from the entry list, behind five guards that each turn a malformed
// wire payload into a loud failure rather than a wrong render.
//
// Every assertion below was written from EMITTED OUTPUT captured from the real
// emitter, not from a description of it. Each guard is pinned twice — by its
// emitted structure and by its distinct message — so that renaming either half
// fails here rather than drifting green. A bare absence assertion would not:
// it stays true when the thing it names is simply renamed.
import 'package:restage_codegen/src/customer_map_plan.dart';
import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:restage_codegen/src/user_factory_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

const String _fqn = 'package:acme/widgets/field_notes.dart#FieldNotes';

WidgetEntry _widget(String propName) => WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: 'FieldNotes',
      library: const WidgetLibrary.custom('acme.design_system'),
      category: WidgetCategory.layout,
      description: 'A widget.',
      flutterType: _fqn,
      childrenSlot: ChildrenSlot.none,
      fires: const [],
      properties: [
        PropertyEntry(
          wireId: WireId.unallocatedProperty,
          name: propName,
          type: PropertyType.unknown,
          description: '',
          required: true,
          valueShape: ScalarShape.opaqueStringKeyedMap(),
        ),
      ],
    );

const MapKeyPlan _stringKey = (enumRef: null);

String _emit(String propName, MapPlan plan) {
  final source = emitUserFactoriesDart(
    [_widget(propName)],
    mapPlans: {structuredSlotKey(_fqn, propName): plan},
  );
  expect(source, isNotNull, reason: 'the widget must be emittable');
  return source!;
}

/// A `Map<String, String>` slot — one key layer, scalar value.
String _emitScalarMap() => _emit(
      'glossary',
      (
        keys: const [_stringKey],
        valueShape: const ScalarShape(propertyType: PropertyType.string),
        valueSourceType: null,
      ),
    );

/// A `Map<String, Map<String, int>>` slot — two key layers.
String _emitNestedMap() => _emit(
      'nested',
      (
        keys: const [_stringKey, _stringKey],
        valueShape: const ScalarShape(propertyType: PropertyType.integer),
        valueSourceType: null,
      ),
    );

void main() {
  group('the five reconstruction guards are emitted', () {
    test('the slot is list-shaped before it is iterated', () {
      final src = _emitScalarMap();

      expect(src, contains("source.isList(<Object>['glossary'])"));
      expect(
        src,
        contains("ArgumentError('FieldNotes.glossary is required.')"),
      );
      // Paired absence: the reconstruction closure must never be invoked
      // unconditionally. Without the shape check the emitter would open the
      // slot with the closure itself rather than with the ternary.
      expect(src, isNot(contains('glossary: () {')));
    });

    test('each entry is object-shaped before its fields are read', () {
      final src = _emitScalarMap();

      expect(src, contains("!source.isMap(<Object>['glossary', i0])"));
      expect(src, contains('FieldNotes.glossary entry must be an object.'));
    });

    test('a missing entry key fails loudly rather than defaulting', () {
      final src = _emitScalarMap();

      expect(
        src,
        contains("source.v<String>(<Object>['glossary', i0, 'key'])"),
      );
      expect(src, contains('FieldNotes.glossary entry key is required.'));
      // Paired absence: a key must never fall back to a value. The record
      // path's neighbouring convention defaults an absent scalar; a map key
      // may not, because a defaulted key silently merges two entries.
      expect(src, isNot(contains("'key']) ?? '")));
    });

    test('a duplicate key fails loudly rather than overwriting', () {
      final src = _emitScalarMap();

      expect(src, contains('m0.containsKey(k0)'));
      expect(src, contains('FieldNotes.glossary has a duplicate key.'));
    });

    test('a missing entry value fails loudly rather than defaulting', () {
      final src = _emitScalarMap();

      expect(
        src,
        contains("source.v<String>(<Object>['glossary', i0, 'value'])"),
      );
      expect(src, contains('FieldNotes.glossary entry value is required.'));
    });
  });

  group('a nested map guards every layer', () {
    test('the INNER value is list-shaped before it is iterated', () {
      final src = _emitNestedMap();

      // The inner layer repeats the shape check at its own path. Skipping it
      // would fail OPEN: an inner value that is not list-shaped would be
      // iterated as one rather than refused.
      expect(
        src,
        contains("source.isList(<Object>['nested', i0, 'value'])"),
      );
      expect(src, contains('final m1 = <String, int>{};'));
    });

    test('the inner layer carries its own key and duplicate guards', () {
      final src = _emitNestedMap();

      // The path fragment rather than the whole call: the emitted source is
      // formatted, so a long read wraps across lines and a single-line match
      // would fail for a reason unrelated to the guard.
      expect(src, contains("<Object>['nested', i0, 'value', i1, 'key']"));
      expect(src, contains('m1.containsKey(k1)'));
    });

    test('the reconstructed type is the real nested Dart map type', () {
      final src = _emitNestedMap();

      expect(src, contains('final m0 = <String, Map<String, int>>{};'));
      // Paired absence: the outer map must not collapse to its inner value
      // type, which would compile and render the wrong shape.
      expect(src, isNot(contains('final m0 = <String, int>{};')));
    });
  });

  test('a map slot never reconstructs from a key-keyed wire object', () {
    final src = _emitScalarMap();

    // The wire carries an entry LIST. A reader that indexed the slot by the
    // customer's own key would be reading the spelling the contract forbids.
    expect(src, contains("<Object>['glossary', i0, 'key']"));
    expect(src, isNot(contains("source.isMap(<Object>['glossary'])")));
  });
}
