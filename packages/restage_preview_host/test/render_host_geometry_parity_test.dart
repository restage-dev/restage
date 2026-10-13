import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
// ignore: implementation_imports
import 'package:restage/src/render_host/render_host_app.dart';
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
      final seam = RenderHostProvider(
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
                child: RenderHostApp(
                  entryWidgetName: 'Preview',
                  transport: bundleTransport,
                  manifest: _manifest(),
                  engine: RenderEngine(
                    flutterVersion: '3.41.0',
                    renderer: 'canvaskit',
                  ),
                  registerAppWidgets: () {},
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
}
