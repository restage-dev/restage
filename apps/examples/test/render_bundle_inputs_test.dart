import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_example/src/render_bundle_manifest_loader.dart';
import 'package:restage_preview_host/restage_preview_host.dart';

String _sha256(File file) => sha256.convert(file.readAsBytesSync()).toString();

const _manifestSource = '''
{
  "formatVersion": 1,
  "catalog": {
    "libraries": {
      "package:example/widgets.dart": {"capabilityVersion": 1}
    },
    "widgets": [
      {
        "library": "package:example/widgets.dart",
        "name": "PulseBadge",
        "wireId": "pulse_badge"
      }
    ]
  }
}
''';

void main() {
  test('render bundle inputs pin offline loader and exact font authorities',
      () {
    final font = File('assets/fonts/fallback/Roboto-Regular.ttf');
    final license = File('assets/fonts/fallback/Roboto_LICENSE.txt');
    expect(font.lengthSync(), 171676);
    expect(
      _sha256(font),
      '79e851404657dac2106b3d22ad256d47824a9a5765458edb72c9102a45816d95',
    );
    expect(
      _sha256(license),
      'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30',
    );

    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    expect(bootstrap, contains("renderer: 'skwasm'"));
    expect(
      bootstrap,
      contains("fontFallbackBaseUrl: 'assets/fonts/fallback/'"),
    );
    expect(bootstrap, isNot(contains('http://')));
    expect(bootstrap, isNot(contains('https://')));
    expect(bootstrap, isNot(contains('serviceWorker')));
    expect(bootstrap, isNot(contains("'*'")));

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/fonts/fallback/Roboto_LICENSE.txt'));
    expect(pubspec, contains('assets/fonts/fallback/Roboto-Regular.ttf'));
    expect(pubspec, contains('family: Roboto'));
  });

  test('entrypoint loads the sidecar before transport using one small define',
      () {
    final entrypoint = File('lib/main_render_bundle.dart').readAsStringSync();
    expect(entrypoint, contains('RESTAGE_RENDER_BUNDLE_PARENT_ORIGIN'));
    expect(entrypoint, isNot(contains('RESTAGE_BUNDLE_CATALOG_JSON')));
    expect(
      RegExp(r"String\.fromEnvironment\(\s*'([^']+)'", multiLine: true)
          .allMatches(entrypoint)
          .map((match) => match.group(1))
          .toSet(),
      <String>{'RESTAGE_RENDER_BUNDLE_PARENT_ORIGIN'},
    );
    expect(entrypoint, isNot(contains('token')));
    expect(entrypoint, isNot(contains('grant')));
    expect(entrypoint, isNot(contains('cookie')));
    expect(entrypoint, isNot(contains('auth')));
    expect(
      entrypoint.indexOf('await loadRenderBundleManifest('),
      inInclusiveRange(
        0,
        entrypoint.indexOf('createBrowserRenderMessageTransport(') - 1,
      ),
    );
  });

  test('sidecar request is exact, cookie-gated, and no-store', () async {
    RenderBundleManifestFetchRequest? captured;
    final manifest = await loadRenderBundleManifest(
      documentUri: Uri.parse(
        'http://bundle.test/render-bundles/v1/b/42/bootstrap',
      ),
      fetch: (request) async {
        captured = request;
        return (
          status: HttpStatus.ok,
          bytes: Uint8List.fromList(utf8.encode(_manifestSource)),
        );
      },
    );

    expect(
      captured!.uri,
      Uri.parse(
        'http://bundle.test/render-bundles/v1/b/42/'
        'restage_bundle_manifest.json',
      ),
    );
    expect(captured!.method, 'GET');
    expect(captured!.credentials, 'same-origin');
    expect(captured!.cache, 'no-store');
    expect(captured!.mode, 'same-origin');
    expect(captured!.redirect, 'error');
    expect(manifest.toJson(), jsonDecode(_manifestSource));
  });

  test('browser fetch maps the exact credential and cache policy', () {
    final fetcher = File(
      'lib/src/render_bundle_manifest_fetcher_web.dart',
    ).readAsStringSync();
    expect(fetcher, contains('credentials: request.credentials'));
    expect(fetcher, contains('cache: request.cache'));
    expect(fetcher, contains('method: request.method'));
    expect(fetcher, contains('mode: request.mode'));
    expect(fetcher, contains('redirect: request.redirect'));
    expect(fetcher, contains('response.arrayBuffer()'));
  });

  test('load, status, UTF-8, JSON, and manifest failures fail closed',
      () async {
    Future<void> expectRejected(
      RenderBundleManifestFetcher fetch,
    ) async {
      await expectLater(
        loadRenderBundleManifest(
          documentUri: Uri.parse(
            'http://bundle.test/render-bundles/v1/b/42/bootstrap',
          ),
          fetch: fetch,
        ),
        throwsA(isA<FormatException>()),
      );
    }

    await expectRejected((_) async => throw StateError('network failed'));
    await expectRejected(
      (_) async => (
        status: HttpStatus.notFound,
        bytes: Uint8List.fromList(utf8.encode(_manifestSource)),
      ),
    );
    await expectRejected(
      (_) async => (status: HttpStatus.ok, bytes: Uint8List.fromList([0xff])),
    );
    await expectRejected(
      (_) async => (
        status: HttpStatus.ok,
        bytes: Uint8List.fromList(utf8.encode('{not json')),
      ),
    );
    await expectRejected(
      (_) async => (
        status: HttpStatus.ok,
        bytes: Uint8List.fromList(
          utf8.encode(
            '{"formatVersion":2,"catalog":{"libraries":{},"widgets":[]}}',
          ),
        ),
      ),
    );
  });

  test('generated catalog remains valid and credential-free as a manifest', () {
    final source =
        File('lib/src/widget_catalog/catalog.json').readAsStringSync();
    final manifest = RenderBundleManifest.fromCatalogJson(source);
    final catalog = jsonDecode(source) as Map<String, Object?>;

    expect(manifest.catalog, catalog);
    expect(
      (manifest.catalog['widgets']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .any((widget) => widget['name'] == 'PulseBadge'),
      isTrue,
    );
  });
}
