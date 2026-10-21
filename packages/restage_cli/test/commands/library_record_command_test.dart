import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/library_command.dart';
import 'package:test/test.dart';

void main() {
  late Directory package;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    package = Directory.systemTemp.createTempSync('library_record_');
    File(
      p.join(package.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: acme\n');
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() => package.deleteSync(recursive: true));

  File draft(String namespace, int version) => File(
    p.joinAll([
      package.path,
      '.restage',
      'build',
      'library-contracts',
      namespace,
      'v$version.json',
    ]),
  );

  File recorded(String namespace, int version) => File(
    p.joinAll([
      package.path,
      '.restage',
      'library-contracts',
      namespace,
      'v$version.json',
    ]),
  );

  void writeDraft(String namespace, int version) {
    draft(namespace, version)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'namespace': namespace,
          'capabilityVersion': version,
          'compatibleSince': 1,
        }),
      );
  }

  Future<int?> record(List<String> arguments) =>
      (CommandRunner<int>('restage', '')
            ..addCommand(LibraryCommand(stdout: out, stderr: err)))
          .run(['library', 'record', ...arguments]);

  test('records every drafted library from inside the package', () async {
    writeDraft('acme.widgets', 2);
    writeDraft('acme.icons', 1);
    final nested = Directory(p.join(package.path, 'lib'))..createSync();

    final code = await record(['-C', nested.path]);

    expect(code, 0, reason: err.toString());
    expect(
      recorded('acme.widgets', 2).readAsStringSync(),
      draft('acme.widgets', 2).readAsStringSync(),
    );
    expect(recorded('acme.icons', 1).existsSync(), isTrue);
    expect(out.toString(), contains('Recorded library acme.icons v1'));
    expect(out.toString(), contains('Recorded library acme.widgets v2'));
  });

  test('keeps a version recorded before', () async {
    writeDraft('acme.widgets', 2);
    recorded('acme.widgets', 2)
      ..createSync(recursive: true)
      ..writeAsStringSync('kept');

    final code = await record(['-C', package.path]);

    expect(code, 0);
    expect(recorded('acme.widgets', 2).readAsStringSync(), 'kept');
    expect(out.toString(), 'Library acme.widgets v2 is already recorded.\n');
  });

  test('reports JSON', () async {
    writeDraft('acme.widgets', 2);

    final code = await record(['-C', package.path, '--json']);

    expect(code, 0);
    final json = jsonDecode(out.toString()) as Map<String, Object?>;
    expect((json['recorded']! as List).single, containsPair('version', 2));
    expect(json['alreadyRecorded'], isEmpty);
  });

  test('fails when the build drafted nothing', () async {
    final code = await record(['-C', package.path]);

    expect(code, 1);
    expect(err.toString(), contains('dart run build_runner build'));
    expect(
      Directory(
        p.join(package.path, '.restage', 'library-contracts'),
      ).existsSync(),
      isFalse,
    );
  });
}
