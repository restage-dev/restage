import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError, debugPrint;
import 'package:flutter/services.dart' show AssetBundle, ByteData;
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/assets/bundled_asset_source.dart';

import '../support/packaged_assets.dart';

void main() {
  test('serves a logical path out of a packaged bundle', () async {
    final source = BundledAssetSource(
      _Bundle({
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
        'assets/paywalls/pulse.rfw': _utf8('loose'),
        'assets/restage/bundles/lib/a.rsbundle': _bundle({
          'assets/paywalls/pulse.rfw': 'packaged',
        }),
      }),
    );

    expect(await source.loadString('assets/paywalls/pulse.rfw'), 'loose');
  });

  test('reports a missing asset when nothing carries the path', () async {
    final source = BundledAssetSource(
      _Bundle({
        'assets/restage/bundles/lib/a.rsbundle': _bundle({
          'assets/paywalls/pulse.rfw': 'pulse-blob',
        }),
      }),
    );

    await expectLater(
      source.load('assets/paywalls/absent.rfw'),
      throwsA(
        isA<FlutterError>().having(
          (error) => error.toString(),
          'toString()',
          contains('Unable to load asset: "assets/paywalls/absent.rfw".'),
        ),
      ),
    );
  });

  test('passes through when the application packages no bundles', () async {
    final source = BundledAssetSource(
      _Bundle({'assets/paywalls/pulse.rfw': _utf8('loose')}),
    );

    expect(await source.loadString('assets/paywalls/pulse.rfw'), 'loose');
    await expectLater(
      source.load('assets/paywalls/absent.rfw'),
      throwsA(isA<FlutterError>()),
    );
  });

  test('passes through when there is no asset manifest at all', () async {
    final source = BundledAssetSource(
      _Bundle.withoutManifest({'assets/paywalls/pulse.rfw': _utf8('loose')}),
    );

    expect(await source.loadString('assets/paywalls/pulse.rfw'), 'loose');
  });

  group('a key the manifest proves is not a loose asset', () {
    // A surface probes for optional artifacts by logical path — a flow
    // document only a multi-screen surface has, a screen a single-screen one
    // never emits. Where assets travel over the network, asking the delegate
    // for one of those costs a request per read whose failure the browser
    // logs, so a key the manifest does not list is never asked for.
    test('is never fetched from the delegate', () async {
      final delegate = _Bundle({
        'assets/restage/bundles/lib/a.rsbundle': _bundle({
          'assets/paywalls/pulse.rfw': 'pulse-blob',
        }),
      });
      final source = BundledAssetSource(delegate);

      await expectLater(
        source.load('assets/paywalls/pulse.flow.json'),
        throwsA(isA<FlutterError>()),
      );
      expect(
        delegate.loaded,
        isNot(contains('assets/paywalls/pulse.flow.json')),
      );
    });

    test('is still served when a container carries it', () async {
      final delegate = _Bundle({
        'assets/restage/bundles/lib/a.rsbundle': _bundle({
          'assets/paywalls/pulse.flow.json': 'flow-document',
        }),
      });
      final source = BundledAssetSource(delegate);

      expect(
        await source.loadString('assets/paywalls/pulse.flow.json'),
        'flow-document',
      );
      expect(
        delegate.loaded,
        isNot(contains('assets/paywalls/pulse.flow.json')),
      );
    });
  });

  test('a key the manifest lists is fetched from the delegate', () async {
    // The control for the test above: the skip is decided by the manifest,
    // not by the file extension or by the logical path's shape.
    final delegate = _Bundle({
      'assets/paywalls/pulse.flow.json': _utf8('loose-flow'),
    });
    final source = BundledAssetSource(delegate);

    expect(
      await source.loadString('assets/paywalls/pulse.flow.json'),
      'loose-flow',
    );
    expect(delegate.loaded, contains('assets/paywalls/pulse.flow.json'));
  });

  test('an absent key is fetched when there is no manifest to prove it absent',
      () async {
    final delegate = _Bundle.withoutManifest({});
    final source = BundledAssetSource(delegate);

    await expectLater(
      source.load('assets/paywalls/pulse.flow.json'),
      throwsA(isA<FlutterError>()),
    );
    expect(delegate.loaded, contains('assets/paywalls/pulse.flow.json'));
  });

  test('falls back to the containers when a listed asset fails to load',
      () async {
    // The manifest lists the key, so the delegate is asked and gets to fail.
    // Only a container can answer then, and this is the one path where that
    // fallback is still reached.
    final delegate = _Bundle({
      'assets/paywalls/pulse.rfw': _utf8('loose'),
      'assets/restage/bundles/lib/a.rsbundle': _bundle({
        'assets/paywalls/pulse.rfw': 'packaged',
      }),
    })
      ..fail('assets/paywalls/pulse.rfw');
    final source = BundledAssetSource(delegate);

    expect(await source.loadString('assets/paywalls/pulse.rfw'), 'packaged');
    expect(delegate.loaded, contains('assets/paywalls/pulse.rfw'));
  });

  test('a manifest that cannot be read serves nothing and says why', () async {
    // Failing open is the safe direction, but a silent one sends the reader
    // hunting a packaging problem that does not exist.
    final source = BundledAssetSource(
      _Bundle.withoutManifest({
        'AssetManifest.bin': _utf8('not a binary manifest'),
        'assets/restage/bundles/lib/a.rsbundle': _bundle({
          'assets/paywalls/pulse.rfw': 'packaged',
        }),
      }),
    );

    final printed = <String>[];
    final previous = debugPrint;
    debugPrint =
        (String? message, {int? wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = previous);

    await expectLater(
      source.load('assets/paywalls/pulse.rfw'),
      throwsA(isA<FlutterError>()),
    );
    expect(
      printed.join('\n'),
      contains('the asset manifest could not be read'),
    );
  });

  test('indexes only as many bundles as it takes to find the path', () async {
    final delegate = _Bundle({
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

    // A later read is answered from the index rather than by reading anything
    // at all: the container was already indexed and the manifest already says
    // the logical path is not loose.
    delegate.loaded.clear();
    expect(await source.loadString('assets/x/a.rfw'), 'a');
    expect(delegate.loaded, isEmpty, reason: 'already indexed');
  });

  test('refuses to answer "absent" while a bundle cannot be read', () async {
    // Corruption must never be reported as "this artifact was not packaged" —
    // that sends a reader hunting a build problem that does not exist.
    final source = BundledAssetSource(
      _Bundle({
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
    final delegate = _Bundle(const {});
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

Uint8List _bundle(Map<String, String> entries) => encodeRestageContainer({
      for (final entry in entries.entries) entry.key: _utf8(entry.value),
    });

final class _Bundle extends AssetBundle {
  /// An application bundle whose manifest lists exactly the assets it carries,
  /// the way a real build's manifest does.
  _Bundle(Map<String, Uint8List> assets)
      : _assets = <String, Uint8List>{
          'AssetManifest.bin': encodeAssetManifest(assets.keys),
          ...assets,
        };

  /// A bundle with no manifest at all: a narrow test bundle, or an
  /// application that declares no assets.
  _Bundle.withoutManifest(this._assets);

  final Map<String, Uint8List> _assets;
  final List<String> loaded = <String>[];
  final Set<String> _failing = <String>{};

  /// Makes [key] fail to load even though the manifest declares it.
  void fail(String key) => _failing.add(key);

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    final bytes = _failing.contains(key) ? null : _assets[key];
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
