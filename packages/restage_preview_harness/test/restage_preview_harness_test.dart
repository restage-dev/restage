import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_preview_harness/restage_preview_harness.dart';
import 'package:restage_preview_harness/src/render_completion_tracker.dart';
import 'package:restage_preview_host/restage_preview_host.dart';
// Test-only fixture encoding uses the host package's pinned RFW dependency.
// ignore: depend_on_referenced_packages
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

final class _LinkedTransport implements RenderMessageTransport {
  _LinkedTransport(this.origin);

  final String origin;
  final _messages = StreamController<RenderTransportMessage>.broadcast(
    sync: true,
  );
  _LinkedTransport? _peer;

  @override
  Stream<RenderTransportMessage> get messages => _messages.stream;

  void connect(_LinkedTransport peer) {
    _peer = peer;
  }

  @override
  void send(Map<String, Object?> payload, {required String targetOrigin}) {
    final peer = _peer;
    if (peer == null || (targetOrigin != '*' && targetOrigin != peer.origin)) {
      return;
    }
    peer._messages.add(
      RenderTransportMessage(origin: origin, payload: payload),
    );
  }

  @override
  Future<void> dispose() => _messages.close();
}

void main() {
  test('production snapshot path never reads debug-only paint state', () {
    final source = File(
      'lib/src/restage_preview_harness_app.dart',
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
      RestagePreviewHarnessApp(
        transport: transport,
        manifest: _manifest(),
        engine: RenderEngine(flutterVersion: '3.41.0', renderer: 'canvaskit'),
        initialize: (_) {},
        registerCustomerWidgets: () => registrations += 1,
      ),
    );
    expect(registrations, 1);
    expect(transport.sent.single.payload['type'], 'ready');
    expect(
      transport.sent.single.payload['capabilities'],
      const <String>[renderSnapshotCapability],
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
        RestagePreviewHarnessApp(
          transport: transport,
          manifest: _manifest(),
          engine: RenderEngine(
            flutterVersion: '3.41.0',
            renderer: 'canvaskit',
          ),
          initialize: (_) {},
          registerCustomerWidgets: () {},
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
        RestagePreviewHarnessApp(
          transport: transport,
          manifest: _manifest(),
          engine: RenderEngine(
            flutterVersion: '3.41.0',
            renderer: 'canvaskit',
          ),
          initialize: (_) {},
          registerCustomerWidgets: () {},
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

      // A target this harness cannot capture is refused quietly. Nothing
      // claiming to be a snapshot goes out, and — unlike the stale-epoch case
      // above, which is a malformed message and so a real contract violation —
      // no `protocolError` either: the contract reserves that for violations
      // outside any epoch, and the shell treats every one as terminal, so
      // answering an unsupported *optional* capture with one would discard the
      // session and drop a healthy settled render to placeholders.
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

  testWidgets(
    'settled-frame geometry is equal through in-process and seam providers',
    (tester) async {
      const markerPath = '["Preview","child"]';
      final library = RemoteWidgetLibrary(
        const <Import>[
          Import(LibraryName(<String>['restage', 'editor'])),
          Import(LibraryName(<String>['restage', 'core'])),
        ],
        <WidgetDeclaration>[
          WidgetDeclaration(
            'Preview',
            null,
            ConstructorCall(kReservedPreviewConstructorName, <String, Object?>{
              'path': markerPath,
              'child': const ConstructorCall('Container', <String, Object?>{
                'width': 80.0,
                'height': 40.0,
              }),
            }),
          ),
        ],
      );
      final request = RenderRequest(
        epoch: 1,
        blob: encodeLibraryBlob(library),
        data: const <String, Object?>{},
        env: RenderEnv(
          theme: const <String, Object?>{},
          brightness: 'light',
          locale: 'en-US',
          textScale: 1,
          zoom: 1,
          frame: const Size(200, 100),
        ),
      );

      final direct = InProcessRenderProvider();
      addTearDown(direct.dispose);
      final directEvents = <RenderEvent>[];
      final directGeometry = <GeometrySnapshot>[];
      final directEventSubscription = direct.events.listen(directEvents.add);
      final directSubscription = direct.geometry.listen(directGeometry.add);
      addTearDown(directEventSubscription.cancel);
      addTearDown(directSubscription.cancel);

      final shellTransport = _LinkedTransport('https://shell.example');
      final bundleTransport = _LinkedTransport('https://bundle.example');
      shellTransport.connect(bundleTransport);
      bundleTransport.connect(shellTransport);
      final seam = SeamRenderProvider(
        transport: shellTransport,
        bundleOrigin: bundleTransport.origin,
        supportedVersions: const <int>[renderProtocolV1],
        scheduleFrame: (callback) {
          WidgetsBinding.instance.addPostFrameCallback((_) => callback());
        },
      );
      addTearDown(seam.dispose);
      final seamEvents = <RenderEvent>[];
      final seamGeometry = <GeometrySnapshot>[];
      final seamEventSubscription = seam.events.listen(seamEvents.add);
      final seamSubscription = seam.geometry.listen(seamGeometry.add);
      addTearDown(seamEventSubscription.cancel);
      addTearDown(seamSubscription.cancel);

      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: <Widget>[
              SizedBox(
                width: 200,
                height: 100,
                child: InProcessPreviewSurface(
                  provider: direct,
                  registrations: const <RestageWidgetLibraryRegistration>[],
                  entryWidgetName: 'Preview',
                  onRemoteEvent: (_, __) {},
                ),
              ),
              SizedBox(
                width: 200,
                height: 100,
                child: RestagePreviewHarnessApp(
                  transport: bundleTransport,
                  manifest: _manifest(),
                  engine: RenderEngine(
                    flutterVersion: '3.41.0',
                    renderer: 'canvaskit',
                  ),
                  initialize: (_) {},
                  registerCustomerWidgets: () {},
                ),
              ),
            ],
          ),
        ),
      );
      await seam.ready;
      await direct.render(request);
      await seam.render(request);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(directEvents.whereType<Settled>(), hasLength(1));
      expect(seamEvents.whereType<Settled>(), hasLength(1));
      expect(directEvents.whereType<Settled>().single.epoch, request.epoch);
      expect(seamEvents.whereType<Settled>().single.epoch, request.epoch);
      expect(directGeometry, hasLength(1));
      expect(directGeometry.single.generation, 0);
      expect(directGeometry.single.epoch, request.epoch);
      expect(seamGeometry, hasLength(1));
      expect(seamGeometry.single.generation, 0);
      expect(seamGeometry.single.epoch, request.epoch);
      expect(seamGeometry.single.rects, directGeometry.single.rects);
      expect(seamGeometry.single.rects[markerPath], isNotNull);
    },
  );

  testWidgets('superseded render completes without emitting a stale epoch', (
    tester,
  ) async {
    final transport = _Transport();
    await tester.pumpWidget(
      RestagePreviewHarnessApp(
        transport: transport,
        manifest: _manifest(),
        engine: RenderEngine(flutterVersion: '3.41.0', renderer: 'canvaskit'),
        initialize: (_) {},
        registerCustomerWidgets: () {},
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
    'a customer rebuild failure after settle emits one terminal renderError',
    (tester) async {
      final transport = _Transport();
      final fail = ValueNotifier<bool>(false);
      addTearDown(fail.dispose);

      await tester.pumpWidget(
        RestagePreviewHarnessApp(
          transport: transport,
          manifest: _manifest(),
          engine: RenderEngine(flutterVersion: '3.41.0', renderer: 'canvaskit'),
          initialize: (_) {},
          registerCustomerWidgets: () {
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
        RestagePreviewHarnessApp(
          transport: transport,
          manifest: _manifest(),
          engine: RenderEngine(flutterVersion: '3.41.0', renderer: 'canvaskit'),
          initialize: (_) {},
          registerCustomerWidgets: () {
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
        library: 'restage_preview_harness_test',
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
          if (shouldFail) throw StateError('late customer rebuild failed');
          return const Text('Initially stable');
        },
      );
}
