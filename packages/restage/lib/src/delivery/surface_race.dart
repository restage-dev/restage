import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:meta/meta.dart';

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

/// Starts [fresh] and [bestLocal] together and settles by [deadline].
///
/// Fresh wins if it is accepted before the deadline. Otherwise the local
/// candidate ready at that moment renders. A fresh value accepted after the
/// race settled goes to [onLateFresh].
@internal
Future<RaceOutcome<T>> raceSurface<T extends Object>({
  required RenderDeadline deadline,
  required Future<T?> Function() fresh,
  required Future<T?> Function() bestLocal,
  void Function(T value)? onLateFresh,
}) {
  final settled = Completer<RaceOutcome<T>>();
  T? local;
  var localDone = false;
  var freshDone = false;
  Object? freshError;

  void settle(RaceOutcome<T> outcome) {
    if (!settled.isCompleted) settled.complete(outcome);
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

  unawaited(Future<T?>.sync(bestLocal)
      .then<void>(
    (value) => local = value,
    onError: (Object _) {},
  )
      .whenComplete(() {
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
    onError: (Object error) => freshError = error,
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
