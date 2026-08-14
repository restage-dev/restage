// The delivery-path parity gate.
//
// WRITTEN BEFORE THE SPLIT PATH EXISTS, deliberately. Every verdict below was
// reasoned out from the delivery contract first and then confirmed against the
// self-contained path, which is the shipped, reviewed reference. When the split
// path lands it must reproduce this table exactly; a difference is a finding
// about the split path, never a reason to edit a line of this file.
//
// The table pins the STAGE a refusal happens at and the FACTS an acceptance
// assembles. It deliberately does not pin hash literals: the two hash claims
// are written structurally instead — the assembled content hash, and the hash
// of the canonical bytes RE-DERIVED from the decoded parts, must both equal the
// hash of the frame that arrived. A pinned hex string would go stale on any
// change to an unrelated fixture byte; the structural claim never does, and it
// says something stronger.

import 'package:flutter_test/flutter_test.dart';

import 'surface_artifact_parity_cases.dart';
import 'surface_artifact_parity_corpus.dart';

void main() {
  group('delivery path parity', () {
    final cases = parityCases();

    test('the corpus and the pinned table cover exactly the same cases', () {
      final corpusNames = cases.map((c) => c.name).toSet();
      final pinnedNames = _expected.keys.toSet();
      expect(
        corpusNames.difference(pinnedNames),
        isEmpty,
        reason: 'a case with no pinned verdict proves nothing',
      );
      expect(
        pinnedNames.difference(corpusNames),
        isEmpty,
        reason: 'a pinned verdict with no case is dead weight',
      );
      // Guards the shape of the instrument itself: a corpus silently emptied
      // would otherwise satisfy every per-case expectation by iterating none.
      expect(cases.length, _expectedCaseCount);
    });

    test('every payload kind is represented, in both directions', () {
      // A parity gate that only ever saw one kind accepted would miss exactly
      // the divergence the split path is most likely to introduce.
      final acceptedKinds = <String>{
        for (final entry in _expected.entries)
          if (entry.value case final _Accept accept) accept.payloadKind,
      };
      expect(acceptedKinds, containsAll(<String>{'blob', 'flow'}));
      final stages = <ParityStage>{
        for (final entry in _expected.entries)
          if (entry.value case final _Reject reject) reject.stage,
      };
      expect(
        stages,
        containsAll(<ParityStage>{
          ParityStage.contentHash,
          ParityStage.payloadFrame,
          ParityStage.identity,
          ParityStage.capability,
        }),
      );
    });

    for (final testCase in cases) {
      test('self-contained path: ${testCase.name}', () {
        final outcome = evaluateSelfContained(testCase);
        _assertMatches(outcome, _expected[testCase.name]!, testCase);
      });
    }

    for (final testCase in cases) {
      test('split path: ${testCase.name}', () {
        final outcome = evaluateSplitPath(testCase);
        _assertMatches(outcome, _expected[testCase.name]!, testCase);
      });
    }

    for (final testCase in cases) {
      test('both paths reach the same verdict: ${testCase.name}', () {
        // Asserted directly as well as against the table. The table is what
        // makes a change to BOTH evaluators still fail; this is what catches
        // the case where they diverge in a way the table does not describe —
        // a different assembled fact under the same accept, say.
        expect(evaluateSplitPath(testCase), evaluateSelfContained(testCase));
      });
    }
  });
}

/// The pinned table. One entry per case, by name.
const int _expectedCaseCount = 26;

final Map<String, _Verdict> _expected = <String, _Verdict>{
  // ---- blob, accepted -------------------------------------------------
  'blob: plain': const _Accept(
    payloadKind: 'blob',
    minClient: 2,
    requiredLibraries: <String>[],
    version: 12,
    surfaceType: 'paywall',
    surfaceSlug: 'pro_upgrade',
  ),
  'blob: with a satisfied library requirement': const _Accept(
    payloadKind: 'blob',
    minClient: 2,
    requiredLibraries: <String>['acme.widgets@2'],
    version: 3,
    surfaceType: 'paywall',
    surfaceSlug: 'pro_upgrade',
  ),
  'blob: an engagement surface, not a paywall': const _Accept(
    payloadKind: 'blob',
    minClient: 2,
    requiredLibraries: <String>[],
    version: 2,
    surfaceType: 'message',
    surfaceSlug: 'welcome_back',
  ),

  // ---- blob, refused --------------------------------------------------
  'blob: the declared hash is not the bytes':
      const _Reject(ParityStage.contentHash),
  'blob: truncated frame': const _Reject(ParityStage.payloadFrame),
  'blob: trailing bytes after the frame':
      const _Reject(ParityStage.payloadFrame),
  'blob: unknown payload kind': const _Reject(ParityStage.payloadFrame),
  'blob: empty frame': const _Reject(ParityStage.payloadFrame),
  'blob: requirement section missing': const _Reject(ParityStage.payloadFrame),
  'blob: requirements out of canonical order':
      const _Reject(ParityStage.payloadFrame),
  'blob: floor above this build': const _Reject(ParityStage.capability),
  'blob: requires a library this build lacks':
      const _Reject(ParityStage.capability),
  'blob: requires a newer version of a present library':
      const _Reject(ParityStage.capability),
  'blob: a different slug than was asked for':
      const _Reject(ParityStage.identity),
  'blob: a different surface category than was asked for':
      const _Reject(ParityStage.identity),

  // ---- flow -----------------------------------------------------------
  'flow: plain': const _Accept(
    payloadKind: 'flow',
    minClient: 2,
    requiredLibraries: <String>[],
    version: 5,
    surfaceType: 'onboarding',
    surfaceSlug: 'first_run',
  ),
  'flow: with a satisfied library requirement': const _Accept(
    payloadKind: 'flow',
    minClient: 2,
    requiredLibraries: <String>['acme.widgets@3'],
    version: 5,
    surfaceType: 'onboarding',
    surfaceSlug: 'first_run',
  ),
  'flow: the declared hash is not the bytes':
      const _Reject(ParityStage.contentHash),
  'flow: truncated frame': const _Reject(ParityStage.payloadFrame),
  'flow: a screen blob that is not the one the graph names':
      const _Reject(ParityStage.payloadFrame),
  'flow: floor above this build': const _Reject(ParityStage.capability),
  'flow: requires a library this build lacks':
      const _Reject(ParityStage.capability),
  'flow: a different slug than was asked for':
      const _Reject(ParityStage.identity),

  // ---- screen ---------------------------------------------------------
  'screen: plain': const _Accept(
    payloadKind: 'blob',
    minClient: 2,
    requiredLibraries: <String>[],
    version: 9,
    surfaceType: 'general',
    surfaceSlug: 'feature_announcement',
  ),
  'screen: the declared hash is not the bytes':
      const _Reject(ParityStage.contentHash),
  'screen: floor above this build': const _Reject(ParityStage.capability),
};

/// Asserts one outcome against its pinned verdict.
///
/// Exported shape rather than an inline closure so the split-path suite asserts
/// through the identical comparison — two suites that compare differently do
/// not prove parity, they prove two things.
void _assertMatches(
  ParityOutcome outcome,
  _Verdict expected,
  ParityCase testCase,
) {
  switch (expected) {
    case _Reject(:final stage):
      expect(
        outcome,
        isA<ParityRejected>(),
        reason: '${testCase.name} must be refused; got $outcome',
      );
      final rejected = outcome as ParityRejected;
      expect(
        rejected.stage,
        isNot(ParityStage.unclassified),
        reason: '${testCase.name} was refused with a message this instrument '
            'cannot classify — extend the classifier rather than the '
            'expectation: ${rejected.diagnostic}',
      );
      expect(
        rejected.stage,
        stage,
        reason: '${testCase.name} was refused at the wrong stage '
            '(${rejected.diagnostic})',
      );
    case _Accept():
      expect(
        outcome,
        isA<ParityAccepted>(),
        reason: '${testCase.name} must be accepted; got $outcome',
      );
      final accepted = outcome as ParityAccepted;
      expect(accepted.payloadKind, expected.payloadKind, reason: testCase.name);
      expect(accepted.minClient, expected.minClient, reason: testCase.name);
      expect(
        accepted.requiredLibraries,
        expected.requiredLibraries,
        reason: testCase.name,
      );
      expect(accepted.version, expected.version, reason: testCase.name);
      expect(
        accepted.surfaceType,
        expected.surfaceType,
        reason: testCase.name,
      );
      expect(
        accepted.surfaceSlug,
        expected.surfaceSlug,
        reason: testCase.name,
      );
      expect(
        accepted.publishedAtMicros,
        testCase.publishedAt.toUtc().microsecondsSinceEpoch,
        reason: testCase.name,
      );
      // The two structural hash claims. Both compare against the frame that
      // arrived, so neither can be satisfied by a path that quietly assembled
      // a different document.
      expect(
        accepted.contentHash,
        contentHashOf(testCase.artifactBytes),
        reason: '${testCase.name}: assembled content hash is not the frame',
      );
      expect(
        accepted.canonicalBytesDigest,
        contentHashOf(testCase.artifactBytes),
        reason: '${testCase.name}: canonical bytes re-derived from the decoded '
            'parts are not the frame that arrived',
      );
  }
}

sealed class _Verdict {
  const _Verdict();
}

final class _Accept extends _Verdict {
  const _Accept({
    required this.payloadKind,
    required this.minClient,
    required this.requiredLibraries,
    required this.version,
    required this.surfaceType,
    required this.surfaceSlug,
  });

  final String payloadKind;
  final int minClient;
  final List<String> requiredLibraries;
  final int version;
  final String surfaceType;
  final String surfaceSlug;
}

final class _Reject extends _Verdict {
  const _Reject(this.stage);

  final ParityStage stage;
}
