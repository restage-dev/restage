import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/render_host/render_host_app.dart';
import 'package:restage/src/render_host/render_bundle_view_binding.dart';
import 'package:restage/src/render_host/render_core.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

RenderBundleManifest _manifest() => RenderBundleManifest(
      formatVersion: 1,
      catalog: const <String, Object?>{
        'schemaVersion': 4,
        'libraries': <String, Object?>{},
        'widgets': <Object?>[],
      },
    );

RenderBundleManifest _manifestWithMissingWidget() => RenderBundleManifest(
      formatVersion: 1,
      catalog: const <String, Object?>{
        'schemaVersion': 4,
        'libraries': <String, Object?>{
          'acme.widgets': <String, Object?>{
            'version': '1.0.0',
            'capabilityVersion': 1,
          },
        },
        'widgets': <Object?>[
          <String, Object?>{
            'wireId': 'w0001',
            'library': 'acme.widgets',
            'name': 'AcmeBadge',
            'properties': <Object?>[
              <String, Object?>{'wireId': 'p0001', 'name': 'label'},
            ],
          },
        ],
      },
    );

final class _Transport implements RenderMessageTransport {
  final _messages =
      StreamController<RenderTransportMessage>.broadcast(sync: true);
  final sent = <Map<String, Object?>>[];

  @override
  Stream<RenderTransportMessage> get messages => _messages.stream;

  void render(Uint8List blob) {
    _messages.add(
      RenderTransportMessage(
        origin: 'https://shell.example',
        payload: <String, Object?>{
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
        },
      ),
    );
  }

  @override
  void send(Map<String, Object?> payload, {required String targetOrigin}) {
    sent.add(payload);
  }

  @override
  Future<void> dispose() => _messages.close();
}

Uint8List _blobWithDeclarations(List<String> names) {
  final parsed = parseLibraryFile('''
import restage.core;
widget Template = Text(text: "selected");
''');
  final template = parsed.widgets.single;
  return Uint8List.fromList(
    encodeLibraryBlob(
      RemoteWidgetLibrary(
        parsed.imports,
        <WidgetDeclaration>[
          for (final name in names)
            WidgetDeclaration(name, template.initialState, template.root),
        ],
      ),
    ),
  );
}

Future<_Transport> _mount(
  WidgetTester tester,
  Uint8List blob, {
  RenderBundleManifest? manifest,
  RenderBundleRasterController? rasterController,
}) async {
  final transport = _Transport();
  final app = rasterController == null
      ? RenderHostApp(
          transport: transport,
          manifest: manifest ?? _manifest(),
          engine: RenderEngine(flutterVersion: '3.47.0', renderer: 'skwasm'),
          registerAppWidgets: () {},
        )
      : RenderHostApp(
          transport: transport,
          manifest: manifest ?? _manifest(),
          engine: RenderEngine(flutterVersion: '3.47.0', renderer: 'skwasm'),
          registerAppWidgets: () {},
          rasterController: rasterController,
        );
  await tester.pumpWidget(app);
  transport.render(blob);
  await tester.pump();
  await tester.pump();
  return transport;
}

void main() {
  setUp(Restage.debugReset);

  testWidgets('one main wins over legacy Paywall declarations', (tester) async {
    final transport = await _mount(
      tester,
      _blobWithDeclarations(<String>['Paywall', 'main', 'Paywall']),
    );

    expect(find.text('selected'), findsOneWidget);
    expect(
      transport.sent.map((payload) => payload['type']),
      <String>['ready', 'settled', 'geometry'],
    );
  });

  testWidgets('one legacy Paywall is selected when main is absent',
      (tester) async {
    final transport = await _mount(
      tester,
      _blobWithDeclarations(<String>['Other', 'Paywall']),
    );

    expect(find.text('selected'), findsOneWidget);
    expect(
      transport.sent.map((payload) => payload['type']),
      <String>['ready', 'settled', 'geometry'],
    );
  });

  final rejected = <String, Uint8List>{
    'multiple main declarations':
        _blobWithDeclarations(<String>['main', 'main', 'Paywall']),
    'duplicate Paywall without main':
        _blobWithDeclarations(<String>['Paywall', 'Paywall']),
    'neither supported declaration':
        _blobWithDeclarations(<String>['Other', 'Another']),
    'malformed blob': Uint8List.fromList(<int>[0, 1, 2, 3]),
  };
  for (final entry in rejected.entries) {
    testWidgets('${entry.key} emits one controlled error and no pixels',
        (tester) async {
      final transport = await _mount(tester, entry.value);

      expect(find.text('selected'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(
        transport.sent.map((payload) => payload['type']),
        <String>['ready', 'renderError'],
      );
      expect(
        transport.sent.last['message'],
        'Unable to select the render bundle entry.',
      );
    });
  }

  testWidgets(
    'manifest-covered widget missing from runtime uses structured placeholder',
    (tester) async {
      final blob = encodeLibraryBlob(
        parseLibraryFile('''
import acme.widgets;
widget main = AcmeBadge(label: "Pro");
'''),
      );

      final transport = await _mount(
        tester,
        blob,
        manifest: _manifestWithMissingWidget(),
      );

      expect(find.text('AcmeBadge'), findsOneWidget);
      expect(find.textContaining('label'), findsOneWidget);
      expect(
        transport.sent.map((payload) => payload['type']),
        <String>['ready', 'settled', 'geometry'],
      );
    },
  );

  testWidgets('latest render waits for matching backing metrics before paint',
      (tester) async {
    final raster = _ControlledRasterController();
    final blob = _blobWithDeclarations(<String>['main']);
    final transport = _Transport();
    await tester.pumpWidget(
      RenderHostApp(
        transport: transport,
        manifest: _manifest(),
        engine: RenderEngine(flutterVersion: '3.47.0', renderer: 'skwasm'),
        registerAppWidgets: () {},
        rasterController: raster,
      ),
    );
    transport.render(blob);
    await tester.pump();

    expect(raster.environments.single.zoom, 1);
    expect(find.text('selected'), findsNothing);
    raster.pending.single.complete(true);
    await tester.pump();
    await tester.pump();

    expect(find.text('selected'), findsOneWidget);
    expect(
      transport.sent.map((payload) => payload['type']),
      <String>['ready', 'settled', 'geometry'],
    );
  });
}

final class _ControlledRasterController
    implements RenderBundleRasterController {
  final environments = <RenderEnv>[];
  final pending = <Completer<bool>>[];

  @override
  Future<bool> prepare(RenderEnv environment) {
    environments.add(environment);
    final completer = Completer<bool>();
    pending.add(completer);
    return completer.future;
  }

  @override
  void cancelPending() {
    for (final completer in pending) {
      if (!completer.isCompleted) completer.complete(false);
    }
  }
}
