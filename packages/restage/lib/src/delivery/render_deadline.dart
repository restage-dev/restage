import 'dart:async';

import 'package:meta/meta.dart';

/// One mount's waits, started when the mount starts: the first-launch wait
/// for a placement with nothing saved, and the shorter fresh window for one
/// with saved content.
@internal
final class RenderDeadline {
  /// Starts a deadline that passes [duration] from now, and a fresh window
  /// that passes [window] from now.
  RenderDeadline.start(Duration duration, {Duration? window}) {
    if (duration <= Duration.zero) {
      _pass();
    } else {
      _timer = Timer(duration, _pass);
    }
    final fresh = window ?? duration;
    if (fresh <= Duration.zero) {
      _passWindow();
    } else {
      _windowTimer = Timer(fresh, _passWindow);
    }
  }

  /// The default time a placement with nothing saved waits for delivered
  /// content before it renders its original.
  static const Duration defaultFirstLaunchWait = Duration(seconds: 1);

  /// The default time a placement with saved content waits for a fresher
  /// version.
  static const Duration defaultFreshWindow = Duration(milliseconds: 150);

  final Completer<void> _reached = Completer<void>();
  final Completer<void> _windowReached = Completer<void>();
  Timer? _timer;
  Timer? _windowTimer;

  /// Whether the fresh window has passed.
  bool get windowHasPassed => _windowReached.isCompleted;

  /// Completes when the fresh window passes.
  Future<void> get windowPassed => _windowReached.future;

  /// Whether the deadline has passed.
  bool get hasPassed => _reached.isCompleted;

  /// Completes when the deadline passes.
  Future<void> get reached => _reached.future;

  /// Stops the timer; [reached] then never completes.
  void cancel() {
    _timer?.cancel();
    _windowTimer?.cancel();
  }

  void _passWindow() {
    if (!_windowReached.isCompleted) _windowReached.complete();
  }

  void _pass() {
    if (!_reached.isCompleted) _reached.complete();
  }
}
