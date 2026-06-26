// `flutter_test` (via `matcher`) also exports a top-level `allOf`; hide it so
// these tests exercise the flow-authoring `allOf` from `package:restage`.
// Authoring code in `lib/` never imports `flutter_test`, so this collision is
// test-context-only.
import 'package:flutter_test/flutter_test.dart' hide allOf;
import 'package:restage/restage.dart';

void main() {
  group('state()', () {
    test('returns a StateFlowValueSource usable as a plain value source', () {
      final source = state('goal');
      expect(source, isA<StateFlowValueSource>());
      expect(source.key, 'goal');
      expect(source.path, isEmpty);
    });
  });

  group('comparison operators desugar to single-field predicates', () {
    EqualsFlowPredicateCondition equalsOf(FlowBranchPredicate p, String key) {
      return p.fields[key]! as EqualsFlowPredicateCondition;
    }

    test('equals auto-wraps a String literal', () {
      final predicate = state('goal').equals('sleep');
      expect(predicate.fields.keys, ['goal']);
      final value = equalsOf(predicate, 'goal').value as LiteralFlowValueSource;
      expect(value.type, FlowDataType.string);
      expect(value.value, 'sleep');
    });

    test('equals auto-wraps a bool literal', () {
      final predicate = state('isPro').equals(true);
      final value =
          equalsOf(predicate, 'isPro').value as LiteralFlowValueSource;
      expect(value.type, FlowDataType.bool);
      expect(value.value, true);
    });

    test('equals passes a value source through (no wrapping)', () {
      final other = state('preferred');
      final predicate = state('goal').equals(other);
      final value = equalsOf(predicate, 'goal').value;
      expect(value, same(other));
    });

    test('notEquals desugars to NotEqualsFlowPredicateCondition', () {
      final predicate = state('goal').notEquals('sleep');
      expect(
        predicate.fields['goal'],
        isA<NotEqualsFlowPredicateCondition>(),
      );
    });

    test('the four numeric operators map to their wire conditions', () {
      expect(
        state('age').greaterThan(18).fields['age'],
        isA<GreaterThanFlowPredicateCondition>(),
      );
      expect(
        state('age').atLeast(18).fields['age'],
        isA<GreaterThanOrEqualsFlowPredicateCondition>(),
      );
      expect(
        state('age').lessThan(65).fields['age'],
        isA<LessThanFlowPredicateCondition>(),
      );
      expect(
        state('age').atMost(65).fields['age'],
        isA<LessThanOrEqualsFlowPredicateCondition>(),
      );
    });

    test('numeric operators wrap an int literal as FlowDataType.int', () {
      final condition = state('age').atLeast(18).fields['age']!
          as GreaterThanOrEqualsFlowPredicateCondition;
      final value = condition.value as LiteralFlowValueSource;
      expect(value.type, FlowDataType.int);
      expect(value.value, 18);
    });

    test('numeric operators accept a negative int literal', () {
      final condition = state('age').greaterThan(-5).fields['age']!
          as GreaterThanFlowPredicateCondition;
      final value = condition.value as LiteralFlowValueSource;
      expect(value.type, FlowDataType.int);
      expect(value.value, -5);
    });

    test('numeric operators pass a state-ref RHS through', () {
      final threshold = state('threshold');
      final condition = state('age').greaterThan(threshold).fields['age']!
          as GreaterThanFlowPredicateCondition;
      expect(condition.value, same(threshold));
    });

    test('oneOf desugars to InFlowPredicateCondition with wrapped values', () {
      final predicate = state('goal').oneOf(['sleep', 'focus']);
      final condition = predicate.fields['goal']! as InFlowPredicateCondition;
      expect(condition.values, hasLength(2));
      expect(
        (condition.values.first as LiteralFlowValueSource).value,
        'sleep',
      );
      expect(
        (condition.values.last as LiteralFlowValueSource).value,
        'focus',
      );
    });

    test('isSet/isUnset desugar to ExistsFlowPredicateCondition(true|false)',
        () {
      expect(
        (state('goal').isSet().fields['goal']! as ExistsFlowPredicateCondition)
            .exists,
        isTrue,
      );
      expect(
        (state('goal').isUnset().fields['goal']!
                as ExistsFlowPredicateCondition)
            .exists,
        isFalse,
      );
    });
  });

  group('loud failures (deliverability discipline)', () {
    test('a non-scalar literal RHS throws ArgumentError', () {
      expect(() => state('goal').equals(1.5), throwsArgumentError);
      expect(() => state('goal').equals(<int>[1]), throwsArgumentError);
    });

    test('a non-int literal to a comparison operator throws ArgumentError', () {
      expect(() => state('age').greaterThan('old'), throwsArgumentError);
      expect(() => state('age').atLeast(true), throwsArgumentError);
      expect(() => state('age').lessThan(1.5), throwsArgumentError);
    });

    test('a pre-wrapped non-int value source cannot bypass the int-only guard',
        () {
      expect(
        () => state('age').greaterThan(
          const LiteralFlowValueSource(
            type: FlowDataType.string,
            value: 'old',
          ),
        ),
        throwsArgumentError,
      );
      // An internally-mismatched source is rejected in BOTH directions — the
      // guard requires int in the declared type AND the value.
      expect(
        () => state('age').atMost(
          const LiteralFlowValueSource(type: FlowDataType.int, value: 'old'),
        ),
        throwsArgumentError,
      );
      expect(
        () => state('age').greaterThan(
          const LiteralFlowValueSource(type: FlowDataType.string, value: 18),
        ),
        throwsArgumentError,
      );
      // An int-typed literal source is fine.
      expect(
        state('age').atLeast(
          const LiteralFlowValueSource(type: FlowDataType.int, value: 18),
        ),
        isA<FlowBranchPredicate>(),
      );
    });
  });

  group('allOf', () {
    test('merges distinct single-field predicates into one AND-ed predicate',
        () {
      final predicate = allOf([
        state('goal').equals('sleep'),
        state('isPro').equals(true),
      ]);
      expect(predicate.fields.keys, containsAll(<String>['goal', 'isPro']));
      expect(predicate.fields, hasLength(2));
    });

    test('a single-element allOf returns that predicate', () {
      final predicate = allOf([state('goal').equals('sleep')]);
      expect(predicate.fields.keys, ['goal']);
    });

    test('two conditions on the same field throw ArgumentError (loud)', () {
      expect(
        () => allOf([
          state('age').atLeast(18),
          state('age').atMost(65),
        ]),
        throwsArgumentError,
      );
    });
  });
}
