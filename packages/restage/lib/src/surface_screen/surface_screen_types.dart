import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

import '../flow/flow_descriptors.dart';
import '../measurement/measurement_resolved_publication_provenance.dart';

/// Why a standalone screen could not be rendered.
enum SurfaceScreenUnavailableReason {
  /// No matching generated publication is available.
  missing,

  /// The resolved identity differs from the generated identity.
  identityMismatch,

  /// The resolved contract differs from the generated contract.
  contractMismatch,

  /// The installed runtime cannot satisfy the screen capabilities.
  incompatible,

  /// The resolved content is malformed or fails integrity validation.
  invalidPayload,

  /// A screen event could not be delivered through the generated contract.
  eventRejected,

  /// Rendering the validated screen failed.
  renderFailure,
}

/// The fail-closed error supplied to a standalone screen's unavailable policy.
@immutable
final class SurfaceScreenUnavailableError implements Exception {
  /// Creates an unavailable standalone-screen error.
  const SurfaceScreenUnavailableError({
    required this.reason,
    required this.message,
    this.cause,
  });

  /// The classified reason the screen was unavailable.
  final SurfaceScreenUnavailableReason reason;

  /// A public-safe diagnostic for host logging or fallback UI.
  final String message;

  /// The underlying failure, when one is safe for in-process inspection.
  final Object? cause;

  @override
  String toString() => message;
}

/// Where a standalone screen was resolved.
enum SurfaceScreenOrigin {
  /// The screen was loaded from the generated package assets.
  bundled,

  /// The screen was selected by hosted delivery.
  hosted,
}

/// A fully resolved standalone screen ready for host validation and rendering.
@immutable
final class ResolvedSurfaceScreen {
  /// Creates a screen resolved from the exact generated bundled closure.
  ResolvedSurfaceScreen.bundled({
    required Surface surface,
    required String slug,
    required int contractVersion,
    required SurfaceSourceKind sourceKind,
    required SurfacePayloadKind payloadKind,
    required CapabilityManifest capabilities,
    required String contractFingerprint,
    required String eventContractHash,
    required Uint8List blob,
    required String contentHash,
    String? bundledEntryHash,
  }) : this._(
          origin: SurfaceScreenOrigin.bundled,
          surface: surface,
          slug: slug,
          contractVersion: contractVersion,
          publishedRevision: null,
          sourceKind: sourceKind,
          payloadKind: payloadKind,
          capabilities: capabilities,
          contractFingerprint: contractFingerprint,
          eventContractHash: eventContractHash,
          blob: blob,
          contentHash: contentHash,
          bundledEntryHash: bundledEntryHash,
          assignment: null,
          cacheHit: false,
        );

  /// Creates a screen selected by hosted delivery.
  ResolvedSurfaceScreen.hosted({
    required Surface surface,
    required String slug,
    required int contractVersion,
    required int publishedRevision,
    required SurfaceSourceKind sourceKind,
    required SurfacePayloadKind payloadKind,
    required CapabilityManifest capabilities,
    required String contractFingerprint,
    required String eventContractHash,
    required Uint8List blob,
    required String contentHash,
    required SurfaceExperimentAssignment? assignment,
    required bool cacheHit,
  }) : this._(
          origin: SurfaceScreenOrigin.hosted,
          surface: surface,
          slug: slug,
          contractVersion: contractVersion,
          publishedRevision: publishedRevision,
          sourceKind: sourceKind,
          payloadKind: payloadKind,
          capabilities: capabilities,
          contractFingerprint: contractFingerprint,
          eventContractHash: eventContractHash,
          blob: blob,
          contentHash: contentHash,
          bundledEntryHash: null,
          assignment: assignment,
          cacheHit: cacheHit,
        );

  ResolvedSurfaceScreen._({
    required this.origin,
    required this.surface,
    required this.slug,
    required this.contractVersion,
    required this.publishedRevision,
    required this.sourceKind,
    required this.payloadKind,
    required this.capabilities,
    required this.contractFingerprint,
    required this.eventContractHash,
    required Uint8List blob,
    required this.contentHash,
    required this.bundledEntryHash,
    required this.assignment,
    required this.cacheHit,
  }) : blob = Uint8List.fromList(blob) {
    if (contractVersion < 1) {
      throw ArgumentError.value(
        contractVersion,
        'contractVersion',
        'must be positive',
      );
    }
    if (origin == SurfaceScreenOrigin.bundled) {
      if (publishedRevision != null || assignment != null || cacheHit) {
        throw ArgumentError(
          'Bundled results cannot carry hosted delivery metadata.',
        );
      }
    } else if (bundledEntryHash != null) {
      throw ArgumentError(
        'Hosted results cannot carry bundled entry metadata.',
      );
    } else if (publishedRevision == null || publishedRevision! < 1) {
      throw ArgumentError.value(
        publishedRevision,
        'publishedRevision',
        'must be positive for a hosted result',
      );
    }
  }

  /// Whether the content originated from bundled assets or hosted delivery.
  final SurfaceScreenOrigin origin;

  /// Exact generated surface category.
  final Surface surface;

  /// Exact generated publication slug.
  final String slug;

  /// Exact generated standalone-screen contract version.
  final int contractVersion;

  /// Mutable hosted publication revision, absent for bundled content.
  final int? publishedRevision;

  /// Authoring semantics selected by the generated publication.
  final SurfaceSourceKind sourceKind;

  /// Delivered artifact shape.
  final SurfacePayloadKind payloadKind;

  /// Capability requirements pinned by the generated contract.
  final CapabilityManifest capabilities;

  /// Immutable generated contract fingerprint.
  final String contractFingerprint;

  /// Hash of the complete generated event schema.
  final String eventContractHash;

  /// The validated RFW blob to render.
  final Uint8List blob;

  /// Canonical content hash for the resolved blob payload.
  final String contentHash;

  /// SHA-256 of the exact bundle entry the blob came from, when it came from
  /// a packaged bundle.
  ///
  /// This pins bundled content to one generated entry rather than merely to a
  /// matching contract, so a repackaged bundle cannot substitute other bytes.
  final String? bundledEntryHash;

  /// The exact hosted experiment assignment, when one was selected.
  final SurfaceExperimentAssignment? assignment;

  /// Whether this hosted result came from the resolver cache.
  final bool cacheHit;

  /// Re-emits this hosted result as a cache hit without changing identity.
  ResolvedSurfaceScreen withCacheHit() {
    if (origin != SurfaceScreenOrigin.hosted) {
      throw StateError('Only hosted screens may be returned from cache.');
    }
    return attachMeasurementPublicationBindingReference(
      ResolvedSurfaceScreen.hosted(
        surface: surface,
        slug: slug,
        contractVersion: contractVersion,
        publishedRevision: publishedRevision!,
        sourceKind: sourceKind,
        payloadKind: payloadKind,
        capabilities: capabilities,
        contractFingerprint: contractFingerprint,
        eventContractHash: eventContractHash,
        blob: blob,
        contentHash: contentHash,
        assignment: assignment,
        cacheHit: true,
      ),
      measurementPublicationBindingReferenceFor(this),
    );
  }
}

/// Resolves one independently published standalone screen.
abstract interface class SurfaceScreenResolver {
  /// Resolves the exact generated [screen] contract.
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen);
}

/// A resolver that can supply only a generated bundled screen closure.
abstract interface class BundledSurfaceScreenResolver
    implements SurfaceScreenResolver {}
