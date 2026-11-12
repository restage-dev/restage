import 'dart:io';

import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/version.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('the version is the one the pubspec states', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect(restageCliVersion, pubspec['version']);
  });

  test('restage --version prints it and exits 0', () async {
    final stdout = StringBuffer();
    final code = await RestageCli(
      stdout: stdout,
      stderr: StringBuffer(),
      hasTerminal: () => false,
    ).run(const ['--version']);
    expect(code, 0);
    expect(stdout.toString(), startsWith('restage $restageCliVersion'));
  });

  test('--help lists --version', () async {
    final stdout = StringBuffer();
    await RestageCli(
      stdout: stdout,
      stderr: StringBuffer(),
      hasTerminal: () => false,
    ).run(const ['--help']);
    expect(stdout.toString(), contains('--version'));
  });

  test('a git install names its commit', () {
    expect(
      commitInPackagePath(
        '/home/a/.pub-cache/git/restage-03d9b2b115c19d16572a5d0700f6a35d8deba4e6'
        '/packages/restage_cli/lib/',
      ),
      '03d9b2b115c19d16572a5d0700f6a35d8deba4e6',
    );
    expect(
      commitInPackagePath('/workspaces/src/restage/packages/restage_cli/lib/'),
      isNull,
    );
  });
}
