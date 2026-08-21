import 'dart:io';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  const fixtures = <String>{
    'experiment_publication_joint_v1.json',
    'experiment_layer_v1.json',
    'joint_allocation_v1.json',
  };

  for (final name in fixtures) {
    test('$name is canonical JSON before its typed codec exists', () {
      final bytes =
          File('test/fixtures/layer_allocation/$name').readAsBytesSync();
      final value = CanonicalJsonCodec.decode(bytes);

      expect(CanonicalJsonCodec.encode(value), bytes, reason: name);
      expect(value, isA<Map<String, Object?>>(), reason: name);
    });
  }
}
