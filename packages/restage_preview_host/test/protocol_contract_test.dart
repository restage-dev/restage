import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_preview_host/restage_preview_host.dart';

import 'support/fake_transport.dart';

const _origin = 'https://bundle.example';
const _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNg'
    'YAAAAAMAASsJTYQAAAAASUVORK5CYII=';
const _smallIhdrOverrunPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAVElEQVR42u3B'
    'AQEAAACAkP6v7ggKAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAagAPAAEn3N0JAAAAAElF'
    'TkSuQmCC';
const _falsePositiveSafeSnapshotPath =
    '["tokenization","dashboardStatement",0,"passwordHint"]';

const _rejectedSnapshotPaths =
    <({String label, String path, bool credentialShaped})>[
  (
    label: 'noncanonical JSON',
    path: '["Preview", "children", 0]',
    credentialShaped: false,
  ),
  (
    label: 'malformed nested shape',
    path: '["Preview","children",0,1]',
    credentialShaped: false,
  ),
  (
    label: 'credential-shaped first segment',
    path: '["dashboardState"]',
    credentialShaped: true,
  ),
  (
    label: 'credential-shaped middle segment',
    path: '["Preview","csrf-token"]',
    credentialShaped: true,
  ),
  (
    label: 'credential-shaped nested segment',
    path: '["Preview","children",0,"auth_credentials"]',
    credentialShaped: true,
  ),
];

RenderEnv _env({String brightness = 'light'}) => RenderEnv(
      theme: const <String, Object?>{'accent': 0xFF123456},
      brightness: brightness,
      locale: 'en-US',
      textScale: 1,
      zoom: 1,
      frame: const Size(390, 844),
    );

RenderRequest _request(int epoch, {RenderEnv? env, Uint8List? blob}) =>
    RenderRequest(
      epoch: epoch,
      blob: blob ?? Uint8List.fromList(<int>[0, 1, 2, 255]),
      data: const <String, Object?>{'title': 'Preview'},
      env: env ?? _env(),
    );

Map<String, Object?> _manifest() => <String, Object?>{
      'formatVersion': 1,
      'catalog': <String, Object?>{
        'schemaVersion': 4,
        'libraries': <String, Object?>{
          'acme.widgets': <String, Object?>{
            'version': '1.0.0',
            'capabilityVersion': 4,
          },
        },
        'widgets': <Object?>[
          <String, Object?>{
            'wireId': 'w0001',
            'library': 'acme.widgets',
            'name': 'Badge',
            'properties': <Object?>[
              <String, Object?>{
                'wireId': 'p0001',
                'name': 'label',
                'type': 'string',
              },
            ],
          },
        ],
        'structuredTypes': <Object?>[],
        'unions': <Object?>[],
        'designTokens': <Object?>[],
        'compatRules': <Object?>[],
      },
    };

Map<String, Object?> _ready({
  List<int> versions = const <int>[1],
  List<String>? capabilities,
}) =>
    <String, Object?>{
      'type': 'ready',
      'protocolVersions': versions,
      if (capabilities != null) 'capabilities': capabilities,
      'manifest': _manifest(),
      'engine': <String, Object?>{
        'flutterVersion': '3.41.0',
        'renderer': 'canvaskit',
      },
    };

Map<String, Object?> _wireRoundTrip(Map<String, Object?> value) =>
    (jsonDecode(jsonEncode(value))! as Map<Object?, Object?>).cast();

const Set<String> _credentialFieldNames = <String>{
  'apikey',
  'sessionkey',
  'jwt',
  'bearer',
  'token',
  'accesstoken',
  'refreshtoken',
  'authtoken',
  'idtoken',
  'apitoken',
  'sessiontoken',
  'bearertoken',
  'cookie',
  'cookies',
  'sessioncookie',
  'authcookie',
  'authorization',
  'authorizationheader',
  'authheader',
  'credential',
  'credentials',
  'authcredential',
  'authcredentials',
  'usercredential',
  'password',
  'currentpassword',
  'newpassword',
  'secret',
  'clientsecret',
  'apisecret',
  'signingsecret',
};

const List<({String key, bool rejected})> _credentialKeySecurityOracle =
    <({String key, bool rejected})>[
  (key: 'auth', rejected: true),
  (key: 'csrfToken', rejected: true),
  (key: 'privateKey', rejected: true),
  (key: 'dashboardState', rejected: true),
  (key: 'designTokens', rejected: false),
  (key: 'tokenization', rejected: false),
  (key: 'passwordHint', rejected: false),
  (key: 'authorizationStatus', rejected: false),
  (key: 'authenticity', rejected: false),
  (key: 'dashboardStatement', rejected: false),
];

String _normalizedKey(String key) =>
    key.toLowerCase().replaceAll(RegExp('[^a-z]'), '');

void _expectNoCredentialFields(Object? value) {
  if (value is Map<Object?, Object?>) {
    for (final entry in value.entries) {
      final key = entry.key;
      expect(key, isA<String>());
      expect(
        _credentialFieldNames,
        isNot(contains(_normalizedKey(key! as String))),
        reason: 'credential-shaped field appeared in a wire envelope: $key',
      );
      _expectNoCredentialFields(entry.value);
    }
  } else if (value is List<Object?>) {
    for (final child in value) {
      _expectNoCredentialFields(child);
    }
  }
}

Map<String, Object?> _acceptedData() => <String, Object?>{
      'tokenization': <String, Object?>{
        'designTokens': <Object?>[
          <String, Object?>{'cookiePolicy': 'strict'},
          <String, Object?>{'authorizationStatus': 'unknown'},
        ],
      },
      'credentialStyle': 'compact',
      'passwordHint': 'shown',
      'secretary': 'Ada',
      'monkey': 'capuchin',
      'label': 'Bearer secret',
    };

Map<String, Object?> _acceptedTheme() => <String, Object?>{
      'apiKeyboard': 'compact',
      'sessionKeyboard': 'numeric',
      'palette': <String, Object?>{
        'designTokens': <Object?>['primary', 'secondary'],
      },
    };

void main() {
  group('shell/client endpoint contract', () {
    late FakeRenderMessageTransport transport;
    late ManualFrameScheduler frames;
    late SeamRenderProvider provider;

    setUp(() {
      transport = FakeRenderMessageTransport();
      frames = ManualFrameScheduler();
      provider = SeamRenderProvider(
        transport: transport,
        bundleOrigin: _origin,
        supportedVersions: const <int>[1, 2],
        scheduleFrame: frames.schedule,
      );
    });

    tearDown(() async => provider.dispose());

    SurfaceSnapshotProvider snapshotProvider() =>
        surfaceSnapshotProviderFor(provider)!;

    test('advertised snapshot pair is exact and returns bounded PNG bytes',
        () async {
      transport.receive(
        _origin,
        _ready(capabilities: const <String>[renderSnapshotCapability]),
      );
      await provider.ready;
      expect(provider, isNot(isA<SurfaceSnapshotProvider>()));
      expect(surfaceSnapshotProviderFor(provider), isNotNull);
      await provider.render(_request(9));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 9,
        'diagnostics': <Object?>[],
      });

      const path = _falsePositiveSafeSnapshotPath;
      final snapshot = snapshotProvider().snapshot(path: path);
      expect(transport.sent.last.payload, <String, Object?>{
        'v': 1,
        'type': 'snapshotRequest',
        'epoch': 9,
        'path': path,
      });

      const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNg'
          'YAAAAAMAASsJTYQAAAAASUVORK5CYII=';
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'snapshotResult',
        'epoch': 9,
        'path': path,
        'png': png,
        'futureField': <String, Object?>{'ignored': true},
      });
      expect(await snapshot, base64Decode(png));
    });

    test('snapshot receiver rejects a small-IHDR inflate overrun', () async {
      transport.receive(
        _origin,
        _ready(capabilities: const <String>[renderSnapshotCapability]),
      );
      await provider.ready;
      await provider.render(_request(9));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 9,
        'diagnostics': <Object?>[],
      });

      const path = _falsePositiveSafeSnapshotPath;
      final snapshot = snapshotProvider().snapshot(path: path);
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'snapshotResult',
        'epoch': 9,
        'path': path,
        'png': _smallIhdrOverrunPngBase64,
      });

      await expectLater(snapshot, throwsFormatException);
    });

    for (final testCase in _rejectedSnapshotPaths) {
      test(
        'snapshot provider rejects ${testCase.label} before transport send',
        () async {
          transport.receive(
            _origin,
            _ready(capabilities: const <String>[renderSnapshotCapability]),
          );
          await provider.ready;
          await provider.render(_request(9));
          transport.receive(_origin, <String, Object?>{
            'v': 1,
            'type': 'settled',
            'epoch': 9,
            'diagnostics': <Object?>[],
          });
          final messagesBefore = transport.sent.length;

          expect(
            () => snapshotProvider().snapshot(path: testCase.path).ignore(),
            throwsA(
              testCase.credentialShaped
                  ? isA<ArgumentError>()
                  : isA<FormatException>(),
            ),
          );
          expect(transport.sent, hasLength(messagesBefore));
        },
      );
    }

    test('snapshot timeout clears exact state and permits recovery', () async {
      await provider.dispose();
      provider = SeamRenderProvider(
        transport: transport = FakeRenderMessageTransport(),
        bundleOrigin: _origin,
        supportedVersions: const <int>[1],
        scheduleFrame: frames.schedule,
        snapshotTimeout: const Duration(milliseconds: 5),
      );
      transport.receive(
        _origin,
        _ready(capabilities: const <String>[renderSnapshotCapability]),
      );
      await provider.ready;
      await provider.render(_request(9));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 9,
        'diagnostics': <Object?>[],
      });

      await expectLater(
        snapshotProvider().snapshot(path: '["Preview"]'),
        throwsA(isA<StateError>()),
      );

      final recovered = snapshotProvider().snapshot(path: '["Preview"]');
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'snapshotResult',
        'epoch': 9,
        'path': '["Preview"]',
        'png': _onePixelPngBase64,
      });
      expect(await recovered, base64Decode(_onePixelPngBase64));
    });

    test('snapshot send failure clears exact state and permits recovery',
        () async {
      transport.receive(
        _origin,
        _ready(capabilities: const <String>[renderSnapshotCapability]),
      );
      await provider.ready;
      await provider.render(_request(9));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 9,
        'diagnostics': <Object?>[],
      });

      final sendError = StateError('transport rejected the send');
      transport.nextSendError = sendError;
      await expectLater(
        snapshotProvider().snapshot(path: '["Preview"]'),
        throwsA(same(sendError)),
      );

      final recovered = snapshotProvider().snapshot(path: '["Preview"]');
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'snapshotResult',
        'epoch': 9,
        'path': '["Preview"]',
        'png': _onePixelPngBase64,
      });
      expect(await recovered, base64Decode(_onePixelPngBase64));
    });

    test('protocol and render errors reject an outstanding snapshot', () async {
      transport.receive(
        _origin,
        _ready(capabilities: const <String>[renderSnapshotCapability]),
      );
      await provider.ready;
      await provider.render(_request(9));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 9,
        'diagnostics': <Object?>[],
      });
      final protocolFailure = snapshotProvider().snapshot(path: '["Preview"]');
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'protocolError',
        'message': 'Snapshot capture failed.',
      });
      await expectLater(protocolFailure, throwsA(isA<StateError>()));

      final renderFailure = snapshotProvider().snapshot(path: '["Preview"]');
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'renderError',
        'epoch': 9,
        'message': 'Render failed.',
      });
      await expectLater(renderFailure, throwsA(isA<StateError>()));
    });

    test('new render and dispose reject an outstanding snapshot', () async {
      transport.receive(
        _origin,
        _ready(capabilities: const <String>[renderSnapshotCapability]),
      );
      await provider.ready;
      await provider.render(_request(9));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 9,
        'diagnostics': <Object?>[],
      });
      final replaced = snapshotProvider().snapshot(path: '["Preview"]');
      final replacedExpectation = expectLater(
        replaced,
        throwsA(isA<StateError>()),
      );
      await provider.render(_request(10));
      await replacedExpectation;
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 10,
        'diagnostics': <Object?>[],
      });
      final disposed = snapshotProvider().snapshot(path: '["Preview"]');
      final disposedExpectation = expectLater(
        disposed,
        throwsA(isA<StateError>()),
      );
      await provider.dispose();
      await disposedExpectation;
    });

    test('new shell keeps snapshots unavailable for a legacy bundle', () async {
      transport.receive(_origin, _ready());
      await provider.ready;
      expect(surfaceSnapshotProviderFor(provider), isNull);

      await provider.render(_request(9));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 9,
        'diagnostics': <Object?>[],
      });

      expect(
        transport.sent.where(
          (message) => message.payload['type'] == 'snapshotRequest',
        ),
        isEmpty,
      );
      expect(
        transport.sent.last.payload.keys,
        unorderedEquals(<String>['v', 'type', 'epoch', 'blob', 'data', 'env']),
      );
    });

    test('snapshot PNG decoding rejects corrupt structural envelopes', () {
      const valid =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNg'
          'YAAAAAMAASsJTYQAAAAASUVORK5CYII=';
      final bytes = base64Decode(valid);
      final badCrc = Uint8List.fromList(bytes)..[41] = bytes[41] ^ 1;
      final impossibleLength = Uint8List.fromList(bytes)
        ..setRange(33, 37, const [0x7f, 0xff, 0xff, 0xff]);
      final invalidChunkType = Uint8List.fromList([
        ...bytes.sublist(0, bytes.length - 12),
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0x21,
        0x44,
        0xdf,
        0x1c,
        ...bytes.sublist(bytes.length - 12),
      ]);
      for (final malformed in <Uint8List>[
        badCrc,
        Uint8List.fromList(bytes.sublist(0, bytes.length - 1)),
        Uint8List.fromList([...bytes, 0]),
        impossibleLength,
        invalidChunkType,
      ]) {
        expect(
          () => decodeRenderSnapshotPng(base64Encode(malformed)),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('1. negotiates highest overlap and fails closed when disjoint',
        () async {
      final dynamic publicProvider = provider;
      expect(
        () => publicProvider.negotiatedVersion = 99,
        throwsA(isA<NoSuchMethodError>()),
      );
      expect(
        () => publicProvider.manifest = null,
        throwsA(isA<NoSuchMethodError>()),
      );
      expect(
        () => publicProvider.engine = null,
        throwsA(isA<NoSuchMethodError>()),
      );
      transport.receive(_origin, _ready(versions: const <int>[1, 2]));
      expect(provider.negotiatedVersion, 2);
      await provider.initialize(
        frame: const Size(390, 844),
        fontUrls: <Uri>[Uri.parse('https://bundle.example/font.woff2')],
      );
      await provider.render(_request(1));
      expect(transport.sent.first.payload['type'], 'init');
      expect(transport.sent.last.payload['v'], 2);

      final malformedTransport = FakeRenderMessageTransport();
      final malformed = SeamRenderProvider(
        transport: malformedTransport,
        bundleOrigin: _origin,
        supportedVersions: const <int>[1],
        scheduleFrame: frames.schedule,
      );
      final malformedErrors = <RenderEvent>[];
      malformed.events.listen(malformedErrors.add);
      malformedTransport.receive(_origin, <String, Object?>{
        ..._ready(versions: const <int>[1]),
        'engine': 'not an object',
      });
      expect(malformed.negotiatedVersion, isNull);
      expect(malformed.manifest, isNull);
      expect(malformed.engine, isNull);
      expect(malformedErrors.whereType<ProtocolError>(), hasLength(1));
      malformedTransport.receive(_origin, _ready(versions: const <int>[1]));
      expect(malformed.negotiatedVersion, 1);
      expect(malformed.manifest, isNotNull);
      expect(malformed.engine, isNotNull);
      await malformed.dispose();

      final isolated = FakeRenderMessageTransport();
      final other = SeamRenderProvider(
        transport: isolated,
        bundleOrigin: _origin,
        supportedVersions: const <int>[1],
        scheduleFrame: frames.schedule,
      );
      final errors = <RenderEvent>[];
      other.events.listen(errors.add);
      isolated.receive(_origin, _ready(versions: const <int>[7]));
      isolated.receive(_origin, _ready(versions: const <int>[1]));
      await expectLater(other.render(_request(1)), throwsStateError);
      expect(isolated.sent, isEmpty);
      expect(other.negotiatedVersion, isNull);
      expect(other.manifest, isNull);
      expect(other.engine, isNull);
      expect(errors.whereType<ProtocolError>(), hasLength(1));
      await other.dispose();
    });

    test('1b. exposes explicit retryable and terminal readiness states',
        () async {
      final delayedTransport = FakeRenderMessageTransport();
      final delayed = SeamRenderProvider(
        transport: delayedTransport,
        bundleOrigin: _origin,
        supportedVersions: const <int>[1, 2],
        scheduleFrame: frames.schedule,
      );
      var readyCompleted = false;
      delayed.ready.then((_) => readyCompleted = true);
      await pumpEventQueue();
      expect(readyCompleted, isFalse);
      await expectLater(
        delayed.initialize(frame: const Size(390, 844)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('await ready'),
          ),
        ),
      );
      await expectLater(
        delayed.render(_request(1)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('await ready'),
          ),
        ),
      );
      expect(delayedTransport.sent, isEmpty);

      delayedTransport.receive(_origin, _ready(versions: const <int>[1, 2]));
      await expectLater(delayed.ready, completion(2));
      expect(readyCompleted, isTrue);
      await delayed.initialize(frame: const Size(390, 844));
      await delayed.render(_request(1));
      expect(
        delayedTransport.sent.map((message) => message.payload['type']),
        <String>['init', 'render'],
      );
      await delayed.dispose();

      final retryTransport = FakeRenderMessageTransport();
      final retry = SeamRenderProvider(
        transport: retryTransport,
        bundleOrigin: _origin,
        supportedVersions: const <int>[1],
        scheduleFrame: frames.schedule,
      );
      var retryReadyCompleted = false;
      retry.ready.then((_) => retryReadyCompleted = true);
      retryTransport.receive(_origin, <String, Object?>{
        ..._ready(),
        'engine': 'malformed',
      });
      await pumpEventQueue();
      expect(retryReadyCompleted, isFalse);
      retryTransport.receive(_origin, _ready());
      await expectLater(retry.ready, completion(1));
      await retry.dispose();

      final disjointTransport = FakeRenderMessageTransport();
      final disjoint = SeamRenderProvider(
        transport: disjointTransport,
        bundleOrigin: _origin,
        supportedVersions: const <int>[1],
        scheduleFrame: frames.schedule,
      );
      final disjointReady = expectLater(disjoint.ready, throwsStateError);
      disjointTransport.receive(
        _origin,
        _ready(versions: const <int>[7]),
      );
      await disjointReady;
      await expectLater(
        disjoint.initialize(frame: const Size(390, 844)),
        throwsStateError,
      );
      await expectLater(disjoint.render(_request(1)), throwsStateError);
      expect(disjointTransport.sent, isEmpty);
      await disjoint.dispose();

      final disposedTransport = FakeRenderMessageTransport();
      final disposed = SeamRenderProvider(
        transport: disposedTransport,
        bundleOrigin: _origin,
        supportedVersions: const <int>[1],
        scheduleFrame: frames.schedule,
      );
      final disposedReady = expectLater(disposed.ready, throwsStateError);
      await disposed.dispose();
      await disposedReady;
    });

    test('1c. validates client versions and initialize frame before send',
        () async {
      expect(
        () => SeamRenderProvider(
          transport: FakeRenderMessageTransport(),
          bundleOrigin: _origin,
          supportedVersions: const <int>[],
          scheduleFrame: frames.schedule,
        ),
        throwsArgumentError,
      );
      expect(
        () => SeamRenderProvider(
          transport: FakeRenderMessageTransport(),
          bundleOrigin: _origin,
          supportedVersions: const <int>[0, 1],
          scheduleFrame: frames.schedule,
        ),
        throwsArgumentError,
      );

      transport.receive(_origin, _ready());
      await provider.ready;
      final sentBefore = transport.sent.length;
      for (final frame in <Size>[
        const Size(0, 844),
        const Size(-1, 844),
        const Size(double.nan, 844),
        const Size(double.infinity, 844),
        const Size(390, 0),
        const Size(390, -1),
        const Size(390, double.negativeInfinity),
      ]) {
        await expectLater(
          provider.initialize(frame: frame),
          throwsArgumentError,
          reason: '$frame must be rejected',
        );
      }
      expect(transport.sent, hasLength(sentBefore));
    });

    test('1d. malformed advertised versions stay retryable and unpublished',
        () async {
      var readyCompleted = false;
      provider.ready.then((_) => readyCompleted = true);
      final events = <RenderEvent>[];
      provider.events.listen(events.add);

      for (final versions in <List<int>>[
        <int>[],
        <int>[0, 1],
        <int>[0],
        <int>[-1, 1],
      ]) {
        transport.receive(_origin, _ready(versions: versions));
        await pumpEventQueue();
        expect(provider.negotiatedVersion, isNull, reason: '$versions');
        expect(provider.manifest, isNull, reason: '$versions');
        expect(provider.engine, isNull, reason: '$versions');
        expect(readyCompleted, isFalse, reason: '$versions');
        await expectLater(provider.render(_request(1)), throwsStateError);
        expect(transport.sent, isEmpty, reason: '$versions');
      }
      expect(events.whereType<ProtocolError>(), hasLength(4));

      transport.receive(_origin, _ready(versions: const <int>[1, 2]));
      await expectLater(provider.ready, completion(2));
      expect(readyCompleted, isTrue);
      expect(provider.manifest, isNotNull);
      expect(provider.engine, isNotNull);
      await provider.render(_request(1));
      expect(transport.sent.single.payload['type'], 'render');
    });

    test('2. discards stale epoch emissions', () async {
      transport.receive(_origin, _ready());
      final events = <RenderEvent>[];
      final geometry = <GeometrySnapshot>[];
      provider.events.listen(events.add);
      provider.geometry.listen(geometry.add);
      await provider.render(_request(2));
      await provider.render(_request(3));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 2,
        'diagnostics': <Object?>[],
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'geometry',
        'epoch': 2,
        'generation': 0,
        'rects': <String, Object?>{
          '["stale"]': <double>[0, 0, 10, 10],
        },
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'renderError',
        'epoch': 2,
        'message': 'stale failure',
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 3,
        'diagnostics': <Object?>[],
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'geometry',
        'epoch': 3,
        'generation': 0,
        'rects': <String, Object?>{
          '["current"]': <double>[0, 0, 10, 10],
        },
      });
      expect(events.whereType<Settled>().map((event) => event.epoch), <int>[3]);
      expect(events.whereType<RenderError>(), isEmpty);
      expect(
        geometry.map((snapshot) => (snapshot.epoch, snapshot.generation)),
        <(int, int)>[(3, 0)],
      );
    });

    test('3. enforces settled then geometry with increasing generations',
        () async {
      transport.receive(_origin, _ready());
      final geometry = <GeometrySnapshot>[];
      final events = <RenderEvent>[];
      provider.geometry.listen(geometry.add);
      provider.events.listen(events.add);
      await provider.render(_request(1));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 1,
        'diagnostics': <Object?>[],
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'geometry',
        'epoch': 1,
        'generation': 1,
        'rects': <String, Object?>{
          '["main"]': <double>[0, 0, 10, 10]
        },
      });
      expect(geometry, isEmpty);
      expect(events.whereType<ProtocolError>(), hasLength(1));
      for (final generation in <int>[0, 1, 2]) {
        transport.receive(_origin, <String, Object?>{
          'v': 1,
          'type': 'geometry',
          'epoch': 1,
          'generation': generation,
          'rects': <String, Object?>{
            '["main"]': <double>[0, 0, 10, 10]
          },
        });
        frames.flush();
      }
      expect(geometry.map((snapshot) => snapshot.generation), <int>[0, 1, 2]);
    });

    test('3b. malformed settled cannot commit state or authorize geometry',
        () async {
      transport.receive(_origin, _ready());
      final geometry = <GeometrySnapshot>[];
      final events = <RenderEvent>[];
      provider.geometry.listen(geometry.add);
      provider.events.listen(events.add);
      await provider.render(_request(1));

      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 1,
        'diagnostics': 'malformed',
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'geometry',
        'epoch': 1,
        'generation': 0,
        'rects': <String, Object?>{},
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 1,
        'diagnostics': <Object?>[],
        'timings': <String, Object?>{'build': double.nan},
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'geometry',
        'epoch': 1,
        'generation': 0,
        'rects': <String, Object?>{},
      });
      expect(events.whereType<ProtocolError>(), hasLength(4));
      expect(events.whereType<Settled>(), isEmpty);
      expect(geometry, isEmpty);

      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 1,
        'diagnostics': <Object?>[],
        'timings': <String, Object?>{'build': 1.0},
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'geometry',
        'epoch': 1,
        'generation': 0,
        'rects': <String, Object?>{},
      });
      expect(events.whereType<Settled>(), hasLength(1));
      expect(geometry.single.generation, 0);

      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 1,
        'diagnostics': <Object?>[],
      });
      expect(events.whereType<ProtocolError>(), hasLength(5));
      expect(events.whereType<Settled>(), hasLength(1));
    });

    test('4. current post-settle renderError terminates exactly once',
        () async {
      transport.receive(_origin, _ready());
      final events = <RenderEvent>[];
      final geometry = <GeometrySnapshot>[];
      provider.events.listen(events.add);
      provider.geometry.listen(geometry.add);
      await provider.render(_request(1));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 1,
        'diagnostics': <Object?>[],
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'geometry',
        'epoch': 1,
        'generation': 0,
        'rects': <String, Object?>{},
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'renderError',
        'epoch': 1,
        'message': 'bad input',
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'renderError',
        'epoch': 1,
        'message': 'duplicate bad input',
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'geometry',
        'epoch': 1,
        'generation': 1,
        'rects': <String, Object?>{},
      });
      expect(events.whereType<RenderError>(), hasLength(1));
      expect(events.whereType<Settled>(), hasLength(1));
      expect(geometry.map((snapshot) => snapshot.generation), <int>[0]);
    });

    test('4a. pre-settle renderError suppresses all later output', () async {
      transport.receive(_origin, _ready());
      final events = <RenderEvent>[];
      final geometry = <GeometrySnapshot>[];
      provider.events.listen(events.add);
      provider.geometry.listen(geometry.add);
      await provider.render(_request(1));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'renderError',
        'epoch': 1,
        'message': 'bad input',
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 1,
        'diagnostics': <Object?>[],
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'geometry',
        'epoch': 1,
        'generation': 0,
        'rects': <String, Object?>{},
      });
      expect(events.whereType<RenderError>(), hasLength(1));
      expect(events.whereType<Settled>(), isEmpty);
      expect(geometry, isEmpty);
    });

    test('4b. emits each inbound protocolError once', () {
      transport.receive(_origin, _ready());
      final events = <RenderEvent>[];
      provider.events.listen(events.add);

      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'protocolError',
        'message': 'invalid request',
      });

      expect(events.whereType<ProtocolError>(), hasLength(1));
    });

    test('5. includes the full environment in every render epoch', () async {
      transport.receive(_origin, _ready());
      final events = <RenderEvent>[];
      provider.events.listen(events.add);
      await provider.render(_request(1, env: _env()));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 1,
        'diagnostics': <Object?>[],
      });
      await provider.render(_request(2, env: _env(brightness: 'dark')));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 2,
        'diagnostics': <Object?>[],
      });
      expect(transport.sent.map((message) => message.payload['epoch']),
          <int>[1, 2]);
      expect(
        transport.sent.map(
          (message) =>
              (message.payload['env']! as Map<String, Object?>)['brightness'],
        ),
        <String>['light', 'dark'],
      );
      expect(
        events.whereType<Settled>().map((event) => event.epoch),
        <int>[1, 2],
      );
    });

    test('6. ignores unknown types and fields', () async {
      final events = <RenderEvent>[];
      provider.events.listen(events.add);
      transport.receive(_origin, <String, Object?>{
        'type': 'future-nonsense',
        'newField': true,
      });
      transport
          .receive(_origin, <String, Object?>{..._ready(), 'newField': true});
      await provider.render(_request(1));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 1,
        'diagnostics': <Object?>[],
        'newField': true,
      });
      expect(events.whereType<Settled>(), hasLength(1));
      expect(events.whereType<ProtocolError>(), isEmpty);
    });

    test('7. drops all messages from the wrong origin', () async {
      transport.receive('https://wrong.example', _ready());
      expect(provider.negotiatedVersion, isNull);
      transport.receive(_origin, _ready());
      await provider.render(_request(1));
      final events = <RenderEvent>[];
      provider.events.listen(events.add);
      transport.receive('https://wrong.example', <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 1,
        'diagnostics': <Object?>[],
      });
      expect(events, isEmpty);
    });

    test('8. recursively gates and round-trips the complete render envelope',
        () async {
      transport.receive(_origin, _ready());
      final acceptedEnv = RenderEnv(
        theme: _acceptedTheme(),
        brightness: 'light',
        locale: 'en-US',
        textScale: 1,
        zoom: 1,
        frame: const Size(390, 844),
      );
      final accepted = RenderRequest(
        epoch: 1,
        blob: Uint8List.fromList(<int>[0, 127, 128, 255]),
        data: _acceptedData(),
        env: acceptedEnv,
      );
      expect(
        () => (accepted.data['tokenization']!
            as Map<String, Object?>)['apiKey'] = 'late injection',
        throwsUnsupportedError,
      );
      expect(
        () => (accepted.env.theme['palette']!
            as Map<String, Object?>)['sessionKey'] = 'late injection',
        throwsUnsupportedError,
      );
      expect(() => accepted.blob[0] = 9, throwsUnsupportedError);
      await provider.render(accepted);

      final envelope = _wireRoundTrip(transport.sent.single.payload);
      _expectNoCredentialFields(envelope);
      expect(
        envelope.keys,
        unorderedEquals(<String>['v', 'type', 'epoch', 'blob', 'data', 'env']),
      );
      expect(envelope['data'], accepted.data);
      final envEnvelope = envelope['env']! as Map<String, Object?>;
      expect(
        envEnvelope.keys,
        unorderedEquals(<String>[
          'theme',
          'brightness',
          'locale',
          'textScale',
          'zoom',
          'frame',
        ]),
      );
      expect(
        RenderEnv.fromJson(envEnvelope).toJson(),
        accepted.env.toJson(),
      );
      expect(decodeRenderBlob(envelope['blob']! as String), accepted.blob);

      for (final field in _credentialFieldNames) {
        expect(
          () => RenderRequest(
            epoch: 2,
            blob: Uint8List(0),
            data: <String, Object?>{
              'nested': <Object?>[
                <String, Object?>{field: 'not allowed'},
              ],
            },
            env: _env(),
          ),
          throwsArgumentError,
          reason: 'data.$field must be rejected',
        );
        expect(
          () => RenderEnv(
            theme: <String, Object?>{
              'nested': <Object?>[
                <String, Object?>{field: 'not allowed'},
              ],
            },
            brightness: 'light',
            locale: 'en-US',
            textScale: 1,
            zoom: 1,
            frame: const Size(390, 844),
          ),
          throwsArgumentError,
          reason: 'env.theme.$field must be rejected',
        );
      }

      for (final value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => RenderRequest(
            epoch: 2,
            blob: Uint8List(0),
            data: <String, Object?>{
              'nested': <Object?>[
                <String, Object?>{'value': value},
              ],
            },
            env: _env(),
          ),
          throwsArgumentError,
        );
        expect(
          () => RenderEnv(
            theme: <String, Object?>{
              'nested': <Object?>[
                <String, Object?>{'value': value},
              ],
            },
            brightness: 'light',
            locale: 'en-US',
            textScale: 1,
            zoom: 1,
            frame: const Size(390, 844),
          ),
          throwsArgumentError,
        );
      }
    });

    test('8b. snapshots mutable public inputs recursively', () {
      final blob = Uint8List.fromList(<int>[1, 2, 3]);
      final request = RenderRequest(
        epoch: 1,
        blob: blob,
        data: const <String, Object?>{},
        env: _env(),
      );
      blob[0] = 9;
      expect(request.blob, <int>[1, 2, 3]);

      final timings = <String, Object?>{
        'phases': <Object?>[
          <String, Object?>{'name': 'build', 'millis': 3},
        ],
      };
      final settled = Settled(
        epoch: 1,
        diagnostics: <RenderDiagnostic>[
          RenderDiagnostic(severity: 'info', message: 'ok'),
        ],
        timings: timings,
      );
      (timings['phases']! as List<Object?>).clear();
      expect(settled.timings!['phases'], hasLength(1));
      expect(
        () => ((settled.timings!['phases']! as List<Object?>).single
            as Map<String, Object?>)['millis'] = 99,
        throwsUnsupportedError,
      );

      expect(
        () => RenderDiagnostic(severity: 'error', message: 'not accepted'),
        throwsArgumentError,
      );
    });

    test('8c. applies the credential-key security oracle recursively', () {
      for (final testCase in _credentialKeySecurityOracle) {
        RenderRequest buildRequest() => RenderRequest(
              epoch: 1,
              blob: Uint8List(0),
              data: <String, Object?>{
                'outer': <Object?>[
                  <String, Object?>{testCase.key: 'value'},
                ],
              },
              env: _env(),
            );
        RenderEnv buildEnv() => RenderEnv(
              theme: <String, Object?>{
                'outer': <Object?>[
                  <String, Object?>{testCase.key: 'value'},
                ],
              },
              brightness: 'light',
              locale: 'en-US',
              textScale: 1,
              zoom: 1,
              frame: const Size(390, 844),
            );

        if (testCase.rejected) {
          expect(buildRequest, throwsArgumentError, reason: testCase.key);
          expect(buildEnv, throwsArgumentError, reason: testCase.key);
        } else {
          expect(buildRequest, returnsNormally, reason: testCase.key);
          expect(buildEnv, returnsNormally, reason: testCase.key);
        }
      }
    });

    test('9. base64 blob round-trips byte-identically', () async {
      transport.receive(_origin, _ready());
      final bytes = Uint8List.fromList(<int>[0, 127, 128, 255]);
      await provider.render(_request(1, blob: bytes));
      expect(decodeRenderBlob(transport.sent.single.payload['blob']! as String),
          bytes);
    });

    test('10. coalesces incoming geometry updates to one per frame', () async {
      transport.receive(_origin, _ready());
      final geometry = <GeometrySnapshot>[];
      provider.geometry.listen(geometry.add);
      await provider.render(_request(1));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 1,
        'diagnostics': <Object?>[],
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'geometry',
        'epoch': 1,
        'generation': 0,
        'rects': <String, Object?>{},
      });
      for (final generation in <int>[1, 2, 3]) {
        transport.receive(_origin, <String, Object?>{
          'v': 1,
          'type': 'geometry',
          'epoch': 1,
          'generation': generation,
          'rects': <String, Object?>{
            '["main"]': <double>[0, 0, generation.toDouble(), 1]
          },
        });
      }
      expect(geometry.map((snapshot) => snapshot.generation), <int>[0]);
      frames.flush();
      expect(geometry.map((snapshot) => snapshot.generation), <int>[0, 3]);
    });

    test('11. rejects invalid geometry and accepts negative origins and zeros',
        () async {
      final invalidRects = <Rect>[
        const Rect.fromLTWH(double.nan, 0, 1, 1),
        const Rect.fromLTWH(0, double.infinity, 1, 1),
        const Rect.fromLTWH(0, 0, -1, 1),
        const Rect.fromLTWH(0, 0, 1, -1),
      ];
      for (final rect in invalidRects) {
        expect(
          () => GeometrySnapshot(
            epoch: 1,
            generation: 0,
            rects: <String, Rect>{'["main"]': rect},
          ),
          throwsArgumentError,
          reason: '$rect must be rejected',
        );
      }
      for (final snapshot in <({int epoch, int generation})>[
        (epoch: -1, generation: 0),
        (epoch: 1, generation: -1),
      ]) {
        expect(
          () => GeometrySnapshot(
            epoch: snapshot.epoch,
            generation: snapshot.generation,
            rects: const <String, Rect>{},
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => GeometrySnapshot(
          epoch: 1,
          generation: 0,
          rects: const <String, Rect>{
            '["main"]': Rect.fromLTWH(-10, -20, 0, 0),
          },
        ),
        returnsNormally,
      );
      for (final rects in <Map<String, Rect>>[
        const <String, Rect>{
          'not-json': Rect.fromLTWH(0, 0, 1, 1),
        },
        const <String, Rect>{
          '[ "main" ]': Rect.fromLTWH(0, 0, 1, 1),
        },
        const <String, Rect>{
          '["main"]': Rect.fromLTWH(0, 0, 1, 1),
          '[ "main" ]': Rect.fromLTWH(0, 0, 1, 1),
        },
      ]) {
        expect(
          () => GeometrySnapshot(
            epoch: 1,
            generation: 0,
            rects: rects,
          ),
          throwsArgumentError,
          reason: '$rects must reject malformed or duplicate identities',
        );
      }

      transport.receive(_origin, _ready());
      final geometry = <GeometrySnapshot>[];
      final events = <RenderEvent>[];
      provider.geometry.listen(geometry.add);
      provider.events.listen(events.add);
      await provider.render(_request(1));
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'settled',
        'epoch': 1,
        'diagnostics': <Object?>[],
      });
      for (final values in <List<double>>[
        <double>[double.nan, 0, 1, 1],
        <double>[0, double.negativeInfinity, 1, 1],
        <double>[0, 0, -1, 1],
        <double>[0, 0, 1, -1],
      ]) {
        transport.receive(_origin, <String, Object?>{
          'v': 1,
          'type': 'geometry',
          'epoch': 1,
          'generation': 0,
          'rects': <String, Object?>{'["main"]': values},
        });
      }
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'geometry',
        'epoch': 1,
        'generation': -1,
        'rects': <String, Object?>{},
      });
      expect(events.whereType<ProtocolError>(), hasLength(5));
      expect(geometry, isEmpty);

      var expectedProtocolErrorCount = 6;
      for (final rects in <String, Object?>{
        'malformed key': <String, Object?>{
          'not-json': <double>[0, 0, 1, 1],
        },
        'whitespace alias': <String, Object?>{
          '[ "main" ]': <double>[0, 0, 1, 1],
        },
        'duplicate semantic identity': <String, Object?>{
          '["main"]': <double>[0, 0, 1, 1],
          '[ "main" ]': <double>[0, 0, 1, 1],
        },
      }.entries) {
        transport.receive(_origin, <String, Object?>{
          'v': 1,
          'type': 'geometry',
          'epoch': 1,
          'generation': 0,
          'rects': rects.value,
        });
        expect(
          events.whereType<ProtocolError>(),
          hasLength(expectedProtocolErrorCount),
          reason: rects.key,
        );
        expect(geometry, isEmpty, reason: rects.key);
        expectedProtocolErrorCount += 1;
      }

      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'geometry',
        'epoch': 1,
        'generation': 0,
        'rects': <String, Object?>{
          '["main"]': <double>[-10, -20, 0, 0],
        },
      });
      expect(
        geometry.single.rects['["main"]'],
        const Rect.fromLTWH(-10, -20, 0, 0),
      );
    });
  });

  group('bundle/server endpoint contract', () {
    late FakeRenderMessageTransport transport;
    late ManualFrameScheduler frames;
    late List<RenderRequest> requests;
    late List<BundleInitialization> initializations;
    late Map<int, Completer<BundleRenderResult>> results;
    late RenderProtocolServer server;

    setUp(() {
      transport = FakeRenderMessageTransport();
      frames = ManualFrameScheduler();
      requests = <RenderRequest>[];
      initializations = <BundleInitialization>[];
      results = <int, Completer<BundleRenderResult>>{};
      server = RenderProtocolServer(
        transport: transport,
        manifest: RenderBundleManifest.fromJson(_manifest()),
        engine: RenderEngine(flutterVersion: '3.41.0', renderer: 'canvaskit'),
        supportedVersions: const <int>[1, 2],
        scheduleFrame: frames.schedule,
        initialize: initializations.add,
        render: (request) {
          requests.add(request);
          return (results[request.epoch] = Completer<BundleRenderResult>())
              .future;
        },
      )..start();
    });

    tearDown(() async => server.dispose());

    void receiveRender(
      int epoch, {
      String origin = _origin,
      int version = 1,
      RenderEnv? env,
      Uint8List? blob,
    }) {
      transport.receive(origin, <String, Object?>{
        'v': version,
        'type': 'render',
        'epoch': epoch,
        'blob': encodeRenderBlob(blob ?? Uint8List.fromList(<int>[1, 2, 3])),
        'data': <String, Object?>{'title': 'Preview'},
        'env': (env ?? _env()).toJson(),
      });
    }

    test('1. advertises all versions and pins the first valid init version',
        () async {
      final dynamic publicServer = server;
      expect(
        () => publicServer.lockedOrigin = 'https://mutation.example',
        throwsA(isA<NoSuchMethodError>()),
      );
      expect(transport.sent.single.payload['type'], 'ready');
      expect(transport.sent.single.payload['protocolVersions'], <int>[1, 2]);
      expect(
        (transport.sent.single.payload['manifest']! as Map<String, Object?>)
            .keys,
        unorderedEquals(<String>['formatVersion', 'catalog']),
      );
      expect(
        transport.sent.single.payload.keys,
        unorderedEquals(
          <String>['type', 'protocolVersions', 'manifest', 'engine'],
        ),
      );
      transport.receive(_origin, <String, Object?>{
        'v': 7,
        'type': 'render',
        'epoch': 1,
        'blob': encodeRenderBlob(Uint8List(0)),
        'data': <String, Object?>{},
        'env': _env().toJson(),
      });
      expect(server.lockedOrigin, isNull);
      expect(transport.sent.last.payload, containsPair('v', 7));
      transport.receive(_origin, <String, Object?>{
        'type': 'render',
        'epoch': 1,
      });
      expect(server.lockedOrigin, isNull);
      expect(transport.sent.last.payload, containsPair('v', 1));
      transport.receive(_origin, <String, Object?>{
        'v': 2,
        'type': 'init',
        'protocol': 2,
        'frame': <String, Object?>{'w': 390.0, 'h': 844.0},
      });
      expect(server.lockedOrigin, _origin);
      transport.receive(_origin, <String, Object?>{'type': 'init'});
      expect(transport.sent.last.payload['type'], 'protocolError');
      expect(transport.sent.last.payload['v'], 2);
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'init',
        'protocol': 1,
        'frame': <String, Object?>{'w': 390.0, 'h': 844.0},
      });
      expect(transport.sent.last.payload['type'], 'protocolError');
      expect(transport.sent.last.payload['v'], 2);
      receiveRender(1);
      expect(transport.sent.last.payload['type'], 'protocolError');
      expect(transport.sent.last.payload['v'], 2);
      expect(requests, isEmpty);
      receiveRender(1, version: 2);
      expect(requests, hasLength(1));
      results[1]!.complete(BundleRenderResult());
      await pumpEventQueue();
      expect(
        transport.sent
            .where((message) => const <String>{'settled', 'geometry'}
                .contains(message.payload['type']))
            .map((message) => message.payload['v']),
        <int>[2, 2],
      );
      transport.receive(_origin, <String, Object?>{
        'v': 7,
        'type': 'render',
        'epoch': 2,
        'blob': encodeRenderBlob(Uint8List(0)),
        'data': <String, Object?>{},
        'env': _env().toJson(),
      });
      expect(transport.sent.last.payload['type'], 'protocolError');
      expect(transport.sent.last.payload['v'], 2);
    });

    test(
        'snapshot-capable server advertises, renders for a legacy shell, and '
        'returns bounded PNG', () async {
      final snapshotTransport = FakeRenderMessageTransport();
      final snapshotPaths = <String>[];
      final snapshotServer = RenderProtocolServer(
        transport: snapshotTransport,
        manifest: RenderBundleManifest.fromJson(_manifest()),
        engine: RenderEngine(
          flutterVersion: '3.41.0',
          renderer: 'canvaskit',
        ),
        supportedVersions: const <int>[1],
        scheduleFrame: frames.schedule,
        initialize: (_) {},
        render: (_) async => BundleRenderResult(),
        snapshot: (_, path) async {
          snapshotPaths.add(path);
          return base64Decode(_onePixelPngBase64);
        },
      )..start();
      addTearDown(snapshotServer.dispose);
      expect(
        snapshotTransport.sent.single.payload['capabilities'],
        const <String>[renderSnapshotCapability],
      );
      // A legacy shell ignores the additive ready field and sends its normal
      // v1 render envelope unchanged.
      snapshotTransport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'render',
        'epoch': 1,
        'blob': encodeRenderBlob(Uint8List.fromList(<int>[1])),
        'data': <String, Object?>{},
        'env': _env().toJson(),
      });
      await pumpEventQueue();

      snapshotTransport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'snapshotRequest',
        'epoch': 1,
        'path': _falsePositiveSafeSnapshotPath,
        'futureField': <String, Object?>{'ignored': true},
      });
      await pumpEventQueue();

      expect(snapshotTransport.sent.last.payload, <String, Object?>{
        'v': 1,
        'type': 'snapshotResult',
        'epoch': 1,
        'path': _falsePositiveSafeSnapshotPath,
        'png': _onePixelPngBase64,
      });
      expect(snapshotPaths, <String>[_falsePositiveSafeSnapshotPath]);
    });

    test('snapshot sender rejects a small-IHDR inflate overrun', () async {
      final snapshotTransport = FakeRenderMessageTransport();
      // The assertion below is that nothing reaches the wire, which would also
      // hold if the handler never ran at all. Anchor it: the capture must
      // actually have been attempted for the silence to mean anything.
      var captureAttempted = false;
      final snapshotServer = RenderProtocolServer(
        transport: snapshotTransport,
        manifest: RenderBundleManifest.fromJson(_manifest()),
        engine: RenderEngine(
          flutterVersion: '3.41.0',
          renderer: 'canvaskit',
        ),
        supportedVersions: const <int>[1],
        scheduleFrame: frames.schedule,
        initialize: (_) {},
        render: (_) async => BundleRenderResult(),
        snapshot: (_, __) async {
          captureAttempted = true;
          return base64Decode(_smallIhdrOverrunPngBase64);
        },
      )..start();
      addTearDown(snapshotServer.dispose);
      snapshotTransport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'render',
        'epoch': 1,
        'blob': encodeRenderBlob(Uint8List.fromList(<int>[1])),
        'data': <String, Object?>{},
        'env': _env().toJson(),
      });
      await pumpEventQueue();

      snapshotTransport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'snapshotRequest',
        'epoch': 1,
        'path': _falsePositiveSafeSnapshotPath,
      });
      await pumpEventQueue();

      expect(
        captureAttempted,
        isTrue,
        reason: 'the silence asserted below only means anything if the '
            'capture was actually attempted',
      );
      // The malformed capture is refused — nothing claiming to be a snapshot
      // goes out — but it is refused quietly. A payload this bundle produced
      // itself is not a peer contract violation, and answering with
      // `protocolError` would be read shell-side as terminal and discard an
      // otherwise healthy session.
      expect(
        snapshotTransport.sent.where(
          (message) => const <String>{
            'snapshotResult',
            'protocolError',
          }.contains(message.payload['type']),
        ),
        isEmpty,
      );
    });

    for (final testCase in _rejectedSnapshotPaths) {
      test(
        'snapshot server rejects ${testCase.label} before bundle handler',
        () async {
          final snapshotTransport = FakeRenderMessageTransport();
          final snapshotPaths = <String>[];
          final snapshotServer = RenderProtocolServer(
            transport: snapshotTransport,
            manifest: RenderBundleManifest.fromJson(_manifest()),
            engine: RenderEngine(
              flutterVersion: '3.41.0',
              renderer: 'canvaskit',
            ),
            supportedVersions: const <int>[1],
            scheduleFrame: frames.schedule,
            initialize: (_) {},
            render: (_) async => BundleRenderResult(),
            snapshot: (_, path) async {
              snapshotPaths.add(path);
              return base64Decode(_onePixelPngBase64);
            },
          )..start();
          addTearDown(snapshotServer.dispose);
          snapshotTransport.receive(_origin, <String, Object?>{
            'v': 1,
            'type': 'render',
            'epoch': 1,
            'blob': encodeRenderBlob(Uint8List.fromList(<int>[1])),
            'data': <String, Object?>{},
            'env': _env().toJson(),
          });
          await pumpEventQueue();
          final messagesBefore = snapshotTransport.sent.length;

          snapshotTransport.receive(_origin, <String, Object?>{
            'v': 1,
            'type': 'snapshotRequest',
            'epoch': 1,
            'path': testCase.path,
          });
          await pumpEventQueue();

          expect(snapshotPaths, isEmpty);
          expect(snapshotTransport.sent, hasLength(messagesBefore + 1));
          expect(
            snapshotTransport.sent.last.payload['type'],
            'protocolError',
          );
          expect(
            snapshotTransport.sent.where(
              (message) => message.payload['type'] == 'snapshotResult',
            ),
            isEmpty,
          );
        },
      );
    }

    test('legacy server ignores unsupported snapshot traffic', () async {
      receiveRender(1);
      results[1]!.complete(BundleRenderResult());
      await pumpEventQueue();

      final messagesBefore = transport.sent.length;
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'snapshotRequest',
        'epoch': 1,
        'path': '["Preview"]',
      });

      expect(transport.sent, hasLength(messagesBefore));
    });

    test('a failed snapshot capture emits nothing and stays retryable',
        () async {
      final snapshotTransport = FakeRenderMessageTransport();
      var attempts = 0;
      final snapshotServer = RenderProtocolServer(
        transport: snapshotTransport,
        manifest: RenderBundleManifest.fromJson(_manifest()),
        engine: RenderEngine(
          flutterVersion: '3.41.0',
          renderer: 'canvaskit',
        ),
        supportedVersions: const <int>[1],
        scheduleFrame: frames.schedule,
        initialize: (_) {},
        render: (_) async => BundleRenderResult(),
        snapshot: (_, __) async {
          attempts++;
          if (attempts == 1) throw StateError('capture unavailable');
          return base64Decode(_onePixelPngBase64);
        },
      )..start();
      addTearDown(snapshotServer.dispose);
      snapshotTransport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'render',
        'epoch': 1,
        'blob': encodeRenderBlob(Uint8List.fromList(<int>[1])),
        'data': <String, Object?>{},
        'env': _env().toJson(),
      });
      await pumpEventQueue();
      final request = <String, Object?>{
        'v': 1,
        'type': 'snapshotRequest',
        'epoch': 1,
        'path': '["Preview"]',
      };

      final sentBeforeFailedCapture = snapshotTransport.sent.length;
      snapshotTransport.receive(_origin, request);
      await pumpEventQueue();
      expect(
        snapshotTransport.sent,
        hasLength(sentBeforeFailedCapture),
        reason: 'a failed optional capture must put nothing on the wire. '
            'This previously answered with protocolError, which the contract '
            'reserves for a violation outside any epoch and which the shell '
            'treats as terminal — so an oversized PNG discarded the session '
            'and tore a healthy settled render down to placeholders. The '
            'requester resolves its own outstanding snapshot on timeout.',
      );
      snapshotTransport.receive(_origin, request);
      await pumpEventQueue();
      expect(snapshotTransport.sent.last.payload['type'], 'snapshotResult');
      expect(attempts, 2);
    });

    test('1b. accepted init resends retain latest prewarm state and call work',
        () {
      Map<String, Object?> init({
        required double width,
        required List<Object?> fonts,
        int version = 1,
      }) =>
          <String, Object?>{
            'v': version,
            'type': 'init',
            'protocol': version,
            'frame': <String, Object?>{'w': width, 'h': 844.0},
            'prewarm': <String, Object?>{'fontUrls': fonts},
          };

      transport.receive(
        _origin,
        init(
          width: 390,
          fonts: <Object?>['https://example.test/first.woff2'],
        ),
      );
      expect(initializations, hasLength(1));
      expect(server.latestInitialization, same(initializations.single));
      expect(server.latestInitialization!.frame, const Size(390, 844));
      expect(
        server.latestInitialization!.fontUrls,
        <String>['https://example.test/first.woff2'],
      );
      expect(
        () => server.latestInitialization!.fontUrls.add('late injection'),
        throwsUnsupportedError,
      );

      transport.receive(
        _origin,
        init(
          width: 430,
          fonts: <Object?>['https://example.test/latest.woff2'],
        ),
      );
      expect(initializations, hasLength(2));
      expect(server.latestInitialization, same(initializations.last));
      expect(server.latestInitialization!.frame, const Size(430, 844));
      expect(
        server.latestInitialization!.fontUrls,
        <String>['https://example.test/latest.woff2'],
      );

      final latest = server.latestInitialization;
      final sentBeforeWrongOrigin = transport.sent.length;
      transport.receive(
        'https://wrong.example',
        init(width: 999, fonts: <Object?>['wrong-origin']),
      );
      expect(transport.sent, hasLength(sentBeforeWrongOrigin));
      expect(initializations, hasLength(2));
      expect(server.latestInitialization, same(latest));

      transport.receive(
        _origin,
        init(width: 999, fonts: <Object?>['unsupported'], version: 7),
      );
      expect(transport.sent.last.payload['type'], 'protocolError');
      expect(initializations, hasLength(2));
      expect(server.latestInitialization, same(latest));

      transport.receive(_origin, <String, Object?>{
        ...init(width: 999, fonts: <Object?>['malformed']),
        'frame': <String, Object?>{'w': double.nan, 'h': 844.0},
      });
      expect(transport.sent.last.payload['type'], 'protocolError');
      expect(initializations, hasLength(2));
      expect(server.latestInitialization, same(latest));
    });

    test('1c. rejects empty engine facts and invalid protocol version sets',
        () {
      expect(
        () => RenderEngine(flutterVersion: '', renderer: 'canvaskit'),
        throwsArgumentError,
      );
      expect(
        () => RenderEngine(flutterVersion: '3.41.0', renderer: ''),
        throwsArgumentError,
      );
      expect(
        () => RenderProtocolServer(
          transport: FakeRenderMessageTransport(),
          manifest: RenderBundleManifest.fromJson(_manifest()),
          engine: RenderEngine(
            flutterVersion: '3.41.0',
            renderer: 'canvaskit',
          ),
          supportedVersions: const <int>[],
          scheduleFrame: frames.schedule,
          initialize: (_) {},
          render: (_) async => BundleRenderResult(),
        ),
        throwsArgumentError,
      );
      expect(
        () => RenderProtocolServer(
          transport: FakeRenderMessageTransport(),
          manifest: RenderBundleManifest.fromJson(_manifest()),
          engine: RenderEngine(
            flutterVersion: '3.41.0',
            renderer: 'canvaskit',
          ),
          supportedVersions: const <int>[0, 1],
          scheduleFrame: frames.schedule,
          initialize: (_) {},
          render: (_) async => BundleRenderResult(),
        ),
        throwsArgumentError,
      );
    });

    test('2. drops a late stale render and suppresses stale completion',
        () async {
      receiveRender(2);
      receiveRender(3);
      results[3]!.complete(BundleRenderResult());
      await pumpEventQueue();
      results[2]!.complete(BundleRenderResult());
      await pumpEventQueue();
      receiveRender(2);
      expect(requests.map((request) => request.epoch), <int>[2, 3]);
      expect(
        transport.sent
            .where((message) => message.payload['type'] == 'settled')
            .map(
              (message) => message.payload['epoch'],
            ),
        <int>[3],
      );
    });

    test('3. emits settled before geometry zero and increasing generations',
        () async {
      receiveRender(1);
      results[1]!.complete(BundleRenderResult());
      await pumpEventQueue();
      server.publishGeometry(
        1,
        const <String, Rect>{
          '["main"]': Rect.fromLTWH(0, 0, 1, 1),
        },
      );
      frames.flush();
      expect(
        transport.sent.map((message) => message.payload['type']),
        <String>['ready', 'settled', 'geometry', 'geometry'],
      );
      expect(transport.sent[2].payload['generation'], 0);
      expect(transport.sent[3].payload['generation'], 1);
    });

    test('4. renderError terminates the epoch', () async {
      receiveRender(1);
      results[1]!.completeError(const BundleRenderFailure('bad input'));
      await pumpEventQueue();
      server.publishGeometry(1, const <String, Rect>{});
      frames.flush();
      expect(
        transport.sent
            .where((message) => message.payload['type'] == 'renderError'),
        hasLength(1),
      );
      expect(
        transport.sent
            .where((message) => message.payload['type'] == 'geometry'),
        isEmpty,
      );
      expect(
        transport.sent.where((message) => message.payload['type'] == 'settled'),
        isEmpty,
      );
    });

    test(
        '4b. a post-settle failure terminates once and suppresses later output',
        () async {
      receiveRender(1);
      results[1]!.complete(BundleRenderResult());
      await pumpEventQueue();
      expect(
        transport.sent.map((message) => message.payload['type']),
        <String>['ready', 'settled', 'geometry'],
      );

      server.reportRenderFailure(
        1,
        const BundleRenderFailure('late rebuild failed'),
      );
      server.reportRenderFailure(
        1,
        const BundleRenderFailure('duplicate late failure'),
      );
      server.publishGeometry(1, const <String, Rect>{});
      frames.flush();

      expect(
        transport.sent.map((message) => message.payload['type']),
        <String>['ready', 'settled', 'geometry', 'renderError'],
      );
      expect(
        transport.sent
            .where((message) => message.payload['type'] == 'renderError'),
        hasLength(1),
      );
    });

    test('5. receives environment changes on distinct settled render epochs',
        () async {
      receiveRender(1, env: _env());
      results[1]!.complete(BundleRenderResult());
      await pumpEventQueue();
      receiveRender(2, env: _env(brightness: 'dark'));
      results[2]!.complete(BundleRenderResult());
      await pumpEventQueue();
      expect(requests.map((request) => request.epoch), <int>[1, 2]);
      expect(requests.map((request) => request.env.brightness),
          <String>['light', 'dark']);
      expect(
        transport.sent
            .where((message) => message.payload['type'] == 'settled')
            .map((message) => message.payload['epoch']),
        <int>[1, 2],
      );
    });

    test('6. ignores unknown message types and fields', () {
      transport.receive(_origin, <String, Object?>{
        'type': 'future-nonsense',
        'newField': true,
      });
      transport.receive(_origin, <String, Object?>{
        'v': 1,
        'type': 'render',
        'epoch': 1,
        'blob': encodeRenderBlob(Uint8List(0)),
        'data': <String, Object?>{},
        'env': _env().toJson(),
        'newField': true,
      });
      expect(requests, hasLength(1));
      expect(
          transport.sent
              .where((message) => message.payload['type'] == 'protocolError'),
          isEmpty);
    });

    test('7. locks independently on first fully valid supported init or render',
        () async {
      const attacker = 'https://attacker.example';
      final invalidInitMessages = <Map<String, Object?>>[
        <String, Object?>{
          'v': 7,
          'type': 'init',
          'protocol': 7,
          'frame': <String, Object?>{'w': 390.0, 'h': 844.0},
        },
        <String, Object?>{
          'v': 1,
          'type': 'init',
          'protocol': 2,
          'frame': <String, Object?>{'w': 390.0, 'h': 844.0},
        },
        <String, Object?>{
          'v': 1,
          'type': 'init',
          'protocol': 1,
          'frame': <String, Object?>{'w': 0.0, 'h': 844.0},
        },
        <String, Object?>{
          'v': 1,
          'type': 'init',
          'protocol': 1,
          'frame': <String, Object?>{'w': double.nan, 'h': 844.0},
        },
        <String, Object?>{
          'v': 1,
          'type': 'init',
          'protocol': 1,
          'frame': <String, Object?>{'w': 390.0, 'h': double.infinity},
        },
        <String, Object?>{
          'v': 1,
          'type': 'init',
          'protocol': 1,
          'frame': <String, Object?>{'w': 390.0, 'h': 844.0},
          'prewarm': <String, Object?>{
            'fontUrls': <Object?>['https://example.test/font.woff2', 7],
          },
        },
      ];
      for (final message in invalidInitMessages) {
        transport.receive(attacker, message);
        expect(server.lockedOrigin, isNull);
      }
      transport.receive(attacker, <String, Object?>{
        'v': 7,
        'type': 'render',
        'epoch': 1,
        'blob': encodeRenderBlob(Uint8List(0)),
        'data': <String, Object?>{},
        'env': _env().toJson(),
      });
      expect(server.lockedOrigin, isNull);

      transport.receive(_origin, <String, Object?>{
        'v': 2,
        'type': 'init',
        'protocol': 2,
        'frame': <String, Object?>{'w': 390.0, 'h': 844.0},
        'prewarm': <String, Object?>{
          'fontUrls': <Object?>['https://example.test/font.woff2'],
        },
      });
      expect(server.lockedOrigin, _origin);
      final repliesBeforeWrongOrigin = transport.sent.length;
      receiveRender(1, origin: attacker);
      expect(requests, isEmpty);
      expect(transport.sent, hasLength(repliesBeforeWrongOrigin));

      final renderTransport = FakeRenderMessageTransport();
      final renderRequests = <RenderRequest>[];
      final renderResults = <int, Completer<BundleRenderResult>>{};
      final renderServer = RenderProtocolServer(
        transport: renderTransport,
        manifest: RenderBundleManifest.fromJson(_manifest()),
        engine: RenderEngine(
          flutterVersion: '3.41.0',
          renderer: 'canvaskit',
        ),
        supportedVersions: const <int>[1, 2],
        scheduleFrame: frames.schedule,
        initialize: (_) {},
        render: (request) {
          renderRequests.add(request);
          return (renderResults[request.epoch] =
                  Completer<BundleRenderResult>())
              .future;
        },
      )..start();
      renderTransport.receive('https://render.example', <String, Object?>{
        'v': 2,
        'type': 'render',
        'epoch': 1,
        'blob': encodeRenderBlob(Uint8List.fromList(<int>[1, 2, 3])),
        'data': <String, Object?>{'title': 'Preview'},
        'env': _env().toJson(),
      });
      expect(renderServer.lockedOrigin, 'https://render.example');
      expect(renderRequests, hasLength(1));
      renderTransport.receive('https://render.example', <String, Object?>{
        'v': 1,
        'type': 'init',
        'protocol': 1,
        'frame': <String, Object?>{'w': 390.0, 'h': 844.0},
      });
      expect(renderTransport.sent.last.payload['type'], 'protocolError');
      expect(renderTransport.sent.last.payload['v'], 2);
      renderTransport.receive('https://render.example', <String, Object?>{
        'v': 1,
        'type': 'render',
        'epoch': 2,
        'blob': encodeRenderBlob(Uint8List.fromList(<int>[1, 2, 3])),
        'data': <String, Object?>{'title': 'Preview'},
        'env': _env().toJson(),
      });
      expect(renderTransport.sent.last.payload['type'], 'protocolError');
      expect(renderTransport.sent.last.payload['v'], 2);
      expect(renderRequests, hasLength(1));
      renderTransport.receive('https://render.example', <String, Object?>{
        'v': 2,
        'type': 'render',
        'epoch': 2,
        'blob': encodeRenderBlob(Uint8List.fromList(<int>[1, 2, 3])),
        'data': <String, Object?>{'title': 'Preview'},
        'env': _env().toJson(),
      });
      expect(renderRequests, hasLength(2));
      renderResults[2]!.complete(BundleRenderResult());
      await pumpEventQueue();
      expect(
        renderTransport.sent
            .where((message) => const <String>{'settled', 'geometry'}
                .contains(message.payload['type']))
            .map((message) => message.payload['v']),
        <int>[2, 2],
      );
      await renderServer.dispose();
    });

    test('8. recursively gates and round-trips the complete render envelope',
        () {
      for (final testCase
          in _credentialKeySecurityOracle.where((entry) => entry.rejected)) {
        for (final location in <String>['data', 'theme']) {
          final env = _env().toJson();
          if (location == 'theme') {
            env['theme'] = <String, Object?>{
              'outer': <Object?>[
                <String, Object?>{testCase.key: 'not allowed'},
              ],
            };
          }
          transport.receive(_origin, <String, Object?>{
            'v': 1,
            'type': 'render',
            'epoch': 1,
            'blob': encodeRenderBlob(Uint8List(0)),
            'data': location == 'data'
                ? <String, Object?>{
                    'outer': <Object?>[
                      <String, Object?>{testCase.key: 'not allowed'},
                    ],
                  }
                : <String, Object?>{},
            'env': env,
          });
          expect(requests, isEmpty,
              reason: '$location.${testCase.key} must be rejected');
          expect(server.lockedOrigin, isNull);
          expect(transport.sent.last.payload['type'], 'protocolError');
        }
      }

      for (final field in _credentialFieldNames) {
        for (final location in <String>['data', 'theme']) {
          final env = _env().toJson();
          if (location == 'theme') {
            env['theme'] = <String, Object?>{
              'nested': <Object?>[
                <String, Object?>{field: 'not allowed'},
              ],
            };
          }
          transport.receive(_origin, <String, Object?>{
            'v': 1,
            'type': 'render',
            'epoch': 1,
            'blob': encodeRenderBlob(Uint8List(0)),
            'data': location == 'data'
                ? <String, Object?>{
                    'nested': <Object?>[
                      <String, Object?>{field: 'not allowed'},
                    ],
                  }
                : <String, Object?>{},
            'env': env,
          });
          expect(requests, isEmpty,
              reason: '$location.$field must be rejected');
          expect(server.lockedOrigin, isNull);
          expect(transport.sent.last.payload['type'], 'protocolError');
        }
      }

      for (final value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        for (final location in <String>['data', 'theme']) {
          final env = _env().toJson();
          if (location == 'theme') {
            env['theme'] = <String, Object?>{
              'nested': <Object?>[
                <String, Object?>{'value': value},
              ],
            };
          }
          transport.receive(_origin, <String, Object?>{
            'v': 1,
            'type': 'render',
            'epoch': 1,
            'blob': encodeRenderBlob(Uint8List(0)),
            'data': location == 'data'
                ? <String, Object?>{
                    'nested': <Object?>[
                      <String, Object?>{'value': value},
                    ],
                  }
                : <String, Object?>{},
            'env': env,
          });
          expect(requests, isEmpty,
              reason: '$location.$value must be rejected');
          expect(server.lockedOrigin, isNull);
          expect(transport.sent.last.payload['type'], 'protocolError');
        }
      }

      final acceptedEnv = RenderEnv(
        theme: _acceptedTheme(),
        brightness: 'light',
        locale: 'en-US',
        textScale: 1,
        zoom: 1,
        frame: const Size(390, 844),
      );
      final acceptedBlob = Uint8List.fromList(<int>[0, 127, 128, 255]);
      transport.receive(
          _origin,
          _wireRoundTrip(<String, Object?>{
            'v': 2,
            'type': 'render',
            'epoch': 2,
            'blob': encodeRenderBlob(acceptedBlob),
            'data': _acceptedData(),
            'env': acceptedEnv.toJson(),
          }));

      final request = requests.single;
      expect(request.epoch, 2);
      expect(request.blob, acceptedBlob);
      expect(request.data, _acceptedData());
      expect(request.env.toJson(), acceptedEnv.toJson());
      for (final message in transport.sent) {
        _expectNoCredentialFields(message.payload);
      }
    });

    test('8b. render result snapshots diagnostics, geometry, and timings', () {
      final diagnostics = <RenderDiagnostic>[
        RenderDiagnostic(severity: 'warning', message: 'check this'),
      ];
      final geometry = <String, Rect>{
        '["main"]': const Rect.fromLTWH(0, 0, 10, 10),
      };
      final timings = <String, Object?>{
        'phases': <Object?>[
          <String, Object?>{'name': 'build', 'millis': 3},
        ],
      };
      final result = BundleRenderResult(
        diagnostics: diagnostics,
        geometry: geometry,
        timings: timings,
      );

      diagnostics.clear();
      geometry.clear();
      (timings['phases']! as List<Object?>).clear();
      expect(result.diagnostics, hasLength(1));
      expect(result.geometry, contains('["main"]'));
      expect(result.timings!['phases'], hasLength(1));
      expect(() => result.diagnostics.clear(), throwsUnsupportedError);
      expect(() => result.geometry.clear(), throwsUnsupportedError);
      expect(
        () => ((result.timings!['phases']! as List<Object?>).single
            as Map<String, Object?>)['millis'] = 99,
        throwsUnsupportedError,
      );
    });

    test('9. decodes base64 blobs byte-identically', () {
      final bytes = Uint8List.fromList(<int>[0, 127, 128, 255]);
      receiveRender(1, blob: bytes);
      expect(requests.single.blob, bytes);
    });

    test('10. coalesces N geometry mutations to one emission per frame',
        () async {
      receiveRender(1);
      results[1]!.complete(BundleRenderResult());
      await pumpEventQueue();
      for (final width in <double>[1, 2, 3]) {
        server.publishGeometry(
          1,
          <String, Rect>{'["main"]': Rect.fromLTWH(0, 0, width, 1)},
        );
      }
      expect(
        transport.sent
            .where((message) => message.payload['type'] == 'geometry'),
        hasLength(1),
      );
      frames.flush();
      final geometry = transport.sent
          .where((message) => message.payload['type'] == 'geometry')
          .toList();
      expect(geometry, hasLength(2));
      expect(geometry.last.payload['generation'], 1);
      expect(
        ((geometry.last.payload['rects']! as Map<String, Object?>)['["main"]']!
            as List<Object?>)[2],
        3,
      );
    });

    test('11. validates initialization and every outbound geometry boundary',
        () async {
      for (final frame in <Size>[
        const Size(0, 844),
        const Size(-1, 844),
        const Size(double.nan, 844),
        const Size(390, double.infinity),
      ]) {
        expect(
          () => BundleInitialization(frame: frame, fontUrls: const <String>[]),
          throwsArgumentError,
          reason: '$frame must be rejected',
        );
      }

      final invalidRects = <Rect>[
        const Rect.fromLTWH(double.nan, 0, 1, 1),
        const Rect.fromLTWH(0, double.infinity, 1, 1),
        const Rect.fromLTWH(0, 0, -1, 1),
        const Rect.fromLTWH(0, 0, 1, -1),
      ];
      for (final rect in invalidRects) {
        expect(
          () => BundleRenderResult(
            geometry: <String, Rect>{'["main"]': rect},
          ),
          throwsArgumentError,
          reason: '$rect must be rejected',
        );
      }

      for (final geometry in <Map<String, Rect>>[
        const <String, Rect>{
          'not-json': Rect.fromLTWH(0, 0, 1, 1),
        },
        const <String, Rect>{
          '[ "main" ]': Rect.fromLTWH(0, 0, 1, 1),
        },
        const <String, Rect>{
          '["main"]': Rect.fromLTWH(0, 0, 1, 1),
          '[ "main" ]': Rect.fromLTWH(0, 0, 1, 1),
        },
      ]) {
        expect(
          () => BundleRenderResult(geometry: geometry),
          throwsArgumentError,
          reason: '$geometry must reject malformed or duplicate identities',
        );
      }

      receiveRender(1);
      results[1]!.complete(
        BundleRenderResult(
          geometry: const <String, Rect>{
            '["main"]': Rect.fromLTWH(-10, -20, 0, 0),
          },
        ),
      );
      await pumpEventQueue();
      final sentBeforeInvalid = transport.sent.length;
      for (final rect in invalidRects) {
        expect(
          () => server.publishGeometry(
            1,
            <String, Rect>{'["main"]': rect},
          ),
          throwsArgumentError,
          reason: '$rect must be rejected',
        );
      }
      for (final geometry in <Map<String, Rect>>[
        const <String, Rect>{
          'not-json': Rect.fromLTWH(0, 0, 1, 1),
        },
        const <String, Rect>{
          '[ "main" ]': Rect.fromLTWH(0, 0, 1, 1),
        },
        const <String, Rect>{
          '["main"]': Rect.fromLTWH(0, 0, 1, 1),
          '[ "main" ]': Rect.fromLTWH(0, 0, 1, 1),
        },
      ]) {
        expect(
          () => server.publishGeometry(1, geometry),
          throwsArgumentError,
          reason: '$geometry must reject malformed or duplicate identities',
        );
      }
      frames.flush();
      expect(transport.sent, hasLength(sentBeforeInvalid));

      server.publishGeometry(
        1,
        const <String, Rect>{
          '["main"]': Rect.fromLTWH(-30, -40, 0, 0),
        },
      );
      frames.flush();
      final geometry = transport.sent
          .where((message) => message.payload['type'] == 'geometry')
          .toList();
      expect(geometry, hasLength(2));
      expect(
        (geometry.last.payload['rects']! as Map<String, Object?>)['["main"]'],
        <double>[-30, -40, 0, 0],
      );

      receiveRender(2);
      final sentBeforeStale = transport.sent.length;
      expect(
        () => server.publishGeometry(
          1,
          <String, Rect>{'["main"]': invalidRects.first},
        ),
        returnsNormally,
      );
      frames.flush();
      expect(transport.sent, hasLength(sentBeforeStale));
    });
  });
}
