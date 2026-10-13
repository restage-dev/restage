import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/render_host/render_host_app.dart';
import 'package:restage/src/render_host/render_completion_tracker.dart';
import 'package:restage/src/render_host/render_core.dart';

import 'package:rfw/formats.dart' hide WidgetLibrary;

RenderBundleManifest _manifest() => RenderBundleManifest(
      formatVersion: 1,
      catalog: const <String, Object?>{
        'schemaVersion': 4,
        'libraries': <String, Object?>{},
        'widgets': <Object?>[],
        'structuredTypes': <Object?>[],
        'unions': <Object?>[],
      },
    );

final class _SentMessage {
  const _SentMessage(this.payload, this.origin);

  final Map<String, Object?> payload;
  final String origin;
}

Map<String, Object?> _surfaceMessage({
  required String type,
  required int epoch,
  required String source,
  Map<String, Object?> data = const <String, Object?>{'title': 'Tap me'},
}) =>
    <String, Object?>{
      'v': 1,
      'type': type,
      'epoch': epoch,
      'blob': encodeRenderBlob(encodeLibraryBlob(parseLibraryFile(source))),
      'data': data,
      'env': <String, Object?>{
        'theme': <String, Object?>{},
        'brightness': 'light',
        'locale': 'en-US',
        'textScale': 1.0,
        'zoom': 1.0,
        'frame': <String, Object?>{'w': 390.0, 'h': 844.0},
      },
    };

String _tappableSurface({String arguments = 'value: "often", index: 2'}) =>
    'import restage.core; '
    'widget Preview = GestureDetector('
    'onTap: event "answerSelected" {$arguments}, '
    'child: Text(text: data.title));';

final class _Transport implements RenderMessageTransport {
  final String inboundOrigin = 'https://shell.example';
  final _messages = StreamController<RenderTransportMessage>.broadcast(
    sync: true,
  );
  final sent = <_SentMessage>[];

  @override
  Stream<RenderTransportMessage> get messages => _messages.stream;

  void receive(Map<String, Object?> payload) {
    _messages.add(
      RenderTransportMessage(origin: inboundOrigin, payload: payload),
    );
  }

  @override
  void send(Map<String, Object?> payload, {required String targetOrigin}) {
    sent.add(_SentMessage(payload, targetOrigin));
  }

  @override
  Future<void> dispose() => _messages.close();
}

void main() {
  test('production snapshot path never reads debug-only paint state', () {
    final source = File(
      '../restage/lib/src/render_host/render_host_app.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('debugNeedsPaint')));
  });

  test(
    'superseding an epoch completes and removes its pending future',
    () async {
      final completions = RenderCompletionTracker();
      final first = completions.begin(1);

      final second = completions.begin(2);

      await expectLater(first, completion(isA<BundleRenderResult>()));
      expect(completions.pendingEpochs, <int>[2]);

      completions.completeSuccess(2);
      await expectLater(second, completion(isA<BundleRenderResult>()));
      expect(completions.pendingEpochs, isEmpty);
      expect(
        completions.completeFailure(
          2,
          const BundleRenderFailure('late failure'),
        ),
        isFalse,
      );
    },
  );

  testWidgets('entrypoint registers once and settles an incoming render', (
    tester,
  ) async {
    final transport = _Transport();
    var registrations = 0;
    await tester.pumpWidget(
      RenderHostApp(
        entryWidgetName: 'Preview',
        transport: transport,
        manifest: _manifest(),
        engine: RenderEngine(flutterVersion: '3.41.0', renderer: 'canvaskit'),
        registerAppWidgets: () => registrations += 1,
      ),
    );
    expect(registrations, 1);
    expect(transport.sent.single.payload['type'], 'ready');
    expect(
      transport.sent.single.payload['capabilities'],
      const <String>[renderSnapshotCapability, renderMountCapability],
    );

    final blob = encodeLibraryBlob(
      parseLibraryFile(
        'import restage.core; widget Preview = Text(text: data.title);',
      ),
    );
    transport.receive(<String, Object?>{
      'v': 1,
      'type': 'render',
      'epoch': 1,
      'blob': encodeRenderBlob(blob),
      'data': <String, Object?>{'title': 'Harness preview'},
      'env': <String, Object?>{
        'theme': <String, Object?>{},
        'brightness': 'light',
        'locale': 'en-US',
        'textScale': 1.0,
        'zoom': 1.0,
        'frame': <String, Object?>{'w': 390.0, 'h': 844.0},
      },
    });
    await tester.pump();
    await tester.pump();

    expect(find.text('Harness preview'), findsOneWidget);
    expect(transport.sent.map((message) => message.payload['type']), <String>[
      'ready',
      'settled',
      'geometry',
    ]);
    expect(
      transport.sent
          .skip(1)
          .every((message) => message.origin == 'https://shell.example'),
      isTrue,
    );
  });

  testWidgets(
    'canonical root snapshot captures the real harness RepaintBoundary',
    (tester) async {
      final transport = _Transport();
      await tester.pumpWidget(
        RenderHostApp(
          transport: transport,
          manifest: _manifest(),
          engine: RenderEngine(
            flutterVersion: '3.41.0',
            renderer: 'canvaskit',
          ),
          registerAppWidgets: () {},
          entryWidgetName: 'main',
        ),
      );
      final blob = encodeLibraryBlob(
        parseLibraryFile(
          'import restage.core; '
          'widget main = Container(color: 0xFF336699, '
          'width: 80.0, height: 40.0);',
        ),
      );
      transport.receive(<String, Object?>{
        'v': 1,
        'type': 'render',
        'epoch': 7,
        'blob': encodeRenderBlob(blob),
        'data': <String, Object?>{},
        'env': <String, Object?>{
          'theme': <String, Object?>{},
          'brightness': 'light',
          'locale': 'en-US',
          'textScale': 1.0,
          'zoom': 1.0,
          'frame': <String, Object?>{'w': 120.0, 'h': 80.0},
        },
      });
      await tester.pump();
      await tester.pump();
      expect(
        transport.sent.where(
          (message) => message.payload['type'] == 'settled',
        ),
        hasLength(1),
      );

      const path = '["main"]';
      transport.receive(<String, Object?>{
        'v': 1,
        'type': 'snapshotRequest',
        'epoch': 7,
        'path': path,
      });
      await tester.pump();
      final sentResult = await tester.runAsync(
        () => _waitForMessage(transport, 'snapshotResult'),
      );

      final result = sentResult!.payload;
      expect(result.keys, <String>{'v', 'type', 'epoch', 'path', 'png'});
      expect(result['v'], 1);
      expect(result['type'], 'snapshotResult');
      expect(result['epoch'], 7);
      expect(result['path'], path);
      final encoded = result['png'];
      expect(encoded, isA<String>());
      final png = base64Decode(encoded! as String);
      expect(
        png.take(8),
        <int>[137, 80, 78, 71, 13, 10, 26, 10],
      );
    },
  );

  testWidgets(
    'harness snapshot rejects pre-settle, stale-epoch, and non-root targets',
    (tester) async {
      final transport = _Transport();
      await tester.pumpWidget(
        RenderHostApp(
          transport: transport,
          manifest: _manifest(),
          engine: RenderEngine(
            flutterVersion: '3.41.0',
            renderer: 'canvaskit',
          ),
          registerAppWidgets: () {},
          entryWidgetName: 'main',
        ),
      );

      transport.receive(<String, Object?>{
        'v': 1,
        'type': 'snapshotRequest',
        'epoch': 7,
        'path': '["main"]',
      });
      expect(
        transport.sent.map((message) => message.payload['type']),
        <String>['ready'],
      );

      final blob = encodeLibraryBlob(
        parseLibraryFile(
          'import restage.core; widget main = Text(text: "Snapshot target");',
        ),
      );
      transport.receive(<String, Object?>{
        'v': 1,
        'type': 'render',
        'epoch': 7,
        'blob': encodeRenderBlob(blob),
        'data': <String, Object?>{},
        'env': <String, Object?>{
          'theme': <String, Object?>{},
          'brightness': 'light',
          'locale': 'en-US',
          'textScale': 1.0,
          'zoom': 1.0,
          'frame': <String, Object?>{'w': 120.0, 'h': 80.0},
        },
      });
      await tester.pump();
      await tester.pump();

      transport.receive(<String, Object?>{
        'v': 1,
        'type': 'snapshotRequest',
        'epoch': 6,
        'path': '["main"]',
      });
      expect(transport.sent.last.payload['type'], 'protocolError');

      // Ignore unsupported paths because snapshots are optional and protocol
      // errors are terminal.
      final messagesBeforeWrongPath = transport.sent.length;
      transport.receive(<String, Object?>{
        'v': 1,
        'type': 'snapshotRequest',
        'epoch': 7,
        'path': '["main","child"]',
      });
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(
        transport.sent.skip(messagesBeforeWrongPath).where(
              (message) => const <String>{
                'snapshotResult',
                'protocolError',
              }.contains(message.payload['type']),
            ),
        isEmpty,
      );
    },
  );

  testWidgets('superseded render completes without emitting a stale epoch', (
    tester,
  ) async {
    final transport = _Transport();
    await tester.pumpWidget(
      RenderHostApp(
        entryWidgetName: 'Preview',
        transport: transport,
        manifest: _manifest(),
        engine: RenderEngine(flutterVersion: '3.41.0', renderer: 'canvaskit'),
        registerAppWidgets: () {},
      ),
    );
    final blob = encodeLibraryBlob(
      parseLibraryFile(
        'import restage.core; widget Preview = Text(text: data.title);',
      ),
    );

    Map<String, Object?> render(int epoch) => <String, Object?>{
          'v': 1,
          'type': 'render',
          'epoch': epoch,
          'blob': encodeRenderBlob(blob),
          'data': <String, Object?>{'title': 'Epoch $epoch'},
          'env': <String, Object?>{
            'theme': <String, Object?>{},
            'brightness': 'light',
            'locale': 'en-US',
            'textScale': 1.0,
            'zoom': 1.0,
            'frame': <String, Object?>{'w': 390.0, 'h': 844.0},
          },
        };

    transport.receive(render(1));
    transport.receive(render(2));
    await tester.pump();
    await tester.pump();

    expect(find.text('Epoch 2'), findsOneWidget);
    expect(
      transport.sent
          .where((message) => message.payload['type'] == 'settled')
          .map((message) => message.payload['epoch']),
      <int>[2],
    );
    expect(
      transport.sent
          .where((message) => message.payload['type'] == 'geometry')
          .map((message) => message.payload['epoch']),
      <int>[2],
    );
  });

  testWidgets(
    'an app-defined rebuild failure after settle emits one terminal renderError',
    (tester) async {
      final transport = _Transport();
      final fail = ValueNotifier<bool>(false);
      addTearDown(fail.dispose);

      await tester.pumpWidget(
        RenderHostApp(
          entryWidgetName: 'Preview',
          transport: transport,
          manifest: _manifest(),
          engine: RenderEngine(flutterVersion: '3.41.0', renderer: 'canvaskit'),
          registerAppWidgets: () {
            Restage.registerWidgetLibrary(
              const WidgetLibrary.custom('acme.late'),
              widgets: <RestageWidgetFactory>[
                RestageWidgetFactory(
                  name: 'LateFailure',
                  builder: (_, __) => _LateFailure(fail: fail),
                ),
              ],
              capabilityVersion: 1,
            );
          },
        ),
      );
      final blob = encodeLibraryBlob(
        parseLibraryFile('''
import acme.late;
widget Preview = LateFailure();
'''),
      );
      transport.receive(<String, Object?>{
        'v': 1,
        'type': 'render',
        'epoch': 1,
        'blob': encodeRenderBlob(blob),
        'data': <String, Object?>{},
        'env': <String, Object?>{
          'theme': <String, Object?>{},
          'brightness': 'light',
          'locale': 'en-US',
          'textScale': 1.0,
          'zoom': 1.0,
          'frame': <String, Object?>{'w': 390.0, 'h': 844.0},
        },
      });
      await tester.pump();
      await tester.pump();
      expect(transport.sent.map((message) => message.payload['type']), <String>[
        'ready',
        'settled',
        'geometry',
      ]);

      fail.value = true;
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(transport.sent.map((message) => message.payload['type']), <String>[
        'ready',
        'settled',
        'geometry',
        'renderError',
      ]);
      expect(
        transport.sent.where(
          (message) => message.payload['type'] == 'renderError',
        ),
        hasLength(1),
      );

      fail.value = false;
      fail.value = true;
      await tester.pump();
      expect(
        transport.sent.where(
          (message) => message.payload['type'] == 'renderError',
        ),
        hasLength(1),
      );
      final terminalIndex = transport.sent.indexWhere(
        (message) => message.payload['type'] == 'renderError',
      );
      expect(
        transport.sent.skip(terminalIndex + 1).where(
              (message) => const <String>{
                'settled',
                'geometry',
              }.contains(message.payload['type']),
            ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'owned repaint with a later lazy diagnostic failure emits one terminal '
    'renderError and fallback',
    (tester) async {
      final transport = _Transport();
      final repaint = _RepaintReportController();
      addTearDown(repaint.dispose);

      await tester.pumpWidget(
        RenderHostApp(
          entryWidgetName: 'Preview',
          transport: transport,
          manifest: _manifest(),
          engine: RenderEngine(flutterVersion: '3.41.0', renderer: 'canvaskit'),
          registerAppWidgets: () {
            Restage.registerWidgetLibrary(
              const WidgetLibrary.custom('acme.repaint'),
              widgets: <RestageWidgetFactory>[
                RestageWidgetFactory(
                  name: 'RepaintReporter',
                  builder: (_, __) => _RepaintReportProbe(repaint),
                ),
              ],
              capabilityVersion: 1,
            );
          },
        ),
      );
      final blob = encodeLibraryBlob(
        parseLibraryFile('''
import acme.repaint;
widget Preview = RepaintReporter();
'''),
      );
      transport.receive(<String, Object?>{
        'v': 1,
        'type': 'render',
        'epoch': 2,
        'blob': encodeRenderBlob(blob),
        'data': <String, Object?>{},
        'env': <String, Object?>{
          'theme': <String, Object?>{},
          'brightness': 'light',
          'locale': 'en-US',
          'textScale': 1.0,
          'zoom': 1.0,
          'frame': <String, Object?>{'w': 390.0, 'h': 844.0},
        },
      });
      await tester.pump();
      await tester.pump();
      expect(transport.sent.map((message) => message.payload['type']), <String>[
        'ready',
        'settled',
        'geometry',
      ]);

      repaint.trigger();
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(transport.sent.map((message) => message.payload['type']), <String>[
        'ready',
        'settled',
        'geometry',
        'renderError',
      ]);
      expect(find.byType(_RepaintReportProbe), findsNothing);
      repaint.trigger();
      await tester.pump();
      await tester.pump();
      expect(
        transport.sent.where(
          (message) => message.payload['type'] == 'renderError',
        ),
        hasLength(1),
      );
      final terminalIndex = transport.sent.indexWhere(
        (message) => message.payload['type'] == 'renderError',
      );
      expect(
        transport.sent.skip(terminalIndex + 1).where(
              (message) => const <String>{
                'settled',
                'geometry',
              }.contains(message.payload['type']),
            ),
        isEmpty,
      );
    },
  );

  testWidgets('a tap on a mounted surface sends the event it fired', (
    tester,
  ) async {
    final transport = _Transport();
    await tester.pumpWidget(
      RenderHostApp(
        entryWidgetName: 'Preview',
        transport: transport,
        manifest: _manifest(),
        engine: RenderEngine(flutterVersion: '3.41.0', renderer: 'canvaskit'),
        registerAppWidgets: () {},
      ),
    );

    transport.receive(
      _surfaceMessage(type: 'mount', epoch: 1, source: _tappableSurface()),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Tap me'), findsOneWidget);

    await tester.tap(find.text('Tap me'));
    await tester.pump();

    final events = transport.sent
        .where((message) => message.payload['type'] == 'event')
        .toList();
    expect(events, hasLength(1));
    expect(events.single.origin, 'https://shell.example');
    expect(events.single.payload, <String, Object?>{
      'v': 1,
      'type': 'event',
      'epoch': 1,
      'name': 'answerSelected',
      'arguments': <String, Object?>{'value': 'often', 'index': 2},
    });
  });

  testWidgets('a tap on a rendered surface sends nothing and says nothing', (
    tester,
  ) async {
    final lines = <String>[];
    final transport = _Transport();

    final previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) lines.add(message);
    };
    try {
      await tester.pumpWidget(
        RenderHostApp(
          entryWidgetName: 'Preview',
          transport: transport,
          manifest: _manifest(),
          engine: RenderEngine(flutterVersion: '3.41.0', renderer: 'canvaskit'),
          registerAppWidgets: () {},
        ),
      );
      transport.receive(
        _surfaceMessage(type: 'render', epoch: 1, source: _tappableSurface()),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Tap me'));
      await tester.pump();
    } finally {
      debugPrint = previousPrint;
    }

    expect(
      transport.sent.map((message) => message.payload['type']),
      <String>['ready', 'settled', 'geometry'],
    );
    expect(
      lines,
      isEmpty,
      reason: 'a surface that was never mounted has nothing to explain',
    );
  });

  testWidgets('a newer mount replaces the surface and its events', (
    tester,
  ) async {
    final transport = _Transport();
    await tester.pumpWidget(
      RenderHostApp(
        entryWidgetName: 'Preview',
        transport: transport,
        manifest: _manifest(),
        engine: RenderEngine(flutterVersion: '3.41.0', renderer: 'canvaskit'),
        registerAppWidgets: () {},
      ),
    );

    transport.receive(
      _surfaceMessage(type: 'mount', epoch: 1, source: _tappableSurface()),
    );
    await tester.pump();
    await tester.pump();

    transport.receive(
      _surfaceMessage(
        type: 'mount',
        epoch: 2,
        source: _tappableSurface(arguments: 'value: "rarely"'),
        data: const <String, Object?>{'title': 'Tap me again'},
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Tap me'), findsNothing);
    expect(find.text('Tap me again'), findsOneWidget);

    await tester.tap(find.text('Tap me again'));
    await tester.pump();

    final events = transport.sent
        .where((message) => message.payload['type'] == 'event')
        .toList();
    expect(events, hasLength(1));
    expect(events.single.payload['epoch'], 2);
    expect(
      events.single.payload['arguments'],
      <String, Object?>{'value': 'rarely'},
    );
  });

  testWidgets('an event too large to carry is dropped and explained', (
    tester,
  ) async {
    final lines = <String>[];
    final transport = _Transport();
    var nested = 'leaf: "swallowed"';
    for (var depth = 0; depth < renderWireMaxDepth; depth += 1) {
      nested = 'child: {$nested}';
    }

    final previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) lines.add(message);
    };
    try {
      await tester.pumpWidget(
        RenderHostApp(
          entryWidgetName: 'Preview',
          transport: transport,
          manifest: _manifest(),
          engine: RenderEngine(flutterVersion: '3.41.0', renderer: 'canvaskit'),
          registerAppWidgets: () {},
        ),
      );
      transport.receive(
        _surfaceMessage(
          type: 'mount',
          epoch: 1,
          source: _tappableSurface(arguments: nested),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Tap me'));
      await tester.pump();
    } finally {
      debugPrint = previousPrint;
    }

    expect(
      transport.sent.where((message) => message.payload['type'] == 'event'),
      isEmpty,
    );
    expect(lines, hasLength(1));
    expect(lines.single, contains('answerSelected'));
    expect(lines.single, isNot(contains('swallowed')));
  });
}

Future<_SentMessage> _waitForMessage(
  _Transport transport,
  String type, {
  int afterIndex = 0,
}) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    for (final message in transport.sent.skip(afterIndex)) {
      if (message.payload['type'] == type) return message;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Timed out waiting for $type.');
}

final class _RepaintReportController extends ChangeNotifier {
  int revision = 0;

  void trigger() {
    revision += 1;
    notifyListeners();
  }
}

final class _RepaintReportProbe extends LeafRenderObjectWidget {
  const _RepaintReportProbe(this.controller);

  final _RepaintReportController controller;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRepaintReportProbe(controller);
}

final class _RenderRepaintReportProbe extends RenderBox {
  _RenderRepaintReportProbe(this.controller);

  final _RepaintReportController controller;
  int _reportedRevision = 0;

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    controller.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    controller.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    size = constraints.constrain(const Size.square(20));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_reportedRevision == controller.revision) return;
    _reportedRevision = controller.revision;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError('late independent harness repaint report'),
        stack: StackTrace.current,
        library: 'render_host_app_test',
        informationCollector: () => <DiagnosticsNode>[
          DiagnosticsProperty<RenderObject>('renderObject', this),
          DiagnosticsProperty<Object?>.lazy(
            'lazy failure',
            () => throw StateError('lazy diagnostic failed'),
          ),
        ],
      ),
    );
  }
}

class _LateFailure extends StatelessWidget {
  const _LateFailure({required this.fail});

  final ValueListenable<bool> fail;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: fail,
        builder: (context, shouldFail, child) {
          if (shouldFail) throw StateError('late app-defined rebuild failed');
          return const Text('Initially stable');
        },
      );
}
