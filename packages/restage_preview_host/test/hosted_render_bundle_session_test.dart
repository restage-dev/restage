import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_preview_host/restage_preview_host.dart';

const _bundleOrigin = 'https://bundles.example.test';

Map<String, Object?> _ready({List<String>? capabilities}) => <String, Object?>{
      'type': 'ready',
      'protocolVersions': <int>[1],
      if (capabilities != null) 'capabilities': capabilities,
      'manifest': <String, Object?>{
        'formatVersion': 1,
        'catalog': <String, Object?>{
          'libraries': <String, Object?>{},
          'widgets': <Object?>[],
        },
      },
      'engine': <String, Object?>{
        'flutterVersion': '3.41.0',
        'renderer': 'canvaskit',
      },
    };

Map<String, Object?> _settled(int epoch) => <String, Object?>{
      'v': 1,
      'type': 'settled',
      'epoch': epoch,
      'diagnostics': <Object?>[],
    };

Map<String, Object?> _surfaceEvent(int epoch, String name) => <String, Object?>{
      'v': 1,
      'type': 'event',
      'epoch': epoch,
      'name': name,
      'arguments': const <String, Object?>{},
    };

Map<String, Object?> _renderError(int epoch) => <String, Object?>{
      'v': 1,
      'type': 'renderError',
      'epoch': epoch,
      'message': 'Render failed.',
    };

RenderRequest _request(int epoch) => RenderRequest(
      epoch: epoch,
      blob: Uint8List.fromList(<int>[1, 2, 3]),
      data: const <String, Object?>{},
      env: RenderEnv(
        theme: const <String, Object?>{},
        brightness: 'light',
        locale: 'en-US',
        textScale: 1,
        zoom: 1,
        frame: const Size(390, 844),
      ),
    );

void main() {
  test('hosted session delegates frame lifecycle and owns one provider',
      () async {
    final frame = _FakeHostedFrame();
    final session = HostedRenderBundleSession(
      frame: frame,
      bundleOrigin: Uri.parse(_bundleOrigin),
      scheduleFrame: (callback) => callback(),
    );

    expect(session.view, same(frame.view));
    expect(session.provider, isA<RenderHostProvider>());
    session.concealPixels();
    session.revealPixels();
    session.setRasterScale(2);
    session.emergencyRemovePixels();
    expect(frame.calls, ['conceal', 'reveal', 'scale:2.0', 'remove']);

    await session.dispose();
    await session.dispose();
    expect(frame.disposeCalls, 1);
  });

  test('an interactive session refuses to mount a bundle that cannot mount',
      () async {
    final frame = _FakeHostedFrame();
    final session = _interactiveSession(frame);
    addTearDown(session.dispose);

    frame.receive(_ready());
    await session.ready;

    await expectLater(
      session.mount(_request(1)),
      throwsA(isA<RenderMountUnsupported>()),
    );
    expect(frame.sent, isEmpty);
    expect(session.interactive, isFalse);
    expect(frame.calls, isEmpty);
  });

  test('input follows the mounted, settled and revealed surface', () async {
    final frame = _FakeHostedFrame();
    final session = _interactiveSession(frame);
    addTearDown(session.dispose);

    frame.receive(_ready(capabilities: const <String>['mount']));
    await session.ready;
    await session.mount(_request(1));

    expect(frame.sent.single['type'], 'mount');
    expect(
      session.interactive,
      isFalse,
      reason: 'a mounted surface takes input only once it has painted',
    );

    frame.receive(_settled(1));
    expect(
      session.interactive,
      isFalse,
      reason: 'concealed pixels cannot be touched',
    );

    session.revealPixels();
    expect(session.interactive, isTrue);

    session.concealPixels();
    expect(session.interactive, isFalse);

    session.revealPixels();
    expect(
      session.interactive,
      isTrue,
      reason: 'revealing the same settled mount restores input',
    );

    expect(frame.calls, <String>[
      'send:mount',
      'reveal',
      'interactive:true',
      'interactive:false',
      'conceal',
      'reveal',
      'interactive:true',
    ]);
  });

  test('a newer mount withdraws input before it is sent', () async {
    final frame = _FakeHostedFrame();
    final session = _interactiveSession(frame);
    addTearDown(session.dispose);

    frame.receive(_ready(capabilities: const <String>['mount']));
    await session.ready;
    await session.mount(_request(1));
    frame.receive(_settled(1));
    session.revealPixels();
    expect(session.interactive, isTrue);

    await session.mount(_request(2));
    expect(
      session.interactive,
      isFalse,
      reason: 'epoch 1 pixels must not take input meant for epoch 2',
    );
    expect(
      frame.calls.sublist(frame.calls.indexOf('interactive:true')),
      <String>['interactive:true', 'interactive:false', 'send:mount'],
      reason: 'input goes back before the newer mount leaves the shell',
    );

    frame.receive(_settled(2));
    expect(session.interactive, isTrue);
  });

  test('a render after a mount makes the frame inert again', () async {
    final frame = _FakeHostedFrame();
    final session = _interactiveSession(frame);
    addTearDown(session.dispose);

    frame.receive(_ready(capabilities: const <String>['mount']));
    await session.ready;
    await session.mount(_request(1));
    frame.receive(_settled(1));
    session.revealPixels();
    expect(session.interactive, isTrue);

    await session.render(_request(2));
    expect(session.interactive, isFalse);
    frame.receive(_settled(2));
    expect(session.interactive, isFalse);
    expect(
      frame.sent.map((payload) => payload['type']),
      <String>['mount', 'render'],
    );
  });

  test('a failure on the mounted epoch makes the frame inert', () async {
    final frame = _FakeHostedFrame();
    final session = _interactiveSession(frame);
    addTearDown(session.dispose);

    frame.receive(_ready(capabilities: const <String>['mount']));
    await session.ready;
    await session.mount(_request(1));
    frame.receive(_settled(1));
    session.revealPixels();
    expect(session.interactive, isTrue);

    frame.receive(_renderError(1));
    expect(session.interactive, isFalse);
    expect(frame.calls.last, 'interactive:false');
  });

  test('disposal takes input back and leaves it back', () async {
    final frame = _FakeHostedFrame();
    final session = _interactiveSession(frame);

    frame.receive(_ready(capabilities: const <String>['mount']));
    await session.ready;
    await session.mount(_request(1));
    frame.receive(_settled(1));
    session.revealPixels();
    expect(session.interactive, isTrue);

    await session.dispose();
    expect(session.interactive, isFalse);
    expect(frame.calls.contains('interactive:false'), isTrue);
    expect(frame.disposeCalls, 1);
  });

  test('a frame that refuses to go inert is asked again', () async {
    final frame = _FakeHostedFrame();
    final session = _interactiveSession(frame);
    addTearDown(session.dispose);

    frame.receive(_ready(capabilities: const <String>['mount']));
    await session.ready;
    await session.mount(_request(1));
    frame.receive(_settled(1));
    session.revealPixels();
    expect(session.interactive, isTrue);

    frame.failNextSetInteractive = true;
    expect(session.concealPixels, throwsStateError);
    expect(
      session.interactive,
      isTrue,
      reason: 'a refused change leaves the frame taking input, and says so',
    );

    session.concealPixels();
    expect(session.interactive, isFalse);
    expect(
      frame.calls.where((call) => call == 'interactive:false').length,
      1,
      reason: 'only the second attempt reached the frame',
    );
  });

  test('fired events are reported only while the surface takes input',
      () async {
    final frame = _FakeHostedFrame();
    final session = _interactiveSession(frame);
    addTearDown(session.dispose);
    final reported = <String>[];
    session.surfaceEvents.listen((event) => reported.add(event.name));
    final seen = <String>[];
    session.provider.events.listen((event) {
      if (event is MountedSurfaceEvent) seen.add(event.name);
    });

    frame.receive(_ready(capabilities: const <String>['mount']));
    await session.ready;
    await session.mount(_request(1));
    frame.receive(_settled(1));

    frame.receive(_surfaceEvent(1, 'while-concealed'));
    session.revealPixels();
    frame.receive(_surfaceEvent(1, 'while-visible'));
    session.concealPixels();
    frame.receive(_surfaceEvent(1, 'after-conceal'));

    expect(reported, <String>['while-visible']);
    expect(seen, <String>[
      'while-concealed',
      'while-visible',
      'after-conceal',
    ]);
  });

  test('a refused mount leaves the surface that is already there', () async {
    final frame = _FakeHostedFrame();
    final session = _interactiveSession(frame);
    addTearDown(session.dispose);
    final reported = <String>[];
    session.surfaceEvents.listen((event) => reported.add(event.name));

    frame.receive(_ready(capabilities: const <String>['mount']));
    await session.ready;
    await session.mount(_request(1));
    frame.receive(_settled(1));
    session.revealPixels();
    expect(session.interactive, isTrue);

    await expectLater(session.mount(_request(1)), throwsArgumentError);

    expect(
      session.interactive,
      isTrue,
      reason: 'nothing left the shell, so nothing about the surface changed',
    );
    frame.receive(_surfaceEvent(1, 'still-live'));
    expect(reported, <String>['still-live']);
  });

  test('a mounted surface cannot be rescaled under the viewer', () async {
    final frame = _FakeHostedFrame();
    final session = _interactiveSession(frame);
    addTearDown(session.dispose);

    frame.receive(_ready(capabilities: const <String>['mount']));
    await session.ready;
    session.setRasterScale(2);
    expect(frame.calls, contains('scale:2.0'));

    await session.mount(_request(1));
    expect(() => session.setRasterScale(3), throwsStateError);
    expect(frame.calls, isNot(contains('scale:3.0')));

    await session.render(_request(2));
    session.setRasterScale(3);
    expect(frame.calls, contains('scale:3.0'));
  });

  test('removing pixels in an emergency drops the surface with them', () async {
    final frame = _FakeHostedFrame();
    final session = _interactiveSession(frame);
    addTearDown(session.dispose);
    final reported = <String>[];
    session.surfaceEvents.listen((event) => reported.add(event.name));

    frame.receive(_ready(capabilities: const <String>['mount']));
    await session.ready;
    await session.mount(_request(1));
    frame.receive(_settled(1));
    session.revealPixels();
    expect(session.interactive, isTrue);

    session.emergencyRemovePixels();
    expect(session.interactive, isFalse);

    frame.receive(_surfaceEvent(1, 'after-removal'));
    session.revealPixels();
    expect(
      session.interactive,
      isFalse,
      reason: 'the surface is gone rather than hidden',
    );
    expect(reported, isEmpty);
  });

  test('an event after disposal reaches nobody', () async {
    final frame = _FakeHostedFrame();
    final session = _interactiveSession(frame);
    final reported = <String>[];
    session.surfaceEvents.listen((event) => reported.add(event.name));

    frame.receive(_ready(capabilities: const <String>['mount']));
    await session.ready;
    await session.mount(_request(1));
    frame.receive(_settled(1));
    session.revealPixels();
    frame.receive(_surfaceEvent(1, 'while-visible'));
    expect(session.interactive, isTrue);

    frame.failNextSetInteractive = true;
    final disposing = session.dispose();
    frame.receive(_surfaceEvent(1, 'after-dispose'));
    await disposing;

    expect(
      session.interactive,
      isFalse,
      reason: 'a frame that refused the last change is still torn down',
    );
    expect(reported, <String>['while-visible']);
  });

  test('bootstrap accepts only exact-origin URL and redacts its grant', () {
    final bootstrap = HostedRenderBundleBootstrap(
      renderBundleId: 7,
      bootstrapUrl: Uri.parse(
        'https://bundles.example.test/render-bundles/v1/b/7/bootstrap',
      ),
      bootstrapGrant: 'a' * 64,
      expiresAt: DateTime.utc(2030),
    );

    expect(bootstrap.bundleOrigin, Uri.parse('https://bundles.example.test'));
    expect(bootstrap.toString(), isNot(contains('aaaa')));
    expect(
      () => HostedRenderBundleBootstrap(
        renderBundleId: 7,
        bootstrapUrl: Uri.parse(
          'https://bundles.example.test/render-bundles/v1/b/7/bootstrap?x=1',
        ),
        bootstrapGrant: 'a' * 64,
        expiresAt: DateTime.utc(2030),
      ),
      throwsArgumentError,
    );
    expect(
      HostedRenderBundleBootstrap(
        renderBundleId: 7,
        bootstrapUrl: Uri.parse(
          'http://127.0.0.1:8081/render-bundles/v1/b/7/bootstrap',
        ),
        bootstrapGrant: 'a' * 64,
        expiresAt: DateTime.utc(2030),
      ).bundleOrigin,
      Uri.parse('http://127.0.0.1:8081'),
    );
    for (final unsafe in <String>[
      'http://bundles.example.test/render-bundles/v1/b/7/bootstrap',
      'https://bundles.example.test:8443/render-bundles/v1/b/7/bootstrap',
      'https://user@bundles.example.test/render-bundles/v1/b/7/bootstrap',
    ]) {
      expect(
        () => HostedRenderBundleBootstrap(
          renderBundleId: 7,
          bootstrapUrl: Uri.parse(unsafe),
          bootstrapGrant: 'a' * 64,
          expiresAt: DateTime.utc(2030),
        ),
        throwsArgumentError,
        reason: unsafe,
      );
    }
  });

  test('session origin accepts deployed HTTPS or exact loopback HTTP only', () {
    for (final trusted in <String>[
      'https://bundles.example.test',
      'http://localhost:8081',
      'http://127.0.0.1:8081',
    ]) {
      final frame = _FakeHostedFrame();
      final session = HostedRenderBundleSession(
        frame: frame,
        bundleOrigin: Uri.parse(trusted),
        scheduleFrame: (callback) => callback(),
      );
      expect(session.provider, isA<RenderHostProvider>(), reason: trusted);
      unawaited(session.dispose());
    }
    for (final unsafe in <String>[
      'http://bundles.example.test',
      'https://bundles.example.test:8443',
      'https://user@bundles.example.test',
      'https://bundles.example.test/path',
      'https://bundles.example.test?query=1',
      'https://bundles.example.test#fragment',
    ]) {
      expect(
        () => HostedRenderBundleSession(
          frame: _FakeHostedFrame(),
          bundleOrigin: Uri.parse(unsafe),
          scheduleFrame: (callback) => callback(),
        ),
        throwsArgumentError,
        reason: unsafe,
      );
    }
  });

  test('polling codec is injection-safe and rejects credential keys', () {
    final key = PreviewShellSessionKey(generation: 3, nonce: 'b' * 32);
    final bootstrap = HostedRenderBundleBootstrap(
      renderBundleId: 7,
      bootstrapUrl: Uri.parse(
        'https://bundles.example.test/render-bundles/v1/b/7/bootstrap',
      ),
      bootstrapGrant: 'a' * 64,
      expiresAt: DateTime.utc(2030),
    );
    final invocation = PreviewShellBridgeCodec.bootstrapInvocation(
      key: key,
      bootstrap: bootstrap,
    );
    expect(
      invocation,
      startsWith(
        'window.RestagePreviewBridge.bootstrap('
        'window.RestagePreviewBridge.decode("',
      ),
    );
    expect(invocation, isNot(contains('a' * 64)));

    for (final forbidden in [
      'accessToken',
      'authorizationHeader',
      'sessionKey'
    ]) {
      expect(
        () => PreviewShellBridgeCodec.acceptInvocation(
          key: key,
          targetOrigin: bootstrap.bundleOrigin.origin,
          payload: <String, Object?>{
            'nested': <String, Object?>{forbidden: 'value'},
          },
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => PreviewShellBridgeCodec.acceptInvocation(
        key: key,
        targetOrigin: bootstrap.bundleOrigin.origin,
        payload: const <String, Object?>{
          'tokenization': true,
          'cookiePolicy': 'strict',
          'authorizationStatus': 'none',
          'dashboardStatement': 'safe',
        },
      ),
      returnsNormally,
    );
  });

  test('polling codec preserves Unicode through strict UTF-8 base64', () {
    final key = PreviewShellSessionKey(generation: 3, nonce: 'b' * 32);
    final invocation = PreviewShellBridgeCodec.acceptInvocation(
      key: key,
      targetOrigin: 'https://bundles.example.test',
      payload: const <String, Object?>{
        'label': 'Crème brûlée 👋',
        'path': r'$.slides["日本語"]',
      },
    );
    final encoded = RegExp(r'decode\("([A-Za-z0-9+/=]+)"\)')
        .firstMatch(invocation)!
        .group(1)!;
    final command =
        jsonDecode(utf8.decode(base64Decode(encoded), allowMalformed: false))
            as Map<String, Object?>;
    final payload = command['payload']! as Map<String, Object?>;

    expect(payload['label'], 'Crème brûlée 👋');
    expect(payload['path'], r'$.slides["日本語"]');
  });

  test('polling codec validates session, origin, and lifecycle ordering', () {
    final key = PreviewShellSessionKey(generation: 3, nonce: 'b' * 32);
    final events = PreviewShellBridgeCodec.decodeDrain(
      '[{"kind":"submitted","generation":3,"nonce":"${'b' * 32}"},'
      '{"kind":"loaded","generation":3,"nonce":"${'b' * 32}"},'
      '{"kind":"message","generation":3,"nonce":"${'b' * 32}",'
      '"origin":"https://bundles.example.test","payload":{"v":1}}]',
      key: key,
      bundleOrigin: 'https://bundles.example.test',
    );
    expect(events[0], isA<PreviewShellSubmitted>());
    expect(events[1], isA<PreviewShellLoaded>());
    expect(events[2], isA<PreviewShellMessage>());
  });
}

InteractiveHostedRenderBundleSession _interactiveSession(
  _FakeHostedFrame frame,
) =>
    InteractiveHostedRenderBundleSession(
      frame: frame,
      bundleOrigin: Uri.parse(_bundleOrigin),
      scheduleFrame: (callback) => callback(),
    );

final class _FakeHostedFrame
    implements InteractiveHostedRenderBundleFrame, RenderMessageTransport {
  final List<String> calls = [];
  final List<Map<String, Object?>> sent = [];
  final StreamController<RenderTransportMessage> _messages =
      StreamController<RenderTransportMessage>.broadcast(sync: true);
  int disposeCalls = 0;

  void receive(Map<String, Object?> payload) {
    _messages.add(
      RenderTransportMessage(origin: _bundleOrigin, payload: payload),
    );
  }

  @override
  Widget get view => const SizedBox();

  @override
  RenderMessageTransport get transport => this;

  @override
  Future<void> get bootstrapSubmitted => Future<void>.value();

  @override
  Future<void> get loaded => Future<void>.value();

  @override
  Stream<RenderTransportMessage> get messages => _messages.stream;

  @override
  void concealPixels() => calls.add('conceal');

  @override
  void revealPixels() => calls.add('reveal');

  @override
  void setRasterScale(double scale) => calls.add('scale:$scale');

  @override
  void emergencyRemovePixels() => calls.add('remove');

  bool failNextSetInteractive = false;

  @override
  void setInteractive(bool interactive) {
    if (failNextSetInteractive) {
      failNextSetInteractive = false;
      throw StateError('the frame refused the change');
    }
    calls.add('interactive:$interactive');
  }

  @override
  void send(Map<String, Object?> payload, {required String targetOrigin}) {
    sent.add(payload);
    calls.add('send:${payload['type']}');
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _messages.close();
  }
}
