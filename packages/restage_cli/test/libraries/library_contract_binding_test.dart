import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/libraries/library_contract_binding.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late Directory app;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('contract_binding_');
    app = Directory(p.join(workspace.path, 'app'))..createSync();
  });

  tearDown(() => workspace.deleteSync(recursive: true));

  String contract(String namespace, int version, {String widget = 'Card'}) =>
      jsonEncode({
        'namespace': namespace,
        'capabilityVersion': version,
        'compatibleSince': 1,
        'widgets': [
          {'name': widget},
        ],
      });

  File draft(Directory root, String namespace, int version) => File(
    p.join(
      root.path,
      '.restage',
      'build',
      'library-contracts',
      namespace,
      'v$version.json',
    ),
  );

  File bound(Directory root, String namespace, int version) => File(
    p.join(
      root.path,
      '.restage',
      'library-contracts',
      namespace,
      'v$version.json',
    ),
  );

  void writeDraft(
    Directory root,
    String namespace,
    int version, {
    String widget = 'Card',
  }) {
    draft(root, namespace, version)
      ..createSync(recursive: true)
      ..writeAsStringSync(contract(namespace, version, widget: widget));
  }

  test('binds the draft of each required version', () {
    writeDraft(app, 'app', 2);

    final result = bindLibraryContracts(projectRoot: app, required: {'app': 2});

    expect(result.single.namespace, 'app');
    expect(result.single.version, 2);
    expect(
      bound(app, 'app', 2).readAsStringSync(),
      draft(app, 'app', 2).readAsStringSync(),
    );
  });

  test('never rewrites a bound version', () {
    writeDraft(app, 'app', 2);
    bindLibraryContracts(projectRoot: app, required: {'app': 2});
    final before = bound(app, 'app', 2).readAsStringSync();
    writeDraft(app, 'app', 2, widget: 'Banner');

    final result = bindLibraryContracts(projectRoot: app, required: {'app': 2});

    expect(result, isEmpty);
    expect(bound(app, 'app', 2).readAsStringSync(), before);
  });

  test('leaves a library without a draft to its own package', () {
    final result = bindLibraryContracts(
      projectRoot: app,
      required: {'acme.widgets': 1},
    );

    expect(result, isEmpty);
    expect(Directory(p.join(app.path, '.restage')).existsSync(), isFalse);
  });

  test('binds into a package the app depends on by path', () {
    final design = Directory(p.join(workspace.path, 'design'))..createSync();
    final cached = Directory(p.join(workspace.path, 'cache', 'acme'))
      ..createSync(recursive: true);
    writeDraft(design, 'design', 1);
    writeDraft(cached, 'cached', 1);
    File(p.join(app.path, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'app', 'rootUri': '../'},
            {'name': 'design', 'rootUri': '../../design'},
            {
              'name': 'cached',
              'rootUri': Uri.directory(cached.path).toString(),
            },
          ],
        }),
      );

    final result = bindLibraryContracts(
      projectRoot: app,
      required: {'design': 1, 'cached': 1},
    );

    expect(result.single.namespace, 'design');
    expect(bound(design, 'design', 1).existsSync(), isTrue);
    expect(bound(cached, 'cached', 1).existsSync(), isFalse);
    expect(
      Directory(p.join(app.path, '.restage', 'library-contracts')).existsSync(),
      isFalse,
    );
  });

  test('refuses a draft that records another version', () {
    draft(app, 'app', 2)
      ..createSync(recursive: true)
      ..writeAsStringSync(contract('app', 3));

    expect(
      () => bindLibraryContracts(projectRoot: app, required: {'app': 2}),
      throwsFormatException,
    );
    expect(bound(app, 'app', 2).existsSync(), isFalse);
  });
}
