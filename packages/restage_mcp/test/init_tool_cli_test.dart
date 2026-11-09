import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart' show SelectorSyntax;
import 'package:restage_cli/restage_cli.dart' show NonInteractive, RestageCli;
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_mcp/src/project_tools.dart';
import 'package:test/test.dart';

// Every restage_init argument must be one the real CLI parser accepts.
void main() {
  late Directory app;
  late FileCredentialStore store;

  setUp(() {
    final root = Directory.systemTemp.createTempSync('mcp_init_');
    addTearDown(() => root.deleteSync(recursive: true));
    app = Directory('${root.path}/app')..createSync();
    File(
      '${app.path}/pubspec.yaml',
    ).writeAsStringSync('name: app\nenvironment:\n  sdk: ^3.5.0\n');
    File('${app.path}/lib/restage_preview.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'package:flutter/widgets.dart';\n\n"
        'Widget wrapPreview(Widget child) => child;\n',
      );
    store = FileCredentialStore('${root.path}/credentials');
  });

  Future<(int, String)> run(List<String> args) async {
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final code = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      hasTerminal: () => false,
      interactiveFactory: (_) => const NonInteractive(),
      selectorSyntax: SelectorSyntax.mcp,
    ).run(args);
    return (code, '$stdout\n$stderr');
  }

  Map<String, Object?> every(bool flags) => {
    'projectDirectory': app.path,
    'projectSlug': 'shop',
    'appSlug': 'shop-app',
    'environmentSlug': 'dev',
    'runtimePlane': 'sandbox',
    'starter': flags,
    'addDependencies': flags,
    'sdkKey': 'rs_pk_sandbox_dev_abc',
    'previewWrapper': 'lib/restage_preview.dart#wrapPreview',
    'dryRun': true,
  };

  test('the request covers every schema property', () {
    expect({
      ...every(true).keys,
      'organizationId',
    }, initToolSchema.properties!.keys.toSet());
  });

  for (final flags in [true, false]) {
    test('the CLI parses every argument (booleans $flags)', () async {
      final args = initArguments(
        CallToolRequest(name: 'restage_init', arguments: every(flags)),
        organizationSlug: 'acme',
      );
      final (code, output) = await run(args);
      expect(output, isNot(contains('Could not find an option')));
      expect(code, 0, reason: output);
    });
  }

  test('a removed flag fails the same parser', () async {
    final (code, output) = await run([
      'init',
      '-C',
      app.path,
      '--no-early-request',
    ]);
    expect(code, isNot(0));
    expect(
      output,
      contains('Could not find an option named "--no-early-request"'),
    );
  });
}
