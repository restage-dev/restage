@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage_preview_harness/src/browser_render_message_transport_web.dart'
    as browser_transport;
import 'package:restage_preview_host/restage_preview_host.dart';
import 'package:web/web.dart' as web;

@JS('Object.is')
external bool _isSameJsObject(JSAny? first, JSAny? second);

RenderBundleManifest _manifest() => RenderBundleManifest(
      formatVersion: 1,
      catalog: const <String, Object?>{
        'schemaVersion': 4,
        'libraries': <String, Object?>{},
        'widgets': <Object?>[],
      },
    );

void _dispatch({
  required String origin,
  required JSAny? data,
  web.MessageEventSource? source,
}) {
  web.window.dispatchEvent(
    web.MessageEvent(
      'message',
      web.MessageEventInit(origin: origin, source: source, data: data),
    ),
  );
}

Map<String, Object?> _nestedObject(int depth) {
  Object? value = 'leaf';
  for (var index = 0; index < depth; index += 1) {
    value = <String, Object?>{'child': value};
  }
  return value! as Map<String, Object?>;
}

JSObject _nonFinitePayload(double value) {
  final nested = JSObject()..setProperty('value'.toJS, value.toJS);
  return JSObject()..setProperty('nested'.toJS, nested);
}

Map<String, Object?> _numericEdges() => <String, Object?>{
      'fractional': 1.25,
      'negativeZero': -0.0,
      'largePositive': 1e100,
      'largeNegative': -1e100,
      'maxSafe': 9007199254740991.0,
      'minSafe': -9007199254740991.0,
      'aboveSafe': 9007199254740992.0,
      'belowSafe': -9007199254740992.0,
    };

void _expectNumericEdges(Map<String, Object?> values) {
  expect(values['fractional'], 1.25);
  expect(values['fractional'], isA<double>());

  final negativeZero = values['negativeZero']! as double;
  expect(negativeZero.isNegative, isTrue);
  expect(1.0 / negativeZero, double.negativeInfinity);

  expect(values['largePositive'], 1e100);
  expect(values['largePositive'], isA<double>());
  expect(values['largeNegative'], -1e100);
  expect(values['largeNegative'], isA<double>());

  expect(values['maxSafe'], 9007199254740991);
  expect(values['maxSafe'], isA<int>());
  expect(values['minSafe'], -9007199254740991);
  expect(values['minSafe'], isA<int>());

  expect(values['aboveSafe'], 9007199254740992.0);
  expect(values['aboveSafe'], isA<double>());
  expect(values['belowSafe'], -9007199254740992.0);
  expect(values['belowSafe'], isA<double>());
}

void main() {
  group('browser render message transport', () {
    test('rejects every non-canonical parent origin before listener creation',
        () {
      const invalid = <String>[
        '',
        '*',
        'https://shell.example/',
        'https://shell.example/path',
        'https://user@shell.example',
        'javascript:alert(1)',
      ];
      for (final origin in invalid) {
        var listenerInstalled = false;
        expect(
          () => browser_transport.createBrowserRenderMessageTransportForTest(
            parentOrigin: origin,
            hooks: browser_transport.BrowserRenderMessageTransportWebHooks(
              onListenerInstalled: () => listenerInstalled = true,
            ),
          ),
          throwsArgumentError,
          reason: origin,
        );
        expect(listenerInstalled, isFalse, reason: origin);
        if (origin.isNotEmpty) {
          try {
            browser_transport.createBrowserRenderMessageTransportForTest(
              parentOrigin: origin,
            );
            fail('Expected invalid parent origin to be rejected.');
          } on ArgumentError catch (error) {
            expect(error.toString(), isNot(contains(origin)));
          }
        }
      }
    });

    test('rejects a top-level window before listener creation', () {
      var listenerInstalled = false;
      expect(
        () => browser_transport.createBrowserRenderMessageTransportForTest(
          parentOrigin: web.window.location.origin,
          hooks: browser_transport.BrowserRenderMessageTransportWebHooks(
            readParentWindow: () => web.window,
            onListenerInstalled: () => listenerInstalled = true,
          ),
        ),
        throwsStateError,
      );
      expect(listenerInstalled, isFalse);
    });

    test('accepts only exact parent source, origin, and bounded JSON objects',
        () async {
      final origin = web.window.location.origin;
      final transport =
          browser_transport.createBrowserRenderMessageTransportForTest(
        parentOrigin: origin,
      );
      addTearDown(transport.dispose);
      final received = <RenderTransportMessage>[];
      final subscription = transport.messages.listen(received.add);
      addTearDown(subscription.cancel);

      _dispatch(
        origin: 'https://wrong.example',
        source: web.window.parent,
        data: <String, Object?>{'type': 'render'}.jsify(),
      );
      _dispatch(
        origin: origin,
        data: <String, Object?>{'type': 'render'}.jsify(),
      );
      _dispatch(
        origin: origin,
        source: web.window.parent,
        data: <Object?>['not-an-object'].jsify(),
      );
      _dispatch(
        origin: origin,
        source: web.window.parent,
        data: _nestedObject(65).jsify(),
      );
      _dispatch(
        origin: origin,
        source: web.window.parent,
        data: <String, Object?>{
          'items': List<Object?>.filled(100001, null),
        }.jsify(),
      );
      expect(received, isEmpty, reason: 'malformed and over-budget messages');
      for (final nonFinite in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        _dispatch(
          origin: origin,
          source: web.window.parent,
          data: _nonFinitePayload(nonFinite),
        );
        expect(
          received,
          isEmpty,
          reason: 'non-finite value $nonFinite became '
              '${received.map((message) => message.payload).toList()}',
        );
      }
      _dispatch(
        origin: origin,
        source: web.window.parent,
        data: <String, Object?>{
          'v': 1.0,
          'type': 'render',
          'epoch': 2.0,
          'nested': <String, Object?>{
            'integral': 3.0,
            'items': <Object?>[4.0, true, null, 'ok'],
            'numericEdges': _numericEdges(),
          },
        }.jsify(),
      );

      expect(received, hasLength(1));
      expect(received.single.origin, origin);
      final payload = received.single.payload! as Map<String, Object?>;
      expect(payload, <String, Object?>{
        'v': 1,
        'type': 'render',
        'epoch': 2,
        'nested': <String, Object?>{
          'integral': 3,
          'items': <Object?>[4, true, null, 'ok'],
          'numericEdges': <String, Object?>{
            'fractional': 1.25,
            'negativeZero': -0.0,
            'largePositive': 1e100,
            'largeNegative': -1e100,
            'maxSafe': 9007199254740991,
            'minSafe': -9007199254740991,
            'aboveSafe': 9007199254740992.0,
            'belowSafe': -9007199254740992.0,
          },
        },
      });
      expect(payload['v'], isA<int>());
      expect(payload['epoch'], isA<int>());
      final nested = payload['nested']! as Map<String, Object?>;
      expect(nested['integral'], isA<int>());
      expect((nested['items']! as List<Object?>).first, isA<int>());
      _expectNumericEdges(
        nested['numericEdges']! as Map<String, Object?>,
      );
    });

    test('accepts only the exact opaque parent WindowProxy source', () async {
      final iframe = web.HTMLIFrameElement();
      addTearDown(() => iframe.remove());
      final opaqueLoad = Completer<void>();
      final opaqueLoadListener = ((web.Event _) {
        if (!opaqueLoad.isCompleted) opaqueLoad.complete();
      }).toJS;
      iframe
        ..addEventListener('load', opaqueLoadListener)
        ..sandbox.add('allow-scripts')
        ..setAttribute('srcdoc', '<!doctype html><title>opaque parent</title>');
      web.document.body!.appendChild(iframe);
      await opaqueLoad.future;
      iframe.removeEventListener('load', opaqueLoadListener);

      const origin = 'https://shell.example';
      final opaqueParent = iframe.contentWindow!;
      final transport =
          browser_transport.createBrowserRenderMessageTransportForTest(
        parentOrigin: origin,
        hooks: browser_transport.BrowserRenderMessageTransportWebHooks(
          readParentWindow: () => opaqueParent,
        ),
      );
      addTearDown(transport.dispose);
      final received = <RenderTransportMessage>[];
      final subscription = transport.messages.listen(received.add);
      addTearDown(subscription.cancel);

      final exactSourceEvent = web.MessageEvent(
        'message',
        web.MessageEventInit(
          origin: origin,
          source: opaqueParent,
          data: <String, Object?>{'type': 'render', 'v': 1.0}.jsify(),
        ),
      );
      final wrongSourceEvent = web.MessageEvent(
        'message',
        web.MessageEventInit(
          origin: origin,
          source: web.window,
          data: <String, Object?>{'type': 'wrong-source'}.jsify(),
        ),
      );
      final freshOpaqueParent = iframe.contentWindow!;
      expect(
        _isSameJsObject(exactSourceEvent.source, freshOpaqueParent),
        isTrue,
      );
      expect(
        _isSameJsObject(wrongSourceEvent.source, freshOpaqueParent),
        isFalse,
      );

      web.window
        ..dispatchEvent(wrongSourceEvent)
        ..dispatchEvent(exactSourceEvent);

      expect(received, hasLength(1));
      final payload = received.single.payload! as Map<String, Object?>;
      expect(payload, <String, Object?>{'type': 'render', 'v': 1});
      expect(payload['v'], isA<int>());
    });

    test('installs before server start and pins every send to exact parent',
        () async {
      final origin = web.window.location.origin;
      final trace = <String>[];
      final sent = <Map<String, Object?>>[];
      final transport =
          browser_transport.createBrowserRenderMessageTransportForTest(
        parentOrigin: origin,
        hooks: browser_transport.BrowserRenderMessageTransportWebHooks(
          onListenerInstalled: () => trace.add('listener'),
          onListenerRemoved: () => trace.add('removed'),
          postMessage: (target, payload, targetOrigin) {
            expect(target, web.window.parent);
            expect(targetOrigin, origin);
            sent.add(payload);
            trace.add('send');
          },
        ),
      );
      final server = RenderProtocolServer(
        transport: transport,
        manifest: _manifest(),
        engine: RenderEngine(flutterVersion: '3.47.0', renderer: 'skwasm'),
        supportedVersions: const <int>[renderProtocolV1],
        scheduleFrame: (callback) => callback(),
        initialize: (_) {},
        render: (_) async => BundleRenderResult(),
      )..start();

      expect(trace, <String>['listener', 'send']);
      expect(sent.single['type'], 'ready');

      transport.send(
        <String, Object?>{
          'type': 'numeric-edges',
          'nested': <String, Object?>{'numericEdges': _numericEdges()},
        },
        targetOrigin: origin,
      );
      final sentNested = sent.last['nested']! as Map<String, Object?>;
      _expectNumericEdges(
        sentNested['numericEdges']! as Map<String, Object?>,
      );
      for (final nonFinite in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => transport.send(
            <String, Object?>{
              'nested': <String, Object?>{'value': nonFinite},
            },
            targetOrigin: origin,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => transport.send(_nestedObject(65), targetOrigin: origin),
        throwsFormatException,
      );
      expect(
        () => transport.send(
          <String, Object?>{
            'items': List<Object?>.filled(100001, null),
          },
          targetOrigin: origin,
        ),
        throwsFormatException,
      );

      expect(
        () => transport.send(
          <String, Object?>{'secret': 'not-for-diagnostics'},
          targetOrigin: 'https://wrong.example',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'sanitized error',
            isNot(contains('https://wrong.example')),
          ),
        ),
      );
      expect(
        () => transport.send(
          <String, Object?>{
            'secret': 'not-for-diagnostics',
            'invalid': DateTime(2026),
          },
          targetOrigin: origin,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.toString(),
            'sanitized error',
            isNot(contains('not-for-diagnostics')),
          ),
        ),
      );

      await server.dispose();
      await transport.dispose();
      await transport.dispose();
      expect(trace, <String>['listener', 'send', 'send', 'removed']);
    });
  });
}
