import 'package:flutter_test/flutter_test.dart';

const _hangGuard = Duration(seconds: 20);

/// Pumps frames and yields to the real event loop until [predicate] holds.
///
/// Fails only when [predicate] is still false after the wall-clock hang guard,
/// so a slow machine delays the test but never fails it.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required String reason,
  Duration step = Duration.zero,
  Duration realDelay = const Duration(milliseconds: 5),
}) async {
  final clock = Stopwatch()..start();
  while (!predicate()) {
    if (clock.elapsed > _hangGuard) {
      fail('Timed out after $_hangGuard waiting for $reason.');
    }
    await tester.pump(step);
    await tester.runAsync(() => Future<void>.delayed(realDelay));
  }
}

/// Yields until [predicate] holds, without drawing frames.
///
/// A null [realDelay] spins on microtasks and is safe in widget-test bodies.
/// A non-null [realDelay] waits on the real clock, for `test()` bodies or
/// inside `runAsync`.
Future<void> waitUntil(
  bool Function() predicate, {
  required String reason,
  Duration? realDelay,
}) async {
  final clock = Stopwatch()..start();
  while (!predicate()) {
    if (clock.elapsed > _hangGuard) {
      fail('Timed out after $_hangGuard waiting for $reason.');
    }
    await (realDelay == null
        ? Future<void>.value()
        : Future<void>.delayed(realDelay));
  }
}
