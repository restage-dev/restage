import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/render_bundles/render_bundle_archive.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        kBuilderContinuationWidgetName,
        kReservedPreviewConstructorName,
        kReservedPreviewLibraryName,
        kMeasurementPresentationLibraryName,
        renderBundleMaxCapabilityManifestNodes;
import 'package:test/test.dart';

void main() {
  Map<String, Uint8List> validFiles() => <String, Uint8List>{
    'restage_bundle_manifest.json': Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'formatVersion': 1,
          'catalog': <String, Object?>{
            'libraries': <String, Object?>{},
            'widgets': <Object?>[],
          },
        }),
      ),
    ),
    'index.html': Uint8List.fromList(utf8.encode('<!doctype html>')),
  };

  Map<String, Object?> catalog(String library, List<String> widgets) => {
    'libraries': <String, Object?>{
      library: {'capabilityVersion': 23},
    },
    'widgets': <Object?>[
      for (final name in widgets) {'library': library, 'name': name},
    ],
  };

  void expectCatalogRefusal(Map<String, Object?> catalog, String reason) {
    final rejects = throwsA(
      isA<RenderBundleArchiveException>().having(
        (error) => error.reason,
        'reason',
        reason,
      ),
    );
    expect(
      () => createRenderBundleCapabilityManifest(jsonEncode(catalog)),
      rejects,
    );
    expect(
      () => encodeRenderBundleArchive(
        validFiles()
          ..['restage_bundle_manifest.json'] = Uint8List.fromList(
            utf8.encode(jsonEncode({'formatVersion': 1, 'catalog': catalog})),
          ),
      ),
      rejects,
    );
  }

  test('catalog reservation admits ordinary core metadata', () {
    final metadata = catalog('restage.core', ['Text', 'Column']);
    (metadata['libraries']! as Map<String, Object?>)['app'] =
        <String, Object?>{};
    (metadata['widgets']! as List<Object?>).addAll([
      {'library': 'app', 'name': 'Banner'},
      {'library': 'app', 'name': '${kBuilderContinuationWidgetName}User'},
    ]);
    final manifest = createRenderBundleCapabilityManifest(jsonEncode(metadata));
    expect(
      (jsonDecode(utf8.decode(manifest)) as Map<String, Object?>)['catalog'],
      metadata,
    );
    expect(
      encodeRenderBundleArchive(
        validFiles()..['restage_bundle_manifest.json'] = manifest,
      ),
      isNotEmpty,
    );
  });

  test('catalog reservation rejects hidden constructor metadata globally', () {
    for (final library in ['app', 'restage.core']) {
      for (final name in [
        kBuilderContinuationWidgetName,
        kReservedPreviewConstructorName,
      ]) {
        expectCatalogRefusal(
          catalog(library, [name]),
          'catalog_reserved_widget',
        );
      }
    }
  });

  test('catalog reservation retains preview and measurement namespaces', () {
    for (final library in [
      kReservedPreviewLibraryName,
      kMeasurementPresentationLibraryName,
    ]) {
      expectCatalogRefusal(catalog(library, []), 'catalog_reserved_library');
    }
  });

  test('encodes the canonical sorted container byte-identically', () {
    final first = encodeRenderBundleArchive(validFiles());
    final second = encodeRenderBundleArchive(<String, Uint8List>{
      'index.html': validFiles()['index.html']!,
      'restage_bundle_manifest.json':
          validFiles()['restage_bundle_manifest.json']!,
    });

    expect(first, second);
    expect(utf8.decode(first.sublist(0, 8)), 'RBSRAW1\n');
    final manifestLength = ByteData.sublistView(first).getUint32(8);
    final manifest =
        jsonDecode(utf8.decode(first.sublist(12, 12 + manifestLength)))
            as Map<String, dynamic>;
    expect(manifest.keys, <String>['formatVersion', 'files']);
    expect(
      (manifest['files'] as List<dynamic>).map(
        (entry) => (entry as Map<String, dynamic>)['path'],
      ),
      <String>['index.html', 'restage_bundle_manifest.json'],
    );
  });

  test('enforces the 2 MiB capability manifest byte boundary', () {
    const byteLimit = 2 * 1024 * 1024;
    final source = validFiles()[renderBundleCapabilityManifestPath]!;
    Uint8List paddedManifest(int length) => Uint8List(length)
      ..fillRange(0, length, 0x20)
      ..setRange(0, source.length, source);

    expect(
      encodeRenderBundleArchive(
        validFiles()
          ..[renderBundleCapabilityManifestPath] = paddedManifest(byteLimit),
      ),
      isNotEmpty,
    );
    expect(
      () => encodeRenderBundleArchive(
        validFiles()
          ..[renderBundleCapabilityManifestPath] = paddedManifest(
            byteLimit + 1,
          ),
      ),
      throwsA(
        isA<RenderBundleArchiveException>().having(
          (error) => error.reason,
          'reason',
          'capability_manifest_too_large',
        ),
      ),
    );
  });

  test('rejects every unsafe or ambiguous archive path', () {
    for (final path in <String>[
      '',
      '/index.html',
      '../index.html',
      'a/../index.html',
      './index.html',
      'a//index.html',
      r'a\index.html',
      'a\u0000b',
      'é.html',
    ]) {
      expect(
        () => encodeRenderBundleArchive(<String, Uint8List>{
          ...validFiles(),
          path: Uint8List(0),
        }),
        throwsA(isA<RenderBundleArchiveException>()),
        reason: path,
      );
    }
  });

  test('rejects missing outputs, credential fields, and bounded overflows', () {
    expect(
      () => encodeRenderBundleArchive(<String, Uint8List>{
        'index.html': Uint8List(0),
      }),
      throwsA(isA<RenderBundleArchiveException>()),
    );
    final credentialManifest = validFiles()
      ..['restage_bundle_manifest.json'] = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'formatVersion': 1,
            'catalog': <String, Object?>{
              'libraries': <String, Object?>{},
              'widgets': <Object?>[],
              'nested': <String, Object?>{'accessToken': 'no'},
            },
          }),
        ),
      );
    expect(
      () => encodeRenderBundleArchive(credentialManifest),
      throwsA(isA<RenderBundleArchiveException>()),
    );
    expect(
      () => createRenderBundleCapabilityManifest(
        '{"libraries":{},"widgets":[],"nested":{"accessToken":"no"}}',
      ),
      throwsA(isA<RenderBundleArchiveException>()),
    );
    expect(
      () => encodeRenderBundleArchive(
        validFiles()..['extra'] = Uint8List(1),
        limits: const RenderBundleArchiveLimits(maxFiles: 2),
      ),
      throwsA(isA<RenderBundleArchiveException>()),
    );
    expect(
      () => encodeRenderBundleArchive(
        validFiles(),
        limits: const RenderBundleArchiveLimits(maxFileBytes: 8),
      ),
      throwsA(isA<RenderBundleArchiveException>()),
    );
  });

  test('a file past its limit names the file, its size and the limit', () {
    final files = validFiles()
      ..['assets/garden.riv'] = Uint8List(3 * 1024 * 1024 + 512 * 1024);
    expect(
      () => encodeRenderBundleArchive(
        files,
        limits: const RenderBundleArchiveLimits(maxFileBytes: 2 * 1024 * 1024),
      ),
      throwsA(
        isA<RenderBundleArchiveException>()
            .having((e) => e.reason, 'reason', 'file_too_large')
            .having(
              (e) => e.note,
              'note',
              '`assets/garden.riv` is 3.5 MB, over the 2 MB limit for one '
                  'file. Shrink or remove it and push again.',
            ),
      ),
    );
  });

  test('refuses a capability manifest past the node limit', () {
    final manifest = jsonEncode(<String, Object?>{
      'formatVersion': 1,
      'catalog': <String, Object?>{
        'libraries': <String, Object?>{},
        'widgets': <Object?>[],
        'padding': List<int>.filled(renderBundleMaxCapabilityManifestNodes, 0),
      },
    });
    expect(
      () => encodeRenderBundleArchive(
        validFiles()
          ..['restage_bundle_manifest.json'] = Uint8List.fromList(
            utf8.encode(manifest),
          ),
      ),
      throwsA(
        isA<RenderBundleArchiveException>().having(
          (error) => error.reason,
          'reason',
          'capability_manifest_too_complex',
        ),
      ),
    );
  });

  test('collects regular files and rejects symlinks', () async {
    final root = await Directory.systemTemp.createTemp('render_bundle_tree_');
    addTearDown(() => root.delete(recursive: true));
    await File(p.join(root.path, 'index.html')).writeAsString('ok');
    await File(p.join(root.path, 'restage_bundle_manifest.json')).writeAsString(
      jsonEncode(<String, Object?>{
        'formatVersion': 1,
        'catalog': <String, Object?>{
          'libraries': <String, Object?>{},
          'widgets': <Object?>[],
        },
      }),
    );
    final first = await encodeRenderBundleDirectory(root);
    final second = await encodeRenderBundleDirectory(root);
    expect(first, second);

    final link = Link(p.join(root.path, 'linked'));
    try {
      await link.create(p.join(root.path, 'index.html'));
    } on FileSystemException {
      return;
    }
    expect(
      () => encodeRenderBundleDirectory(root),
      throwsA(isA<RenderBundleArchiveException>()),
    );
  });

  test('offline audit rejects external resources and escaping source maps', () {
    expect(
      () => validateOfflineRenderBundleFiles(<String, Uint8List>{
        ...validFiles(),
        'index.html': Uint8List.fromList(
          utf8.encode('<script src="https://example.com/a.js"></script>'),
        ),
      }),
      throwsA(isA<RenderBundleArchiveException>()),
    );
    expect(
      () => validateOfflineRenderBundleFiles(<String, Uint8List>{
        ...validFiles(),
        'style.css': Uint8List.fromList(
          utf8.encode('@import "https://example.com/theme.css";'),
        ),
      }),
      throwsA(isA<RenderBundleArchiveException>()),
    );
    expect(
      () => validateOfflineRenderBundleFiles(<String, Uint8List>{
        ...validFiles(),
        'main.dart.js.map': Uint8List.fromList(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'sources': ['../secret'],
            }),
          ),
        ),
      }),
      throwsA(isA<RenderBundleArchiveException>()),
    );
  });

  test('offline audit admits the loader engine base', () {
    // The loader reads its engine files from a separate immutable origin, so
    // the one absolute URL in `flutter_bootstrap.js` is admitted by design.
    validateOfflineRenderBundleFiles(<String, Uint8List>{
      ...validFiles(),
      'flutter_bootstrap.js': Uint8List.fromList(
        utf8.encode(
          "_flutter.loader.load({config: {canvasKitBaseUrl: "
          "'https://bundles.example.dev/render-bundles/v1/engine/abc/'}});",
        ),
      ),
    });
  });

  test('offline audit rejects every service-worker artifact shape', () {
    for (final path in <String>[
      'flutter_service_worker.js',
      'nested/flutter_service_worker.js',
      'renamed_service_worker.js',
      'nested/serviceWorker.js',
    ]) {
      expect(
        () => validateOfflineRenderBundleFiles(<String, Uint8List>{
          ...validFiles(),
          path: Uint8List(0),
        }),
        throwsA(isA<RenderBundleArchiveException>()),
        reason: path,
      );
    }
  });
}
