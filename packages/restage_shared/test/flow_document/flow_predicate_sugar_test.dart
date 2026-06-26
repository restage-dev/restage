import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('FlowPredicateOperator', () {
    test('exposes exactly the nine sugar operators with their method names',
        () {
      expect(
        FlowPredicateOperator.values.map((o) => o.methodName).toSet(),
        {
          'equals',
          'notEquals',
          'greaterThan',
          'atLeast',
          'lessThan',
          'atMost',
          'oneOf',
          'isSet',
          'isUnset',
        },
      );
    });

    test('marks exactly the int-only comparison operators', () {
      final intOnly = FlowPredicateOperator.values
          .where((o) => o.intOnly)
          .map((o) => o.methodName)
          .toSet();
      expect(intOnly, {'greaterThan', 'atLeast', 'lessThan', 'atMost'});
    });

    test('assigns the right value arity per operator', () {
      FlowPredicateValueArity arityOf(String name) =>
          FlowPredicateOperator.values
              .firstWhere((o) => o.methodName == name)
              .arity;
      expect(arityOf('equals'), FlowPredicateValueArity.single);
      expect(arityOf('atLeast'), FlowPredicateValueArity.single);
      expect(arityOf('oneOf'), FlowPredicateValueArity.list);
      expect(arityOf('isSet'), FlowPredicateValueArity.none);
      expect(arityOf('isUnset'), FlowPredicateValueArity.none);
    });
  });

  group('flowPredicateLiteralType', () {
    test('infers the scalar wire type for bool, int, and String', () {
      expect(flowPredicateLiteralType(true), FlowDataType.bool);
      expect(flowPredicateLiteralType(42), FlowDataType.int);
      expect(flowPredicateLiteralType('sleep'), FlowDataType.string);
    });

    test('returns null for an unsupported literal', () {
      expect(flowPredicateLiteralType(1.5), isNull);
      expect(flowPredicateLiteralType(<int>[1]), isNull);
    });
  });

  group('buildFlowPredicateCondition', () {
    const value = LiteralFlowValueSource(type: FlowDataType.int, value: 3);

    test('maps single-value operators to their wire condition type', () {
      expect(
        buildFlowPredicateCondition(FlowPredicateOperator.equals, value: value),
        isA<EqualsFlowPredicateCondition>(),
      );
      expect(
        buildFlowPredicateCondition(
          FlowPredicateOperator.notEquals,
          value: value,
        ),
        isA<NotEqualsFlowPredicateCondition>(),
      );
      expect(
        buildFlowPredicateCondition(
          FlowPredicateOperator.greaterThan,
          value: value,
        ),
        isA<GreaterThanFlowPredicateCondition>(),
      );
      expect(
        buildFlowPredicateCondition(
          FlowPredicateOperator.atLeast,
          value: value,
        ),
        isA<GreaterThanOrEqualsFlowPredicateCondition>(),
      );
      expect(
        buildFlowPredicateCondition(
          FlowPredicateOperator.lessThan,
          value: value,
        ),
        isA<LessThanFlowPredicateCondition>(),
      );
      expect(
        buildFlowPredicateCondition(
          FlowPredicateOperator.atMost,
          value: value,
        ),
        isA<LessThanOrEqualsFlowPredicateCondition>(),
      );
    });

    test('maps oneOf to InFlowPredicateCondition with the given values', () {
      final condition = buildFlowPredicateCondition(
        FlowPredicateOperator.oneOf,
        values: const [value],
      );
      expect(condition, isA<InFlowPredicateCondition>());
      expect((condition as InFlowPredicateCondition).values, [value]);
    });

    test('maps isSet/isUnset to ExistsFlowPredicateCondition(true|false)', () {
      final isSet = buildFlowPredicateCondition(FlowPredicateOperator.isSet);
      final isUnset =
          buildFlowPredicateCondition(FlowPredicateOperator.isUnset);
      expect((isSet as ExistsFlowPredicateCondition).exists, isTrue);
      expect((isUnset as ExistsFlowPredicateCondition).exists, isFalse);
    });

    test('carries the exact value through a single-value operator', () {
      final condition = buildFlowPredicateCondition(
        FlowPredicateOperator.equals,
        value: value,
      );
      expect((condition as EqualsFlowPredicateCondition).value, same(value));
    });
  });

  group('mergeFlowBranchPredicates / firstDuplicatePredicateField', () {
    const goalEquals = FlowBranchPredicate(
      fields: {
        'goal': EqualsFlowPredicateCondition(
          value: LiteralFlowValueSource(
            type: FlowDataType.string,
            value: 'sleep',
          ),
        ),
      },
    );
    const ratingAtLeast = FlowBranchPredicate(
      fields: {
        'rating': GreaterThanOrEqualsFlowPredicateCondition(
          value: LiteralFlowValueSource(type: FlowDataType.int, value: 4),
        ),
      },
    );

    test('merges distinct single-field predicates into one', () {
      final merged = mergeFlowBranchPredicates([goalEquals, ratingAtLeast]);
      expect(merged.fields.keys, containsAll(<String>['goal', 'rating']));
      expect(merged.fields, hasLength(2));
    });

    test('firstDuplicatePredicateField finds a colliding field', () {
      expect(
        firstDuplicatePredicateField([ratingAtLeast, ratingAtLeast]),
        'rating',
      );
      expect(
        firstDuplicatePredicateField([goalEquals, ratingAtLeast]),
        isNull,
      );
    });

    test('a same-field collision throws ArgumentError (loud)', () {
      expect(
        () => mergeFlowBranchPredicates([ratingAtLeast, ratingAtLeast]),
        throwsArgumentError,
      );
    });
  });
}
