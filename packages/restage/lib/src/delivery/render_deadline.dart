import 'dart:async';

import 'package:meta/meta.dart';

/// One mount's render deadline, started when the mount starts.
@internal
final class RenderDeadline {
  /// Starts a deadline that passes [duration] from now.
  RenderDeadline.start(Duration duration) {
    if (duration <= Duration.zero) {
      _pass();
    } else {
      _timer = Timer(duration, _pass);
    }
  }

  /// The default time a mount waits before it renders local content.
  static const Duration defaultDuration = Duration(milliseconds: 300);

  final Completer<void> _reached = Completer<void>();
  Timer? _timer;

  /// Whether the deadline has passed.
  bool get hasPassed => _reached.isCompleted;

  /// Completes when the deadline passes.
  Future<void> get reached => _reached.future;

  /// Stops the timer; [reached] then never completes.
  void cancel() => _timer?.cancel();

  void _pass() {
    if (!_reached.isCompleted) _reached.complete();
  }
}
