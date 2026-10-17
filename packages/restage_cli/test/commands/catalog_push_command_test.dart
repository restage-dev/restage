import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/render_bundles/generated_widget_catalog.dart';
import 'package:path/path.dart' as p;
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

const _app = WidgetLibrary.custom('demo.widgets');
const _kit = WidgetLibrary.custom('kit.widgets');

String _catalog(Map<WidgetLibrary, String> widgets) => encodeCatalog(
  Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      for (final library in widgets.keys)
        library: const LibraryInfo(version: '1.0.0'),
    },
    widgets: [
      for (final MapEntry(key: library, value: name) in widgets.entries)
        WidgetEntry(
          wireId: WireId('w0001'),
          name: name,
          library: library,
          category: WidgetCategory.layout,
          description: '$name fixture.',
          flutterType: 'package:fixture/fixture.dart#$name',
          childrenSlot: ChildrenSlot.none,
          properties: const [],
        ),
    ],
  ),
);

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('catalog_push_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    stdout = StringBuffer();
    stderr = StringBuffer();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> seedFile(String path, String contents) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  /// Seeds the generator's merged catalog, built-ins included.
  Future<void> seedMerged(Map<WidgetLibrary, String> custom) async {
    await File(
      p.join(tempDir.path, 'pubspec.yaml'),
    ).writeAsString('name: demo_app\n');
    await seedFile(
      generatedRenderCatalogPath(tempDir, 'demo_app'),
      _catalog({WidgetLibrary.core: 'CoreBox', ...custom}),
    );
  }

  Future<void> seedCatalog(String catalogJson) async {
    final file = File(
      p.join(
        tempDir.path,
        '.restage',
        'build',
        'widget_catalog',
        'catalog.json',
      ),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(catalogJson);
  }

  group('restage catalog push', () {
    test(
      'uploads the widget libraries of the app and its dependencies',
      () async {
        await seedCredential(store);
        await seedRestageConfig(tempDir, 'demo', 'mobile');
        await seedCatalog(_catalog({_app: 'AppBadge'}));
        await seedMerged({_app: 'AppBadge', _kit: 'KitBadge'});
        final catalogJson = _catalog({_app: 'AppBadge', _kit: 'KitBadge'});

        var pushCalls = 0;
        final client = scriptedHttpClient([
          (req) {
            pushCalls++;
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['method'], 'push');
            expect(body['projectSlug'], 'demo');
            expect(body['appSlug'], 'mobile');
            expect(body['catalogJson'], catalogJson);
            expect(
              (body['catalogJson'] as String),
              isNot(startsWith("decode('")),
            );
            return http.Response('4', 200);
          },
        ]);

        final exitCode = await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: client,
        ).run(['catalog', 'push', '-C', tempDir.path]);

        expect(exitCode, 0);
        expect(pushCalls, 1);
        expect(stdout.toString(), contains('version 4'));
        expect(stderr.toString(), isEmpty);
      },
    );

    test(
      'uploads dependency widgets for an app with none of its own',
      () async {
        await seedCredential(store);
        await seedRestageConfig(tempDir, 'demo', 'mobile');
        await seedMerged({_kit: 'KitBadge'});

        String? uploaded;
        final exitCode = await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: scriptedHttpClient([
            (req) {
              uploaded =
                  (jsonDecode(req.body) as Map<String, dynamic>)['catalogJson']
                      as String;
              return http.Response('2', 200);
            },
          ]),
        ).run(['catalog', 'push', '-C', tempDir.path]);

        expect(exitCode, 0, reason: stderr.toString());
        expect(uploaded, _catalog({_kit: 'KitBadge'}));
        expect(stdout.toString(), contains('as version 2'));
        expect(stdout.toString(), contains("dashboard editor's palette"));
      },
    );

    test('a generator without the merged catalog refuses', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');
      await seedCatalog(_catalog({_app: 'AppBadge'}));

      var calls = 0;
      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: scriptedHttpClient([
          (req) {
            calls++;
            return http.Response('1', 200);
          },
        ]),
      ).run(['catalog', 'push', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(calls, 0);
      expect(stderr.toString(), '$renderCatalogMissingMessage\n');
    });

    test(
      'missing catalog exits 0 with a friendly note and no push call',
      () async {
        await seedCredential(store);
        await seedRestageConfig(tempDir, 'demo', 'mobile');

        var calls = 0;
        final client = scriptedHttpClient([
          (req) {
            calls++;
            return http.Response('1', 200);
          },
        ]);

        final exitCode = await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: client,
        ).run(['catalog', 'push', '-C', tempDir.path]);

        expect(exitCode, 0);
        expect(calls, 0);
        expect(stdout.toString().toLowerCase(), contains('nothing to push'));
        expect(stdout.toString(), contains('dart run build_runner build'));
        expect(stdout.toString(), contains('Devices never read it'));
        expect(stderr.toString(), isEmpty);
      },
    );

    test('invalid catalog typed error prints a clear message', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');
      await seedMerged({_app: 'AppBadge'});

      final client = scriptedHttpClient([
        (req) => http.Response(
          jsonEncode({
            'className': 'CatalogInvalidException',
            'data': {
              '__className__': 'CatalogInvalidException',
              'message': 'missing widgets',
            },
          }),
          400,
        ),
      ]);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['catalog', 'push', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('missing widgets'));
      expect(stderr.toString().toLowerCase(), contains('catalog'));
    });

    test('oversized catalog typed error prints a clear message', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');
      await seedMerged({_app: 'AppBadge'});

      final client = scriptedHttpClient([
        (req) => http.Response(
          jsonEncode({
            'className': 'CatalogTooLargeException',
            'data': {
              '__className__': 'CatalogTooLargeException',
              'maxBytes': 524288,
              'actualBytes': 524289,
            },
          }),
          400,
        ),
      ]);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['catalog', 'push', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(stderr.toString().toLowerCase(), contains('too large'));
      expect(stderr.toString(), contains('524288'));
      expect(stderr.toString(), contains('524289'));
    });
  });
}
