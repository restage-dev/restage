import 'dart:io';

import 'package:build/build.dart';
import 'package:restage_codegen/src/durable_state.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
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
  _ReadState(this.path, this.legacyPath, this.onRead);
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
    ));
  }
}
