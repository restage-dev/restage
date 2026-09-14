import 'package:restage_shared/commerce.dart';
import 'package:test/test.dart';

const _intentId = '550e8400-e29b-41d4-a716-446655440000';
const _token = '550e8400-e29b-41d4-a716-446655440001';

void main() {
  test('intent responses tolerate additive fields', () {
    final response = CommerceIntentResponse.fromJson(
      const <String, dynamic>{
        'intentId': _intentId,
        'status': 'ready',
        'resolved': <String, dynamic>{
          'storeProductId': 'pro.monthly.us',
          'productKind': 'autoRenewableSubscription',
          'appAccountToken': _token,
          'futureField': 'ignored',
        },
        'futureField': 'ignored',
      },
    );

    expect(response.resolved.storeProductId, 'pro.monthly.us');
  });
}
