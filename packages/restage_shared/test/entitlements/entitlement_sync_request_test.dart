import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('EntitlementSyncRequest', () {
    test('JSON round-trips with appAnonymousToken and known ids', () {
      final request = EntitlementSyncRequest(
        appAnonymousToken: '11111111-1111-4111-8111-111111111111',
        knownStoreTransactionIds: const ['tx-1', 'tx-2'],
      );

      final json = request.toJson();
      final parsed = EntitlementSyncRequest.fromJson(json);

      expect(parsed, request);
      expect(json['appAnonymousToken'], '11111111-1111-4111-8111-111111111111');
      expect(json['knownStoreTransactionIds'], ['tx-1', 'tx-2']);
    });

    test('JSON omits appAnonymousToken when null', () {
      final request = EntitlementSyncRequest(
        knownStoreTransactionIds: const ['tx-1'],
      );

      final json = request.toJson();

      expect(json.containsKey('appAnonymousToken'), isFalse);
      expect(json['knownStoreTransactionIds'], ['tx-1']);
      expect(EntitlementSyncRequest.fromJson(json), request);
    });

    test('JSON serializes an empty known-ids list explicitly', () {
      final request = EntitlementSyncRequest();

      final json = request.toJson();

      expect(json['knownStoreTransactionIds'], isEmpty);
      expect(EntitlementSyncRequest.fromJson(json), request);
    });

    test('fromJson treats a missing knownStoreTransactionIds as empty', () {
      final parsed = EntitlementSyncRequest.fromJson(const {});

      expect(parsed.knownStoreTransactionIds, isEmpty);
      expect(parsed.appAnonymousToken, isNull);
    });

    test('fromJson rejects a non-list knownStoreTransactionIds', () {
      expect(
        () => EntitlementSyncRequest.fromJson(
          const {'knownStoreTransactionIds': 'tx'},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fromJson rejects a list containing non-string entries', () {
      expect(
        () => EntitlementSyncRequest.fromJson(const {
          'knownStoreTransactionIds': ['tx-1', 123],
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fromJson rejects a list containing empty-string entries', () {
      expect(
        () => EntitlementSyncRequest.fromJson(const {
          'knownStoreTransactionIds': ['tx-1', ''],
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fromJson rejects an empty-string appAnonymousToken', () {
      expect(
        () => EntitlementSyncRequest.fromJson(const {
          'appAnonymousToken': '',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('value equality respects field-by-field comparison', () {
      final a = EntitlementSyncRequest(
        appAnonymousToken: 't',
        knownStoreTransactionIds: const ['x', 'y'],
      );
      final b = EntitlementSyncRequest(
        appAnonymousToken: 't',
        knownStoreTransactionIds: const ['x', 'y'],
      );
      final cDifferentToken = EntitlementSyncRequest(
        appAnonymousToken: 'u',
        knownStoreTransactionIds: const ['x', 'y'],
      );
      final dDifferentIds = EntitlementSyncRequest(
        appAnonymousToken: 't',
        knownStoreTransactionIds: const ['x', 'z'],
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(cDifferentToken));
      expect(a, isNot(dDifferentIds));
    });

    test('primary constructor stores an unmodifiable known-ids list', () {
      final ids = ['tx-1'];
      final request = EntitlementSyncRequest(knownStoreTransactionIds: ids);
      expect(
        () => request.knownStoreTransactionIds.add('tx-2'),
        throwsUnsupportedError,
      );
    });
  });
}
