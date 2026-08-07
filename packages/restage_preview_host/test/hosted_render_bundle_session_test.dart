import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_preview_host/restage_preview_host.dart';

void main() {
  test('hosted session delegates frame lifecycle and owns one provider',
      () async {
    final frame = _FakeHostedFrame();
    final session = HostedRenderBundleSession(
      frame: frame,
      bundleOrigin: Uri.parse('https://bundles.example.test'),
      scheduleFrame: (callback) => callback(),
    );

    expect(session.view, same(frame.view));
    expect(session.provider, isA<SeamRenderProvider>());
    session.concealPixels();
    session.revealPixels();
    session.setRasterScale(2);
    session.emergencyRemovePixels();
    expect(frame.calls, ['conceal', 'reveal', 'scale:2.0', 'remove']);

    await session.dispose();
    await session.dispose();
    expect(frame.disposeCalls, 1);
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
      expect(session.provider, isA<SeamRenderProvider>(), reason: trusted);
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

final class _FakeHostedFrame
    implements HostedRenderBundleFrame, RenderMessageTransport {
  final List<String> calls = [];
  final StreamController<RenderTransportMessage> _messages =
      StreamController<RenderTransportMessage>.broadcast();
  int disposeCalls = 0;

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

  @override
  void send(Map<String, Object?> payload, {required String targetOrigin}) {}

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _messages.close();
  }
}
