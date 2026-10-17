import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:test/test.dart';

import '../_helpers/component_fixtures.dart';
import '../_helpers/test_fixtures.dart';

Map<String, Object?> _component(
  int id,
  String name, {
  String scope = 'project',
  int latest = 1,
  int usedBy = 0,
  int older = 0,
  bool? inAppBuild = true,
}) => {
  'id': id,
  'name': name,
  'scope': scope,
  'latestVersion': latest,
  'updatedAt': '2026-10-14T00:00:00.000Z',
  'usedBy': usedBy,
  'onOlderVersion': older,
  'inAppBuild': inAppBuild,
  '__className__': 'ComponentSummaryView',
};

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late StringBuffer out;
  late StringBuffer err;
  late List<Map<String, dynamic>> calls;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('components_cmd_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    await seedCredential(store);
    await seedRestageConfig(
      tempDir,
      'alpha',
      'mobile',
      defaultEnvironment: 'staging',
    );
    out = StringBuffer();
    err = StringBuffer();
    calls = [];
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<int> run(List<String> args, List<Map<String, Object?>> components) =>
      RestageCli(
        stdout: out,
        stderr: err,
        credentialStore: store,
        httpClient: mockHttpClient((request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['method'] == 'listProjects') {
            return http.Response(
              jsonEncode([
                {'slug': 'alpha', 'name': 'Alpha'},
              ]),
              200,
            );
          }
          calls.add(body);
          if (body['method'] == 'list') {
            return http.Response(jsonEncode(components), 200);
          }
          return http.Response(
            jsonEncode({
              'componentId': body['componentId'],
              'version': body['version'],
              'payload': componentPayloadWire(),
              'createdAt': '2026-10-1${body['version']}T00:00:00.000Z',
            }),
            200,
          );
        }),
      ).run([...args, '-C', tempDir.path]);

  test(
    'components list shows scope, version, usage and the build note',
    () async {
      final code = await run(
        ['components', 'list'],
        [
          _component(1, 'badge', usedBy: 3, older: 1),
          _component(2, 'hero', scope: 'organization', latest: 2, usedBy: 1),
          _component(3, 'chip', inAppBuild: false),
        ],
      );

      expect(code, 0, reason: err.toString());
      expect(out.toString(), '''
NAME\tSCOPE\tVERSION\tUSAGE\tNOTE
badge\tproject\t1\t3 surfaces · 1 on older versions\t-
hero\torganization\t2\t1 surface\t-
chip\tproject\t1\t0 surfaces\tNot in any app build
''');
      final call = calls.single;
      expect(call['projectSlug'], 'alpha');
      expect(call['organizationId'], 7);
    },
  );

  test(
    'components list --json carries the numbers and no display text',
    () async {
      final code = await run(
        ['components', 'list', '--json'],
        [_component(1, 'badge', usedBy: 3, older: 1, inAppBuild: false)],
      );

      expect(code, 0, reason: err.toString());
      final rows = jsonDecode(out.toString()) as List<dynamic>;
      final row = rows.single as Map<String, dynamic>;
      expect(row['usedBy'], 3);
      expect(row['onOlderVersion'], 1);
      expect(row['inAppBuild'], false);
      expect(row.containsKey('usage'), isFalse);
      expect(row.containsKey('note'), isFalse);
    },
  );

  test('components list says when there are none', () async {
    final code = await run(['components', 'list'], []);

    expect(code, 0, reason: err.toString());
    expect(out.toString(), 'No shared components.\n');
  });

  test('components show reads the newest version once', () async {
    final code = await run(
      ['components', 'show', 'badge'],
      [_component(1, 'badge', latest: 2, usedBy: 2, older: 1)],
    );

    expect(code, 0, reason: err.toString());
    final text = out.toString();
    expect(text, contains('name: badge'));
    expect(text, contains('created: 2026-10-12T00:00:00.000Z'));
    expect(text, contains('entry: Container'));
    expect(text, contains('declarations: main, inner'));
    expect(text, contains('imports: restage.core'));
    expect(text, contains('slot main.label: Hello'));
    expect(
      calls.where((c) => c['method'] == 'loadVersion').map((c) => c['version']),
      [2],
    );
  });

  test('components show names a component that is not there', () async {
    final code = await run(['components', 'show', 'ghost'], []);

    expect(code, isNot(0));
    expect(err.toString(), contains('No shared component is named ghost.'));
  });
}
