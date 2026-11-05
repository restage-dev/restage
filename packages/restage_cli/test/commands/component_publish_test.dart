import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/byte_data_wire.dart';
import 'package:restage_cli/src/api/component_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/commands/publication_upload.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/render_bundles/generated_widget_catalog.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart'
    show encodeLibraryBlob, parseLibraryFile;
import 'package:test/test.dart';

Uint8List _blob(String text) => encodeLibraryBlob(parseLibraryFile(text));

// The project's components as the service holds them.
final class _Service {
  final components = <String, ({int id, List<Uint8List> versions})>{};
  final calls = <String>[];

  http.Client get client => MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final method = body['method'] as String;
    final params = body['params'] as Map<String, dynamic>? ?? body;
    calls.add(method);
    Map<String, Object?> summary(String name) => {
      'id': components[name]!.id,
      'name': name,
      'scope': 'project',
      'latestVersion': components[name]!.versions.length,
      'updatedAt': '2026-11-03T00:00:00.000Z',
      'usedBy': 0,
      'onOlderVersion': 0,
    };
    Uint8List payload() =>
        decodeByteDataWire(params['payload'], malformed: FormatException.new);
    String nameOf(int id) =>
        components.entries.firstWhere((e) => e.value.id == id).key;
    final Object? result = switch (method) {
      'list' => [for (final name in components.keys) summary(name)],
      'create' => () {
        final name = params['name'] as String;
        components[name] = (id: components.length + 1, versions: [payload()]);
        return summary(name);
      }(),
      'loadVersion' => () {
        final name = nameOf(params['componentId'] as int);
        final version = params['version'] as int;
        return {
          'version': version,
          'createdAt': '2026-11-03T00:00:00.000Z',
          'payload': encodeByteDataWire(
            components[name]!.versions[version - 1],
          ),
        };
      }(),
      'pushVersion' => () {
        final name = nameOf(params['componentId'] as int);
        components[name]!.versions.add(payload());
        return summary(name);
      }(),
      _ => throw StateError(method),
    };
    return http.Response(jsonEncode(result), 200);
  });
}

void main() {
  late Directory root;
  late _Service service;
  late ComponentTarget target;

  void handOff(Uint8List payload) {
    final file = File(generatedCompilerHandoffPath(root, 'demo_app'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'surfaceComponents': {
          'paywall/offer': [
            {
              'name': 'demo_app.ui.Pill',
              'declaration': 'Pill',
              'payload': base64Encode(payload),
              'fingerprint': 'f1',
              'parts': <String>[],
            },
          ],
        },
      }),
    );
  }

  Future<Map<String, Map<String, Object?>>> push() =>
      publishDeliveredComponents(
        components: target,
        project: 'demo',
        packageRoot: root,
        surface: 'paywall/offer',
      );

  setUp(() {
    root = Directory.systemTemp.createTempSync('component-publish-');
    File(
      p.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: demo_app\n');
    service = _Service();
    target = (
      api: ComponentApi(
        RestageApi(
          endpoint: Uri.parse('http://localhost:8080/'),
          httpClient: service.client,
          credential: const Credential(
            endpoint: 'http://localhost:8080/',
            kind: CredentialKind.authKey,
            authToken: 'kid:secret',
          ),
        ),
      ),
      organizationId: 1,
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  group('a push publishes the shared components its design delivers', () {
    test(
      'creates, reuses an unchanged one, and appends a changed one',
      () async {
        final first = Uint8List.fromList([1, 2, 3]);
        handOff(first);
        expect((await push())['Pill'], {
          'id': 1,
          'version': 1,
          'fingerprint': 'f1',
        });
        expect(service.calls, ['list', 'create']);

        service.calls.clear();
        expect((await push())['Pill']!['version'], 1);
        expect(service.calls, ['list', 'loadVersion']);

        service.calls.clear();
        handOff(Uint8List.fromList([4, 5]));
        expect((await push())['Pill']!['version'], 2);
        expect(service.calls, ['list', 'loadVersion', 'pushVersion']);
        expect(service.components['demo_app.ui.Pill']!.versions, hasLength(2));
      },
    );

    test('pins on the screen that declares the widget', () async {
      final pins = {
        'Pill': <String, Object?>{'id': 1, 'version': 1, 'fingerprint': 'f1'},
      };
      final screen = _blob('''
import restage.core;
widget Pill = Text(text: args.label);
widget root = Pill(label: "Pro");
''');
      final other = _blob('''
import restage.core;
widget root = Text(text: "plain");
''');
      Future<SurfaceEditorState> stateOf(SurfacePayload payload) async =>
          SurfaceEditorState.decode(
            (await pushedEditorState(
              payload: payload,
              packageRoot: root,
              pins: pins,
            ))!,
          );

      final single = await stateOf(
        BlobSurfacePayload(minClient: 2, blob: screen),
      );
      expect(single.meta, {'components': pins});

      ScreenArtifact artifact(String path, Uint8List blob) => ScreenArtifact(
        path: path,
        version: 1,
        schemaVersion: 1,
        minClient: 2,
        contentHash: FlowContentHash.compute(blob),
      );
      final flow = await stateOf(
        FlowSurfacePayload(
          flowDocument: FlowDocument(
            flow: 'tour',
            version: 1,
            schemaVersion: 1,
            minClient: 2,
            initial: 'welcome',
            screenArtifacts: {
              'welcome': artifact('welcome.rfw', other),
              'offer': artifact('offer.rfw', screen),
            },
            states: {
              'welcome': ScreenFlowState(
                screen: 'welcome',
                on: {'next': FlowTransition.goto('offer')},
              ),
              'offer': const ScreenFlowState(screen: 'offer', on: {}),
            },
          ),
          screenBlobs: {'welcome': other, 'offer': screen},
        ),
      );
      expect(flow.meta, isEmpty);
      expect(flow.screens, {
        'offer': {'components': pins},
      });
    });
  });
}
