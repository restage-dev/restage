import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
// ignore: implementation_imports
import 'package:restage/src/flow/flow_experiment_artifact_metadata.dart';
// ignore: implementation_imports
import 'package:restage/src/flow/flow_experiment_mount.dart';
// ignore: implementation_imports
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
// ignore: implementation_imports
import 'package:restage/src/resolver/restage_variant_resolver.dart'
    show stampFlowPayloadForDelivery, withoutAssignmentLeaseForDelivery;
// ignore: implementation_imports
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';

void main() {
  setUp(Restage.debugReset);

  testWidgets(
      'flow-backed paywall renders only the atomically accepted root and '
      'descendants', (tester) async {
    final child = _childFlow();
    final root = _rootFlow(child);
    final substitutedRoot = _screenRootFlow('Substituted root');
    final source = _SeedSource();
    final baselineResolver = _RecordingResolver({
      'pro_upgrade': root,
      'child': child,
    });
    final snapshotOutcome = await FlowMountContractSnapshotBuilder(
      captureSeed: source.capture,
      resolveAssignmentKey: () async => 'assignment-key',
      resolver: baselineResolver,
    ).seal();
    expect(snapshotOutcome, isA<FlowMountSnapshotSealed>());
    final snapshot = (snapshotOutcome as FlowMountSnapshotSealed).snapshot;

    final candidateResolver = _RecordingResolver({'child': child});
    final prefetch = await FlowCandidatePrefetcher.prefetch(
      snapshot: snapshot,
      captureSeed: source.capture,
      candidateRoot: root,
      resolver: candidateResolver,
      serverVerdictAccepted: true,
    );
    expect(prefetch, isA<FlowCandidatePrefetchAccepted>());
    final accepted = prefetch as FlowCandidatePrefetchAccepted;
    final payload = FlowPaywallPayload.experiment(
      acceptedCandidate: accepted,
      paywallId: 'pro_upgrade',
    );
    expect(identical(accepted.candidateRoot, root), isTrue);
    expect(identical(payload.acceptedCandidate, accepted), isTrue);
    expect(identical(payload.flow, root), isTrue);
    expect(identical(payload.flow, substitutedRoot), isFalse);
    expect(identical(payload.pinnedFlowResolver, accepted.resolver), isTrue);

    addTearDown(SurfaceAssignmentKeyProvider.clear);
    SurfaceAssignmentKeyProvider.current = () async => 'assignment-key';
    final assignmentLease = await SurfaceAssignmentKeyProvider.captureLease();
    var published = false;
    final stamped = stampFlowPayloadForDelivery(
      payload,
      assignmentLease,
      hostedPublication: HostedPayloadPublication(
        onCommit: () => published = true,
      ),
    );
    expect(identical(stamped.acceptedCandidate, accepted), isTrue);
    expect(identical(stamped.flow, root), isTrue);
    expect(identical(stamped.pinnedFlowResolver, accepted.resolver), isTrue);
    expect(identical(stamped.assignmentLease, assignmentLease), isTrue);
    stamped.publishHostedLastGood();
    expect(published, isTrue);

    var strippedPublicationRan = false;
    final stripped = withoutAssignmentLeaseForDelivery(
      stampFlowPayloadForDelivery(
        payload,
        assignmentLease,
        hostedPublication: HostedPayloadPublication(
          onCommit: () => strippedPublicationRan = true,
        ),
      ),
    ) as FlowPaywallPayload;
    expect(identical(stripped.acceptedCandidate, accepted), isTrue);
    expect(identical(stripped.flow, root), isTrue);
    expect(identical(stripped.pinnedFlowResolver, accepted.resolver), isTrue);
    expect(stripped.assignmentLease, isNull);
    stripped.publishHostedLastGood();
    expect(strippedPublicationRan, isFalse);
    expect(candidateResolver.calls, ['child']);

    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(
        id: 'pro_upgrade',
        resolver: _FlowPayloadResolver(payload),
      ),
    ));
    await tester.pumpAndSettle();

    final pinnedChildCount = find.text('Pinned child').evaluate().length;
    final substitutedRootCount =
        find.text('Substituted root').evaluate().length;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(
      {
        'acceptedRootDescendantVisible': pinnedChildCount,
        'substitutedRootVisible': substitutedRootCount,
      },
      {
        'acceptedRootDescendantVisible': 1,
        'substitutedRootVisible': 0,
      },
    );
    expect(candidateResolver.calls, ['child']);
  });

  test('ordinary flow paywall payload remains unpinned', () {
    final payload = FlowPaywallPayload(
      flow: _screenRootFlow('Ordinary root'),
      paywallId: 'pro_upgrade',
    );

    expect(payload.acceptedCandidate, isNull);
    expect(payload.pinnedFlowResolver, isNull);
    expect(
      payload.copyForDelivery(assignmentLease: null).acceptedCandidate,
      isNull,
    );
  });
}

final class _SeedSource {
  FlowMountLeaseSeed capture() => FlowMountLeaseSeed.capture(
        flow: const OnboardingFlowRef<void>(
          id: 'pro_upgrade',
          version: 1,
          minClient: 3,
          surfaceType: SurfaceType.paywall,
          decodeResult: _decodeVoid,
        ),
        deliveryMode: FlowDeliveryMode.typed,
        assignmentKeyProviderGeneration: 1,
        analyticsIdentityGeneration: 1,
        configurationGeneration: 1,
        libraryGeneration: 1,
        actionGeneration: 1,
        signalGeneration: 1,
        builtInCatalogVersion: 5,
        installedLibraries: const [],
        actionBindings: const {},
        installedSignals: const {},
      );
}

final class _RecordingResolver
    implements FlowResolver, FlowExperimentArtifactMetadataProvider {
  _RecordingResolver(this.flows);

  final Map<String, ResolvedFlow> flows;
  final List<String> calls = [];

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    calls.add(flow.id);
    return flows[flow.id]!;
  }

  @override
  FlowExperimentArtifactMetadata metadataFor(ResolvedFlow flow) =>
      FlowExperimentArtifactOwnership.verifiedMetadata(
        requiredLibraries: [],
      );
}

final class _FlowPayloadResolver
    implements VariantResolver, FlowCapableVariantResolver {
  _FlowPayloadResolver(this.payload);

  final FlowPaywallPayload payload;

  @override
  Future<ResolvedPaywallPayload> resolvePayload(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      payload;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) {
    throw UnimplementedError();
  }
}

ResolvedFlow _childFlow() {
  final bytes = _screenBlob('Pinned child');
  final document = FlowDocument(
    flow: 'child',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'screen',
    actions: const {},
    screenArtifacts: {
      'screen': ScreenArtifact(
        path: 'child.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        contentHash: FlowContentHash.compute(bytes),
      ),
    },
    states: const {
      'screen': ScreenFlowState(screen: 'screen', on: {}),
    },
  );
  return _resolved(document, {'screen': bytes});
}

ResolvedFlow _rootFlow(ResolvedFlow child) {
  final document = FlowDocument(
    flow: 'pro_upgrade',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'child',
    actions: const {},
    screenArtifacts: const {},
    states: {
      'child': SubFlowState(
        flow: 'child',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        contentHash: child.contentHash!,
        input: const {},
        onComplete: const [],
        defaultBranch: const FlowBranchTarget(target: 'done'),
      ),
      'done': const EndFlowState(result: {}),
    },
  );
  return _resolved(document, const {});
}

ResolvedFlow _screenRootFlow(String text) {
  final bytes = _screenBlob(text);
  final document = FlowDocument(
    flow: 'pro_upgrade',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'screen',
    actions: const {},
    screenArtifacts: {
      'screen': ScreenArtifact(
        path: 'root.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        contentHash: FlowContentHash.compute(bytes),
      ),
    },
    states: const {
      'screen': ScreenFlowState(screen: 'screen', on: {}),
    },
  );
  return _resolved(document, {'screen': bytes});
}

ResolvedFlow _resolved(
  FlowDocument document,
  Map<String, Uint8List> screenBlobs,
) {
  final resolved = ResolvedFlow(
    document: document,
    screenBlobs: screenBlobs,
    contentHash: FlowContentHash.compute(
      FlowDocumentCodec.encodeCanonicalJson(document),
    ),
    cacheHit: false,
  );
  return resolved;
}

Uint8List _screenBlob(String text) {
  final source = '''
    import restage.core;
    widget OnboardingScreen = Text(text: "$text");
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

void _decodeVoid(Map<String, Object?> result) {}
