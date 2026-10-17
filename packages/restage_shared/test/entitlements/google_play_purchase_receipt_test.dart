import 'package:restage_shared/commerce.dart';
import 'package:test/test.dart';

void main() {
  test('preserves signed JSON bytes and signature through the current wire',
      () {
    const original = ' { "purchaseToken": "owned-token", "note": "é" } ';
    final receipt = GooglePlayPurchaseReceipt(
      originalJson: original,
      signature: 'signature-one',
    );
    final decoded = GooglePlayPurchaseReceipt.fromVerificationData(
      receipt.toVerificationData(),
    );
    expect(decoded.originalJson, original);
    expect(decoded.signature, 'signature-one');
    expect(decoded.purchaseToken, 'owned-token');
  });

  test('updated signed snapshots retain the same provider identity', () {
    final first = GooglePlayPurchaseReceipt(
      originalJson: '{"purchaseToken":"owned-token","acknowledged":false}',
      signature: 'signature-one',
    ).toVerificationData();
    final next = GooglePlayPurchaseReceipt(
      originalJson: '{"token":"owned-token","acknowledged":true}',
      signature: 'signature-two',
    ).toVerificationData();
    expect(commerceVerificationIdentity('play_store', first),
        commerceVerificationIdentity('play_store', next));
    expect(first, isNot(next));
  });

  test('bare tokens and malformed receipt objects are not current evidence',
      () {
    for (final value in [
      'owned-token',
      '{}',
      '{"originalJson":"{}","signature":"sig"}',
      '{"originalJson":"{\\"purchaseToken\\":\\"x\\"}","signature":"sig","extra":1}',
    ]) {
      expect(() => GooglePlayPurchaseReceipt.fromVerificationData(value),
          throwsFormatException);
    }
  });
}
