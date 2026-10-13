import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/render_host/render_bundle_manifest_loader.dart';

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

final _document = Uri.parse(
  'http://bundle.test/render-bundles/v1/b/42/bootstrap',
);

void main() {
  test('sidecar request is exact, same-origin, and no-store', () async {
    RenderBundleManifestFetchRequest? captured;
    final manifest = await loadRenderBundleManifest(
      documentUri: _document,
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
      'lib/src/render_host/render_bundle_manifest_fetcher_web.dart',
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
    Future<void> expectRejected(RenderBundleManifestFetcher fetch) async {
      await expectLater(
        loadRenderBundleManifest(documentUri: _document, fetch: fetch),
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

  test('a document that is not http or https is refused', () async {
    await expectLater(
      loadRenderBundleManifest(
        documentUri: Uri.parse('file:///bundle/index.html'),
        fetch: (_) async => (
          status: HttpStatus.ok,
          bytes: Uint8List.fromList(utf8.encode(_manifestSource)),
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
