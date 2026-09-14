import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('DismissReason enum stable', () {
    expect(DismissReason.values.toSet(), {
      DismissReason.userClose,
      DismissReason.programmatic,
    });
  });

  test('DismissReason parses known wire names', () {
    expect(DismissReasonWire.fromWire('user_close'), DismissReason.userClose);
    expect(
      DismissReasonWire.fromWire('unsupported'),
      DismissReason.programmatic,
    );
  });

  test('SurfaceDeliveryRateLimited exposes the requested delivery identity',
      () {
    final firedAt = DateTime.utc(2026, 9, 5, 12);
    final event = SurfaceDeliveryRateLimited(
      surface: Surface.message,
      surfaceId: 'welcome',
      retryAfter: const Duration(seconds: 7),
      firedAt: firedAt,
    );

    expect(event, isA<RestageEvent>());
    expect(event.name, 'surface_delivery_rate_limited');
    expect(event.paywallId, isNull);
    expect(event.toMap(), {
      'name': 'surface_delivery_rate_limited',
      'surface': 'message',
      'surfaceId': 'welcome',
      'retryAfterMs': 7000,
      'firedAt': firedAt.toIso8601String(),
    });
  });
}
