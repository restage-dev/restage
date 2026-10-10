import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/receipts/release_receipt.dart';
import 'package:restage_cli/src/receipts/release_recorder.dart';
import 'package:restage_cli/src/receipts/render_bundle_receipt.dart';
import 'package:test/test.dart';

const _contentHash =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _engineSetId =
    '2222222222222222222222222222222222222222222222222222222222222222';

Future<ProcessResult> _git(
  Directory repository,
  List<String> arguments, {
  bool allowFailure = false,
}) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: repository.path,
    runInShell: false,
  );
  if (!allowFailure && result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result;
}

void _write(Directory root, String relative, String contents) {
  File(p.join(root.path, relative))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);
}

String _out(ProcessResult result) => (result.stdout as String).trim();

void main() {
  late Directory root;
  late Directory app;
  late StringBuffer out;
  late StringBuffer err;
  late String sourceCommit;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bundle_receipt_');
    app = Directory(p.join(root.path, 'app'))..createSync(recursive: true);
    out = StringBuffer();
    err = StringBuffer();

    await _git(root, ['init', '-b', 'main', '.']);
    await _git(root, ['config', 'user.name', 'Receipt Test']);
    await _git(root, ['config', 'user.email', 'receipts@example.test']);
    await _git(root, ['config', 'commit.gpgsign', 'false']);
    await _git(root, ['config', 'core.hooksPath', '.git/hooks']);
    // Background maintenance after a commit can race teardown.
    await _git(root, ['config', 'gc.auto', '0']);
    await _git(root, ['config', 'maintenance.auto', 'false']);
    _write(root, 'app/lib/main.dart', 'void main() {}\n');
    await _git(root, ['add', '-A']);
    await _git(root, ['commit', '-m', 'source']);
    sourceCommit = _out(await _git(root, ['rev-parse', 'HEAD']));
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<ReleaseRecorder> recorder() async {
    final opened = await ReleaseRecorder.open(projectRoot: app, stderr: err);
    expect(opened, isNotNull, reason: err.toString());
    return opened!;
  }

  Future<bool> record({
    required String head,
    int version = 4,
    bool dirty = false,
    String? environment,
    ReleaseRecorder? open,
  }) async => recordRenderBundlePush(
    recorder: open ?? await recorder(),
    organization: 'acme',
    organizationId: 7,
    project: 'demo',
    app: 'mobile',
    head: head,
    version: version,
    contentHash: _contentHash,
    engineSetId: _engineSetId,
    dirty: dirty,
    environment: environment,
    toolchain: '3.47.0',
    stdout: out,
    stderr: err,
  );

  test('records a bundle pushed to a personal head and commits it', () async {
    expect(await record(head: 'user/jo'), isTrue, reason: err.toString());

    final file = File(
      p.join(
        app.path,
        '.restage/receipts/acme/demo/mobile/bundle/user-jo/v4.json',
      ),
    );
    expect(file.existsSync(), isTrue);
    final recorded = ReleaseReceipt.decode(file.readAsStringSync());
    expect(recorded.operation, ReceiptOperation.renderBundlePush);
    expect(recorded.bundle?.head, 'user/jo');
    expect(recorded.bundle?.version, 4);
    expect(recorded.bundle?.contentHash, _contentHash);
    expect(recorded.bundle?.engineSetId, _engineSetId);
    expect(recorded.bundle?.toolchain, '3.47.0');
    expect(recorded.target.project, 'demo');
    expect(recorded.target.app, 'mobile');
    // A personal head is not an environment, so the record does not claim one.
    expect(recorded.target.environment, isNull);
    expect(recorded.source.state, ReceiptSourceState.verified);
    expect(recorded.source.commit, sourceCommit);
    expect(recorded.source.branch, 'main');

    final committed = await _git(root, [
      'show',
      '--name-only',
      '--format=%s',
      'HEAD',
    ]);
    expect(_out(committed).split('\n').where((line) => line.isNotEmpty), [
      'restage: push bundle v4 to user/jo',
      'app/.restage/receipts/acme/demo/mobile/bundle/user-jo/v4.json',
    ]);
    expect(_out(await _git(root, ['status', '--porcelain=v1'])), isEmpty);
  });

  test('names the environment when the head is one', () async {
    expect(
      await record(head: 'staging', environment: 'staging'),
      isTrue,
      reason: err.toString(),
    );

    final recorded = ReleaseReceipt.decode(
      File(
        p.join(
          app.path,
          '.restage/receipts/acme/demo/mobile/bundle/staging/v4.json',
        ),
      ).readAsStringSync(),
    );
    expect(recorded.target.environment, 'staging');
    expect(recorded.bundle?.head, 'staging');
  });

  test('records a dirty tree as dirty rather than as the source', () async {
    _write(root, 'app/lib/main.dart', 'void main() { print(1); }\n');

    expect(
      await record(head: 'dev', environment: 'dev', dirty: true),
      isTrue,
      reason: err.toString(),
    );

    final recorded = ReleaseReceipt.decode(
      File(
        p.join(
          app.path,
          '.restage/receipts/acme/demo/mobile/bundle/dev/v4.json',
        ),
      ).readAsStringSync(),
    );
    expect(recorded.source.state, ReceiptSourceState.dirty);
    expect(recorded.source.commit, sourceCommit);
    // The edit the developer was carrying is still theirs.
    final status = await _git(root, ['status', '--porcelain=v1']);
    expect((status.stdout as String).trimRight().split('\n'), [
      ' M app/lib/main.dart',
    ]);
  });

  test('two versions of one head each get their own record', () async {
    expect(await record(head: 'user/jo'), isTrue, reason: err.toString());
    expect(await record(head: 'user/jo', version: 5), isTrue, reason: '$err');

    expect(
      Directory(
        p.join(app.path, '.restage/receipts/acme/demo/mobile/bundle/user-jo'),
      ).listSync().map((entry) => p.basename(entry.path)).toList()..sort(),
      ['v4.json', 'v5.json'],
    );
    expect(
      _out(await _git(root, ['log', '--oneline'])).split('\n'),
      hasLength(3),
    );
  });

  test(
    'reports a pending receipt when the commit does not go through',
    () async {
      final hook = File(p.join(root.path, '.git', 'hooks', 'pre-commit'))
        ..writeAsStringSync('#!/bin/sh\nexit 1\n');
      await Process.run('chmod', ['+x', hook.path]);

      expect(await record(head: 'user/jo'), isFalse);

      expect(
        File(
          p.join(
            app.path,
            '.restage/receipts/acme/demo/mobile/bundle/user-jo/v4.json',
          ),
        ).existsSync(),
        isTrue,
      );
      expect(err.toString(), contains('Git receipt pending'));
      expect(err.toString(), contains('commit --only'));
      expect(
        _out(await _git(root, ['log', '--oneline'])).split('\n'),
        hasLength(1),
      );
    },
  );

  test('refuses to record outside a repository', () async {
    final loose = await Directory.systemTemp.createTemp('bundle_loose_');
    addTearDown(() => loose.deleteSync(recursive: true));

    expect(await ReleaseRecorder.open(projectRoot: loose, stderr: err), isNull);
    expect(err.toString(), contains('not in a Git repository'));
  });
}
