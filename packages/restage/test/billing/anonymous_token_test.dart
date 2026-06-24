import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/billing/anonymous_token.dart';
import 'package:restage/src/billing/in_app_purchase_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnonymousTokenStore.isValidUuid', () {
    test('accepts canonical-form lowercase UUIDv4', () {
      expect(
        AnonymousTokenStore.isValidUuid(
          '11111111-2222-4333-8444-555555555555',
        ),
        isTrue,
      );
    });

    test('accepts canonical-form uppercase UUIDv4', () {
      expect(
        AnonymousTokenStore.isValidUuid(
          'AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE',
        ),
        isTrue,
      );
    });

    test('rejects wrong length', () {
      expect(AnonymousTokenStore.isValidUuid('too-short'), isFalse);
      expect(
        AnonymousTokenStore.isValidUuid(
          '11111111-2222-4333-8444-5555555555555',
        ),
        isFalse,
      );
    });

    test('rejects missing dash separators', () {
      expect(
        AnonymousTokenStore.isValidUuid(
          '111111112222433384445555555555555555',
        ),
        isFalse,
      );
    });

    test('rejects non-hex characters', () {
      expect(
        AnonymousTokenStore.isValidUuid(
          '1111111z-2222-4333-8444-555555555555',
        ),
        isFalse,
      );
    });

    test('rejects wrong version nibble (not 4)', () {
      expect(
        AnonymousTokenStore.isValidUuid(
          '11111111-2222-1333-8444-555555555555',
        ),
        isFalse,
      );
    });

    test('rejects wrong variant nibble (not 8/9/a/b, case-insensitive)', () {
      // Lowercase 'c' (valid hex digit but not a valid variant) → rejected.
      expect(
        AnonymousTokenStore.isValidUuid(
          '11111111-2222-4333-c444-555555555555',
        ),
        isFalse,
      );
      // Uppercase 'C' — same outcome; ensures case-insensitive acceptance
      // of A/B doesn't accidentally expand to C/D.
      expect(
        AnonymousTokenStore.isValidUuid(
          '11111111-2222-4333-C444-555555555555',
        ),
        isFalse,
      );
    });

    test('accepts every valid variant nibble (8/9/a/b, case-insensitive)', () {
      for (final nibble in ['8', '9', 'a', 'b', 'A', 'B']) {
        expect(
          AnonymousTokenStore.isValidUuid(
            '11111111-2222-4333-${nibble}444-555555555555',
          ),
          isTrue,
          reason: 'variant nibble "$nibble" should be accepted',
        );
      }
    });
  });

  group('AnonymousTokenStore.generateUuidV4', () {
    test('produces a canonical-form UUIDv4 string', () {
      final token = AnonymousTokenStore.generateUuidV4();

      expect(AnonymousTokenStore.isValidUuid(token), isTrue);
    });

    test('produces distinct values across invocations', () {
      final a = AnonymousTokenStore.generateUuidV4();
      final b = AnonymousTokenStore.generateUuidV4();

      expect(a, isNot(b));
    });

    test(
        'with a seeded Random, produces a deterministic shape (version + variant nibbles forced)',
        () {
      // The seeded Random's exact bytes vary across Dart versions, so we
      // only assert the structural guarantees: version=4 + variant=8-b +
      // canonical length.
      final token = AnonymousTokenStore.generateUuidV4(random: Random(42));

      expect(AnonymousTokenStore.isValidUuid(token), isTrue);
    });
  });

  group('AnonymousTokenStore.getOrCreate', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('generates and persists a new UUID on first call', () async {
      final store = AnonymousTokenStore();

      final token = await store.getOrCreate();

      expect(AnonymousTokenStore.isValidUuid(token), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('restage.anonymous_app_user_token'), token);
    });

    test('returns the same token on subsequent calls', () async {
      final store = AnonymousTokenStore();

      final first = await store.getOrCreate();
      final second = await store.getOrCreate();

      expect(second, first);
    });

    test('a fresh instance reads the persisted token', () async {
      final firstStore = AnonymousTokenStore();
      final token = await firstStore.getOrCreate();

      final secondStore = AnonymousTokenStore();
      final secondToken = await secondStore.getOrCreate();

      expect(secondToken, token);
    });

    test('regenerates when the persisted value is not a valid UUID', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'restage.anonymous_app_user_token': 'corrupted-value',
      });
      final store = AnonymousTokenStore();

      final token = await store.getOrCreate();

      expect(token, isNot('corrupted-value'));
      expect(AnonymousTokenStore.isValidUuid(token), isTrue);
    });

    test('cached returns null before any getOrCreate call', () {
      final store = AnonymousTokenStore();

      expect(store.cached, isNull);
    });

    test('cached returns the resolved token after getOrCreate', () async {
      final store = AnonymousTokenStore();

      final token = await store.getOrCreate();

      expect(store.cached, token);
    });
  });

  group('resolveApplicationUserNameForStamping', () {
    test('returns null when the provider is null', () async {
      expect(await resolveApplicationUserNameForStamping(null), isNull);
    });

    test('returns null when the provider yields null', () async {
      expect(
        await resolveApplicationUserNameForStamping(() async => null),
        isNull,
      );
    });

    test('returns null when the provider yields a non-UUID string', () async {
      expect(
        await resolveApplicationUserNameForStamping(() async => 'not-a-uuid'),
        isNull,
      );
    });

    test('returns the value when the provider yields a canonical UUIDv4',
        () async {
      const token = '11111111-2222-4333-8444-555555555555';

      expect(
        await resolveApplicationUserNameForStamping(() async => token),
        token,
      );
    });
  });
}
