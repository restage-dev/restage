import 'dart:async';

import 'package:flutter/widgets.dart' show Rect;
import 'package:restage_preview_host/restage_preview_host.dart';

/// Internal pending-completion tracker for the preview harness.
///
/// This library is intentionally not exported from the package front door.
final class RenderCompletionTracker {
  final Map<int, Completer<BundleRenderResult>> _pending =
      <int, Completer<BundleRenderResult>>{};

  /// Snapshot of epochs whose render futures have not completed.
  List<int> get pendingEpochs => List<int>.unmodifiable(_pending.keys);

  /// Begins [epoch] and successfully completes every older pending epoch.
  Future<BundleRenderResult> begin(int epoch) {
    for (final pendingEpoch in _pending.keys.toList(growable: false)) {
      if (pendingEpoch < epoch) {
        _pending.remove(pendingEpoch)?.complete(BundleRenderResult());
      }
    }
    if (_pending.containsKey(epoch)) {
      throw StateError('Render epoch $epoch is already pending.');
    }
    final completer = Completer<BundleRenderResult>();
    _pending[epoch] = completer;
    return completer.future;
  }

  /// Successfully completes [epoch], if it remains pending.
  void completeSuccess(
    int epoch, {
    Map<String, Rect> geometry = const <String, Rect>{},
  }) {
    _pending.remove(epoch)?.complete(BundleRenderResult(geometry: geometry));
  }

  /// Completes [epoch] with a controlled render failure when still pending.
  ///
  /// Returns whether a pending render future consumed the failure. A false
  /// result lets the harness report a later lifecycle failure directly.
  bool completeFailure(int epoch, BundleRenderFailure failure) {
    final completer = _pending.remove(epoch);
    if (completer == null) return false;
    completer.completeError(failure);
    return true;
  }

  /// Completes and removes every pending epoch with [failure].
  void completeAllWithFailure(BundleRenderFailure failure) {
    final pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(failure);
    }
  }
}
