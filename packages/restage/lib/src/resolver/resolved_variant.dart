import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Result of resolving a paywall variant — the `.rfw` blob + delivery metadata.
///
/// Returned by [VariantResolver.resolve]. Carries the encoded bytes the runtime
/// will hand to RFW for rendering, plus identifiers needed for analytics
/// attribution (which paywall, which variant, which experiment, which version).
///
/// Equality is defined over the **identity tuple** — [paywallId], [variantId],
/// [experimentId], [experimentEpoch], [paywallVersion],
/// [paywallPublishedVersion], and [surfaceVersion] — so two
/// resolutions of the same variant compare equal, and a host caching layer can
/// use `==` for a "same variant, skip re-render" check. Two fields are
/// deliberately **excluded** from equality:
///   - [bytes]: the rendered-content [surfaceVersion] changes whenever the
///     resolved bytes change, so a deep O(n) byte compare would add nothing.
///   - [cacheHit]: delivery metadata — a cache hit and a fresh fetch of the
///     same variant are the same variant, so including it would reintroduce
///     the false-inequality this equality is meant to avoid.
///
/// [paywallPublishedVersion] is in the tuple precisely to keep
/// "bytes determined by the tuple" sound for hosted delivery: a hosted blob's
/// bytes are fixed by (id + published version), so a republish (v1 → v2) yields
/// different bytes and must compare unequal. Omitting it would let two
/// resolutions of the same id at different published versions compare equal and
/// show stale content after a republish.
@immutable
class ResolvedVariant {
  /// Creates a [ResolvedVariant]. Custom [VariantResolver] implementations
  /// construct this directly and provide a new [surfaceVersion] whenever their
  /// resolved bytes change.
  ResolvedVariant({
    required this.bytes,
    required this.paywallId,
    required this.surfaceVersion,
    this.variantId,
    this.experimentId,
    this.experimentEpoch,
    this.paywallVersion,
    this.paywallPublishedVersion,
    this.cacheHit = false,
  }) {
    if (surfaceVersion.isEmpty) {
      throw ArgumentError.value(
        surfaceVersion,
        'surfaceVersion',
        'must not be empty',
      );
    }
  }

  /// The `.rfw` blob bytes.
  final Uint8List bytes;

  /// Stable identifier for the paywall (e.g. `'pro_upgrade'`).
  final String paywallId;

  /// Stable rendered-content identity for this exact blob.
  ///
  /// Hosted resolution uses the served publication revision. Bundled resolution
  /// uses a deterministic content hash. Custom resolvers must change this value
  /// whenever they return different bytes.
  final String surfaceVersion;

  /// Variant identifier when an experiment assigned a specific arm.
  final String? variantId;

  /// Experiment identifier when this variant came from an A/B test.
  final String? experimentId;

  /// Experiment epoch when this variant came from an A/B test.
  final int? experimentEpoch;

  /// Authoring version of the paywall blob — an author-facing label (e.g. a
  /// semver or editor revision string). This is distinct from
  /// [paywallPublishedVersion]; a bundled or custom resolver may set it, the
  /// hosted resolver leaves it null.
  final String? paywallVersion;

  /// Server-assigned published version of the paywall this resolution served.
  ///
  /// An integer counter the delivery backend increments on each publish. Set by
  /// the hosted resolver (read from the served document); `null` for bundled or
  /// custom resolutions that have no published version. Carried through to
  /// runtime telemetry so interactions attribute to the exact served version.
  final int? paywallPublishedVersion;

  /// Whether the bytes came from a local cache rather than a fresh fetch.
  final bool cacheHit;

  /// Returns a copy with the given fields overridden; every un-passed field is
  /// preserved. Replacing [bytes] also requires a different [surfaceVersion],
  /// so a changed blob cannot retain the identity of the previous content.
  ///
  /// Override-or-preserve: a nullable field cannot be *cleared* to null through
  /// this method (a passed null reads as "not overridden"). That is not needed —
  /// the only re-emit in the runtime overrides [cacheHit] and preserves the
  /// rest.
  ResolvedVariant copyWith({
    Uint8List? bytes,
    String? paywallId,
    String? surfaceVersion,
    String? variantId,
    String? experimentId,
    int? experimentEpoch,
    String? paywallVersion,
    int? paywallPublishedVersion,
    bool? cacheHit,
  }) {
    if (bytes != null &&
        (surfaceVersion == null || surfaceVersion == this.surfaceVersion)) {
      throw ArgumentError.value(
        surfaceVersion,
        'surfaceVersion',
        'must change when bytes are replaced',
      );
    }
    return ResolvedVariant(
      bytes: bytes ?? this.bytes,
      paywallId: paywallId ?? this.paywallId,
      surfaceVersion: surfaceVersion ?? this.surfaceVersion,
      variantId: variantId ?? this.variantId,
      experimentId: experimentId ?? this.experimentId,
      experimentEpoch: experimentEpoch ?? this.experimentEpoch,
      paywallVersion: paywallVersion ?? this.paywallVersion,
      paywallPublishedVersion:
          paywallPublishedVersion ?? this.paywallPublishedVersion,
      cacheHit: cacheHit ?? this.cacheHit,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedVariant &&
          other.paywallId == paywallId &&
          other.surfaceVersion == surfaceVersion &&
          other.variantId == variantId &&
          other.experimentId == experimentId &&
          other.experimentEpoch == experimentEpoch &&
          other.paywallVersion == paywallVersion &&
          other.paywallPublishedVersion == paywallPublishedVersion;

  @override
  int get hashCode => Object.hash(
        paywallId,
        surfaceVersion,
        variantId,
        experimentId,
        experimentEpoch,
        paywallVersion,
        paywallPublishedVersion,
      );
}
