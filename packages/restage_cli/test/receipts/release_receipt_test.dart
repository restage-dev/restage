import 'package:restage_cli/src/receipts/release_receipt.dart';
import 'package:test/test.dart';

const _hashA =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _hashB =
    '2222222222222222222222222222222222222222222222222222222222222222';
const _fingerprint =
    '3333333333333333333333333333333333333333333333333333333333333333';
const _commit = '4444444444444444444444444444444444444444';

ReleaseReceipt _pushReceipt() => ReleaseReceipt(
  operation: ReceiptOperation.surfacePush,
  recordedAt: DateTime.utc(2026, 9, 17, 19, 52, 37, 123),
  target: const ReceiptTarget(
    organization: 'acme',
    project: 'acme-app',
    app: 'ios',
    environment: 'staging',
    environmentTargetId: 3,
    runtimePlane: 'live',
  ),
  surface: const ReceiptSurface(
    type: 'paywall',
    id: 'welcome',
    sourceKind: 'paywall',
    contractVersion: 2,
  ),
  revision: const ReceiptRevision(stored: 17, identityFrozen: false),
  // Deliberately out of order: the encoder is what makes the file canonical.
  artifacts: const [
    ReceiptArtifact(path: 'welcome/screen.rfw', contentHash: _hashB),
    ReceiptArtifact(path: 'welcome/flow.json', contentHash: _hashA),
  ],
  generationFingerprint: _fingerprint,
  source: const ReceiptSource(
    state: ReceiptSourceState.verified,
    commit: _commit,
    branch: 'main',
    packages: ['packages/ui', 'apps/example'],
  ),
);

void main() {
  group('canonical encoding', () {
    test('writes fixed key order, two-space indent and a trailing newline', () {
      expect(_pushReceipt().encode(), '''
{
  "receiptVersion": 1,
  "operation": "surface-push",
  "recordedAt": "2026-09-17T19:52:37Z",
  "target": {
    "organization": "acme",
    "project": "acme-app",
    "app": "ios",
    "environment": "staging",
    "environmentTargetId": 3,
    "runtimePlane": "live"
  },
  "surface": {
    "type": "paywall",
    "id": "welcome",
    "sourceKind": "paywall",
    "contractVersion": 2
  },
  "revision": {
    "stored": 17,
    "identityFrozen": false
  },
  "artifacts": [
    {
      "path": "welcome/flow.json",
      "contentHash": "$_hashA"
    },
    {
      "path": "welcome/screen.rfw",
      "contentHash": "$_hashB"
    }
  ],
  "generation": {
    "fingerprint": "$_fingerprint"
  },
  "source": {
    "state": "verified",
    "commit": "$_commit",
    "branch": "main",
    "packages": [
      "apps/example",
      "packages/ui"
    ]
  }
}
''');
    });

    test('the same operation encodes byte-identically twice', () {
      expect(_pushReceipt().encode(), _pushReceipt().encode());
    });

    test('absent sections are left out rather than written as null', () {
      final receipt = ReleaseReceipt(
        operation: ReceiptOperation.surfacePublish,
        recordedAt: DateTime.utc(2026, 9, 17),
        target: const ReceiptTarget(
          project: 'acme-app',
          app: 'ios',
          environment: 'production',
        ),
        source: const ReceiptSource.unknown(),
      );
      final json = receipt.toJson();

      expect(json.keys, [
        'receiptVersion',
        'operation',
        'recordedAt',
        'target',
        'source',
      ]);
      expect(receipt.encode(), isNot(contains('null')));
      expect(receipt.encode(), contains('"state": "unknown"'));
    });

    test('a bundle receipt records its head, version and engine set', () {
      final receipt = ReleaseReceipt(
        operation: ReceiptOperation.renderBundlePush,
        recordedAt: DateTime.utc(2026, 9, 17),
        target: const ReceiptTarget(
          project: 'acme-app',
          app: 'ios',
          environment: 'staging',
        ),
        bundle: const ReceiptBundle(
          head: 'user/jo',
          version: 4,
          contentHash: _hashA,
          engineSetId: _hashB,
          toolchain: '3.47.0',
        ),
        source: const ReceiptSource(
          state: ReceiptSourceState.dirty,
          commit: _commit,
        ),
      );

      expect(receipt.toJson()['bundle'], {
        'head': 'user/jo',
        'version': 4,
        'contentHash': _hashA,
        'engineSetId': _hashB,
        'toolchain': '3.47.0',
      });
      expect(receipt.toJson()['source'], {'state': 'dirty', 'commit': _commit});
    });

    test('timestamps are recorded in UTC at second precision', () {
      final local = DateTime.utc(2026, 1, 2, 3, 4, 5, 678).toLocal();
      expect(formatReceiptTimestamp(local), '2026-01-02T03:04:05Z');
    });
  });

  group('decoding', () {
    test('round-trips a push receipt', () {
      final decoded = ReleaseReceipt.decode(_pushReceipt().encode());

      expect(decoded.operation, ReceiptOperation.surfacePush);
      expect(decoded.recordedAt, DateTime.utc(2026, 9, 17, 19, 52, 37));
      expect(decoded.target.organization, 'acme');
      expect(decoded.surface?.id, 'welcome');
      expect(decoded.surface?.contractVersion, 2);
      expect(decoded.revision?.stored, 17);
      expect(decoded.artifacts.map((a) => a.path), [
        'welcome/flow.json',
        'welcome/screen.rfw',
      ]);
      expect(decoded.generationFingerprint, _fingerprint);
      expect(decoded.source.state, ReceiptSourceState.verified);
      expect(decoded.source.commit, _commit);
      expect(decoded.encode(), _pushReceipt().encode());
    });

    test('refuses a receipt written to a later schema', () {
      final source = _pushReceipt().encode().replaceFirst(
        '"receiptVersion": 1',
        '"receiptVersion": 2',
      );

      expect(
        () => ReleaseReceipt.decode(source),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('version 2'),
          ),
        ),
      );
    });

    test('refuses an unknown operation', () {
      final source = _pushReceipt().encode().replaceFirst(
        '"surface-push"',
        '"surface-teleport"',
      );

      expect(() => ReleaseReceipt.decode(source), throwsFormatException);
    });

    test('refuses a commit that is not a full hash', () {
      final source = _pushReceipt().encode().replaceFirst(_commit, '444444');

      expect(() => ReleaseReceipt.decode(source), throwsFormatException);
    });

    test('refuses an artifact hash that is not a content hash', () {
      final source = _pushReceipt().encode().replaceFirst(_hashA, 'abc');

      expect(() => ReleaseReceipt.decode(source), throwsFormatException);
    });

    test('reads a hash that names its algorithm', () {
      final source = _pushReceipt().encode().replaceFirst(
        _hashA,
        'sha256:$_hashA',
      );

      expect(
        ReleaseReceipt.decode(source).artifacts.first.contentHash,
        'sha256:$_hashA',
      );
    });

    test('refuses a timestamp that is not UTC', () {
      final source = _pushReceipt().encode().replaceFirst(
        '2026-09-17T19:52:37Z',
        '2026-09-17T19:52:37+02:00',
      );

      expect(() => ReleaseReceipt.decode(source), throwsFormatException);
    });

    test('refuses text that is not JSON', () {
      expect(() => ReleaseReceipt.decode('not json'), throwsFormatException);
    });
  });
}
