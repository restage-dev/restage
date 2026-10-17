import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/render_bundles/generated_widget_catalog.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late StringBuffer out;
  late StringBuffer err;
  late List<Map<String, dynamic>> calls;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('organization_flags_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    await seedCredential(store);
    out = StringBuffer();
    err = StringBuffer();
    calls = [];
  });

  tearDown(() => tempDir.delete(recursive: true));

  Future<int> run(List<String> args, String response) => RestageCli(
    stdout: out,
    stderr: err,
    credentialStore: store,
    httpClient: mockHttpClient((request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      calls.add(body);
      return http.Response(response, 200);
    }),
  ).run([...args, '-C', tempDir.path]);

  test('audit reads take --organization', () async {
    final code = await run(['audit', 'log', '--organization', 'restage'], '[]');

    expect(code, 0, reason: err.toString());
    expect(calls.last['method'], 'listAuditLog');
    expect(calls.last['organizationId'], 7);
  });

  test('an unknown --organization is refused', () async {
    final code = await run([
      'audit',
      'verdict',
      '--organization',
      'nope',
    ], '[]');

    expect(code, 1);
    expect(err.toString(), contains('nope'));
  });

  test('catalog push takes --organization', () async {
    await File(
      p.join(tempDir.path, 'pubspec.yaml'),
    ).writeAsString('name: demo_app\n');
    const library = WidgetLibrary.custom('demo.widgets');
    final merged = File(generatedRenderCatalogPath(tempDir, 'demo_app'));
    await merged.create(recursive: true);
    await merged.writeAsString(
      encodeCatalog(
        Catalog(
          schemaVersion: kSupportedSchemaVersion,
          generatedAt: '1970-01-01T00:00:00Z',
          libraries: {library: const LibraryInfo(version: '1.0.0')},
          widgets: [
            WidgetEntry(
              wireId: WireId('w0001'),
              name: 'DemoBadge',
              library: library,
              category: WidgetCategory.layout,
              description: 'A badge.',
              flutterType: 'package:demo_app/badge.dart#DemoBadge',
              childrenSlot: ChildrenSlot.none,
              properties: const [],
            ),
          ],
        ),
      ),
    );

    final code = await run([
      'catalog',
      'push',
      '--project',
      'alpha',
      '--app',
      'mobile',
      '--organization',
      'restage',
    ], '3');

    expect(code, 0, reason: err.toString());
    expect(calls.last['organizationId'], 7);
    expect(out.toString(), contains('version 3'));
  });
}
