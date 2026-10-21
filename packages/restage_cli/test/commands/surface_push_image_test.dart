import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/byte_data_wire.dart';
import 'package:restage_cli/src/commands/surface_push_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/render_bundles/surface_capture.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';
import '../_helpers/test_fixtures.dart';

void main() {
  late Directory app;
  late Directory home;
  late FileCredentialStore store;
  late StringBuffer out;
  late StringBuffer err;

  final png = Uint8List.fromList(const [137, 80, 78, 71, 1, 2, 3]);
  final imageName = surfaceImageName(
    surfaceType: 'paywall',
    slug: 'pro_upgrade',
  );

  late List<Map<String, Object?>> published;

  http.Client backend() => mockHttpClient((request) {
    final body = jsonDecode(request.body) as Map<String, Object?>;
    if (body['method'] == 'publishPublication') {
      published.add(body);
    }
    return publishSucceeded('pro_upgrade', storedRevision: 7);
  });

  Future<int?> push(
    SurfaceCaptureResult result, {
    List<List<SurfacePublicationManifestEntry>>? captured,
    http.Client? httpClient,
    Future<SurfaceCaptureResult> Function(Future<void>? cancel)? render,
  }) {
    final command = SurfacePushCommand(
      stdout: out,
      stderr: err,
      interactive: const NonInteractive(),
      credentialStore: store,
      httpClient: httpClient ?? backend(),
      imageCapturer:
          ({
            required projectRoot,
            required entries,
            flagRoot,
            configRoot,
            wrapper,
            timeout = surfaceCaptureTimeout,
            cancel,
          }) async {
            captured?.add(entries);
            if (render != null) return render(cancel);
            return result;
          },
    );
    return (CommandRunner<int>(
      'restage',
      '',
    )..addCommand(command)).run(['push', 'pro_upgrade', '-C', app.path]);
  }

  setUp(() async {
    app = await Directory.systemTemp.createTemp('surface_push_image_');
    home = await Directory.systemTemp.createTemp('surface_push_image_home_');
    store = FileCredentialStore(p.join(home.path, 'credentials'));
    await seedCredential(store);
    out = StringBuffer();
    err = StringBuffer();
    published = [];
    File(p.join(app.path, 'restage_config.yaml')).writeAsStringSync(
      'project: demo\napp: mobile\ndefaultEnvironment: staging\n',
    );
    await seedGeneratedPaywall(
      app,
      slug: 'pro_upgrade',
      requiredLibraries: const [
        LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
      ],
    );
  });

  tearDown(() {
    app.deleteSync(recursive: true);
    home.deleteSync(recursive: true);
  });

  test('each pushed surface carries its image in the push', () async {
    final captured = <List<SurfacePublicationManifestEntry>>[];
    final code = await push(
      SurfaceCaptureResult(images: {imageName: png}),
      captured: captured,
    );

    expect(code, 0, reason: err.toString());
    expect(captured.single.single.publication.slug, 'pro_upgrade');
    expect(
      decodeByteDataWire(
        published.single['pushImage'],
        malformed: FormatException.new,
      ),
      png,
    );
    expect(err.toString(), isNot(contains('image')));
  });

  test('a capture that fails warns once and pushes without images', () async {
    final code = await push(
      const SurfaceCaptureResult(failure: 'Flutter could not be started'),
    );

    expect(code, 0, reason: err.toString());
    expect(out.toString(), contains('Pushed pro_upgrade'));
    expect(
      'Pushing without surface images'.allMatches(err.toString()),
      hasLength(1),
    );
    expect(
      err.toString(),
      contains('Pushing without surface images: Flutter could not be started.'),
    );
    expect(published.single.containsKey('pushImage'), isFalse);
  });

  test('says why a surface has no image', () async {
    final code = await push(
      SurfaceCaptureResult(
        skipped: {imageName: 'its widget threw while rendering'},
      ),
    );

    expect(code, 0, reason: err.toString());
    expect(
      err.toString(),
      contains(
        'Pushing pro_upgrade without an image: its widget threw while '
        'rendering.',
      ),
    );
    expect(published.single.containsKey('pushImage'), isFalse);
  });

  test(
    'a surface drawn with built-in widgets is pushed without an image',
    () async {
      await seedGeneratedPaywall(app, slug: 'pro_upgrade');
      final captured = <List<SurfacePublicationManifestEntry>>[];
      final code = await push(
        SurfaceCaptureResult(images: {imageName: png}),
        captured: captured,
      );

      expect(code, 0, reason: err.toString());
      expect(captured.single, isEmpty);
      expect(published.single.containsKey('pushImage'), isFalse);
      expect(err.toString(), isNot(contains('image')));
    },
  );

  test('a push that stops early stops its render', () async {
    var stopped = false;
    final code = await push(
      const SurfaceCaptureResult(),
      httpClient: mockHttpClient(
        (request) => throw const SocketException('down'),
        withDefaultTargetDiscovery: false,
      ),
      render: (cancel) async {
        await cancel;
        stopped = true;
        return const SurfaceCaptureResult(failure: 'the push stopped first');
      },
    );

    expect(code, isNot(0));
    expect(stopped, isTrue);
  });
}
