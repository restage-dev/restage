import 'dart:collection';

import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:test/test.dart';

void main() {
  test('seals strict parser maps and lists without changing public decode', () {
    final bytes = CanonicalJsonCodec.encode({
      'nested': {
        'items': [
          1,
          {'name': 'sealed'},
        ],
      },
    });

    final publicRoot =
        CanonicalJsonCodec.decode(bytes)! as Map<String, Object?>;
    final publicItems = (publicRoot['nested']!
        as Map<String, Object?>)['items']! as List<Object?>;
    expect(publicItems..add('mutable'), hasLength(3));

    final matches = decodeStrictCanonicalObject(bytes, (root) {
      final nested = root['nested']! as Map<String, Object?>;
      final nestedFromEntry =
          root.entries.single.value! as Map<String, Object?>;
      final items = nested['items']! as List<Object?>;
      final item = items[1]! as Map<String, Object?>;

      expect(() => root['other'] = true, throwsUnsupportedError);
      expect(() => nested.remove('items'), throwsUnsupportedError);
      expect(() => nestedFromEntry['other'] = true, throwsUnsupportedError);
      expect(() => items.add('blocked'), throwsUnsupportedError);
      expect(
        () => (root.keys as List<String>).add('blocked'),
        throwsUnsupportedError,
      );
      expect(
        () => (root.values as List<Object?>).add('blocked'),
        throwsUnsupportedError,
      );
      expect(() => item['other'] = true, throwsUnsupportedError);

      return strictCanonicalFidelityCanReturn(
        root,
        () => {
          'nested': {
            'items': [
              1,
              {'name': 'sealed'},
            ],
          },
        },
      );
    });

    expect(matches, isTrue);
  });

  test('uses structural fidelity only for complete equal strict trees', () {
    final bytes = CanonicalJsonCodec.encode({
      'count': 1,
      'items': [
        {'name': 'first'},
        {'name': 'second'},
      ],
    });

    final results = decodeStrictCanonicalObject(
      bytes,
      (root) => [
        strictCanonicalFidelityCanReturn(
          root,
          () => {
            'count': 1,
            'items': [
              {'name': 'first'},
              {'name': 'second'},
            ],
          },
        ),
        strictCanonicalFidelityCanReturn(
          root,
          () => {
            'count': 1.0,
            'items': [
              {'name': 'first'},
              {'name': 'second'},
            ],
          },
        ),
        strictCanonicalFidelityCanReturn(
          root,
          () => {
            'count': 1,
            'items': [
              {'name': 'second'},
              {'name': 'first'},
            ],
          },
        ),
        strictCanonicalFidelityCanReturn(
          root,
          () => {
            'count': 1,
            'extra': true,
            'items': [
              {'name': 'first'},
              {'name': 'second'},
            ],
          },
        ),
      ],
    );

    expect(results, [isTrue, isFalse, isFalse, isFalse]);
  });

  test('does not inspect public collection wrappers or swallow reconstruction',
      () {
    var rebuilt = false;
    expect(
      strictCanonicalFidelityCanReturn(_PublicMap(), () {
        rebuilt = true;
        return const {};
      }),
      isFalse,
    );
    expect(rebuilt, isFalse);

    final bytes = CanonicalJsonCodec.encode({'value': true});
    final customListFallback = decodeStrictCanonicalObject(
      CanonicalJsonCodec.encode({
        'items': [1],
      }),
      (root) => strictCanonicalFidelityCanReturn(
        root,
        () => {'items': _PublicList()},
      ),
    );
    expect(customListFallback, isFalse);

    expect(
      () => decodeStrictCanonicalObject(
        bytes,
        (root) => strictCanonicalFidelityCanReturn(
          root,
          () => throw StateError('reconstruct marker'),
        ),
      ),
      throwsStateError,
    );
  });
}

final class _PublicList extends ListBase<Object?> {
  @override
  int get length => throw StateError('public list was inspected');

  @override
  set length(int value) {
    throw UnsupportedError('public list is not mutable here');
  }

  @override
  Object? operator [](int index) =>
      throw StateError('public list was inspected');

  @override
  void operator []=(int index, Object? value) {
    throw UnsupportedError('public list is not mutable here');
  }
}

final class _PublicMap extends MapBase<String, Object?> {
  @override
  Iterable<String> get keys => throw StateError('public keys were inspected');

  @override
  Object? operator [](Object? key) => throw StateError('public map was read');

  @override
  void operator []=(String key, Object? value) {
    throw UnsupportedError('public map is not mutable here');
  }

  @override
  Object? remove(Object? key) {
    throw UnsupportedError('public map is not mutable here');
  }

  @override
  void clear() {
    throw UnsupportedError('public map is not mutable here');
  }
}
