import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart' show decodeByteDataWire;
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_publication_api.dart';
import 'package:restage_cli/src/commands/publication_upload.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('measured_push_state_');
  });
  tearDown(() => root.delete(recursive: true));

  test('a measured push carries the editor state too', () async {
    await seedMeasurementPaywall(root);
    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: root,
    );
    final assembled = await SurfacePublicationAssembler().assemble(
      loaded: loaded,
      entry: loaded.manifest.publications.single,
    );
    expect(assembled.measurementUpload, isNotNull);

    final sent = <Map<String, dynamic>>[];
    final api = SurfacePublicationApi(
      RestageApi(
        endpoint: Uri.parse('http://localhost:8080/'),
        httpClient: MockClient((request) async {
          sent.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{}', 500);
        }),
        credential: const Credential(
          endpoint: 'http://localhost:8080/',
          kind: CredentialKind.authKey,
          authToken: 'kid:secret',
        ),
      ),
    );
    final state = Uint8List.fromList(utf8.encode('{"meta":{}}'));

    await expectLater(
      publishAssembledSurfacePublication(
        api: api,
        assembled: assembled,
        packageRoot: root,
        project: 'demo',
        app: 'mobile',
        environment: 'staging',
        editorStateOf: (_) async => state,
      ),
      throwsA(anything),
    );

    expect(sent.single['method'], 'publishMeasurementBound');
    expect(
      decodeByteDataWire(
        sent.single['editorState'],
        malformed: FormatException.new,
      ),
      state,
    );
  });
}
