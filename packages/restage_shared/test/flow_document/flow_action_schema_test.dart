import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('FlowActionSchema hashing', () {
    test('computes golden hashes for primitive bool args and results', () {
      const schema = FlowActionSchema.bool();

      expect(
        FlowActionSchema.hashFor(contractKind: 'args', schema: schema).value,
        _boolArgsHash,
      );
      expect(
        FlowActionSchema.hashFor(contractKind: 'result', schema: schema).value,
        _boolResultHash,
      );
    });

    test('computes a golden hash for an object result with a bool field', () {
      const schema = FlowActionSchema.object({
        'completed': FlowActionSchemaField(
          required: true,
          schema: FlowActionSchema.bool(),
        ),
      });

      expect(
        FlowActionSchema.hashFor(contractKind: 'result', schema: schema).value,
        _objectResultHash,
      );
    });

    test('object field order does not affect canonical hash', () {
      const schema = FlowActionSchema.object({
        'enabled': FlowActionSchemaField(
          required: false,
          schema: FlowActionSchema.bool(),
        ),
        'completed': FlowActionSchemaField(
          required: true,
          schema: FlowActionSchema.bool(),
        ),
      });
      const reordered = FlowActionSchema.object({
        'completed': FlowActionSchemaField(
          required: true,
          schema: FlowActionSchema.bool(),
        ),
        'enabled': FlowActionSchemaField(
          required: false,
          schema: FlowActionSchema.bool(),
        ),
      });

      expect(
        FlowActionSchema.hashFor(contractKind: 'result', schema: reordered),
        FlowActionSchema.hashFor(contractKind: 'result', schema: schema),
      );
    });

    test('changed field type changes the hash and reports a structural diff',
        () {
      const expected = FlowActionSchema.object({
        'completed': FlowActionSchemaField(
          required: true,
          schema: FlowActionSchema.bool(),
        ),
      });
      const actual = FlowActionSchema.object({
        'completed': FlowActionSchemaField(
          required: true,
          schema: FlowActionSchema.string(),
        ),
      });

      expect(
        FlowActionSchema.hashFor(contractKind: 'result', schema: actual),
        isNot(
            FlowActionSchema.hashFor(contractKind: 'result', schema: expected)),
      );
      expect(
        FlowActionSchema.diff(expected, actual),
        contains(
          const FlowActionSchemaDiff(
            code: FlowActionSchemaDiffCode.kindMismatch,
            path: r'$.completed',
            expected: 'bool',
            actual: 'string',
          ),
        ),
      );
    });

    test('changed enum wire value changes the hash and reports a diff', () {
      const expected = FlowActionSchema.enumValues(['granted']);
      const actual = FlowActionSchema.enumValues(['denied']);

      expect(
        FlowActionSchema.hashFor(contractKind: 'result', schema: actual),
        isNot(
            FlowActionSchema.hashFor(contractKind: 'result', schema: expected)),
      );
      expect(
        FlowActionSchema.diff(expected, actual),
        contains(
          const FlowActionSchemaDiff(
            code: FlowActionSchemaDiffCode.enumValueMismatch,
            path: r'$[0]',
            expected: 'granted',
            actual: 'denied',
          ),
        ),
      );
    });

    test('enum wire value order does not affect canonical hash', () {
      const schema = FlowActionSchema.enumValues(['denied', 'granted']);
      const reordered = FlowActionSchema.enumValues(['granted', 'denied']);

      expect(
        FlowActionSchema.hashFor(contractKind: 'result', schema: reordered),
        FlowActionSchema.hashFor(contractKind: 'result', schema: schema),
      );
      expect(FlowActionSchema.diff(schema, reordered), isEmpty);
    });

    test('rejects empty and duplicate enum wire values', () {
      expect(
        () => FlowActionSchema.hashFor(
          contractKind: 'result',
          schema: const FlowActionSchema.enumValues([]),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => FlowActionSchema.hashFor(
          contractKind: 'result',
          schema: const FlowActionSchema.enumValues(['granted', 'granted']),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('reports missing and extra object fields', () {
      const expected = FlowActionSchema.object({
        'completed': FlowActionSchemaField(
          required: true,
          schema: FlowActionSchema.bool(),
        ),
      });
      const actual = FlowActionSchema.object({
        'enabled': FlowActionSchemaField(
          required: true,
          schema: FlowActionSchema.bool(),
        ),
      });

      expect(
        FlowActionSchema.diff(expected, actual),
        containsAll([
          const FlowActionSchemaDiff(
            code: FlowActionSchemaDiffCode.missingField,
            path: r'$.completed',
            expected: 'field',
            actual: null,
          ),
          const FlowActionSchemaDiff(
            code: FlowActionSchemaDiffCode.extraField,
            path: r'$.enabled',
            expected: null,
            actual: 'field',
          ),
        ]),
      );
    });

    test('reports field required mismatches distinctly', () {
      const expected = FlowActionSchema.object({
        'completed': FlowActionSchemaField(
          required: true,
          schema: FlowActionSchema.bool(),
        ),
      });
      const actual = FlowActionSchema.object({
        'completed': FlowActionSchemaField(
          required: false,
          schema: FlowActionSchema.bool(),
        ),
      });

      expect(
        FlowActionSchema.diff(expected, actual),
        contains(
          const FlowActionSchemaDiff(
            code: FlowActionSchemaDiffCode.fieldRequiredMismatch,
            path: r'$.completed.required',
            expected: 'true',
            actual: 'false',
          ),
        ),
      );
    });

    test('reports list and nullable child mismatches', () {
      const expected = FlowActionSchema.list(FlowActionSchema.bool());
      const actual = FlowActionSchema.list(FlowActionSchema.string());
      const nullableExpected = FlowActionSchema.nullable(
        FlowActionSchema.bool(),
      );
      const nullableActual = FlowActionSchema.nullable(
        FlowActionSchema.string(),
      );

      expect(
        FlowActionSchema.diff(expected, actual),
        contains(
          const FlowActionSchemaDiff(
            code: FlowActionSchemaDiffCode.listChildMismatch,
            path: r'$[]',
            expected: 'bool',
            actual: 'string',
          ),
        ),
      );
      expect(
        FlowActionSchema.diff(nullableExpected, nullableActual),
        contains(
          const FlowActionSchemaDiff(
            code: FlowActionSchemaDiffCode.nullableChildMismatch,
            path: r'$?',
            expected: 'bool',
            actual: 'string',
          ),
        ),
      );
    });

    test('rejects unsupported contract kinds', () {
      expect(
        () => FlowActionSchema.hashFor(
          contractKind: 'event',
          schema: const FlowActionSchema.bool(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

const _boolArgsHash = 'sha256:9f23435e83458f85c193f9a262b7fee'
    '6fac66c8e45ebd5743dbceadf45bc7221';
const _boolResultHash = 'sha256:b381695502a4099cf3610d182b471a25'
    '62086e5e8bdb11f4426f63ba512542b3';
const _objectResultHash = 'sha256:af25943be7c85d12d72ca1430e2ba0f6'
    '5c8b9ff63177292b90a4624407324c8b';
