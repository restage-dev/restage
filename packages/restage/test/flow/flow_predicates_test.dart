// `flutter_test` (via `matcher`) also exports a top-level `allOf`; hide it so
// these tests exercise the flow-authoring `allOf` from `package:restage`.
// Authoring code in `lib/` never imports `flutter_test`, so this collision is
// test-context-only.
import 'package:flutter_test/flutter_test.dart' hide allOf;
import 'package:restage/restage.dart';

void main() {
  group('flowState()', () {
    test('returns a StateFlowValueSource usable as a plain value source', () {
      final source = flowState('goal');
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
      final predicate = flowState('goal').equals('sleep');
      expect(predicate.fields.keys, ['goal']);
      final value = equalsOf(predicate, 'goal').value as LiteralFlowValueSource;
      expect(value.type, FlowDataType.string);
      expect(value.value, 'sleep');
    });

    test('equals auto-wraps a bool literal', () {
      final predicate = flowState('isPro').equals(true);
      final value =
          equalsOf(predicate, 'isPro').value as LiteralFlowValueSource;
      expect(value.type, FlowDataType.bool);
      expect(value.value, true);
    });

    test('equals passes a value source through (no wrapping)', () {
      final other = flowState('preferred');
      final predicate = flowState('goal').equals(other);
      final value = equalsOf(predicate, 'goal').value;
      expect(value, same(other));
    });

    test('notEquals desugars to NotEqualsFlowPredicateCondition', () {
      final predicate = flowState('goal').notEquals('sleep');
      expect(
        predicate.fields['goal'],
        isA<NotEqualsFlowPredicateCondition>(),
      );
    });

    test('the four numeric operators map to their wire conditions', () {
      expect(
        flowState('age').greaterThan(18).fields['age'],
        isA<GreaterThanFlowPredicateCondition>(),
      );
      expect(
        flowState('age').atLeast(18).fields['age'],
        isA<GreaterThanOrEqualsFlowPredicateCondition>(),
      );
      expect(
        flowState('age').lessThan(65).fields['age'],
        isA<LessThanFlowPredicateCondition>(),
      );
      expect(
        flowState('age').atMost(65).fields['age'],
        isA<LessThanOrEqualsFlowPredicateCondition>(),
      );
    });

    test('numeric operators wrap an int literal as FlowDataType.int', () {
      final condition = flowState('age').atLeast(18).fields['age']!
          as GreaterThanOrEqualsFlowPredicateCondition;
      final value = condition.value as LiteralFlowValueSource;
      expect(value.type, FlowDataType.int);
      expect(value.value, 18);
    });

    test('numeric operators accept a negative int literal', () {
      final condition = flowState('age').greaterThan(-5).fields['age']!
          as GreaterThanFlowPredicateCondition;
      final value = condition.value as LiteralFlowValueSource;
      expect(value.type, FlowDataType.int);
      expect(value.value, -5);
    });

    test('numeric operators pass a state-ref RHS through', () {
      final threshold = flowState('threshold');
      final condition = flowState('age').greaterThan(threshold).fields['age']!
          as GreaterThanFlowPredicateCondition;
      expect(condition.value, same(threshold));
    });

    test('oneOf desugars to InFlowPredicateCondition with wrapped values', () {
      final predicate = flowState('goal').oneOf(['sleep', 'focus']);
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
        (flowState('goal').isSet().fields['goal']!
                as ExistsFlowPredicateCondition)
            .exists,
        isTrue,
      );
      expect(
        (flowState('goal').isUnset().fields['goal']!
                as ExistsFlowPredicateCondition)
            .exists,
        isFalse,
      );
    });
  });

  group('loud failures (deliverability discipline)', () {
    test('a non-scalar literal RHS throws ArgumentError', () {
      expect(() => flowState('goal').equals(1.5), throwsArgumentError);
      expect(() => flowState('goal').equals(<int>[1]), throwsArgumentError);
    });

    test('a non-int literal to a comparison operator throws ArgumentError', () {
      expect(() => flowState('age').greaterThan('old'), throwsArgumentError);
      expect(() => flowState('age').atLeast(true), throwsArgumentError);
      expect(() => flowState('age').lessThan(1.5), throwsArgumentError);
    });

    test('a pre-wrapped non-int value source cannot bypass the int-only guard',
        () {
      expect(
        () => flowState('age').greaterThan(
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
        () => flowState('age').atMost(
          const LiteralFlowValueSource(type: FlowDataType.int, value: 'old'),
        ),
        throwsArgumentError,
      );
      expect(
        () => flowState('age').greaterThan(
          const LiteralFlowValueSource(type: FlowDataType.string, value: 18),
        ),
        throwsArgumentError,
      );
      // An int-typed literal source is fine.
      expect(
        flowState('age').atLeast(
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
        flowState('goal').equals('sleep'),
        flowState('isPro').equals(true),
      ]);
      expect(predicate.fields.keys, containsAll(<String>['goal', 'isPro']));
      expect(predicate.fields, hasLength(2));
    });

    test('a single-element allOf returns that predicate', () {
      final predicate = allOf([flowState('goal').equals('sleep')]);
      expect(predicate.fields.keys, ['goal']);
    });

    test('two conditions on the same field throw ArgumentError (loud)', () {
      expect(
        () => allOf([
          flowState('age').atLeast(18),
          flowState('age').atMost(65),
        ]),
        throwsArgumentError,
      );
    });
  });
}
