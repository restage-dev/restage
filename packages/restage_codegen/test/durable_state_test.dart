import 'dart:io';

import 'package:build/build.dart';
import 'package:restage_codegen/src/durable_state.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  untrackedStateTests();
  for (final legacy in [false, true]) {
    test(
        'dependency ${legacy ? 'legacy' : 'current'} state must be visible '
        'to the build', () async {
      final root = (await restagePackageRoot('restage_codegen'))!;
      final directory = Directory.fromUri(
        root.resolve('.restage/build/'),
      )..createSync(recursive: true);
      final temporary = directory.createTempSync('dependency-input-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final relativeDirectory = temporary.uri.path.substring(root.path.length);
      final filename = legacy ? 'wire_ids.events.jsonl' : 'state.json';
      final path = '$relativeDirectory$filename';
      final currentPath = legacy ? '$path.current' : path;
      final legacyPath = legacy ? path : '$path.legacy';
      File.fromUri(root.resolve(path)).writeAsStringSync('{}');
      final errors = <String>[];
      final result = await testBuilder(
        _ReadState(currentPath, legacyPath, (_) {}, requireTracked: true),
        {'restage_codegen|lib/probe.dart': ''},
        rootPackage: 'restage_codegen',
        onLog: (record) => errors.add(record.toString()),
      );
      expect(result.succeeded, isFalse);
      expect(
        errors.join('\n'),
        allOf(
          contains(path),
          contains('`additional_public_assets: [.restage/**]`'),
          contains(
            'If the target restricts sources, include `.restage/**` there too.',
          ),
        ),
      );
      List<int>? tracked;
      final success = await testBuilder(
        _ReadState(
          currentPath,
          legacyPath,
          (bytes) => tracked = bytes,
          requireTracked: true,
        ),
        {'restage_codegen|$path': '{}'},
        rootPackage: 'restage_codegen',
      );
      expect(success.succeeded, isTrue);
      expect(tracked, '{}'.codeUnits);
    });
  }

  for (final paths in [
    ('.restage/measurement-state.json', 'restage_measurement.compiler.json'),
    ('.restage/wire-ids.events.jsonl', 'wire_ids.events.jsonl'),
  ]) {
    group(paths.$1, () {
      late Directory root;
      setUp(() => root = Directory.systemTemp.createTempSync('restage-state-'));
      tearDown(() => root.deleteSync(recursive: true));

      test('migrates exact bytes and preserves an already migrated file', () {
        final bytes = [123, 125, 13, 10, 32, 10];
        final legacy = File.fromUri(root.uri.resolve(paths.$2))
          ..writeAsBytesSync(bytes);
        final current = migrateDurableRestageState(
          root: root,
          path: paths.$1,
          legacyPath: paths.$2,
        );
        expect(current.readAsBytesSync(), bytes);
        expect(legacy.existsSync(), isFalse);
        migrateDurableRestageState(
          root: root,
          path: paths.$1,
          legacyPath: paths.$2,
        );
        expect(current.readAsBytesSync(), bytes);
      });

      test('removes an identical legacy copy without changing state', () {
        final legacy = File.fromUri(root.uri.resolve(paths.$2))
          ..writeAsStringSync('same\r\n');
        final current = File.fromUri(root.uri.resolve(paths.$1));
        current.parent.createSync(recursive: true);
        current.writeAsBytesSync(legacy.readAsBytesSync());
        migrateDurableRestageState(
          root: root,
          path: paths.$1,
          legacyPath: paths.$2,
        );
        expect(current.readAsStringSync(), 'same\r\n');
        expect(legacy.existsSync(), isFalse);
      });

      test('conflicting files fail without modifying either location', () {
        final legacy = File.fromUri(root.uri.resolve(paths.$2))
          ..writeAsStringSync('old');
        final current = File.fromUri(root.uri.resolve(paths.$1));
        current.parent.createSync(recursive: true);
        current.writeAsStringSync('new');
        expect(
          () => migrateDurableRestageState(
            root: root,
            path: paths.$1,
            legacyPath: paths.$2,
          ),
          throwsA(isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
                contains(paths.$1), contains(paths.$2), contains('Reconcile')),
          )),
        );
        expect(legacy.readAsStringSync(), 'old');
        expect(current.readAsStringSync(), 'new');
      });

      test('reads the new tracked asset and rejects conflicting tracked state',
          () async {
        List<int>? read;
        await testBuilder(
          _ReadState(paths.$1, paths.$2, (bytes) => read = bytes),
          {'state_fixture|${paths.$1}': 'identity'},
          rootPackage: 'state_fixture',
        );
        expect(read, 'identity'.codeUnits);
        final result = await testBuilder(
          _ReadState(paths.$1, paths.$2, (_) {}),
          {
            'state_fixture|${paths.$1}': 'identity',
            'state_fixture|${paths.$2}': 'different',
          },
          rootPackage: 'state_fixture',
        );
        expect(result.succeeded, isFalse);
      });
    });
  }
}

class _ReadState implements Builder {
  _ReadState(this.path, this.legacyPath, this.onRead,
      {this.requireTracked = false});
  final bool requireTracked;
  final String path;
  final String legacyPath;
  final void Function(List<int>?) onRead;
  @override
  Map<String, List<String>> get buildExtensions => {
        r'$package$': ['read.txt']
      };
  @override
  Future<void> build(BuildStep buildStep) async {
    onRead(await readDurableRestageState(
      buildStep,
      path: path,
      legacyPath: legacyPath,
      requireTracked: requireTracked,
    ));
  }
}

void untrackedStateTests() {
  group('untracked durable state', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('restage_untracked_');
      File('${root.path}/.restage/measurement-state.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
    });

    tearDown(() => root.deleteSync(recursive: true));

    Future<List<String>> untracked(Set<String> inputs) =>
        untrackedDurableRestageState(
          package: 'app',
          canRead: (asset) async => inputs.contains(asset.path),
          packageRoot: root.uri,
          paths: const [
            '.restage/measurement-state.json',
            '.restage/wire-ids.events.jsonl',
          ],
        );

    test('a state file on disk that is not a build input is untracked',
        () async {
      expect(await untracked({}), ['.restage/measurement-state.json']);
    });

    test('a state file build.yaml admits is tracked even when absent at start',
        () async {
      File('${root.path}/build.yaml').writeAsStringSync('''
additional_public_assets:
  - .restage/measurement-state.json
  - .restage/wire-ids.events.jsonl
''');
      expect(await untracked({}), isEmpty);
    });

    test('a state file a target source glob admits is tracked', () async {
      for (final sources in [
        '[lib/**, .restage/**]',
        '{include: [lib/**, .restage/**]}',
      ]) {
        File('${root.path}/build.yaml').writeAsStringSync(
          'targets:\n  \$default:\n    sources: $sources\n',
        );
        expect(await untracked({}), isEmpty, reason: sources);
      }
    });

    test('a state file admitted as a build input is tracked', () async {
      expect(await untracked({'.restage/measurement-state.json'}), isEmpty);
    });

    test('an untracked refusal gains the build.yaml advice', () {
      const refusal = 'This build cannot decide. Then rebuild.';
      expect(withUntrackedStateAdvice(refusal, untracked: false), refusal);
      expect(
        withUntrackedStateAdvice(refusal, untracked: true),
        '$refusal $kUntrackedDurableStateAdvice',
      );
      expect(
        withUntrackedStateAdvice('Other error.', untracked: true),
        'Other error.',
      );
    });
  });
}
