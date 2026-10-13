import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_outbox_protocol.dart';

void main() {
  test('retry delay stays within ±25% of the base for every attempt', () {
    for (var attempt = 0;
        attempt <= kMeasurementOutboxMaximumRetryAttempt;
        attempt++) {
      final base = attempt >= 12 ? 3600 : 1 << attempt;
      for (var i = 0; i < 50; i++) {
        final delay = measurementOutboxRetryDelay(attempt, random: Random(i))
            .inMilliseconds;
        expect(
          delay,
          inInclusiveRange((base * 750).round(), (base * 1250).round()),
        );
      }
    }
  });

  test('two records with the same attempt do not share a delay', () {
    final a = measurementOutboxRetryDelay(3, random: Random(1));
    final b = measurementOutboxRetryDelay(3, random: Random(2));
    expect(a, isNot(b));
  });

  test('rejects an attempt outside the persisted range', () {
    expect(() => measurementOutboxRetryDelay(-1), throwsArgumentError);
    expect(
      () => measurementOutboxRetryDelay(
        kMeasurementOutboxMaximumRetryAttempt + 1,
      ),
      throwsArgumentError,
    );
  });
}
