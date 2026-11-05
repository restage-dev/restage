import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/build_report_command.dart';
import 'package:restage_cli/src/commands/surface_push_command.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:test/test.dart';

void main() {
  test("a generated part that doesn't compile stops a push and shows in the "
      'report', () async {
    final root = Directory.systemTemp.createTempSync('broken_part_');
    addTearDown(() => root.deleteSync(recursive: true));
    void write(String path, String text) => File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    write('pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.8.0\n');
    write(
      '.dart_tool/package_config.json',
      jsonEncode({'configVersion': 2, 'packages': <Object?>[]}),
    );
    write('lib/a.dart', "part 'restage.generated/a.restage.g.dart';\n");
    write(
      'lib/restage.generated/a.restage.g.dart',
      "part of '../a.dart';\n\nint broken = 'x';\n",
    );
    write(
      '.dart_tool/build/generated/app/lib/src/surface_publication/'
      'surface_publication.compiler.json',
      jsonEncode({'splitSites': <Object?>[]}),
    );
    const sentence =
        "Restage generated code that doesn't compile "
        '(lib/restage.generated/a.restage.g.dart:3:14): A value of type '
        "'String' can't be assigned to a variable of type 'int'. Please "
        'report this as a Restage bug. Try updating Restage, then running '
        '`dart run build_runner build` again.';

    // Each command's arguments, and whether the sentence is on stdout.
    for (final (arguments, inStdout) in [
      (['report', '--check'], true),
      (['push', 'offer', '--project', 'p', '--app', 'a'], false),
    ]) {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = CommandRunner<int>('restage', '')
        ..addCommand(BuildReportCommand(stdout: out, stderr: err))
        ..addCommand(
          SurfacePushCommand(
            stdout: out,
            stderr: err,
            interactive: const NonInteractive(),
          ),
        );
      final exit = await runner.run([...arguments, '-C', root.path]);
      expect(exit, 1, reason: '$arguments');
      expect(
        '${inStdout ? out : err}'.split('\n'),
        contains(sentence),
        reason: '$arguments',
      );
    }
  });
}
