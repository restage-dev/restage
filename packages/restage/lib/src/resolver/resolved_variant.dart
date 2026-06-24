import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Result of resolving a paywall variant — the `.rfw` blob + delivery metadata.
///
/// Returned by [VariantResolver.resolve]. Carries the encoded bytes the runtime
/// will hand to RFW for rendering, plus identifiers needed for analytics
/// attribution (which paywall, which variant, which experiment, which version).
///
/// Equality is defined over the **identity tuple** — [paywallId], [variantId],
/// [experimentId], [paywallVersion], and [paywallPublishedVersion] — so two
/// resolutions of the same variant compare equal, and a host caching layer can
/// use `==` for a "same variant, skip re-render" check. Two fields are
/// deliberately **excluded** from equality:
///   - [bytes]: the blob is fully determined by the identity tuple equality
///     already compares (paywall id + variant + version), so a deep O(n) byte
///     compare would add nothing and is not what "same variant" means.
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
  /// construct this directly.
  const ResolvedVariant({
    required this.bytes,
    required this.paywallId,
    this.variantId,
    this.experimentId,
    this.paywallVersion,
    this.paywallPublishedVersion,
    this.cacheHit = false,
  });

  /// The `.rfw` blob bytes.
  final Uint8List bytes;

  /// Stable identifier for the paywall (e.g. `'pro_upgrade'`).
  final String paywallId;

  /// Variant identifier when an experiment assigned a specific arm.
  final String? variantId;

  /// Experiment identifier when this variant came from an A/B test.
  final String? experimentId;

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
  /// purchase reporting so a conversion attributes to the exact served version.
  final int? paywallPublishedVersion;

  /// Whether the bytes came from a local cache rather than a fresh fetch.
  final bool cacheHit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedVariant &&
          other.paywallId == paywallId &&
          other.variantId == variantId &&
          other.experimentId == experimentId &&
          other.paywallVersion == paywallVersion &&
          other.paywallPublishedVersion == paywallPublishedVersion;

  @override
  int get hashCode => Object.hash(
        paywallId,
        variantId,
        experimentId,
        paywallVersion,
        paywallPublishedVersion,
      );
}
