import 'package:restage_shared/commerce.dart';
import 'package:test/test.dart';

const _token = '550e8400-e29b-41d4-a716-446655440001';

void main() {
  group('CommercePurchaserStateRequest', () {
    test('round-trips a purchaser state request', () {
      final request = CommercePurchaserStateRequest(
        appAnonymousToken: _token,
        knownStoreTransactionIds: const ['tx-1', 'tx-2'],
      );

      expect(CommercePurchaserStateRequest.fromJson(request.toJson()), request);
      expect(
        () => request.knownStoreTransactionIds.add('tx-3'),
        throwsUnsupportedError,
      );
    });

    test('requires the application token and transaction list', () {
      expect(
        () => CommercePurchaserStateRequest.fromJson(const <String, dynamic>{
          'knownStoreTransactionIds': <String>[],
        }),
        throwsArgumentError,
      );
      expect(
        () => CommercePurchaserStateRequest.fromJson(const <String, dynamic>{
          'appAnonymousToken': _token,
        }),
        throwsArgumentError,
      );
    });
  });
}
