import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  final received = DateTime.utc(2026, 6, 13, 12);

  test('kMaxEventSkew is 48 hours', () {
    expect(kMaxEventSkew, const Duration(hours: 48));
  });

  test('future client time (clock-ahead device) clamps to receivedAt', () {
    final client = received.add(const Duration(hours: 3));
    expect(
      clampOccurredAt(clientOccurredAt: client, receivedAt: received),
      received,
    );
  });

  test('past within skew is kept verbatim', () {
    final client = received.subtract(const Duration(hours: 12));
    expect(
      clampOccurredAt(clientOccurredAt: client, receivedAt: received),
      client,
    );
  });

  test('exactly at the skew floor is kept (boundary inclusive)', () {
    final client = received.subtract(kMaxEventSkew);
    expect(
      clampOccurredAt(clientOccurredAt: client, receivedAt: received),
      client,
    );
  });

  test('stale/malicious past clamps to receivedAt - skew, never dropped', () {
    final client = received.subtract(const Duration(days: 30));
    expect(
      clampOccurredAt(clientOccurredAt: client, receivedAt: received),
      received.subtract(kMaxEventSkew),
    );
  });
}
