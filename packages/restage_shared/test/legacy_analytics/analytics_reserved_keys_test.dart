import 'package:restage_shared/legacy_analytics.dart';
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
        scrubReservedKeys({
          'database': 1,
          'contextual': 2,
          'metadata': 3,
          'experimentIdentifier': 4,
          'variantIdentity': 5,
          'experimentEpochId': 6,
        }),
        {
          'database': 1,
          'contextual': 2,
          'metadata': 3,
          'experimentIdentifier': 4,
          'variantIdentity': 5,
          'experimentEpochId': 6,
        },
      );
    });

    test('drops case/space variants of the reserved namespaces', () {
      expect(
        scrubReservedKeys({'Data': 1, ' context': 2, 'ok': 3}),
        {'ok': 3},
      );
    });

    test('preserves data and context below the top level', () {
      const properties = <String, Object?>{
        'result': <String, Object?>{
          'data': <String, Object?>{'context': 'local'},
          'context': 'nested',
          'data.context.locale': 'en_US',
          'Context.Theme': 'dark',
        },
      };

      expect(scrubReservedKeys(properties), properties);
    });

    test('drops retired property tuples at exact and mixed casing', () {
      const preserved = <String, Object?>{
        'plan': 'pro',
        'experimentIdentifier': 'keep',
        'variantIdentity': 'keep',
        'experimentEpochId': 'keep',
      };

      for (final properties in <Map<String, Object?>>[
        <String, Object?>{
          ...preserved,
          'experimentId': 'exp-1',
          'variantId': 'variant-a',
          'experimentEpoch': 7,
        },
        <String, Object?>{
          ...preserved,
          'ExPeRiMeNtId': 'exp-2',
          'vArIaNtId': 'variant-b',
          'eXpErImEnTePoCh': 8,
        },
      ]) {
        expect(scrubReservedKeys(properties), preserved);
      }
    });

    test('drops nested retired property keys from maps and lists', () {
      final input = <String, Object?>{
        'payload': <String, Object?>{
          'label': 'visible',
          'ExPeRiMeNtId': 'exp-1',
          'experimentIdentifier': 'keep',
          'Data': 'preserve',
          'Contextual': 'keep',
          'items': <Object?>[
            <String, Object?>{
              'vArIaNtId': 'variant-a',
              'label': 'first',
              'variantIdentity': 'keep',
            },
            <String, Object?>{
              'nested': <String, Object?>{
                'eXpErImEnTePoCh': 7,
                'experimentEpochId': 'keep',
                'enabled': true,
                'nothing': null,
              },
            },
            'ordinary',
            42,
          ],
        },
      };

      expect(
        scrubReservedKeys(input),
        <String, Object?>{
          'payload': <String, Object?>{
            'label': 'visible',
            'experimentIdentifier': 'keep',
            'Data': 'preserve',
            'Contextual': 'keep',
            'items': <Object?>[
              <String, Object?>{
                'label': 'first',
                'variantIdentity': 'keep',
              },
              <String, Object?>{
                'nested': <String, Object?>{
                  'experimentEpochId': 'keep',
                  'enabled': true,
                  'nothing': null,
                },
              },
              'ordinary',
              42,
            ],
          },
        },
      );
      final payload = input['payload'];
      expect(payload, isA<Map<Object?, Object?>>());
      expect(
        (payload! as Map<Object?, Object?>).containsKey('ExPeRiMeNtId'),
        isTrue,
      );
    });
  });
}
