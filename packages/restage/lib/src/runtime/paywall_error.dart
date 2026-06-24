import 'package:meta/meta.dart';

/// Stable, machine-readable error codes carried on [RestagePaywallError]
/// and the various `*Failed` event types. Consumers should switch on these
/// constants rather than literal strings — typos in either direction are
/// caught at compile time.
abstract final class RestageErrorCodes {
  RestageErrorCodes._();

  /// Bundled `.rfw` asset wasn't found at the expected path. Likely cause:
  /// the asset isn't declared in `pubspec.yaml` `flutter:assets`.
  static const String assetNotFound = 'asset_not_found';

  /// `.rfw` blob was fetched but failed to decode (corrupt, wrong format,
  /// or schema mismatch with the SDK's RFW version).
  static const String decodeFailed = 'decode_failed';

  /// Hosted delivery could not produce a renderable paywall: the network fetch
  /// failed (or the served document was rejected) and there was no held cache
  /// or bundled asset to fall back to. Typically retryable.
  static const String deliveryUnavailable = 'delivery_unavailable';

  /// A widget within the rendered RFW subtree threw during build / layout.
  /// Caught by the SDK's error boundary; the host app's UI is unaffected.
  static const String renderError = 'render_error';

  /// Unclassified runtime error in the resolve / decode pipeline. Inspect
  /// [RestagePaywallError.cause] for the original exception.
  static const String unknown = 'unknown';
}

/// Error thrown by paywall resolution + rendering paths.
///
/// Carries a stable [code] (machine-readable; see [RestageErrorCodes] for
/// the canonical constants) and a human [message]. [retryable] hints
/// whether the caller should retry; [cause] preserves any underlying
/// exception. [stackTrace] preserves the underlying stack when the error
/// chain crosses a `catch` boundary.
@immutable
final class RestagePaywallError implements Exception {
  /// Creates a [RestagePaywallError]. [VariantResolver] implementations and
  /// the runtime construct these directly; host apps generally only catch.
  const RestagePaywallError({
    required this.code,
    required this.message,
    this.retryable = false,
    this.cause,
    this.stackTrace,
  });

  /// Stable, machine-readable error code. Use [RestageErrorCodes] constants
  /// rather than literal strings.
  final String code;

  /// Human-readable error message.
  final String message;

  /// Whether the caller should retry the operation.
  final bool retryable;

  /// Underlying cause, if any.
  final Object? cause;

  /// Stack trace from the original failure site (when the error was
  /// re-thrown across a catch boundary). Preserved so upstream consumers
  /// (Sentry, Crashlytics) get the real fault location, not the
  /// RestagePaywallError construction site.
  final StackTrace? stackTrace;

  @override
  String toString() => 'RestagePaywallError($code): $message';
}
