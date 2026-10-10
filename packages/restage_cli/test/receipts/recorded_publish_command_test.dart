import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/surface_publish_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/receipts/git_repository.dart';
import 'package:restage_cli/src/receipts/release_receipt.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

const _receiptDirectory =
    '.restage/receipts/restage/demo/mobile/surface/paywall/pro/staging';
const _pushReceiptPath = '$_receiptDirectory/push-r17.json';

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

/// The publish receipt this run wrote, whatever instant is in its name.
File _publishReceipt(Directory app) =>
    Directory(p.join(app.path, _receiptDirectory))
        .listSync()
        .whereType<File>()
        .firstWhere((file) => p.basename(file.path).startsWith('publish-'));

void main() {
  late Directory root;
  late Directory app;
  late Directory home;
  late FileCredentialStore store;
  late StringBuffer out;
  late StringBuffer err;
  late String sourceCommit;

  /// A backend that activates whatever revision it is asked for.
  http.Client acceptsPublish({void Function()? onActivate}) =>
      mockHttpClient((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['method'] != 'activateSurface') {
          fail('Unexpected wire method ${body['method']}.');
        }
        onActivate?.call();
        final revision = body['publishedRevision'] as int;
        return http.Response(
          jsonEncode({
            '__className__': 'SurfaceContractFamilyOperationResult',
            'family': {
              '__className__': 'SurfaceContractFamilyReference',
              'surfaceType': 'paywall',
              'surfaceSlug': 'pro',
              'sourceKind': 'paywall',
            },
            'publishedRevision': revision,
            'activePublishedRevisionBefore': 16,
            'activePublishedRevisionAfter': revision,
            'identityFrozenAfter': false,
          }),
          200,
        );
      });

  ({http.Client client, int Function() calls}) refusesEveryCall() {
    var calls = 0;
    return (
      client: MockClient((request) async {
        calls += 1;
        return http.Response('{}', 500);
      }),
      calls: () => calls,
    );
  }

  Future<int?> publish(
    List<String> args, {
    http.Client? client,
    GitProcessRunner? processRunner,
  }) {
    final command = SurfacePublishCommand(
      stdout: out,
      stderr: err,
      interactive: const NonInteractive(),
      credentialStore: store,
      httpClient: client ?? acceptsPublish(),
      processRunner: processRunner,
    );
    return (CommandRunner<int>('restage', '')..addCommand(command)).run([
      'publish',
      ...args,
      '--type',
      'paywall',
      '--source-kind',
      'paywall',
      '-C',
      app.path,
    ]);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('recorded_publish_');
    home = await Directory.systemTemp.createTemp('recorded_publish_home_');
    app = Directory(p.join(root.path, 'app'))..createSync(recursive: true);
    store = FileCredentialStore(p.join(home.path, 'credentials'));
    await seedCredential(store);
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
    _write(root, 'app/lib/screen.dart', 'const screen = 1;\n');
    _write(
      root,
      'app/restage_config.yaml',
      'project: demo\napp: mobile\ndefaultEnvironment: staging\n',
    );
    await _git(root, ['add', '-A']);
    await _git(root, ['commit', '-m', 'source']);
    sourceCommit = _out(await _git(root, ['rev-parse', 'HEAD']));
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    home.deleteSync(recursive: true);
  });

  /// Record the push of r17 from [sourceCommit], as a recorded push would.
  Future<void> seedPushReceipt() async {
    final pushed = ReleaseReceipt(
      operation: ReceiptOperation.surfacePush,
      recordedAt: DateTime.utc(2026, 9, 17, 12),
      target: const ReceiptTarget(
        project: 'demo',
        app: 'mobile',
        environment: 'staging',
      ),
      surface: const ReceiptSurface(
        type: 'paywall',
        id: 'pro',
        sourceKind: 'paywall',
      ),
      revision: const ReceiptRevision(stored: 17),
      source: ReceiptSource(
        state: ReceiptSourceState.verified,
        commit: sourceCommit,
        branch: 'main',
        packages: const ['app'],
      ),
    );
    _write(root, 'app/$_pushReceiptPath', pushed.encode());
    await _git(root, ['add', '-A']);
    await _git(root, ['commit', '-m', 'receipt']);
  }

  test(
    'links the publication to the source the revision was built from',
    () async {
      await seedPushReceipt();
      // HEAD moves on, and the working tree is dirty: neither changes where
      // r17 came from, and a publication of an existing revision builds nothing.
      _write(root, 'app/lib/later.dart', 'const later = 2;\n');
      await _git(root, ['add', '-A']);
      await _git(root, ['commit', '-m', 'later work']);
      _write(root, 'app/lib/screen.dart', 'const screen = 99;\n');
      final head = _out(await _git(root, ['rev-parse', 'HEAD']));
      expect(head, isNot(sourceCommit));

      final code = await publish(['pro', '--revision', '17', '--record-git']);

      expect(code, 0, reason: err.toString());
      final recorded = ReleaseReceipt.decode(
        _publishReceipt(app).readAsStringSync(),
      );
      expect(recorded.operation, ReceiptOperation.surfacePublish);
      expect(recorded.revision?.stored, 17);
      expect(recorded.revision?.activeBefore, 16);
      expect(recorded.revision?.activeAfter, 17);
      expect(recorded.surface?.type, 'paywall');
      expect(recorded.surface?.id, 'pro');
      expect(recorded.target.environmentTargetId, 12);
      expect(recorded.target.runtimePlane, 'sandbox');
      expect(recorded.source.state, ReceiptSourceState.verified);
      expect(recorded.source.commit, sourceCommit);
      expect(recorded.source.from, 'app/$_pushReceiptPath');

      final committed = await _git(root, [
        'show',
        '--name-only',
        '--format=%s',
        'HEAD',
      ]);
      expect(_out(committed).split('\n').where((line) => line.isNotEmpty), [
        'restage: publish pro r17 to staging',
        'app/${p.relative(_publishReceipt(app).path, from: app.path)}',
      ]);
      // The unrelated edit is still exactly where the developer left it.
      final status = await _git(root, ['status', '--porcelain=v1']);
      expect((status.stdout as String).trimRight().split('\n'), [
        ' M app/lib/screen.dart',
      ]);
    },
  );

  test(
    'records that the source is unknown when nothing recorded the push',
    () async {
      final code = await publish(['pro', '--revision', '5', '--record-git']);

      expect(code, 0, reason: err.toString());
      final recorded = ReleaseReceipt.decode(
        _publishReceipt(app).readAsStringSync(),
      );
      expect(recorded.source.state, ReceiptSourceState.unknown);
      expect(recorded.source.commit, isNull);
      expect(recorded.revision?.stored, 5);
      expect(out.toString(), contains('Nothing here records where r5'));
      expect(out.toString(), contains('unknown'));
    },
  );

  test(
    'records unknown rather than trusting a receipt it cannot read',
    () async {
      _write(root, 'app/$_pushReceiptPath', '{ not a receipt');
      await _git(root, ['add', '-A']);
      await _git(root, ['commit', '-m', 'damaged receipt']);

      final code = await publish(['pro', '--revision', '17', '--record-git']);

      expect(code, 0, reason: err.toString());
      final recorded = ReleaseReceipt.decode(
        _publishReceipt(app).readAsStringSync(),
      );
      expect(recorded.source.state, ReceiptSourceState.unknown);
      expect(recorded.source.commit, isNull);
    },
  );

  test(
    'refuses before the server when the repository cannot be recorded',
    () async {
      await _git(root, ['checkout', '--detach']);
      final backend = refusesEveryCall();

      final code = await publish([
        'pro',
        '--revision',
        '17',
        '--record-git',
      ], client: backend.client);

      expect(code, 1);
      expect(backend.calls(), 0);
      expect(err.toString(), contains('detached'));
    },
  );

  test('without the flag it publishes exactly as before', () async {
    final code = await publish(['pro', '--revision', '17']);

    expect(code, 0, reason: err.toString());
    expect(out.toString(), contains('Published "pro" at r17'));
    expect(
      Directory(p.join(app.path, '.restage', 'receipts')).existsSync(),
      isFalse,
    );
    expect(
      _out(await _git(root, ['log', '--oneline'])).split('\n'),
      hasLength(1),
    );
  });

  test('the project setting records without the flag', () async {
    await seedPushReceipt();
    _write(
      root,
      'app/restage_config.yaml',
      'project: demo\napp: mobile\ndefaultEnvironment: staging\n'
          'recordGit: true\n',
    );

    final code = await publish(['pro', '--revision', '17']);

    expect(code, 0, reason: err.toString());
    expect(_publishReceipt(app).existsSync(), isTrue);
  });

  test('--no-record-git overrides the project setting', () async {
    _write(
      root,
      'app/restage_config.yaml',
      'project: demo\napp: mobile\ndefaultEnvironment: staging\n'
          'recordGit: true\n',
    );

    final code = await publish(
      ['pro', '--revision', '17', '--no-record-git'],
      processRunner: (executable, arguments, {workingDirectory}) async =>
          fail('Git ran for a publish that opted out of recording'),
    );

    expect(code, 0, reason: err.toString());
    expect(
      Directory(p.join(app.path, '.restage', 'receipts')).existsSync(),
      isFalse,
    );
  });

  test('two activations of one revision are two records', () async {
    await seedPushReceipt();
    var activeBefore = 16;
    http.Client activates() => mockHttpClient((request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final revision = body['publishedRevision'] as int;
      final before = activeBefore;
      activeBefore = revision;
      return http.Response(
        jsonEncode({
          '__className__': 'SurfaceContractFamilyOperationResult',
          'family': {
            '__className__': 'SurfaceContractFamilyReference',
            'surfaceType': 'paywall',
            'surfaceSlug': 'pro',
            'sourceKind': 'paywall',
          },
          'publishedRevision': revision,
          'activePublishedRevisionBefore': before,
          'activePublishedRevisionAfter': revision,
          'identityFrozenAfter': false,
        }),
        200,
      );
    });

    expect(
      await publish([
        'pro',
        '--revision',
        '17',
        '--record-git',
      ], client: activates()),
      0,
      reason: err.toString(),
    );
    expect(
      await publish([
        'pro',
        '--revision',
        '17',
        '--record-git',
      ], client: activates()),
      0,
      reason: err.toString(),
    );

    final records = Directory(p.join(app.path, _receiptDirectory))
        .listSync()
        .map((entry) => p.basename(entry.path))
        .where((name) => name.startsWith('publish-'))
        .toList();
    expect(records, hasLength(2));
    expect(_out(await _git(root, ['log', '--format=%s', '-2'])).split('\n'), [
      'restage: publish pro r17 to staging',
      'restage: publish pro r17 to staging',
    ]);
  });

  test(
    'reports a pending receipt when the commit does not go through',
    () async {
      await seedPushReceipt();
      final hook = File(p.join(root.path, '.git', 'hooks', 'pre-commit'))
        ..writeAsStringSync('#!/bin/sh\nexit 1\n');
      await Process.run('chmod', ['+x', hook.path]);
      var activated = 0;

      final code = await publish([
        'pro',
        '--revision',
        '17',
        '--record-git',
      ], client: acceptsPublish(onActivate: () => activated += 1));

      expect(code, 2);
      expect(activated, 1);
      expect(_publishReceipt(app).existsSync(), isTrue);
      expect(out.toString(), contains('Published "pro" at r17'));
      expect(err.toString(), contains('Git receipt pending'));
      expect(err.toString(), contains('commit --only'));
      expect(
        _out(await _git(root, ['log', '--oneline'])).split('\n'),
        hasLength(2),
      );
    },
  );
}
