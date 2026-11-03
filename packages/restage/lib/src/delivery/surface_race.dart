import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:meta/meta.dart';

import '../measurement/measurement_resolved_publication_provenance.dart'
    show surfaceResolutionSourceFor;
import '../resolver/surface_resolution_report.dart'
    show SurfaceResolutionSource;
import 'raced_surface_resolver.dart';
import 'render_deadline.dart';
import 'surface_store_key.dart';

/// What a mount renders when its race settles.
@internal
sealed class RaceOutcome<T> {
  const RaceOutcome({this.freshError});

  /// The candidate to render, or null for the compiled or fallback floor.
  T? get value;

  /// Why fresh failed before the race settled, if it did.
  final Object? freshError;
}

/// Fresh content accepted before the deadline.
@internal
final class RaceFresh<T> extends RaceOutcome<T> {
  const RaceFresh(this.value);

  @override
  final T value;
}

/// The best local candidate ready when the race settled.
@internal
final class RaceLocal<T> extends RaceOutcome<T> {
  const RaceLocal(this.value, {super.freshError});

  @override
  final T value;
}

/// Nothing local was ready; the mount renders its compiled or fallback floor.
@internal
final class RaceNone<T> extends RaceOutcome<T> {
  const RaceNone({required this.freshPending, super.freshError});

  @override
  T? get value => null;

  /// Whether fresh was still running when the race settled.
  final bool freshPending;
}

final _heldDecisions = Expando<bool>('restage.heldDecision');

/// Marks [local] as a saved decision that passed every check, so a race
/// settles on it as soon as it is ready.
@internal
void markHeldDecision(Object local) => _heldDecisions[local] = true;

bool _isTrackable(Object local) =>
    local is! String && local is! num && local is! bool && local is! Record;

bool _isHeldDecision(Object local) =>
    _isTrackable(local) && _heldDecisions[local] == true;

/// Whether [local] is content this device saved earlier, as opposed to the
/// compiled or bundled original.
bool _isSaved(Object local) =>
    _isHeldDecision(local) ||
    (_isTrackable(local) &&
        surfaceResolutionSourceFor(local) ==
            SurfaceResolutionSource.holdLastGood);

/// Starts [fresh] and [bestLocal] together.
///
/// A mount with nothing saved waits for fresh until [deadline], then renders
/// its original. A mount with saved content waits for fresh only until
/// the deadline's fresh window, then renders the saved content. A fresh value accepted after
/// the race settled goes to [onLateFresh].
@internal
Future<RaceOutcome<T>> raceSurface<T extends Object>({
  required RenderDeadline deadline,
  required Future<T?> Function() fresh,
  required Future<T?> Function() bestLocal,
  void Function(T value)? onLateFresh,
  bool Function()? answerArrived,
}) {
  final settled = Completer<RaceOutcome<T>>();
  T? local;
  var localDone = false;
  var freshDone = false;
  Object? freshError;

  void settle(RaceOutcome<T> outcome) {
    if (!settled.isCompleted) {
      settled.complete(outcome);
    }
  }

  RaceOutcome<T> localOutcome() {
    final candidate = local;
    return candidate == null
        ? RaceNone<T>(freshPending: !freshDone, freshError: freshError)
        : RaceLocal<T>(candidate, freshError: freshError);
  }

  if (deadline.hasPassed) {
    // Let local candidates that are already in memory finish first.
    Timer.run(() => settle(localOutcome()));
  } else {
    unawaited(deadline.reached.then((_) => settle(localOutcome())));
  }

  unawaited(Future<T?>.sync(bestLocal).then<void>(
    (value) {
      local = value;
      // Saved content waits only for the fresh window; fresh that misses it
      // is kept for the next mount.
      if (value != null && _isSaved(value)) {
        void atWindow() {
          // An answer already on the device is accepted first; the deadline
          // still ends the wait.
          if (answerArrived?.call() ?? false) return;
          settle(RaceLocal<T>(value, freshError: freshError));
        }

        if (deadline.windowHasPassed) {
          atWindow();
        } else {
          unawaited(deadline.windowPassed.then((_) => atWindow()));
        }
      }
    },
    onError: (Object _) {},
  ).whenComplete(() {
    localDone = true;
    if (freshDone) settle(localOutcome());
  }));

  unawaited(Future<T?>.sync(fresh).then<void>(
    (value) {
      if (value == null) return;
      if (settled.isCompleted) {
        onLateFresh?.call(value);
      } else {
        settle(RaceFresh<T>(value));
      }
    },
    onError: (Object error) {
      freshError = error;
      if (kDebugMode) {
        debugPrint('[restage] hosted resolve failed '
            '(${error.runtimeType}): $error');
      }
    },
  ).whenComplete(() {
    freshDone = true;
    if (localDone) settle(localOutcome());
  }));

  return settled.future;
}

/// Reports the candidate a mount rendered. A reporting failure asserts in
/// debug builds; in release it is logged once and never affects the mount.
@internal
void reportRaceWinner<T>(
  RacedSurfaceResolver<T> resolver,
  SurfaceStoreKey key,
  T? winner,
) {
  try {
    reportRacedSurface(resolver, key, winner);
  } on Object catch (error) {
    assert(
        false, 'Reporting the ${key.surfaceType} ${key.slug} failed: $error');
    if (_reportFailureLogged) return;
    _reportFailureLogged = true;
    debugPrint('[restage] surface delivery reporting failed: $error');
  }
}

var _reportFailureLogged = false;

/// A late render's report, sent once when the content actually paints and
/// never when the swap is refused before paint.
@internal
final class LateRenderReport {
  /// Wraps the report to send at paint.
  LateRenderReport(this._report);

  void Function()? _report;

  /// Sends the report; later calls do nothing.
  void painted() {
    final report = _report;
    _report = null;
    report?.call();
  }
}
