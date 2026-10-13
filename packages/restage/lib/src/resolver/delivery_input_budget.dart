import 'dart:async';

import 'package:meta/meta.dart';

/// One deadline for a hosted request's optional identity, metering, assignment
/// and observation inputs. Unanswered inputs are omitted at the deadline.
/// Call [close] when the request no longer needs it.
@internal
final class DeliveryInputBudget {
  DeliveryInputBudget([Duration total = defaultTotal]) {
    _timer = Timer(total, () {
      if (!_expired.isCompleted) _expired.complete();
    });
  }

  /// The longest a request waits for all of its optional inputs together.
  static const Duration defaultTotal = Duration(seconds: 2);

  /// Runs [body] under [shared], or under a budget owned and closed here.
  static Future<T> run<T>(
    Future<T> Function(DeliveryInputBudget budget) body, {
    DeliveryInputBudget? shared,
    Duration total = defaultTotal,
  }) async {
    if (shared != null) return body(shared);
    final owned = DeliveryInputBudget(total);
    try {
      return await body(owned);
    } finally {
      owned.close();
    }
  }

  final Completer<void> _expired = Completer<void>();
  late final Timer _timer;

  /// [input]'s value, or null once the deadline has passed without one.
  Future<T?> bound<T>(Future<T?> input) => Future.any<T?>(<Future<T?>>[
        input,
        _expired.future.then<T?>((_) => null),
      ]);

  /// Releases the deadline timer.
  void close() => _timer.cancel();
}
