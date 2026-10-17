import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/api.dart' show decodeByteDataWire;
import 'package:restage_cli/src/commands/publication_upload.dart';
import 'package:restage_cli/src/commands/surface_push_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/render_bundles/generated_widget_catalog.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';
import '../_helpers/test_fixtures.dart';

const _acme = WidgetLibrary.custom('acme.widgets');

Catalog _fixture(Map<WidgetLibrary, String> widgets) => Catalog(
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
);

/// The app's widget libraries, as the editor state carries them.
final Map<String, Object?> _catalog =
    jsonDecode(encodeCatalog(_fixture({_acme: 'AcmeBadge'})))
        as Map<String, Object?>;

/// The merged catalog the generator writes, built-ins included.
final String _merged = encodeCatalog(
  _fixture({WidgetLibrary.core: 'CoreBox', _acme: 'AcmeBadge'}),
);

void main() {
  late Directory app;
  late Directory home;
  late FileCredentialStore store;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() async {
    app = await Directory.systemTemp.createTemp('surface_push_editor_state_');
    home = await Directory.systemTemp.createTemp('surface_push_es_home_');
    store = FileCredentialStore(p.join(home.path, 'credentials'));
    await seedCredential(store);
    out = StringBuffer();
    err = StringBuffer();
    File(p.join(app.path, 'restage_config.yaml')).writeAsStringSync(
      'project: demo\napp: mobile\ndefaultEnvironment: staging\n',
    );
  });

  tearDown(() {
    app.deleteSync(recursive: true);
    home.deleteSync(recursive: true);
  });

  void writeCatalog() {
    final file = File(generatedWidgetCatalogPath(app, fixturePackageName));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(_catalog));
    File(
      generatedRenderCatalogPath(app, fixturePackageName),
    ).writeAsStringSync(_merged);
  }

  Future<List<Map<String, dynamic>>> push() async {
    final published = <Map<String, dynamic>>[];
    final client = mockHttpClient((request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['method'] == 'publishPublication') published.add(body);
      return publishSucceeded('pro_upgrade');
    });
    final code =
        await (CommandRunner<int>('restage', '')..addCommand(
              SurfacePushCommand(
                stdout: out,
                stderr: err,
                interactive: const NonInteractive(),
                credentialStore: store,
                httpClient: client,
              ),
            ))
            .run(['push', 'pro_upgrade', '-C', app.path]);
    expect(code, 0, reason: err.toString());
    return published;
  }

  test('a surface using app widgets sends the generated catalog as editor '
      'state', () async {
    await seedGeneratedPaywall(
      app,
      requiredLibraries: const [
        LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
      ],
    );
    writeCatalog();

    final published = await push();

    final state = SurfaceEditorState.decode(
      decodeByteDataWire(
        published.single['editorState'],
        malformed: FormatException.new,
      ),
    );
    expect(state.catalog, _catalog);
    expect(state.meta, isEmpty);
  });

  test('a surface using only built-in widgets sends none', () async {
    await seedGeneratedPaywall(app);
    writeCatalog();

    final published = await push();

    expect(published.single, isNot(contains('editorState')));
  });

  test('a flow using app widgets sends the generated catalog too', () async {
    final screen = ordinaryRfwBlob();
    final payload = FlowSurfacePayload(
      flowDocument: FlowDocument(
        flow: 'tour',
        version: 1,
        schemaVersion: 1,
        minClient: 2,
        initial: 'welcome',
        screenArtifacts: {
          'welcome': ScreenArtifact(
            path: 'welcome.rfw',
            version: 1,
            schemaVersion: 1,
            minClient: 2,
            contentHash: FlowContentHash.compute(screen),
          ),
        },
        states: const {'welcome': ScreenFlowState(screen: 'welcome', on: {})},
      ),
      screenBlobs: {'welcome': screen},
      requiredLibraries: const [
        LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
      ],
    );
    final bytes = await pushedEditorState(
      payload: payload,
      packageRoot: app,
      widgetCatalog:
          ({
            required projectRoot,
            required generate,
            flutterExecutable,
          }) async => GeneratedWidgetCatalog(
            json: jsonEncode(_catalog),
            renderJson: _merged,
            registersWidgets: true,
          ),
    );
    final state = SurfaceEditorState.decode(bytes!);
    expect(state.catalog, _catalog);
    expect(state.screens, isNull);
  });

  test('no generated catalog means no editor state', () async {
    final payload = BlobSurfacePayload(
      minClient: 2,
      blob: ordinaryRfwBlob(),
      requiredLibraries: const [
        LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
      ],
    );
    expect(
      await pushedEditorState(
        payload: payload,
        packageRoot: app,
        widgetCatalog:
            ({required projectRoot, required generate, flutterExecutable}) =>
                throw const GeneratedCatalogException('catalog_missing'),
      ),
      isNull,
    );
  });
}
