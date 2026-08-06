import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

void main() {
  test('real builder preserves fractional integer bounds plus scalar enum', () {
    final schema = S.fromMap(<String, Object?>{
      ...S.integer().value,
      'minimum': 0.5,
      'maximum': 9.5,
      'enum': <Object?>[1, 2],
    });

    expect(schema.value, {
      'type': 'integer',
      'minimum': 0.5,
      'maximum': 9.5,
      'enum': [1, 2],
    });
  });

  test('real builder preserves scalar-list structure plus item counts', () {
    final schema = S.fromMap(<String, Object?>{
      ...S.list(items: S.string()).value,
      'minItems': 1,
      'maxItems': 3,
    });

    expect(schema.value, {
      'type': 'array',
      'items': {'type': 'string'},
      'minItems': 1,
      'maxItems': 3,
    });
  });
}
