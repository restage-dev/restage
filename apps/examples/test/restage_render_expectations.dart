import 'package:flutter/foundation.dart';

/// Lets render tests assert while a Restage error boundary is mounted.
///
/// The failure only manifests when a failed expectation escapes the test body
/// uncaught. Without this helper, it can surface flutter_test's
/// `_pendingExceptionDetails != null` binding assertion instead of the useful
/// Expected/Actual diff, then stall until the ten-minute timeout. Restage's
/// global error-handler shim is deliberate and must not be changed; this is the
/// test-side remedy.
///
/// Call [capture] at the start of the test body, before anything mounts an
/// error boundary. Do not call it from `setUp`: `setUp` runs before
/// flutter_test installs its per-test handler, so capturing there stores a
/// stale handler and silently stops this helper from working.
class RestageRenderExpectations {
  FlutterExceptionHandler? _testHandler;

  /// Captures the per-test error handler installed by flutter_test.
  ///
  /// Call this at the start of the test body, not from `setUp`, which runs
  /// before flutter_test installs the handler this helper needs to preserve.
  void capture() => _testHandler = FlutterError.onError;

  /// Runs [expectations] with the captured flutter_test handler reinstated.
  ///
  /// When every expectation succeeds, the handler installed before this call,
  /// normally Restage's error boundary shim, is restored. When an expectation
  /// throws, the flutter_test handler deliberately remains installed so the
  /// exception can reach flutter_test's zone handler with that handler active.
  ///
  /// Do not add a `finally` block here. Restoring on the failure path
  /// reinstalls the boundary handler before the exception reaches
  /// flutter_test's zone handler, which produces the unreadable binding
  /// assertion. This is
  /// deliberate, measured behavior, not an overlooked cleanup. Leaving the
  /// handler swapped is safe because the test is already failing and about to
  /// abort.
  void check(void Function() expectations) {
    final installed = FlutterError.onError;
    final testHandler = _testHandler;
    if (testHandler != null) {
      FlutterError.onError = testHandler;
    }
    expectations();
    FlutterError.onError = installed;
  }
}
