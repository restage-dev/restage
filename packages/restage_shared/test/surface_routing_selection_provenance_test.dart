import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  final complete = const <String, Object?>{
    'selectedRouteId': 'route-a',
    'audienceRevisionRef': 'audience-v2',
    'routingRevisionOrdinal': 3,
    'rolloutAllocationId': 'allocation-a',
    'rolloutBranch': 'control',
    'defaultSelectionReason': 'no-match'
  };
  for (final missing in [null, ...complete.keys]) {
    test('round trips with omitted member $missing', () {
      final json = {...complete};
      if (missing != null) json.remove(missing);
      final decoded = SurfaceRoutingSelectionProvenanceV1.fromJson(json);
      expect(decoded.toJson(), json);
      final copy =
          SurfaceRoutingSelectionProvenanceV1.fromJson(decoded.toJson());
      expect(copy, decoded);
      expect(copy.hashCode, decoded.hashCode);
    });
  }
  test('all members may be absent or null', () {
    expect(SurfaceRoutingSelectionProvenanceV1.fromJson({}).toJson(), isEmpty);
    expect(
        SurfaceRoutingSelectionProvenanceV1.fromJson({
          for (final key in complete.keys) key: null,
        }).toJson(),
        isEmpty);
    expect(SurfaceRoutingSelectionProvenanceV1.normalize(null), isNull);
  });
  final invalid = <Object?>[
    {...complete, 'unknown': 'value'},
    'invalid',
    [],
    for (final key
        in complete.keys.where((key) => key != 'routingRevisionOrdinal'))
      {...complete, key: 'x' * 257},
    for (final key
        in complete.keys.where((key) => key != 'routingRevisionOrdinal'))
      {...complete, key: 1},
    for (final value in [-1, 1.5, '1'])
      {...complete, 'routingRevisionOrdinal': value},
  ];
  for (var index = 0; index < invalid.length; index++) {
    test('refuses malformed metadata $index', () {
      expect(() => SurfaceRoutingSelectionProvenanceV1.fromJson(invalid[index]),
          throwsFormatException);
      expect(SurfaceRoutingSelectionProvenanceV1.normalize(invalid[index]),
          isNull);
    });
  }
  test('accepts the string bound and zero ordinal', () {
    final json = {
      for (final key in complete.keys)
        key: key == 'routingRevisionOrdinal' ? 0 : 'x' * 256,
    };
    expect(SurfaceRoutingSelectionProvenanceV1.fromJson(json).toJson(), json);
  });
}
