/// Reporting a delivery that resolved but could not be fetched.
///
/// The failure this exists for is the quiet one. When the description of an
/// artifact arrives fine and the artifact does not — an expired pass, an origin
/// that is down, a tombstoned object, bytes that are not the ones named — every
/// surface degrades gracefully to its fallback and the end user sees something
/// reasonable. That is the correct behaviour and it is also indistinguishable,
/// from the outside, from nothing being wrong. An operator would learn about a
/// broken artifact lane from a conversion chart weeks later.
///
/// So the fallback is taken WITH a record, not in silence. One emission point,
/// surface-general, carrying only what identifies the surface and why the fetch
/// failed.
library;

import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

/// Reports one resolved-but-unfetchable delivery.
///
/// Takes the facts rather than a built event: the identity a reported event
/// needs — who, which session, which app build — belongs to the runtime, and
/// the delivery path deliberately cannot see it.
@internal
typedef SurfaceDeliveryEvidenceEmitter = void Function({
  required Surface surfaceType,
  required String surfaceSlug,
  required int version,
  required String reason,
});

/// Reports one rate-limited surface delivery request.
@internal
typedef SurfaceDeliveryRateLimitedEvidenceEmitter = void Function({
  required Surface surfaceType,
  required String surfaceSlug,
  required Duration retryAfter,
});

/// Process-global sink for delivery evidence.
///
/// The same shape as the other process-global providers the delivery path
/// already reaches through. The runtime owns the sinks, while the RPC client
/// remains independent of event delivery infrastructure.
@internal
abstract final class SurfaceDeliveryEvidence {
  static SurfaceDeliveryEvidenceEmitter? _emitter;
  static SurfaceDeliveryRateLimitedEvidenceEmitter? _rateLimitedEmitter;

  /// Installs [emitter] as the process's evidence sink.
  static void install(
    SurfaceDeliveryEvidenceEmitter emitter, {
    SurfaceDeliveryRateLimitedEvidenceEmitter? rateLimited,
  }) {
    _emitter = emitter;
    _rateLimitedEmitter = rateLimited;
  }

  /// Installs only the rate-limit evidence sink.
  static void installRateLimited(
    SurfaceDeliveryRateLimitedEvidenceEmitter emitter,
  ) {
    _rateLimitedEmitter = emitter;
  }

  /// Removes the installed sink.
  static void clear() {
    _emitter = null;
    _rateLimitedEmitter = null;
  }

  /// Reports a rate-limited surface delivery request.
  static void rateLimited({
    required Surface surfaceType,
    required String surfaceSlug,
    required Duration retryAfter,
  }) {
    final emitter = _rateLimitedEmitter;
    if (emitter == null) return;
    try {
      emitter(
        surfaceType: surfaceType,
        surfaceSlug: surfaceSlug,
        retryAfter: retryAfter,
      );
    } on Object {
      // Reporting must never break delivery fallback.
    }
  }

  /// Reports that a resolved delivery's artifact could not be obtained.
  ///
  /// Never throws: a fallback that failed because its own reporting failed
  /// would be strictly worse than no reporting.
  static void artifactFetchFailed({
    required Surface surfaceType,
    required String surfaceSlug,
    required int version,
    required String reason,
  }) {
    final emitter = _emitter;
    if (emitter == null) return;
    try {
      emitter(
        surfaceType: surfaceType,
        surfaceSlug: surfaceSlug,
        version: version,
        reason: reason,
      );
    } on Object {
      // Deliberately swallowed. See the doc comment.
    }
  }
}
