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
    List<Map<String, Map<String, Object?>>?>? plansSeen,
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
            required plans,
            flagRoot,
            configRoot,
            wrapper,
            timeout = surfaceCaptureTimeout,
            cancel,
          }) async {
            captured?.add(entries);
            plansSeen?.add(plans);
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

  group('the build\'s capture plan', () {
    const plan = <String, Object?>{
      'kind': 'object',
      'importUri': 'package:demo/pro_upgrade.dart',
      'name': 'ProUpgradePaywall',
      'parameters': <Object?>[],
    };

    /// Seeds [layout] with a plan beside its manifest and returns the plans
    /// the capturer was handed.
    Future<Map<String, Map<String, Object?>>?> plansFor(
      GeneratedOutputLayout layout, {
      String? fingerprint,
      int version = 1,
    }) async {
      for (final generated in ['.restage', fixtureOutputRoot]) {
        final directory = Directory(p.join(app.path, generated));
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      }
      await seedGeneratedPaywall(app, slug: 'pro_upgrade', layout: layout);
      final index =
          jsonDecode(
                File(
                  p.join(app.path, layout.outputIndexPath),
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      File(
        p.join(app.path, layout.metadataDirectory, surfaceCapturePlanFileName),
      ).writeAsStringSync(
        jsonEncode({
          'version': version,
          'generationFingerprint':
              fingerprint ?? index['generationFingerprint'],
          'surfaces': {imageName: plan},
        }),
      );
      final seen = <Map<String, Map<String, Object?>>?>[];
      final code = await push(
        SurfaceCaptureResult(images: {imageName: png}),
        plansSeen: seen,
      );
      expect(code, 0, reason: err.toString());
      return seen.single;
    }

    for (final layout in [
      GeneratedOutputLayout.generatedDirectory,
      GeneratedOutputLayout.outputRoot,
    ]) {
      test(
        'reaches the capturer from beside the ${layout.name} manifest',
        () async {
          expect(await plansFor(layout), {imageName: plan});
        },
      );
    }

    test(
      'from another build or of another version reaches it as none',
      () async {
        expect(
          await plansFor(
            GeneratedOutputLayout.generatedDirectory,
            fingerprint: 'sha256:${'0' * 64}',
          ),
          isNull,
        );
        expect(
          await plansFor(GeneratedOutputLayout.generatedDirectory, version: 2),
          isNull,
        );
      },
    );
  });

  test('says which fields the image draws with placeholder values', () async {
    final code = await push(
      SurfaceCaptureResult(
        images: {imageName: png},
        placeholders: {
          imageName: ['ProUpgradePaywall.entitled', 'ProUpgradePaywall.title'],
        },
      ),
    );

    expect(code, 0, reason: err.toString());
    expect(
      out.toString(),
      contains('Drawn with placeholder values for `entitled`, `title`.'),
    );
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

  group('the values a paywall computes in the app', () {
    setUp(() async {
      await seedGeneratedPaywall(
        app,
        slug: 'pro_upgrade',
        hostDataContract: SurfaceScreenHostDataSchema({
          '_h0123456789': const SurfaceScreenHostDataScalarShapeV1(
            SurfaceScreenHostDataScalarKind.integer,
          ).withLabel('VColors.of(context).ink'),
        }),
      );
    });

    test('are named when the push recorded them', () async {
      final code = await push(
        SurfaceCaptureResult(
          contexts: {
            imageName: const {
              'light': {'_h0123456789': 1},
              'dark': {'_h0123456789': 2},
            },
          },
        ),
      );

      expect(code, 0, reason: err.toString());
      expect(
        out.toString(),
        contains('Evaluated in the app:\n  VColors.of(context).ink\n'),
      );
    });

    test('say why when an older restage cannot record them', () async {
      final code = await push(
        SurfaceCaptureResult(
          contextSkipped: {
            imageName:
                "the app's restage package is too old to record "
                'them. Update the restage package',
          },
        ),
      );

      expect(code, 0, reason: err.toString());
      expect(
        out.toString(),
        contains(
          "Its app-computed values were not recorded: the app's restage "
          'package is too old to record them. Update the restage package.',
        ),
      );
      expect(out.toString(), isNot(contains('Evaluated in the app')));
    });

    test('are not named when nothing was recorded', () async {
      final code = await push(const SurfaceCaptureResult());

      expect(code, 0, reason: err.toString());
      expect(out.toString(), isNot(contains('Evaluated in the app')));
      expect(out.toString(), isNot(contains('not recorded')));
    });
  });

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
