import 'dart:async';

import 'package:meta/meta.dart';

final Object _baseKey = Object();

/// Micros since a mount, read from the host's monotonic clock.
@internal
final class MeasurementMountClock {
  /// Starts counting from [readMicros]'s current value.
  MeasurementMountClock(this._readMicros) : _origin = _readMicros();

  /// A clock for a host with no monotonic clock of its own.
  factory MeasurementMountClock.stopwatch() {
    final stopwatch = Stopwatch()..start();
    return MeasurementMountClock(() => stopwatch.elapsedMicroseconds);
  }

  final int Function() _readMicros;
  final int _origin;

  /// Micros since the mount.
  int get elapsedMicros => _readMicros() - _origin;
}

/// The clock a deferred Measurement session reads: micros since its mount,
/// so entries held before it opened keep the time they happened.
@internal
abstract final class MeasurementDeferredClock {
  static MeasurementMountClock? _heldClock;
  static int? _heldAt;

  /// Runs [body], opening a session, with [sinceMount] as its clock.
  static R withBase<R>(MeasurementMountClock sinceMount, R Function() body) =>
      runZoned(body, zoneValues: {_baseKey: sinceMount});

  /// Runs [body] with [sinceMount] reading [micros]. Only the synchronous
  /// call sees it; timers and futures [body] starts read the live clock.
  static R atHeld<R>(
      MeasurementMountClock sinceMount, int micros, R Function() body) {
    final (clock, at) = (_heldClock, _heldAt);
    _heldClock = sinceMount;
    _heldAt = micros;
    try {
      return body();
    } finally {
      _heldClock = clock;
      _heldAt = at;
    }
  }

  /// The session clock for a session opened in [withBase], or null.
  static int Function()? sessionSource() {
    final base = Zone.current[_baseKey];
    if (base is! MeasurementMountClock) return null;
    return () => identical(_heldClock, base)
        ? _heldAt ?? base.elapsedMicros
        : base.elapsedMicros;
  }
}
