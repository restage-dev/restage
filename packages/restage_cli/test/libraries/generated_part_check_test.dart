import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/build_report_command.dart';
import 'package:restage_cli/src/commands/paywall_command.dart';
import 'package:restage_cli/src/commands/surface_push_command.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/libraries/generated_part_check.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';

void main() {
  // Each of the three commands runs a real `dart analyze`.
  test("a generated part that doesn't compile stops a push and shows in the "
      'report', () async {
    final root = Directory.systemTemp.createTempSync('broken_part_');
    addTearDown(() => root.deleteSync(recursive: true));
    void write(String path, String text) => File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    // A push checks the parts of a build that succeeded.
    await seedGeneratedPaywall(root, slug: 'offer');
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
      '.dart_tool/build/generated/$fixturePackageName/lib/src/'
      'surface_publication/surface_publication.compiler.json',
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
      (['paywall', 'push', 'offer', '--project', 'p', '--app', 'a'], false),
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
        )
        ..addCommand(
          PaywallCommand(
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
  }, timeout: const Timeout(Duration(minutes: 3)));

  // A workspace member resolves through the workspace root.
  test('a workspace member is checked through its workspace', () async {
    final root = Directory.systemTemp.createTempSync('workspace_part_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, '.dart_tool/package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{}');
    final member = Directory(p.join(root.path, 'apps/app'));
    final part = p.join(member.path, 'lib/restage.generated/a.restage.g.dart');
    File(part)
      ..createSync(recursive: true)
      ..writeAsStringSync("part of '../a.dart';\n");
    final broken = await generatedPartErrors(
      member,
      analyze: (executable, arguments, directory) async => ProcessResult(
        0,
        3,
        'ERROR|COMPILE_TIME_ERROR|X|$part|3|14|1|Broken.',
        '',
      ),
    );
    expect(broken.single.path, 'lib/restage.generated/a.restage.g.dart');
  });

  test(
    'a push after a failed build names the build error, not a part',
    () async {
      final root = Directory.systemTemp.createTempSync('failed_build_part_');
      addTearDown(() => root.deleteSync(recursive: true));
      void write(String path, String text) => File(p.join(root.path, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
      write(
        '.dart_tool/package_config.json',
        jsonEncode({'configVersion': 2, 'packages': <Object?>[]}),
      );
      write('lib/a.dart', "part 'restage.generated/a.restage.g.dart';\n");
      write(
        'lib/restage.generated/a.restage.g.dart',
        "part of '../a.dart';\n\nint broken = 'x';\n",
      );
      await seedGeneratedPaywall(root, slug: 'offer');
      const failure = '[duplicateId] lib/a.dart: two surfaces share an id.';
      await writeBuildResult(root, errors: [failure]);
      var analyzed = false;
      Future<ProcessResult> analyze(
        String executable,
        List<String> arguments,
        String directory,
      ) async {
        analyzed = true;
        return ProcessResult(0, 0, '', '');
      }

      for (final arguments in [
        ['push', 'offer', '--project', 'p', '--app', 'a'],
        ['paywall', 'push', 'offer', '--project', 'p', '--app', 'a'],
      ]) {
        final out = StringBuffer();
        final err = StringBuffer();
        final runner = CommandRunner<int>('restage', '')
          ..addCommand(
            SurfacePushCommand(
              stdout: out,
              stderr: err,
              interactive: const NonInteractive(),
              analyze: analyze,
            ),
          )
          ..addCommand(
            PaywallCommand(
              stdout: out,
              stderr: err,
              interactive: const NonInteractive(),
            ),
          );
        final exit = await runner.run([...arguments, '-C', root.path]);
        expect(exit, 1, reason: '$arguments');
        expect(
          '$err'.trim(),
          'The last `dart run build_runner build` failed, so there is nothing '
          'current to push. $failure Try fixing it, then run '
          '`dart run build_runner build` again.',
          reason: '$arguments',
        );
      }
      expect(analyzed, isFalse);
    },
  );
}
