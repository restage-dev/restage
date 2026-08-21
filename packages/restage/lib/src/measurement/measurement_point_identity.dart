import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'measurement_runtime_capture.dart';

/// One compiler-emitted compact token paired with its pre-mount route carrier.
///
/// The route carrier is admitted only while the table is built. Callback paths
/// retain and resolve [compactToken] only.
@internal
@immutable
final class MeasurementEmittedPointToken {
  /// Creates one bounded compact token from generated artifact data.
  MeasurementEmittedPointToken({
    required String compactToken,
    required this.routeCarrier,
  }) : compactToken = _requireCompactToken(compactToken);

  /// Opaque 192-bit local token emitted with the mounted widget occurrence.
  final String compactToken;

  /// Strict route carrier available only during pre-mount validation.
  final String routeCarrier;
}

/// Internal immutable identity carried after pre-mount route validation.
///
/// Its fields are bounded primitive integers so a later handoff can carry the
/// identity without a Flutter object, text, callback payload, or canonical ID.
@internal
@immutable
final class MeasurementPointIdentity {
  const MeasurementPointIdentity._({
    required this.ownerId,
    required this.publicationId,
    required this.routeIndex,
  });

  /// Opaque owner scope for one mounted identity table.
  final int ownerId;

  /// Opaque publication scope verified against the exact binding context.
  final int publicationId;

  /// Bounded table index for the exact occurrence and lineage route.
  final int routeIndex;

  /// Primitive isolate-transfer fields in their fixed order.
  List<int> get isolateFields =>
      List<int>.unmodifiable([ownerId, publicationId, routeIndex]);
}

/// One already-resolved compact point token for a mounted RFW presentation.
///
/// The construction owner builds this value before a paint or action callback
/// can run. The raw carrier is intentionally absent: its exact binding lookup
/// has already selected [route].
@internal
@immutable
final class MeasurementPreboundPointToken {
  /// Creates one compact token attached to an exact route handle.
  MeasurementPreboundPointToken({
    required String compactToken,
    required this.route,
  }) : compactToken = _requireCompactToken(compactToken);

  /// Compiler-emitted compact token used at the UI append edge.
  final String compactToken;

  /// Exact pre-resolved worker route.
  final MeasurementCaptureRouteHandle route;
}

/// Immutable O(1) compact-token resolver for one mounted publication edge.
@internal
final class MeasurementPointIdentityTable {
  MeasurementPointIdentityTable._({
    required int ownerId,
    required int publicationId,
    required Map<String, MeasurementPointIdentity> identitiesByCompactToken,
    required Map<int, MeasurementPointIdentity> identitiesByRouteIndex,
  })  : _ownerId = ownerId,
        _publicationId = publicationId,
        _identitiesByCompactToken =
            Map<String, MeasurementPointIdentity>.unmodifiable(
          identitiesByCompactToken,
        ),
        _identitiesByRouteIndex =
            Map<int, MeasurementPointIdentity>.unmodifiable(
          identitiesByRouteIndex,
        );

  /// Validates the full emitted route closure before a mounted callback exists.
  factory MeasurementPointIdentityTable.fromPublicationBinding({
    required ExactMeasurementPublicationContextRefV1 publicationContext,
    required MeasurementPublicationBindingV1 binding,
    required ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken,
    required List<MeasurementEmittedPointToken> emittedTokens,
  }) {
    _requireExactPublicationContext(publicationContext, binding);
    final mountedRoutes = binding.routesForMountedArtifact(
      artifactOccurrenceEdgeToken,
    );
    if (mountedRoutes == null) {
      throw ArgumentError.value(
        artifactOccurrenceEdgeToken,
        'artifactOccurrenceEdgeToken',
        'Expected one exact mounted route closure',
      );
    }
    if (emittedTokens.length != mountedRoutes.routes.length) {
      throw ArgumentError.value(
        emittedTokens.length,
        'emittedTokens',
        'Expected the complete exact mounted route closure',
      );
    }
    if (mountedRoutes.routes.length > _maximumPointIdentityFieldValue) {
      throw ArgumentError.value(
        mountedRoutes.routes.length,
        'emittedTokens',
        'Expected a bounded exact mounted route closure',
      );
    }

    final expectedRoutes = <String, _ExpectedRoute>{
      for (final entry in mountedRoutes.routes.indexed)
        entry.$2.opaqueRouteToken.fingerprint.hex: _ExpectedRoute(
          routeIndex: entry.$1,
        ),
    };
    final identitiesByCompactToken = <String, MeasurementPointIdentity>{};
    final identitiesByRouteIndex = <int, MeasurementPointIdentity>{};
    final ownerId = _allocateScopeId();
    final publicationId = _allocateScopeId();

    for (final emitted in emittedTokens) {
      final carrier = MeasurementPublicationRouteCarrierV1.parse(
        emitted.routeCarrier,
      );
      if (carrier.artifactOccurrenceEdgeToken != artifactOccurrenceEdgeToken) {
        throw ArgumentError.value(
          emitted.routeCarrier,
          'emittedTokens',
          'Expected a carrier for the exact mounted artifact edge',
        );
      }
      final compactToken = _compactTokenFromValidatedCarrier(
        emitted.routeCarrier,
      );
      if (compactToken != emitted.compactToken) {
        throw ArgumentError.value(
          emitted.compactToken,
          'emittedTokens',
          'Expected the compact token derived from its exact route carrier',
        );
      }
      final fingerprint = OpaqueMeasurementRouteTokenV1.fromRuntimeCarrier(
        emitted.routeCarrier,
      ).fingerprint.hex;
      final expected = expectedRoutes.remove(fingerprint);
      if (expected == null) {
        throw ArgumentError.value(
          emitted.routeCarrier,
          'emittedTokens',
          'Expected one unique route from the mounted binding closure',
        );
      }
      final identity = MeasurementPointIdentity._(
        ownerId: ownerId,
        publicationId: publicationId,
        routeIndex: expected.routeIndex,
      );
      if (identitiesByCompactToken.putIfAbsent(compactToken, () => identity) !=
          identity) {
        throw ArgumentError.value(
          emitted.compactToken,
          'emittedTokens',
          'Expected each compact point token to be unique',
        );
      }
      if (identitiesByRouteIndex.putIfAbsent(
            expected.routeIndex,
            () => identity,
          ) !=
          identity) {
        throw ArgumentError.value(
          emitted.compactToken,
          'emittedTokens',
          'Expected each exact route to have one compact token',
        );
      }
    }

    if (expectedRoutes.isNotEmpty ||
        identitiesByRouteIndex.length != mountedRoutes.routes.length) {
      throw ArgumentError.value(
        emittedTokens,
        'emittedTokens',
        'Expected every exact mounted route to have one compact token',
      );
    }
    return MeasurementPointIdentityTable._(
      ownerId: ownerId,
      publicationId: publicationId,
      identitiesByCompactToken: identitiesByCompactToken,
      identitiesByRouteIndex: identitiesByRouteIndex,
    );
  }

  /// Binds a presentation wrapper after every raw carrier was resolved by the
  /// exact mounted route table, before its child can paint.
  ///
  /// Unlike [fromPublicationBinding], a compiler may put a strict subset of a
  /// mounted closure in each wrapper. The caller must therefore supply only
  /// already-resolved handles. This constructor never parses a carrier and
  /// creates only bounded compact-token-to-route identities for the UI edge.
  factory MeasurementPointIdentityTable.fromPreboundTokens({
    required List<MeasurementPreboundPointToken> tokens,
  }) {
    if (tokens.isEmpty || tokens.length > _maximumPointIdentityFieldValue) {
      throw ArgumentError.value(
        tokens.length,
        'tokens',
        'Expected a non-empty bounded prebound token set',
      );
    }
    final ownerId = _allocateScopeId();
    final publicationId = _allocateScopeId();
    final identitiesByCompactToken = <String, MeasurementPointIdentity>{};
    final identitiesByRouteIndex = <int, MeasurementPointIdentity>{};
    for (final token in tokens) {
      final routeIndex = token.route.routeIndex;
      final identity = MeasurementPointIdentity._(
        ownerId: ownerId,
        publicationId: publicationId,
        routeIndex: routeIndex,
      );
      if (identitiesByCompactToken.putIfAbsent(
                token.compactToken,
                () => identity,
              ) !=
              identity ||
          identitiesByRouteIndex.putIfAbsent(routeIndex, () => identity) !=
              identity) {
        throw ArgumentError.value(
          token.compactToken,
          'tokens',
          'Expected one compact token and one route per prebound entry',
        );
      }
    }
    return MeasurementPointIdentityTable._(
      ownerId: ownerId,
      publicationId: publicationId,
      identitiesByCompactToken: identitiesByCompactToken,
      identitiesByRouteIndex: identitiesByRouteIndex,
    );
  }

  final int _ownerId;
  final int _publicationId;
  final Map<String, MeasurementPointIdentity> _identitiesByCompactToken;
  final Map<int, MeasurementPointIdentity> _identitiesByRouteIndex;

  /// Resolves a compiler-emitted compact token with one map lookup.
  MeasurementPointIdentity? resolve(String compactToken) {
    return _identitiesByCompactToken[compactToken];
  }

  /// Whether [identity] belongs to this exact owner and publication table.
  bool accepts(MeasurementPointIdentity identity) {
    if (identity.ownerId != _ownerId ||
        identity.publicationId != _publicationId ||
        identity.routeIndex < 0 ||
        identity.routeIndex > _maximumPointIdentityFieldValue) {
      return false;
    }
    final expected = _identitiesByRouteIndex[identity.routeIndex];
    return expected != null &&
        expected.ownerId == identity.ownerId &&
        expected.publicationId == identity.publicationId &&
        expected.routeIndex == identity.routeIndex;
  }
}

final class _ExpectedRoute {
  const _ExpectedRoute({required this.routeIndex});

  final int routeIndex;
}

void _requireExactPublicationContext(
  ExactMeasurementPublicationContextRefV1 publicationContext,
  MeasurementPublicationBindingV1 binding,
) {
  final revision = binding.publishedSurfaceRevision;
  if (publicationContext.bindingReference != binding.reference ||
      publicationContext.surfaceIdentity != revision.surfaceIdentity ||
      publicationContext.surfaceRevisionId != revision.revisionId ||
      publicationContext.artifactGraphHash !=
          binding.exactArtifactGraph.canonicalDigest ||
      publicationContext.measurementManifestHash !=
          binding.completeMeasurementManifest.canonicalDigest) {
    throw ArgumentError.value(
      publicationContext,
      'publicationContext',
      'Expected the exact publication context for this binding',
    );
  }
}

String _requireCompactToken(String value) {
  if (value.length != kMeasurementPublicationRouteCarrierLocalTokenLength) {
    throw ArgumentError.value(
      value,
      'compactToken',
      'Expected one bounded compact point token',
    );
  }
  for (final codeUnit in value.codeUnits) {
    final isAsciiLetter = (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7a);
    final isDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
    if (!isAsciiLetter && !isDigit && codeUnit != 0x2d && codeUnit != 0x5f) {
      throw ArgumentError.value(
        value,
        'compactToken',
        'Expected an opaque unpadded compact point token',
      );
    }
  }
  return value;
}

String _compactTokenFromValidatedCarrier(String routeCarrier) {
  final separator = routeCarrier.lastIndexOf('.');
  return _requireCompactToken(routeCarrier.substring(separator + 1));
}

const _maximumPointIdentityFieldValue = 0x3fffffff;

int _nextScopeId = 0;

int _allocateScopeId() {
  if (_nextScopeId == _maximumPointIdentityFieldValue) {
    throw StateError('Measurement point identity scope capacity is exhausted');
  }
  _nextScopeId += 1;
  return _nextScopeId;
}
