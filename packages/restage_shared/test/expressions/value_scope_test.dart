import 'dart:convert';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

// count > threshold
const _program = ValueProgram(
  nodes: [
    ValueNode('capture', ValueType.integer, name: 'count'),
    ValueNode('parameter', ValueType.integer, name: 'threshold'),
    ValueNode('>', ValueType.boolean, inputs: [0, 1]),
  ],
  root: 2,
  captures: {'count': ValueType.integer},
  parameters: {'threshold': ValueType.integer},
);

const _boolN = ValueType('bool', nullable: true);

// flag != true: true for a null flag, so a missing flag must not read as null.
const _nullableFlag = ValueProgram(
  nodes: [
    ValueNode('capture', _boolN, name: 'flag'),
    ValueNode('literal', ValueType.boolean, value: true),
    ValueNode('!=', ValueType.boolean, inputs: [0, 1]),
  ],
  root: 2,
  captures: {'flag': _boolN},
);

const _user = ValueType('record', fields: {'isPro': _boolN});

// user.isPro != true
const _nestedFlag = ValueProgram(
  nodes: [
    ValueNode('capture', _user, name: 'user'),
    ValueNode('field', _boolN, inputs: [0], name: 'isPro'),
    ValueNode('literal', ValueType.boolean, value: true),
    ValueNode('!=', ValueType.boolean, inputs: [1, 2]),
  ],
  root: 3,
  captures: {'user': _user},
);

final class _FailingOperation implements ValueOperation {
  const _FailingOperation();
  @override
  String get name => 'fail';
  @override
  int get capability => valueProgramCapability;
  @override
  void validate(ValueNode node, List<ValueType> inputs) {}
  @override
  Object? evaluate(List<Object?> inputs, Object? options) =>
      throw StateError('operation failed');
}

ValueProgram _capturing(ValueType type) => ValueProgram(
      nodes: [ValueNode('capture', type, name: 'x')],
      root: 0,
      captures: {'x': type},
    );

// A type rebuilt from JSON, so identity can't pass for structure.
ValueType _decoded(ValueType type) => ValueType.fromJson(
      jsonDecode(jsonEncode(type.toJson())) as Map<String, Object?>,
    );

void main() {
  group('scopeMisses', () {
    test('is empty when every input is a fact of an accepted type', () {
      expect(
        scopeMisses(
          _program,
          captures: {'count': ValueType.integer, 'unused': ValueType.string},
          parameters: {'threshold': ValueType.integer},
        ),
        isEmpty,
      );
    });

    test('names unknown inputs and type mismatches with their binding', () {
      final misses =
          scopeMisses(_program, captures: {'count': ValueType.string});
      expect(misses.map((m) => (m.name, m.binding, m.kind)), [
        ('count', ValueScopeBinding.capture, ValueScopeMissKind.typeMismatch),
        ('threshold', ValueScopeBinding.parameter, ValueScopeMissKind.unknown),
      ]);
      expect(misses.first.declared, same(ValueType.integer));
      expect(misses.first.available, same(ValueType.string));
      expect(misses.last.declared, same(ValueType.integer));
      expect(misses.last.available, isNull);
      expect(
        misses.first.toString(),
        'capture count: declared {kind: int}, available {kind: String}',
      );
      expect(
        misses.last.toString(),
        'parameter threshold: not a declared fact',
      );
    });

    test('matches captures and parameters only against their own facts', () {
      // event == 'buy', with event declared as a capture.
      const program = ValueProgram(
        nodes: [
          ValueNode('capture', ValueType.string, name: 'event'),
          ValueNode('literal', ValueType.string, value: 'buy'),
          ValueNode('==', ValueType.boolean, inputs: [0, 1]),
        ],
        root: 2,
        captures: {'event': ValueType.string},
      );
      expect(
        scopeMisses(program, parameters: {'event': ValueType.string})
            .map((m) => (m.binding, m.kind)),
        [(ValueScopeBinding.capture, ValueScopeMissKind.unknown)],
      );
      expect(
        scopeMisses(program, captures: {'event': ValueType.string}),
        isEmpty,
      );
    });

    test('a parameter is not satisfied by a capture fact', () {
      expect(
        scopeMisses(
          _program,
          captures: {
            'count': ValueType.integer,
            'threshold': ValueType.integer,
          },
        ).map((m) => (m.name, m.binding, m.kind)),
        [
          (
            'threshold',
            ValueScopeBinding.parameter,
            ValueScopeMissKind.unknown
          ),
        ],
      );
    });

    test('accepts a fact the declared type accepts, in one direction', () {
      const intN = ValueType('int', nullable: true);
      expect(
        scopeMisses(_capturing(intN), captures: {'x': ValueType.nullType}),
        isEmpty,
      );
      expect(
        scopeMisses(
          _capturing(ValueType.integer),
          captures: {'x': ValueType.nullType},
        ).map((m) => m.kind),
        [ValueScopeMissKind.typeMismatch],
      );
      expect(
        scopeMisses(_capturing(intN), captures: {'x': ValueType.integer}),
        isEmpty,
      );
      expect(
        scopeMisses(
          _capturing(ValueType.number),
          captures: {'x': ValueType.integer},
        ),
        isEmpty,
      );
      expect(
        scopeMisses(_capturing(ValueType.integer), captures: {'x': intN})
            .map((m) => m.kind),
        [ValueScopeMissKind.typeMismatch],
      );
      expect(
        scopeMisses(
          _capturing(ValueType.integer),
          captures: {'x': ValueType.number},
        ).map((m) => m.kind),
        [ValueScopeMissKind.typeMismatch],
      );
    });

    test('compares nested types structurally', () {
      const fits = <ValueType>[
        ValueType('list', item: ValueType.integer),
        ValueType('list', item: ValueType('list', item: ValueType.string)),
        ValueType(
          'record',
          fields: {
            'a': ValueType('record', fields: {'b': ValueType.string}),
          },
        ),
        ValueType(
          'record',
          fields: {
            'xs': ValueType('list', item: ValueType.integer),
          },
        ),
        ValueType.native('flutter.Color'),
      ];
      for (final type in fits) {
        final decoded = _decoded(type);
        expect(identical(decoded, type), isFalse);
        expect(
          scopeMisses(_capturing(type), captures: {'x': decoded}),
          isEmpty,
          reason: '${type.toJson()}',
        );
      }
      const record = ValueType('record', fields: {'a': ValueType.string});
      final mismatches = <(ValueType, ValueType)>[
        (
          const ValueType('list', item: ValueType.integer),
          const ValueType('list', item: ValueType.string)
        ),
        (record, const ValueType('record', fields: {'b': ValueType.string})),
        (record, const ValueType('record', fields: {'a': ValueType.integer})),
        (record, const ValueType('record')),
        (const ValueType('record'), record),
        (
          const ValueType.native('flutter.Color'),
          const ValueType.native('flutter.Size')
        ),
      ];
      for (final (declared, available) in mismatches) {
        expect(
          scopeMisses(
            _capturing(declared),
            captures: {'x': _decoded(available)},
          ).map((m) => m.kind),
          [ValueScopeMissKind.typeMismatch],
          reason: '${declared.toJson()} vs ${available.toJson()}',
        );
      }
    });

    test('refuses a list fact with no item type for a typed list', () {
      expect(
        scopeMisses(
          _capturing(const ValueType('list', item: ValueType.integer)),
          captures: {'x': const ValueType('list')},
        ).map((m) => m.kind),
        [ValueScopeMissKind.typeMismatch],
      );
    });
  });

  group('evaluateOrMissing', () {
    test('returns the value, including false and null', () {
      expect(
        evaluateOrMissing(
          _program,
          captures: {'count': 5},
          parameters: {'threshold': 3},
        ),
        isTrue,
      );
      final notGreater = evaluateOrMissing(
        _program,
        captures: {'count': 1},
        parameters: {'threshold': 3},
      );
      expect(notGreater, isFalse);
      expect(notGreater, isNot(same(valueMissing)));
      const intN = ValueType('int', nullable: true);
      expect(
        evaluateOrMissing(_capturing(intN), captures: {'x': null}),
        isNull,
      );
    });

    test('returns only the declared fields of nested facts', () {
      const item = ValueType('record', fields: {'id': ValueType.integer});
      const user = ValueType(
        'record',
        fields: {
          'items': ValueType('list', item: item),
        },
      );
      final result = evaluateOrMissing(
        _capturing(user),
        captures: {
          'x': {
            'items': [
              {'id': 1, 'secret': 'a'},
              {'id': 2, 'secret': 'b'},
            ],
            'secret': 'c',
          },
        },
      );
      final record = result! as Map<String, Object?>;
      expect(record.keys, ['items']);
      final items = record['items']! as List<Object?>;
      expect(items.length, 2);
      expect((items.last! as Map<String, Object?>).keys, ['id']);
      expect((items.last! as Map<String, Object?>)['id'], 2);
    });

    test('is missing without evaluating when a declared input is absent', () {
      var reported = false;
      void report(Object error, StackTrace stack) => reported = true;
      expect(
        evaluateOrMissing(_nullableFlag, onError: report),
        same(valueMissing),
      );
      expect(
        evaluateOrMissing(_program, captures: {'count': 5}, onError: report),
        same(valueMissing),
      );
      expect(reported, isFalse);
      expect(
        evaluateOrMissing(_nullableFlag, captures: {'flag': null}),
        isTrue,
      );
    });

    test('is missing when a declared capture it never reads is absent', () {
      const program = ValueProgram(
        nodes: [ValueNode('literal', ValueType.boolean, value: true)],
        root: 0,
        captures: {'unused': ValueType.integer},
      );
      expect(evaluateOrMissing(program), same(valueMissing));
      expect(
        evaluateOrMissing(program, parameters: {'unused': 1}),
        same(valueMissing),
      );
      expect(evaluateOrMissing(program, captures: {'unused': 1}), isTrue);
    });

    test('takes each input only from the map for its binding', () {
      var reported = false;
      void report(Object error, StackTrace stack) => reported = true;
      expect(
        evaluateOrMissing(
          _nullableFlag,
          parameters: {'flag': true},
          onError: report,
        ),
        same(valueMissing),
      );
      expect(
        evaluateOrMissing(
          _program,
          captures: {'count': 5, 'threshold': 3},
          onError: report,
        ),
        same(valueMissing),
      );
      expect(reported, isFalse);
    });

    test('is missing when a value inside a fact is absent or misshaped', () {
      var reported = false;
      void report(Object error, StackTrace stack) => reported = true;
      for (final user in <Object?>[
        <String, Object?>{},
        'not a record',
        {'isPro': 'not a bool'},
      ]) {
        expect(
          evaluateOrMissing(
            _nestedFlag,
            captures: {'user': user},
            onError: report,
          ),
          same(valueMissing),
          reason: '$user',
        );
      }
      expect(reported, isFalse);
      expect(
        evaluateOrMissing(
          _nestedFlag,
          captures: {
            'user': {'isPro': null},
          },
        ),
        isTrue,
      );
      expect(
        evaluateOrMissing(
          _nestedFlag,
          captures: {
            'user': {'isPro': true},
          },
        ),
        isFalse,
      );
    });

    test('checks every field of a record or list result', () {
      const record = ValueType('record', fields: {'id': ValueType.integer});
      const items = ValueType('list', item: record);
      expect(
        evaluateOrMissing(
          _capturing(record),
          captures: {
            'x': {'id': 'not an int'},
          },
        ),
        same(valueMissing),
      );
      expect(
        evaluateOrMissing(
          _capturing(items),
          captures: {
            'x': [
              {'id': 1},
              {'id': 'two'},
            ],
          },
        ),
        same(valueMissing),
      );
      expect(
        evaluateOrMissing(_capturing(items), captures: {'x': 'not a list'}),
        same(valueMissing),
      );
    });

    test('reports and returns valueMissing when evaluation throws', () {
      Object? reported;
      StackTrace? trace;
      final result = evaluateOrMissing(
        const ValueProgram(
          nodes: [ValueNode('fail', ValueType.boolean)],
          root: 0,
        ),
        operations: const {'fail': _FailingOperation()},
        onError: (error, stack) {
          reported = error;
          trace = stack;
        },
      );
      expect(result, same(valueMissing));
      expect(reported, isA<StateError>());
      expect(trace.toString(), isNotEmpty);
      expect(valueMissing.toString(), 'valueMissing');
    });

    test('reports and returns valueMissing when validation throws', () {
      Object? reported;
      final result = evaluateOrMissing(
        const ValueProgram(
          nodes: [ValueNode('noSuchOperation', ValueType.boolean)],
          root: 0,
        ),
        onError: (error, _) => reported = error,
      );
      expect(result, same(valueMissing));
      expect(reported, isA<FormatException>());
    });

    test('ignores an error the reporter throws', () {
      expect(
        evaluateOrMissing(
          const ValueProgram(
            nodes: [ValueNode('noSuchOperation', ValueType.boolean)],
            root: 0,
          ),
          onError: (_, __) => throw StateError('reporter failed'),
        ),
        same(valueMissing),
      );
    });
  });
}
