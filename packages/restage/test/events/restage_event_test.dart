import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('DismissReason enum stable', () {
    expect(DismissReason.values.toSet(), {
      DismissReason.userClose,
      DismissReason.purchaseCompleted,
      DismissReason.purchasePending,
      DismissReason.restoreCompleted,
      DismissReason.programmatic,
    });
  });

  test('PendingReason enum stable', () {
    expect(PendingReason.values.toSet(), {
      PendingReason.askToBuy,
      PendingReason.paymentPending,
      PendingReason.unknown,
    });
  });

  test('RevokeReason enum stable', () {
    expect(RevokeReason.values.toSet(), {
      RevokeReason.expired,
      RevokeReason.refunded,
      RevokeReason.revoked,
      RevokeReason.upgraded,
    });
  });
}
