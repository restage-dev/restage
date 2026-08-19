import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
// ignore: implementation_imports
import 'package:restage/src/flow/flow_experiment_artifact_metadata.dart';
// ignore: implementation_imports
import 'package:restage/src/flow/flow_experiment_mount.dart';
import 'package:restage_shared/flow_experiment.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  group('FlowMountContractSnapshotBuilder', () {
    test('captures and deep-freezes the seed before assignment-key await',
        () async {
      final source = _MutableSeedSource();
      final key = Completer<String?>();
      var keyResolutionStarted = false;
      final resolver = _ControlledResolver({});
      final builder = FlowMountContractSnapshotBuilder(
        captureSeed: source.capture,
        resolveAssignmentKey: () {
          keyResolutionStarted = true;
          expect(source.captureCount, 1);
          return key.future;
        },
        resolver: resolver,
      );

      final future = builder.seal();
      expect(keyResolutionStarted, isTrue);
      expect(source.captureCount, 1);

      final captured = source.capturedSeeds.single;
      source
        ..configurationGeneration += 1
        ..actionBindings.clear()
        ..installedSignals.add('mutated_after_capture')
        ..installedLibraries[0] = const InstalledLibrary(
          namespace: 'acme.widgets',
          version: 99,
        );
      key.complete('assignment-key');

      final outcome = await future;
      expect(
        outcome,
        isA<FlowMountSnapshotRejected>().having(
          (value) => value.reason,
          'reason',
          FlowMountSnapshotRejection.seedDrift,
        ),
      );
      expect(resolver.calls, isEmpty);
      expect(captured.actionBindings, hasLength(1));
      expect(captured.actionBindings.single.actionId, 'request_notifications');
      expect(captured.installedSignals, ['dismiss']);
      expect(
        captured.installedCapability.installedLibraries,
        const [InstalledLibrary(namespace: 'acme.widgets', version: null)],
      );
      expect(
        () => captured.installedSignals.add('not_mutable'),
        throwsUnsupportedError,
      );
    });

    test('initial seed fingerprint failure rejects instead of escaping',
        () async {
      final source = _MutableSeedSource();
      source.actionBindings['invalid action id'] = _actionBinding();
      var assignmentResolutionStarted = false;
      final resolver = _ControlledResolver({});

      final outcome = await FlowMountContractSnapshotBuilder(
        captureSeed: source.capture,
        resolveAssignmentKey: () {
          assignmentResolutionStarted = true;
          return 'assignment-key';
        },
        resolver: resolver,
      ).seal();

      expect(
        outcome,
        isA<FlowMountSnapshotRejected>().having(
          (value) => value.reason,
          'reason',
          FlowMountSnapshotRejection.closureInvalid,
        ),
      );
      expect(assignmentResolutionStarted, isFalse);
      expect(resolver.calls, isEmpty);
    });

    for (final mutation in _generationMutations) {
      for (final boundary in _AwaitBoundary.values) {
        test(
            '${mutation.name} generation is load-bearing at '
            '${boundary.name} await', () async {
          final outcome = await _sealWithMutationAtBoundary(
            boundary,
            mutation.apply,
          );

          _expectSeedDrift(outcome);
        });
      }
    }

    for (final mutation in _semanticMutations) {
      test('${mutation.name} semantic drift rejects with stable generations',
          () async {
        final outcome = await _sealWithMutationAtBoundary(
          _AwaitBoundary.baselineRoot,
          mutation.apply,
        );

        _expectSeedDrift(outcome);
      });
    }

    test('revalidates generation drift after child resolution await', () async {
      final child = _resolved(_document(flow: 'child'));
      final root = _resolved(_parentDocument(child: child));
      final childCompleter = Completer<ResolvedFlow>();
      final resolver = _ControlledResolver({
        'first_run': Future.value(root),
        'child': childCompleter.future,
      });
      final source = _MutableSeedSource();
      final future = FlowMountContractSnapshotBuilder(
        captureSeed: source.capture,
        resolveAssignmentKey: () async => 'assignment-key',
        resolver: resolver,
      ).seal();

      await _waitFor(() => resolver.calls.contains('child'));
      source.signalGeneration += 1;
      childCompleter.complete(child);

      expect(
        await future,
        isA<FlowMountSnapshotRejected>().having(
          (value) => value.reason,
          'reason',
          FlowMountSnapshotRejection.seedDrift,
        ),
      );
    });

    test('seals only after the complete valid shared-DAG closure', () async {
      final leaf = _resolved(_document(flow: 'leaf'));
      final shared = _resolved(_parentDocument(
        flow: 'shared',
        children: {'leaf_state': leaf},
      ));
      final left = _resolved(_parentDocument(
        flow: 'left',
        children: {'shared_state': shared},
      ));
      final right = _resolved(_parentDocument(
        flow: 'right',
        children: {'shared_state': shared},
      ));
      final root = _resolved(_parentDocument(
        children: {'left_state': left, 'right_state': right},
      ));
      final leafCompleter = Completer<ResolvedFlow>();
      final resolver = _ControlledResolver({
        'first_run': Future.value(root),
        'left': Future.value(left),
        'right': Future.value(right),
        'shared': Future.value(shared),
        'leaf': leafCompleter.future,
      });

      final future = FlowMountContractSnapshotBuilder(
        captureSeed: _MutableSeedSource().capture,
        resolveAssignmentKey: () async => 'assignment-key',
        resolver: resolver,
      ).seal();

      await _waitFor(() => resolver.calls.contains('leaf'));
      var completed = false;
      unawaited(future.then((_) => completed = true));
      await Future<void>.value();
      expect(completed, isFalse);
      leafCompleter.complete(leaf);

      final outcome = await future;
      expect(outcome, isA<FlowMountSnapshotSealed>());
      final snapshot = (outcome as FlowMountSnapshotSealed).snapshot;
      expect(snapshot.clientBaselineClosure.documents, hasLength(5));
      expect(
        resolver.calls.where((id) => id == 'shared'),
        hasLength(1),
      );
      expect(snapshot.canonicalBytes, isNotEmpty);
      expect(
        snapshot.contract.contentHash,
        snapshot.contentHash,
      );
    });

    test('memoization does not bypass all-path maximum-depth proof', () async {
      final leaf = _resolved(_document(flow: 'leaf'));
      final shared = _resolved(_parentDocument(
        flow: 'shared',
        children: {'leaf_state': leaf},
      ));
      final c = _resolved(_parentDocument(
        flow: 'c',
        children: {'shared_state': shared},
      ));
      final b = _resolved(_parentDocument(
        flow: 'b',
        children: {'c_state': c},
      ));
      final a = _resolved(_parentDocument(
        flow: 'a',
        children: {'b_state': b},
      ));
      final root = _resolved(_parentDocument(children: {
        'shallow_shared': shared,
        'deep_a': a,
      }));
      final resolver = _ControlledResolver({
        for (final flow in [root, shared, leaf, a, b, c])
          flow.document.flow: Future.value(flow),
      });

      final outcome = await FlowMountContractSnapshotBuilder(
        captureSeed: _MutableSeedSource().capture,
        resolveAssignmentKey: () async => 'assignment-key',
        resolver: resolver,
      ).seal();

      expect(
        outcome,
        isA<FlowMountSnapshotRejected>().having(
          (value) => value.reason,
          'reason',
          FlowMountSnapshotRejection.closureInvalid,
        ),
      );
    });

    test('rejects cycles without publishing a snapshot', () async {
      late ResolvedFlow root;
      late ResolvedFlow child;
      final rootWithoutChild = _document();
      final childWithoutRoot = _document(flow: 'child');
      root = _resolved(_parentDocumentFromPins(
        base: rootWithoutChild,
        children: {
          'child_state': _pinFor(childWithoutRoot),
        },
      ));
      child = _resolved(_parentDocumentFromPins(
        base: childWithoutRoot,
        children: {
          'root_state': _pinFor(root.document),
        },
      ));
      // Replace the root pin so both references are internally exact.
      root = _resolved(_parentDocumentFromPins(
        base: rootWithoutChild,
        children: {
          'child_state': _pinFor(child.document),
        },
      ));
      final resolver = _ControlledResolver({
        'first_run': Future.value(root),
        'child': Future.value(child),
      });

      final outcome = await FlowMountContractSnapshotBuilder(
        captureSeed: _MutableSeedSource().capture,
        resolveAssignmentKey: () async => 'assignment-key',
        resolver: resolver,
      ).seal();

      expect(
        outcome,
        isA<FlowMountSnapshotRejected>().having(
          (value) => value.reason,
          'reason',
          FlowMountSnapshotRejection.closureInvalid,
        ),
      );
    });
  });

  group('FlowCandidatePrefetcher', () {
    test('initial seed recapture failure rejects instead of escaping',
        () async {
      final source = _MutableSeedSource();
      final snapshot = await _sealedSnapshot(source: source);
      source.actionBindings['invalid action id'] = _actionBinding();
      final resolver = _ControlledResolver({});

      final outcome = await FlowCandidatePrefetcher.prefetch(
        snapshot: snapshot,
        captureSeed: source.capture,
        candidateRoot: _resolved(_document(version: 2)),
        resolver: resolver,
        serverVerdictAccepted: true,
      );

      _expectCandidateSeedDrift(outcome);
      expect(resolver.calls, isEmpty);
    });

    test('later seed recapture failure is a typed seed-drift rejection',
        () async {
      final snapshot = await _sealedSnapshot();
      final child = _resolved(_document(flow: 'child', version: 2));
      final root = _resolved(_parentDocument(child: child, version: 2));
      final resolver = _ControlledResolver({
        'child': Future.value(child),
      });
      var captureCount = 0;

      final outcome = await FlowCandidatePrefetcher.prefetch(
        snapshot: snapshot,
        captureSeed: () {
          captureCount += 1;
          if (captureCount == 1) return snapshot.seed;
          throw const FormatException('invalid recaptured seed');
        },
        candidateRoot: root,
        resolver: resolver,
        serverVerdictAccepted: true,
      );

      _expectCandidateSeedDrift(outcome);
      expect(resolver.calls, ['child']);
    });

    test('root-only candidate stays fallback and exposes no child resolver',
        () async {
      final snapshot = await _sealedSnapshot();
      final child = _resolved(_document(flow: 'child', version: 2));
      final root = _resolved(_parentDocument(child: child, version: 2));
      final childCompleter = Completer<ResolvedFlow>();
      final resolver = _ControlledResolver({
        'child': childCompleter.future,
      });

      FlowCandidatePrefetchOutcome? outcome;
      final future = FlowCandidatePrefetcher.prefetch(
        snapshot: snapshot,
        captureSeed: () => snapshot.seed,
        candidateRoot: root,
        resolver: resolver,
        serverVerdictAccepted: true,
      )..then((value) => outcome = value);

      await _waitFor(() => resolver.calls.contains('child'));
      await Future<void>.value();
      expect(outcome, isNull);
      childCompleter.completeError(StateError('controlled child failure'));
      expect(
        await future,
        isA<FlowCandidatePrefetchRejected>().having(
          (value) => value.reason,
          'reason',
          FlowCandidatePrefetchRejection.prefetchFailed,
        ),
      );
      expect(resolver.calls, ['child']);
    });

    test('prefetches every node before parity and pins later resolution',
        () async {
      final baselineChild = _resolved(_document(flow: 'child'));
      final baselineRoot = _resolved(_parentDocument(child: baselineChild));
      final snapshot = await _sealedSnapshot(
        root: baselineRoot,
        descendants: {'child': baselineChild},
      );
      final candidateChild = _resolved(_document(flow: 'child'));
      final candidateRoot = _resolved(_parentDocument(child: candidateChild));
      final childCompleter = Completer<ResolvedFlow>();
      final resolver = _ControlledResolver({
        'child': childCompleter.future,
      });

      final future = FlowCandidatePrefetcher.prefetch(
        snapshot: snapshot,
        captureSeed: () => snapshot.seed,
        candidateRoot: candidateRoot,
        resolver: resolver,
        serverVerdictAccepted: true,
      );
      await _waitFor(() => resolver.calls.contains('child'));
      var completed = false;
      unawaited(future.then((_) => completed = true));
      await Future<void>.value();
      expect(completed, isFalse);
      childCompleter.complete(candidateChild);

      final outcome = await future;
      expect(outcome, isA<FlowCandidatePrefetchAccepted>());
      final accepted = outcome as FlowCandidatePrefetchAccepted;
      expect(accepted.verdict, isA<FlowExperimentAcceptedV1>());
      final callsBeforePinnedResolve = resolver.calls.length;
      final pinnedChild = await accepted.resolver.resolve(
        const OnboardingFlowRef<Map<String, Object?>>(
          id: 'child',
          version: 1,
          minClient: 3,
          surface: Surface.onboarding,
          decodeResult: _decodeMap,
        ),
      );
      expect(identical(pinnedChild, candidateChild), isTrue);
      expect(resolver.calls, hasLength(callsBeforePinnedResolve));
    });

    test(
        'promotion-time schema mutation cannot change accepted root or resolver',
        () async {
      final source = _MutableSeedSource();
      source.actionBindings['request_notifications'] =
          FlowActionBinding<Object?, Object?>(
        actionName: 'request_notifications',
        contractVersion: 1,
        argsSchema: _nestedActionArgsSchema,
        resultSchema: _nestedActionResultSchema,
        minClient: 1,
        idempotent: false,
        handler: (_, __) => 'accepted',
        decodeArgs: (value) => value,
        encodeResult: (value) => value,
      );
      final baseline = _resolved(
        _document().copyWith(
          actions: const {
            'request_notifications': _nestedActionContract,
          },
        ),
      );
      final snapshot = await _sealedSnapshot(
        source: source,
        root: baseline,
      );

      final channelValues = <String>['email', 'push'];
      final payloadFields = <String, FlowActionSchemaField>{
        'channel': FlowActionSchemaField(
          required: true,
          schema: FlowActionSchema.enumValues(channelValues),
        ),
      };
      final argsFields = <String, FlowActionSchemaField>{
        'payloads': FlowActionSchemaField(
          required: true,
          schema: FlowActionSchema.list(
            FlowActionSchema.nullable(
              FlowActionSchema.object(payloadFields),
            ),
          ),
        ),
      };
      final resultValues = <String>['accepted', 'rejected'];
      final candidate = _resolved(
        _document(version: 2).copyWith(
          actions: {
            'request_notifications': FlowActionContract(
              actionName: 'request_notifications',
              contractVersion: 1,
              argsSchema: FlowActionSchema.object(argsFields),
              resultSchema: FlowActionSchema.enumValues(resultValues),
              minClient: 1,
              idempotent: false,
            ),
          },
        ),
      );
      final constructionBytes =
          FlowDocumentCodec.encodeCanonicalJson(candidate.document).toList();

      final outcome = await FlowCandidatePrefetcher.prefetch(
        snapshot: snapshot,
        captureSeed: source.capture,
        candidateRoot: candidate,
        resolver: _ControlledResolver({}),
        serverVerdictAccepted: true,
        beforePromotion: () {
          channelValues[0] = 'sms';
          payloadFields.clear();
          argsFields.clear();
          resultValues.add('pending');
        },
      );

      expect(outcome, isA<FlowCandidatePrefetchAccepted>());
      final accepted = outcome as FlowCandidatePrefetchAccepted;
      expect(
        FlowDocumentCodec.encodeCanonicalJson(
          accepted.candidateClosure.root.flowDocument,
        ),
        constructionBytes,
      );
      expect(
        FlowDocumentCodec.encodeCanonicalJson(
          accepted.candidateRoot.document,
        ),
        constructionBytes,
      );
      final pinnedRoot = await accepted.resolver.resolve(
        const OnboardingFlowRef<Map<String, Object?>>(
          id: 'first_run',
          version: 2,
          minClient: 3,
          surface: Surface.onboarding,
          decodeResult: _decodeMap,
        ),
      );
      expect(identical(pinnedRoot, accepted.candidateRoot), isTrue);
      expect(
        FlowDocumentCodec.encodeCanonicalJson(pinnedRoot.document),
        constructionBytes,
      );
      expect(
        pinnedRoot.contentHash,
        accepted.candidateClosure.root.contentHash,
      );
      final closureAction = accepted
          .candidateClosure.root.flowDocument.actions['request_notifications']!;
      final acceptedAction =
          accepted.candidateRoot.document.actions['request_notifications']!;
      final pinnedAction =
          pinnedRoot.document.actions['request_notifications']!;
      expect(acceptedAction.argsSchemaHash, closureAction.argsSchemaHash);
      expect(acceptedAction.resultSchemaHash, closureAction.resultSchemaHash);
      expect(pinnedAction.argsSchemaHash, closureAction.argsSchemaHash);
      expect(pinnedAction.resultSchemaHash, closureAction.resultSchemaHash);
    });

    test('rejects a descendant that does not match its parent exact pin',
        () async {
      final snapshot = await _sealedSnapshot();
      final pinnedChild = _resolved(_document(flow: 'child', version: 2));
      final candidateRoot = _resolved(
        _parentDocument(child: pinnedChild, version: 2),
      );
      final mismatchedChild = _resolved(
        _document(flow: 'child', version: 3),
      );

      final outcome = await FlowCandidatePrefetcher.prefetch(
        snapshot: snapshot,
        captureSeed: () => snapshot.seed,
        candidateRoot: candidateRoot,
        resolver: _ControlledResolver({
          'child': Future.value(mismatchedChild),
        }),
        serverVerdictAccepted: true,
      );

      expect(
        outcome,
        isA<FlowCandidatePrefetchRejected>().having(
          (value) => value.reason,
          'reason',
          FlowCandidatePrefetchRejection.prefetchFailed,
        ),
      );
    });

    test('shared-verdict mismatch and post-prefetch drift are never renderable',
        () async {
      final snapshot = await _sealedSnapshot();
      final candidate = _resolved(_document(version: 2));

      final mismatch = await FlowCandidatePrefetcher.prefetch(
        snapshot: snapshot,
        captureSeed: () => snapshot.seed,
        candidateRoot: candidate,
        resolver: _ControlledResolver({}),
        serverVerdictAccepted: false,
      );
      expect(
        mismatch,
        isA<FlowCandidatePrefetchRejected>().having(
          (value) => value.reason,
          'reason',
          FlowCandidatePrefetchRejection.serverVerdictMismatch,
        ),
      );

      final source = _MutableSeedSource();
      final driftSnapshot = await _sealedSnapshot(source: source);
      final child = _resolved(_document(flow: 'child', version: 2));
      final root = _resolved(_parentDocument(child: child, version: 2));
      final childCompleter = Completer<ResolvedFlow>();
      final resolver = _ControlledResolver({
        'child': childCompleter.future,
      });
      final future = FlowCandidatePrefetcher.prefetch(
        snapshot: driftSnapshot,
        captureSeed: source.capture,
        candidateRoot: root,
        resolver: resolver,
        serverVerdictAccepted: true,
      );
      await _waitFor(() => resolver.calls.contains('child'));
      source.libraryGeneration += 1;
      childCompleter.complete(child);

      expect(
        await future,
        isA<FlowCandidatePrefetchRejected>().having(
          (value) => value.reason,
          'reason',
          FlowCandidatePrefetchRejection.seedDrift,
        ),
      );
    });

    test('server acceptance cannot override local action parity rejection',
        () async {
      final snapshot = await _sealedSnapshot();
      final candidate = _resolved(
        _document(version: 2).copyWith(
          actions: const {
            'request_notifications': FlowActionContract(
              actionName: 'request_notifications',
              contractVersion: 2,
              argsSchema: FlowActionSchema.object({}),
              resultSchema: FlowActionSchema.bool(),
              minClient: 1,
              idempotent: false,
            ),
          },
        ),
      );

      await _expectLocalParityRejection(
        snapshot: snapshot,
        candidate: candidate,
        resolver: _ControlledResolver({}),
      );
    });

    test('server acceptance cannot override local library parity rejection',
        () async {
      final snapshot = await _sealedSnapshot();
      final candidate = _resolved(_document(version: 2));

      await _expectLocalParityRejection(
        snapshot: snapshot,
        candidate: candidate,
        resolver: _ControlledResolver(
          {},
          requiredLibraries: const [
            LibraryRequirement(
              namespace: 'acme.widgets',
              minVersion: 1,
            ),
          ],
        ),
      );
    });

    test('server acceptance cannot override local signal parity rejection',
        () async {
      final source = _MutableSeedSource(
        deliveryMode: FlowDeliveryMode.general,
      );
      final snapshot = await _sealedSnapshot(
        source: source,
        root: _resolved(
          _document(deliveryMode: FlowDeliveryMode.general),
        ),
      );
      final candidate = _resolved(
        _document(
          version: 2,
          deliveryMode: FlowDeliveryMode.general,
        ).copyWith(
          legacyTerminalResultPassthrough: false,
          outbound: const FlowOutboundDeclarations(
            customEvents: {
              'missing_signal': FlowOutboundPayloadDeclaration(),
            },
          ),
        ),
      );

      await _expectLocalParityRejection(
        snapshot: snapshot,
        candidate: candidate,
        resolver: _ControlledResolver({}),
        captureSeed: source.capture,
      );
    });

    test('post-prefetch drift rejects before pending promotion', () async {
      final source = _MutableSeedSource();
      final baselineChild = _resolved(_document(flow: 'child'));
      final baselineRoot = _resolved(_parentDocument(child: baselineChild));
      final snapshot = await _sealedSnapshot(
        source: source,
        root: baselineRoot,
        descendants: {'child': baselineChild},
      );
      final candidateChild = _resolved(_document(flow: 'child'));
      final candidateRoot = _resolved(
        _parentDocument(child: candidateChild),
      );
      final resolver = _ControlledResolver({
        'child': Future.value(candidateChild),
      });
      final reachedPromotionBoundary = Completer<void>();
      final releasePromotionBoundary = Completer<void>();

      final future = FlowCandidatePrefetcher.prefetch(
        snapshot: snapshot,
        captureSeed: source.capture,
        candidateRoot: candidateRoot,
        resolver: resolver,
        serverVerdictAccepted: true,
        beforePromotion: () {
          reachedPromotionBoundary.complete();
          return releasePromotionBoundary.future;
        },
      );

      await reachedPromotionBoundary.future;
      expect(resolver.calls, ['child']);
      source.signalGeneration += 1;
      releasePromotionBoundary.complete();

      final outcome = await future;
      _expectCandidateSeedDrift(outcome);
      expect(outcome, isNot(isA<FlowCandidatePrefetchAccepted>()));
    });
  });

  test('canonical retry bytes and hash remain exact at every future boundary',
      () async {
    final snapshot = await _sealedSnapshot();
    final sealedBytes = snapshot.canonicalBytes.toList();
    final sealedHash = snapshot.contentHash;

    for (final boundary in FlowMountRevalidationBoundary.values) {
      expect(snapshot.revalidate(boundary, snapshot.seed), isTrue);
      final first = snapshot.bytesForRetry(boundary, snapshot.seed)!;
      final second = snapshot.bytesForRetry(boundary, snapshot.seed)!;
      expect(first, sealedBytes);
      expect(second, sealedBytes);
      expect(() => first[0] ^= 0xff, throwsUnsupportedError);
      expect(() => second[0] = 0, throwsUnsupportedError);
      expect(snapshot.canonicalBytes, sealedBytes);
      expect(snapshot.contentHash, sealedHash);
      expect(snapshot.contentHash, snapshot.contract.contentHash);
    }
    expect(
      () => snapshot.canonicalBytes[0] = 0,
      throwsUnsupportedError,
    );
  });

  test('surface and delivery-mode matrix uses one shared invariant', () async {
    for (final surface in Surface.values) {
      for (final mode in FlowDeliveryMode.values) {
        final source = _MutableSeedSource(
          surfaceType: surface,
          deliveryMode: mode,
        );
        final root = _resolved(_document(deliveryMode: mode));
        final snapshot = await _sealedSnapshot(
          source: source,
          root: root,
        );
        final candidate = _resolved(_document(version: 2, deliveryMode: mode));

        final outcome = await FlowCandidatePrefetcher.prefetch(
          snapshot: snapshot,
          captureSeed: source.capture,
          candidateRoot: candidate,
          resolver: _ControlledResolver({}),
          serverVerdictAccepted: true,
        );

        expect(
          outcome,
          isA<FlowCandidatePrefetchAccepted>(),
          reason: '${surface.wireName}/${mode.wireName}',
        );
      }
    }
  });
}

enum _AwaitBoundary {
  assignmentKey,
  baselineRoot,
  baselineChild,
}

final List<_NamedSeedMutation> _generationMutations = [
  _NamedSeedMutation(
    'assignment provider',
    (source) => source.assignmentKeyProviderGeneration += 1,
  ),
  _NamedSeedMutation(
    'analytics identity',
    (source) => source.analyticsIdentityGeneration += 1,
  ),
  _NamedSeedMutation(
    'configuration',
    (source) => source.configurationGeneration += 1,
  ),
  _NamedSeedMutation(
    'library',
    (source) => source.libraryGeneration += 1,
  ),
  _NamedSeedMutation(
    'action',
    (source) => source.actionGeneration += 1,
  ),
  _NamedSeedMutation(
    'signal',
    (source) => source.signalGeneration += 1,
  ),
];

final List<_NamedSeedMutation> _semanticMutations = [
  _NamedSeedMutation(
    'action fingerprint',
    (source) {
      source.actionBindings['request_notifications'] = _actionBinding(
        actionName: 'changed_notifications',
      );
    },
  ),
  _NamedSeedMutation(
    'signal set',
    (source) => source.installedSignals.add('changed_signal'),
  ),
  _NamedSeedMutation(
    'installed-library version',
    (source) {
      source.installedLibraries[0] = const InstalledLibrary(
        namespace: 'acme.widgets',
        version: 7,
      );
    },
  ),
];

final class _NamedSeedMutation {
  const _NamedSeedMutation(this.name, this.apply);

  final String name;
  final void Function(_MutableSeedSource source) apply;
}

Future<FlowMountSnapshotOutcome> _sealWithMutationAtBoundary(
  _AwaitBoundary boundary,
  void Function(_MutableSeedSource source) mutate,
) async {
  final source = _MutableSeedSource();
  final leaf = _resolved(_document(flow: 'child'));
  final root = boundary == _AwaitBoundary.baselineChild
      ? _resolved(_parentDocument(child: leaf))
      : _resolved(_document());
  final assignmentKey = Completer<String?>();
  final rootCompleter = Completer<ResolvedFlow>();
  final childCompleter = Completer<ResolvedFlow>();
  final resolver = _ControlledResolver({
    'first_run': boundary == _AwaitBoundary.baselineRoot
        ? rootCompleter.future
        : Future.value(root),
    'child': childCompleter.future,
  });
  final future = FlowMountContractSnapshotBuilder(
    captureSeed: source.capture,
    resolveAssignmentKey: () => boundary == _AwaitBoundary.assignmentKey
        ? assignmentKey.future
        : Future.value('assignment-key'),
    resolver: resolver,
  ).seal();

  switch (boundary) {
    case _AwaitBoundary.assignmentKey:
      expect(source.captureCount, 1);
      mutate(source);
      assignmentKey.complete('assignment-key');
      break;
    case _AwaitBoundary.baselineRoot:
      await _waitFor(() => resolver.calls.contains('first_run'));
      mutate(source);
      rootCompleter.complete(root);
      break;
    case _AwaitBoundary.baselineChild:
      await _waitFor(() => resolver.calls.contains('child'));
      mutate(source);
      childCompleter.complete(leaf);
      break;
  }
  return future;
}

void _expectSeedDrift(FlowMountSnapshotOutcome outcome) {
  expect(
    outcome,
    isA<FlowMountSnapshotRejected>().having(
      (value) => value.reason,
      'reason',
      FlowMountSnapshotRejection.seedDrift,
    ),
  );
}

void _expectCandidateSeedDrift(FlowCandidatePrefetchOutcome outcome) {
  expect(
    outcome,
    isA<FlowCandidatePrefetchRejected>().having(
      (value) => value.reason,
      'reason',
      FlowCandidatePrefetchRejection.seedDrift,
    ),
  );
}

final class _MutableSeedSource {
  _MutableSeedSource({
    this.surfaceType = Surface.onboarding,
    this.deliveryMode = FlowDeliveryMode.typed,
  });

  final Surface surfaceType;
  final FlowDeliveryMode deliveryMode;
  int assignmentKeyProviderGeneration = 1;
  int analyticsIdentityGeneration = 1;
  int configurationGeneration = 1;
  int libraryGeneration = 1;
  int actionGeneration = 1;
  int signalGeneration = 1;
  final List<InstalledLibrary> installedLibraries = [
    const InstalledLibrary(namespace: 'acme.widgets'),
  ];
  final Map<String, FlowActionBinding<dynamic, dynamic>> actionBindings = {
    'request_notifications': _actionBinding(),
  };
  final Set<String> installedSignals = {'dismiss'};
  int captureCount = 0;
  final List<FlowMountLeaseSeed> capturedSeeds = [];

  FlowMountLeaseSeed capture() {
    captureCount += 1;
    final seed = FlowMountLeaseSeed.capture(
      flow: OnboardingFlowRef<Object?>(
        id: 'first_run',
        version: 1,
        minClient: 3,
        surface: surfaceType,
        decodeResult: (value) => value,
      ),
      deliveryMode: deliveryMode,
      assignmentKeyProviderGeneration: assignmentKeyProviderGeneration,
      analyticsIdentityGeneration: analyticsIdentityGeneration,
      configurationGeneration: configurationGeneration,
      libraryGeneration: libraryGeneration,
      actionGeneration: actionGeneration,
      signalGeneration: signalGeneration,
      builtInCatalogVersion: 5,
      installedLibraries: installedLibraries,
      actionBindings: actionBindings,
      installedSignals: installedSignals,
    );
    capturedSeeds.add(seed);
    return seed;
  }
}

FlowActionBinding<Object?, bool> _actionBinding({
  String actionName = 'request_notifications',
}) {
  return FlowActionBinding<Object?, bool>(
    actionName: actionName,
    contractVersion: 1,
    argsSchema: const FlowActionSchema.object({}),
    resultSchema: const FlowActionSchema.bool(),
    minClient: 1,
    idempotent: false,
    handler: (_, __) => true,
    decodeArgs: (value) => value,
    encodeResult: (value) => value,
  );
}

final class _ControlledResolver
    implements FlowResolver, FlowExperimentArtifactMetadataProvider {
  _ControlledResolver(
    this.responses, {
    this.requiredLibraries = const [],
  });

  final Map<String, Future<ResolvedFlow>> responses;
  final List<LibraryRequirement> requiredLibraries;
  final List<String> calls = [];

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) {
    calls.add(flow.id);
    final response = responses[flow.id];
    if (response != null) return response;
    throw FlowUnavailableError(
      flowId: flow.id,
      flowVersion: flow.version,
      reason: 'missing',
      message: 'Missing ${flow.id}.',
    );
  }

  @override
  FlowExperimentArtifactMetadata metadataFor(ResolvedFlow flow) =>
      FlowExperimentArtifactOwnership.verifiedMetadata(
        requiredLibraries: requiredLibraries,
      );
}

Future<FlowMountContractSnapshot> _sealedSnapshot({
  _MutableSeedSource? source,
  ResolvedFlow? root,
  Map<String, ResolvedFlow> descendants = const {},
}) async {
  final effectiveSource = source ?? _MutableSeedSource();
  final effectiveRoot = root ?? _resolved(_document());
  final outcome = await FlowMountContractSnapshotBuilder(
    captureSeed: effectiveSource.capture,
    resolveAssignmentKey: () async => 'assignment-key',
    resolver: _ControlledResolver({
      'first_run': Future.value(effectiveRoot),
      for (final entry in descendants.entries)
        entry.key: Future.value(entry.value),
    }),
  ).seal();
  expect(outcome, isA<FlowMountSnapshotSealed>());
  return (outcome as FlowMountSnapshotSealed).snapshot;
}

ResolvedFlow _resolved(FlowDocument document) {
  final resolved = ResolvedFlow(
    document: document,
    screenBlobs: const {},
    contentHash: FlowContentHash.compute(
      FlowDocumentCodec.encodeCanonicalJson(document),
    ),
    cacheHit: false,
  );
  return resolved;
}

FlowDocument _document({
  String flow = 'first_run',
  int version = 1,
  FlowDeliveryMode deliveryMode = FlowDeliveryMode.typed,
}) {
  return FlowDocument(
    flow: flow,
    version: version,
    schemaVersion: 1,
    minClient: 3,
    initial: 'done',
    actions: const {},
    legacyTerminalResultPassthrough: true,
    screenArtifacts: const {},
    states: const {
      'done': EndFlowState(result: {'completed': true}),
    },
    deliveryMode: deliveryMode,
  );
}

FlowDocument _parentDocument({
  String flow = 'first_run',
  int version = 1,
  ResolvedFlow? child,
  Map<String, ResolvedFlow>? children,
  FlowDeliveryMode deliveryMode = FlowDeliveryMode.typed,
}) {
  final effectiveChildren = children ??
      {
        if (child != null) 'child_state': child,
      };
  return _parentDocumentFromPins(
    base: _document(
      flow: flow,
      version: version,
      deliveryMode: deliveryMode,
    ),
    children: {
      for (final entry in effectiveChildren.entries)
        entry.key: _pinFor(entry.value.document),
    },
  );
}

FlowDocument _parentDocumentFromPins({
  required FlowDocument base,
  required Map<String, _DocumentPin> children,
}) {
  return base.copyWith(
    initial: children.keys.first,
    states: {
      for (var index = 0; index < children.length; index += 1)
        children.keys.elementAt(index): SubFlowState(
          flow: children.values.elementAt(index).flow,
          version: children.values.elementAt(index).version,
          schemaVersion: children.values.elementAt(index).schemaVersion,
          minClient: children.values.elementAt(index).minClient,
          contentHash: children.values.elementAt(index).contentHash,
          input: const {},
          onComplete: const [],
          defaultBranch: FlowBranchTarget(
            target: index + 1 < children.length
                ? children.keys.elementAt(index + 1)
                : 'done',
          ),
        ),
      'done': const EndFlowState(result: {'completed': true}),
    },
  );
}

_DocumentPin _pinFor(FlowDocument document) {
  return _DocumentPin(
    flow: document.flow,
    version: document.version,
    schemaVersion: document.schemaVersion,
    minClient: document.minClient,
    contentHash: FlowContentHash.compute(
      FlowDocumentCodec.encodeCanonicalJson(document),
    ),
  );
}

Future<void> _expectLocalParityRejection({
  required FlowMountContractSnapshot snapshot,
  required ResolvedFlow candidate,
  required FlowResolver resolver,
  FlowMountSeedCapture? captureSeed,
}) async {
  final outcome = await FlowCandidatePrefetcher.prefetch(
    snapshot: snapshot,
    captureSeed: captureSeed ?? () => snapshot.seed,
    candidateRoot: candidate,
    resolver: resolver,
    serverVerdictAccepted: true,
  );

  expect(
    outcome,
    isA<FlowCandidatePrefetchRejected>().having(
      (value) => value.reason,
      'reason',
      FlowCandidatePrefetchRejection.parityRejected,
    ),
  );
  expect(outcome, isNot(isA<FlowCandidatePrefetchAccepted>()));
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var index = 0; index < 100; index += 1) {
    if (predicate()) return;
    await Future<void>.value();
  }
  fail('Condition did not become true.');
}

Map<String, Object?> _decodeMap(Map<String, Object?> value) => value;

const _nestedActionArgsSchema = FlowActionSchema.object({
  'payloads': FlowActionSchemaField(
    required: true,
    schema: FlowActionSchema.list(
      FlowActionSchema.nullable(
        FlowActionSchema.object({
          'channel': FlowActionSchemaField(
            required: true,
            schema: FlowActionSchema.enumValues(['email', 'push']),
          ),
        }),
      ),
    ),
  ),
});

const _nestedActionResultSchema = FlowActionSchema.enumValues([
  'accepted',
  'rejected',
]);

const _nestedActionContract = FlowActionContract(
  actionName: 'request_notifications',
  contractVersion: 1,
  argsSchema: _nestedActionArgsSchema,
  resultSchema: _nestedActionResultSchema,
  minClient: 1,
  idempotent: false,
);

final class _DocumentPin {
  const _DocumentPin({
    required this.flow,
    required this.version,
    required this.schemaVersion,
    required this.minClient,
    required this.contentHash,
  });

  final String flow;
  final int version;
  final int schemaVersion;
  final int minClient;
  final FlowContentHash contentHash;
}
