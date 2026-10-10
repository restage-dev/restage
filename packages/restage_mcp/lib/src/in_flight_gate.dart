import 'dart:async';

/// Keeps input open until [track]ed calls finish, bounded by [drainBudget].
/// JSON-RPC peers drop responses after input closes; [holdCloseUntilDrained]
/// lets pending calls respond without letting a hung call pin the process.
final class InFlightGate {
  InFlightGate({this.drainBudget = const Duration(seconds: 60)});

  final Duration drainBudget;
  int _inFlight = 0;
  Completer<void>? _drained;

  /// Run [body], counting it as in flight until it completes.
  Future<T> track<T>(Future<T> Function() body) async {
    _inFlight++;
    try {
      return await body();
    } finally {
      _inFlight--;
      if (_inFlight == 0) {
        _drained?.complete();
        _drained = null;
      }
    }
  }

  Future<void> _whenDrained() {
    if (_inFlight == 0) return Future<void>.value();
    return (_drained ??= Completer<void>()).future;
  }

  /// [input], with its end deferred until in-flight calls have answered.
  Stream<String> holdCloseUntilDrained(Stream<String> input) {
    final controller = StreamController<String>();
    late final StreamSubscription<String> subscription;
    subscription = input.listen(
      controller.add,
      onError: controller.addError,
      onDone: () async {
        await _whenDrained().timeout(drainBudget, onTimeout: () {});
        // Let the peer write the answers of the calls that just finished.
        await Future<void>.delayed(Duration.zero);
        await controller.close();
      },
    );
    controller
      ..onPause = subscription.pause
      ..onResume = subscription.resume
      ..onCancel = subscription.cancel;
    return controller.stream;
  }
}
