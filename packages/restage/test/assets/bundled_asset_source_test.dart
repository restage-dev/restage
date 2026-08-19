import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart'
    show AssetBundle, ByteData, StandardMessageCodec;
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/assets/bundled_asset_source.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  test('serves a logical path out of a packaged bundle', () async {
    final source = BundledAssetSource(
      _Bundle({
        ..._manifest(['assets/restage/bundles/lib/a.rsbundle']),
        'assets/restage/bundles/lib/a.rsbundle': _bundle({
          'assets/paywalls/pulse.rfw': 'pulse-blob',
        }),
      }),
    );

    expect(await source.loadString('assets/paywalls/pulse.rfw'), 'pulse-blob');
  });

  test('prefers a loose asset over the packaged copy', () async {
    // An application may hand-author an artifact at a logical path; packaging
    // must not shadow it.
    final source = BundledAssetSource(
      _Bundle({
        ..._manifest(['assets/restage/bundles/lib/a.rsbundle']),
        'assets/paywalls/pulse.rfw': _utf8('loose'),
        'assets/restage/bundles/lib/a.rsbundle': _bundle({
          'assets/paywalls/pulse.rfw': 'packaged',
        }),
      }),
    );

    expect(await source.loadString('assets/paywalls/pulse.rfw'), 'loose');
  });

  test('reports the delegate failure when nothing carries the path', () async {
    final source = BundledAssetSource(
      _Bundle({
        ..._manifest(['assets/restage/bundles/lib/a.rsbundle']),
        'assets/restage/bundles/lib/a.rsbundle': _bundle({
          'assets/paywalls/pulse.rfw': 'pulse-blob',
        }),
      }),
    );

    await expectLater(
      source.load('assets/paywalls/absent.rfw'),
      throwsA(isA<FlutterError>()),
    );
  });

  test('passes through when the application packages no bundles', () async {
    final source = BundledAssetSource(
      _Bundle({
        ..._manifest(const <String>[]),
        'assets/paywalls/pulse.rfw': _utf8('loose'),
      }),
    );

    expect(await source.loadString('assets/paywalls/pulse.rfw'), 'loose');
    await expectLater(
      source.load('assets/paywalls/absent.rfw'),
      throwsA(isA<FlutterError>()),
    );
  });

  test('passes through when there is no asset manifest at all', () async {
    final source = BundledAssetSource(
      _Bundle({'assets/paywalls/pulse.rfw': _utf8('loose')}),
    );

    expect(await source.loadString('assets/paywalls/pulse.rfw'), 'loose');
  });

  test('indexes only as many bundles as it takes to find the path', () async {
    final delegate = _Bundle({
      ..._manifest([
        'assets/restage/bundles/lib/a.rsbundle',
        'assets/restage/bundles/lib/b.rsbundle',
        'assets/restage/bundles/lib/c.rsbundle',
      ]),
      'assets/restage/bundles/lib/a.rsbundle': _bundle({'assets/x/a.rfw': 'a'}),
      'assets/restage/bundles/lib/b.rsbundle': _bundle({'assets/x/b.rfw': 'b'}),
      'assets/restage/bundles/lib/c.rsbundle': _bundle({'assets/x/c.rfw': 'c'}),
    });
    final source = BundledAssetSource(delegate);

    expect(await source.loadString('assets/x/b.rfw'), 'b');
    expect(
      delegate.loaded,
      isNot(contains('assets/restage/bundles/lib/c.rsbundle')),
      reason: 'the search stops at the bundle that answers',
    );

    // A later read is answered from the index rather than by re-reading any
    // container. (The loose attempt still happens first, so the logical path
    // itself is expected here — no `.rsbundle` should be.)
    delegate.loaded.clear();
    expect(await source.loadString('assets/x/a.rfw'), 'a');
    expect(
      delegate.loaded.where((key) => key.endsWith('.rsbundle')),
      isEmpty,
      reason: 'already indexed',
    );
  });

  test('refuses to answer "absent" while a bundle cannot be read', () async {
    // Corruption must never be reported as "this artifact was not packaged" —
    // that sends a reader hunting a build problem that does not exist.
    final source = BundledAssetSource(
      _Bundle({
        ..._manifest(['assets/restage/bundles/lib/broken.rsbundle']),
        'assets/restage/bundles/lib/broken.rsbundle':
            Uint8List.fromList(const [1, 2, 3, 4]),
      }),
    );

    await expectLater(
      source.load('assets/paywalls/pulse.rfw'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains('could not be read'), contains('broken.rsbundle')),
        ),
      ),
    );
  });

  test('a readable bundle still answers despite an unreadable sibling',
      () async {
    final source = BundledAssetSource(
      _Bundle({
        ..._manifest([
          'assets/restage/bundles/lib/a_broken.rsbundle',
          'assets/restage/bundles/lib/b_good.rsbundle',
        ]),
        'assets/restage/bundles/lib/a_broken.rsbundle':
            Uint8List.fromList(const [1, 2, 3, 4]),
        'assets/restage/bundles/lib/b_good.rsbundle':
            _bundle({'assets/x/found.rfw': 'found'}),
      }),
    );

    expect(await source.loadString('assets/x/found.rfw'), 'found');
  });

  test('rejects two bundles that disagree about one logical path', () async {
    final source = BundledAssetSource(
      _Bundle({
        ..._manifest([
          'assets/restage/bundles/lib/a.rsbundle',
          'assets/restage/bundles/lib/b.rsbundle',
        ]),
        'assets/restage/bundles/lib/a.rsbundle':
            _bundle({'assets/x/dup.rfw': 'one'}),
        'assets/restage/bundles/lib/b.rsbundle':
            _bundle({'assets/x/dup.rfw': 'another'}),
      }),
    );

    await expectLater(
      source.load('assets/x/absent.rfw'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('disagree about "assets/x/dup.rfw"'),
        ),
      ),
    );
  });

  test('reuses one source per delegate so the index is shared', () {
    final delegate = _Bundle(_manifest(const <String>[]));
    expect(
      identical(restageAssetSource(delegate), restageAssetSource(delegate)),
      isTrue,
    );
    expect(
      identical(restageAssetSource(restageAssetSource(delegate)),
          restageAssetSource(delegate)),
      isTrue,
      reason: 'wrapping an already-wrapped bundle must not nest',
    );
  });
}

Uint8List _utf8(String value) => Uint8List.fromList(utf8.encode(value));

Map<String, Uint8List> _manifest(List<String> assets) => <String, Uint8List>{
      'AssetManifest.bin': _encodeManifest(assets),
    };

/// Encodes the binary asset manifest Flutter's [AssetManifest] reads.
Uint8List _encodeManifest(List<String> assets) {
  final data = <String, Object?>{
    for (final asset in assets)
      asset: <Object?>[
        <String, Object?>{'asset': asset},
      ],
  };
  final encoded = const StandardMessageCodec().encodeMessage(data)!;
  return encoded.buffer
      .asUint8List(encoded.offsetInBytes, encoded.lengthInBytes);
}

Uint8List _bundle(Map<String, String> entries) => RestageBundleCodec.encode(
      RestageBundle(
        packageName: 'example_app',
        authoredLibraryPath: 'lib/surfaces.dart',
        entries: <RestageBundleEntry>[
          for (final entry in entries.entries)
            RestageBundleEntry(
              logicalPath: entry.key,
              role: RestageBundleEntryRoleV1.screenBlob,
              bytes: _utf8(entry.value),
            ),
        ],
      ),
    );

final class _Bundle extends AssetBundle {
  _Bundle(this._assets);

  final Map<String, Uint8List> _assets;
  final List<String> loaded = <String>[];

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    final bytes = _assets[key];
    if (bytes == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.sublistView(bytes);
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async =>
      parser(await loadString(key));
}
