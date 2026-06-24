import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('containsReservedKey', () {
    test('true for the top-level reserved namespaces', () {
      expect(containsReservedKey({'data': 1}), isTrue);
      expect(containsReservedKey({'context': 1}), isTrue);
    });

    test('true for flattened reserved paths', () {
      expect(containsReservedKey({'data.context.userId': 'x'}), isTrue);
      expect(containsReservedKey({'data.theme.primary': '#fff'}), isTrue);
      expect(containsReservedKey({'context.locale': 'en'}), isTrue);
    });

    test('false for benign keys', () {
      expect(containsReservedKey({'plan': 'pro', 'price': 9.99}), isFalse);
      // "database" / "contextual" must NOT trip the prefix guard.
      expect(containsReservedKey({'database': 1, 'contextual': 2}), isFalse);
    });

    test('case-insensitive + whitespace-trimmed (no casing/spacing bypass)',
        () {
      expect(containsReservedKey({'Data': 1}), isTrue);
      expect(containsReservedKey({'CONTEXT': 1}), isTrue);
      expect(containsReservedKey({' data': 1}), isTrue);
      expect(containsReservedKey({'Data.Context.x': 1}), isTrue);
      // Benign look-alikes still survive under case-folding.
      expect(containsReservedKey({'Database': 1, 'Contextual': 2}), isFalse);
    });
  });

  group('scrubReservedKeys', () {
    test('drops reserved keys, keeps the rest, returns a new map', () {
      final input = <String, Object?>{
        'plan': 'pro',
        'data': {'context': 'secret'},
        'data.context.foo': 'bar',
        'context': 'leak',
        'count': 3,
      };
      final scrubbed = scrubReservedKeys(input);
      expect(scrubbed, {'plan': 'pro', 'count': 3});
      // Non-mutating.
      expect(input.containsKey('data'), isTrue);
    });

    test('benign look-alikes survive', () {
      expect(
        scrubReservedKeys({'database': 1, 'contextual': 2, 'metadata': 3}),
        {'database': 1, 'contextual': 2, 'metadata': 3},
      );
    });

    test('drops case/space variants of the reserved namespaces', () {
      expect(
        scrubReservedKeys({'Data': 1, ' context': 2, 'ok': 3}),
        {'ok': 3},
      );
    });
  });
}
