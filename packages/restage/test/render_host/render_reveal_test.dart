import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/render_host/render_core.dart';

import 'support/fake_transport.dart';

const _origin = 'https://bundle.example';

Map<String, Object?> _manifest() => <String, Object?>{
      'formatVersion': 1,
      'catalog': <String, Object?>{
        'schemaVersion': 4,
        'libraries': <String, Object?>{},
        'widgets': <Object?>[],
        'structuredTypes': <Object?>[],
        'unions': <Object?>[],
        'designTokens': <Object?>[],
        'compatRules': <Object?>[],
      },
    };

Map<String, Object?> _ready({List<String>? capabilities}) => <String, Object?>{
      'type': 'ready',
      'protocolVersions': const <int>[1],
      if (capabilities != null) 'capabilities': capabilities,
      'manifest': _manifest(),
      'engine': <String, Object?>{
        'flutterVersion': '3.41.0',
        'renderer': 'canvaskit',
      },
    };

RenderEnv _env() => RenderEnv(
      theme: const <String, Object?>{},
      brightness: 'light',
      locale: 'en-US',
      textScale: 1,
      zoom: 1,
      frame: const Size(390, 844),
    );

RenderRequest _request(int epoch) => RenderRequest(
      epoch: epoch,
      blob: Uint8List.fromList(<int>[1, 2, 3]),
      data: const <String, Object?>{},
      env: _env(),
    );

void main() {
  group('shell', () {
    late FakeRenderMessageTransport transport;
    late RenderHostProvider provider;

    setUp(() {
      transport = FakeRenderMessageTransport();
      provider = RenderHostProvider(
        transport: transport,
        bundleOrigin: _origin,
        supportedVersions: const <int>[1],
        scheduleFrame: ManualFrameScheduler().schedule,
      );
    });

    tearDown(() async => provider.dispose());

    Future<void> settle({List<String>? capabilities}) async {
      transport.receive(_origin, _ready(capabilities: capabilities));
      await provider.ready;
      await provider.render(_request(1));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 1,
        'diagnostics': <Object?>[],
      });
    }

    test('asks a bundle that can reveal to reveal a marker instance', () async {
      await settle(capabilities: const <String>[renderRevealCapability]);
      final reveal = surfaceRevealProviderFor(provider)!;
      expect(reveal.reveal('["Screen"]', index: 2), isTrue);
      expect(transport.sent.last.payload, <String, Object?>{
        'v': 1,
        'type': 'reveal',
        'epoch': 1,
        'path': '["Screen"]',
        'index': 2,
      });
    });

    test('a bundle that cannot reveal is never asked', () async {
      await settle();
      expect(surfaceRevealProviderFor(provider), isNull);
    });

    test('nothing is revealed before the render settles', () async {
      transport.receive(
        _origin,
        _ready(capabilities: const <String>[renderRevealCapability]),
      );
      await provider.ready;
      await provider.render(_request(1));
      final sent = transport.sent.length;
      expect(surfaceRevealProviderFor(provider)!.reveal('["Screen"]'), isFalse);
      expect(transport.sent, hasLength(sent));
    });
  });

  group('bundle', () {
    late FakeRenderMessageTransport transport;
    late List<(String, int)> revealed;
    late Map<int, Completer<BundleRenderResult>> results;
    late RenderProtocolServer server;

    setUp(() {
      transport = FakeRenderMessageTransport();
      revealed = <(String, int)>[];
      results = <int, Completer<BundleRenderResult>>{};
      server = RenderProtocolServer(
        transport: transport,
        manifest: RenderBundleManifest.fromJson(_manifest()),
        engine: RenderEngine(flutterVersion: '3.41.0', renderer: 'canvaskit'),
        supportedVersions: const <int>[1],
        scheduleFrame: ManualFrameScheduler().schedule,
        initialize: (_) {},
        render: (request) =>
            (results[request.epoch] = Completer<BundleRenderResult>()).future,
        reveal: (path, index) => revealed.add((path, index)),
      )..start();
    });

    tearDown(() async => server.dispose());

    Future<void> settle(int epoch) async {
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'render',
        'epoch': epoch,
        'blob': encodeRenderBlob(Uint8List.fromList(<int>[1])),
        'data': <String, Object?>{},
        'env': _env().toJson(),
      });
      results[epoch]!.complete(BundleRenderResult());
      await pumpEventQueue();
    }

    Map<String, Object?> reveal(int epoch, Object? path, Object? index) =>
        <String, Object?>{
          'v': 1,
          'type': 'reveal',
          'epoch': epoch,
          'path': path,
          'index': index,
        };

    test('advertises reveal and reveals on the settled epoch', () async {
      expect(
        transport.sent.first.payload['capabilities'],
        contains(renderRevealCapability),
      );
      await settle(1);
      transport.receive(_origin, reveal(1, '["Screen"]', 1));
      expect(revealed, <(String, int)>[('["Screen"]', 1)]);
    });

    test('ignores a stale epoch and rejects a malformed path', () async {
      await settle(1);
      await settle(2);
      transport.receive(_origin, reveal(1, '["Screen"]', 0));
      expect(revealed, isEmpty);
      transport.receive(_origin, reveal(2, 'not a path', 0));
      expect(revealed, isEmpty);
      expect(transport.sent.last.payload['type'], 'protocolError');
    });
  });
}
