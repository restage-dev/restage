import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/runtime/event_demux.dart';

void main() {
  test('reserved event names are dropped', () {
    for (final name in const <String>[
      'purchase',
      'restore',
      'restage.purchase',
      'restage.restore',
      'restage.purchase.succeeded',
      'restage.purchase.pending',
      'restage.purchase.cancelled',
      'restage.purchase.failed',
      'restage.restore.succeeded',
      'restage.restore.noPurchases',
      'restage.restore.failed',
    ]) {
      expect(
        demuxRfwEvent(
          paywallId: 'upgrade',
          name: name,
          args: const {'ignored': true},
        ),
        isNull,
        reason: name,
      );
    }
  });

  test('other names remain custom events', () {
    final result = demuxRfwEvent(
      paywallId: 'upgrade',
      name: 'cta_tapped',
      args: const {'cta': 'continue'},
    );
    expect(result, isA<PaywallCustomEvent>());
    expect((result as PaywallCustomEvent).eventName, 'cta_tapped');
    expect(result.args, {'cta': 'continue'});
  });
}
