import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/summary_ready_resolvers.dart';

// Two isolates resolve through SummaryReadyResolvers in a scratch package
// directory whose deps file is empty and whose lock this test holds. Each
// prints `done <result>` when its resolve finishes.
const _resolveTwice = r'''
import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';

import 'SUPPORT';

Future<String> _resolve() async {
  try {
    final id = AssetId('rfw_catalog_compiler', 'lib/_probe.dart');
    await resolveSource(
      'library probe;',
      (resolver) => resolver.isLibrary(id),
      inputId: id,
      resolvers: SummaryReadyResolvers(),
    );
    return 'ok';
  } on Object catch (error) {
    return error.toString().split('\n').first;
  }
}

Future<void> main() async {
  await Future.wait([
    for (var i = 0; i < 2; i++)
      Isolate.run(_resolve).then((result) => stdout.writeln('done $result')),
  ]);
}
''';

// Kills an isolate while it holds the lock during a summary build, backdates
// the lock past the stale limit, then resolves from this same process.
const _killHolder = '''
import 'dart:io';
import 'dart:isolate';

import 'SUPPORT';

Future<void> main() async {
  final lock = File(sdkSummaryLockPath);
  final holder = await Isolate.spawn((_) => ensureSdkSummary(), null);
  while (!lock.existsSync() || lock.readAsStringSync().isEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await Future<void>.delayed(const Duration(milliseconds: 200));
  holder.kill(priority: Isolate.immediate);
  final old = DateTime.now().subtract(const Duration(minutes: 10));
  lock.setLastModifiedSync(old);
  await Future<void>.delayed(heartbeatEvery + const Duration(seconds: 5));
  final kept = lock.lastModifiedSync().difference(old).inSeconds.abs() < 2;
  stdout.writeln(kept ? 'heartbeat stopped' : 'heartbeat still beating');
  await ensureSdkSummary();
  stdout.writeln('resolved');
}
''';

final String _support =
    p.join('test', 'support', 'summary_ready_resolvers.dart');

void main() {
  // Proves both halves: resolvers wait for the lock instead of reading the
  // torn deps file, and once the holder writes the deps and releases the
  // lock, both resolve. Fails if `get` skips ensureSdkSummary or the lock.
  test(
    'resolvers wait for the SDK summary lock, then resolve',
    () async {
      await ensureSdkSummary();
      final cacheHere = p.join('.dart_tool', 'build_resolvers');
      final validDeps =
          File(p.join(cacheHere, 'sdk.sum.deps')).readAsStringSync();

      final scratch = await Directory.systemTemp.createTemp('sdk-summary-');
      addTearDown(() => scratch.delete(recursive: true));
      final cache = Directory(
        p.join(scratch.path, '.dart_tool', 'build_resolvers'),
      )..createSync(recursive: true);
      File(p.join(cacheHere, 'sdk.sum'))
          .copySync(p.join(cache.path, 'sdk.sum'));
      final deps = File(p.join(cache.path, 'sdk.sum.deps'))
        ..writeAsStringSync('');
      final lock = File(p.join(cache.path, 'restage_test.lock'))
        ..writeAsStringSync('$pid held by the test');
      // Keeps the held lock younger than the stale limit however long the
      // subprocess takes to start.
      final heartbeat = Timer.periodic(
        const Duration(seconds: 20),
        (_) => lock.setLastModifiedSync(DateTime.now()),
      );
      addTearDown(heartbeat.cancel);
      final script = File(p.join(scratch.path, 'resolve_twice.dart'))
        ..writeAsStringSync(
          _resolveTwice.replaceFirst(
            'SUPPORT',
            p.toUri(p.absolute(_support)).toString(),
          ),
        );

      final process = await Process.start(
        Platform.resolvedExecutable,
        [
          '--packages=${(await Isolate.packageConfig)!.toFilePath()}',
          script.path,
        ],
        workingDirectory: scratch.path,
      );
      addTearDown(process.kill);
      final done = <String>[];
      var waiting = 0;
      final bothWaiting = Completer<void>();
      final waited = bothWaiting.future.timeout(const Duration(minutes: 8));
      final stderrLines = <String>[];
      unawaited(
        process.exitCode.then((code) {
          if (!bothWaiting.isCompleted) {
            bothWaiting.completeError(
              StateError('exited $code first:\n${stderrLines.join('\n')}'),
            );
          }
        }),
      );
      final stdoutDone = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.startsWith('done ')) done.add(line);
        if (!bothWaiting.isCompleted && done.isNotEmpty) {
          bothWaiting.completeError(
            StateError(
              'an isolate finished before both waited on the held lock: '
              '$done',
            ),
          );
        }
      }).asFuture<void>();
      final stderrDone = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stderrLines.add(line);
        if (line.startsWith('waiting for the analyzer SDK summary lock') &&
            ++waiting == 2 &&
            !bothWaiting.isCompleted) {
          bothWaiting.complete();
        }
      }).asFuture<void>();

      await waited;
      heartbeat.cancel();
      expect(done, isEmpty);
      expect(deps.readAsStringSync(), isEmpty);

      deps.writeAsStringSync(validDeps);
      lock.deleteSync();
      expect(await process.exitCode, 0, reason: stderrLines.join('\n'));
      await Future.wait([stdoutDone, stderrDone]);
      expect(done, ['done ok', 'done ok']);
    },
  );

  test("a killed holder's lock stops refreshing and is broken", () async {
    final scratch = await Directory.systemTemp.createTemp('sdk-summary-');
    addTearDown(() => scratch.delete(recursive: true));
    // No summary yet, so the holder is mid-build when it is killed.
    Directory(p.join(scratch.path, '.dart_tool', 'build_resolvers'))
        .createSync(recursive: true);
    final script = File(p.join(scratch.path, 'kill_holder.dart'))
      ..writeAsStringSync(
        _killHolder.replaceFirst(
          'SUPPORT',
          p.toUri(p.absolute(_support)).toString(),
        ),
      );

    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        '--packages=${(await Isolate.packageConfig)!.toFilePath()}',
        script.path,
      ],
      workingDirectory: scratch.path,
    );
    addTearDown(process.kill);
    final stdoutText = process.stdout.transform(utf8.decoder).join();
    final stderrText = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(
      const Duration(minutes: 8),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw TimeoutException('the kill-holder script did not finish');
      },
    );

    expect(exitCode, 0, reason: await stderrText);
    expect(
      (await stdoutText).trim().split('\n'),
      ['heartbeat stopped', 'resolved'],
    );
  });

  test('deps that are not UTF-8 are removed', () async {
    final scratch = await Directory.systemTemp.createTemp('sdk-deps-');
    addTearDown(() => scratch.delete(recursive: true));
    final malformed = File(p.join(scratch.path, 'malformed'))
      ..writeAsBytesSync([0xC3]);
    final valid = File(p.join(scratch.path, 'valid'))
      ..writeAsStringSync('{"sdk":"x"}');

    removeUndecodableDeps(malformed);
    removeUndecodableDeps(valid);

    expect(malformed.existsSync(), isFalse);
    expect(valid.existsSync(), isTrue);
  });

  test('a lock created but never owned is released', () async {
    final scratch = await Directory.systemTemp.createTemp('sdk-lock-');
    addTearDown(() => scratch.delete(recursive: true));
    final unowned = File(p.join(scratch.path, 'unowned'))..createSync();
    final taken = File(p.join(scratch.path, 'taken'))
      ..writeAsStringSync('1 2 3');

    releaseLock(unowned, '');
    releaseLock(taken, '');

    expect(unowned.existsSync(), isFalse);
    expect(taken.existsSync(), isTrue);
  });

  test('every test build in this package names its resolvers', () {
    expect(callsWithoutResolvers(Directory('test')), isEmpty);
  });
}
