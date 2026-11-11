import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_catalog.g.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_render_host/restage_render_host.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

import '_support/bundled_artifacts.dart';

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

  void snapshot({required int epoch, required String path}) {
    _messages.add(
      RenderTransportMessage(
        origin: 'https://shell.example',
        payload: <String, Object?>{
          'v': 1,
          'type': 'snapshotRequest',
          'epoch': epoch,
          'path': path,
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

typedef _MountedBundle = ({
  GlobalKey boundaryKey,
  _Transport transport,
});

Future<_MountedBundle> _mountBundle(
  WidgetTester tester, {
  Duration elapsed = Duration.zero,
  bool freezeBeforeReturn = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final transport = _Transport();
  final boundaryKey = GlobalKey();
  final ticking = ValueNotifier<bool>(true);
  addTearDown(ticking.dispose);
  final manifest = RenderBundleManifest.fromCatalogJson(
    encodeCatalog(kUserCatalog),
  );
  await tester.pumpWidget(
    ValueListenableBuilder<bool>(
      valueListenable: ticking,
      builder: (context, enabled, child) => TickerMode(
        enabled: enabled,
        child: child!,
      ),
      child: RepaintBoundary(
        key: boundaryKey,
        child: RenderHostApp(
          transport: transport,
          manifest: manifest,
          engine: RenderEngine(
            flutterVersion: '3.47.0',
            renderer: 'skwasm',
          ),
          registerAppWidgets: registerRestageWidgets,
        ),
      ),
    ),
  );
  final blob = readDeliveryArtifact('assets/paywalls/pulse_paywall.rfw');
  transport.render(Uint8List.fromList(blob));
  await tester.pump();
  await tester.pump();
  if (elapsed > Duration.zero) await tester.pump(elapsed);
  if (freezeBeforeReturn) {
    ticking.value = false;
    await tester.pump();
  }
  return (boundaryKey: boundaryKey, transport: transport);
}

Future<String> _paintHash(WidgetTester tester, GlobalKey key) async {
  return (await tester.runAsync<String>(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return sha256.convert(bytes!.buffer.asUint8List()).toString();
  }))!;
}

Future<Map<String, Object?>> _waitForMessage(
  _Transport transport,
  String type,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    for (final payload in transport.sent) {
      if (payload['type'] == type) return payload;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw TimeoutException('Timed out waiting for $type.');
}

// The badge's own scale: the split widget keeps it in the app, around the
// delivered label.
final _badgeScale = find.ancestor(
  of: find.text('Streak: 12'),
  matching: find.byType(ScaleTransition),
);

void main() {
  setUp(Restage.debugReset);

  test('uses the exact canonical PulseBadge blob', () {
    final blob = readDeliveryArtifact('assets/paywalls/pulse_paywall.rfw');
    expect(blob, hasLength(7064));
    expect(
      sha256.convert(blob).toString(),
      '148af81d89a7727ecb60a48726f0e9346e21eeb47a4e34d860a9d3b5818cf002',
    );
    // PulseBadge is split: its definition delivers the label around the
    // app's scale.
    expect(
      decodeLibraryBlob(Uint8List.fromList(blob))
          .widgets
          .map((declaration) => declaration.name),
      containsAll(['PulseBadge', 'Paywall']),
    );
  });

  testWidgets('PulseBadge animates through the production bundle endpoint',
      (tester) async {
    final mounted = await _mountBundle(tester);
    final scales = <double>[];
    for (var frame = 0; frame < 3; frame += 1) {
      final transitions =
          tester.widgetList<ScaleTransition>(_badgeScale).toList();
      if (transitions.length == 1) scales.add(transitions.single.scale.value);
      if (frame < 2) await tester.pump(const Duration(milliseconds: 100));
    }
    final pulseBadgeCount = _badgeScale.evaluate().length;
    final labelCount = find.text('Streak: 12').evaluate().length;
    final messageTypes =
        mounted.transport.sent.map((payload) => payload['type']).toList();
    await tester.pumpWidget(const SizedBox.shrink());

    expect(pulseBadgeCount, 1);
    expect(labelCount, 1);
    expect(scales, hasLength(3));
    expect(scales.toSet(), hasLength(3));
    expect(messageTypes, <String>['ready', 'settled', 'geometry']);
  });

  testWidgets(
      'harness snapshots the exact root while PulseBadge animation is active',
      (tester) async {
    final mounted = await _mountBundle(tester);
    final transition = tester.widget<ScaleTransition>(_badgeScale);
    expect(transition.scale.status, AnimationStatus.forward);
    expect(transition.scale.value, lessThan(1));

    const path = '["Paywall"]';
    mounted.transport.snapshot(epoch: 1, path: path);
    await tester.pump(const Duration(milliseconds: 16));
    final result = await tester.runAsync(
      () => _waitForMessage(mounted.transport, 'snapshotResult'),
    );

    expect(result, isNotNull);
    expect(result!.keys, <String>{'v', 'type', 'epoch', 'path', 'png'});
    expect(result['v'], 1);
    expect(result['type'], 'snapshotResult');
    expect(result['epoch'], 1);
    expect(result['path'], path);
    final png = base64Decode(result['png']! as String);
    expect(png.take(8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    expect(
      mounted.transport.sent.where(
        (payload) =>
            payload['type'] == 'protocolError' ||
            payload['type'] == 'renderError',
      ),
      isEmpty,
    );
    expect(transition.scale.status, AnimationStatus.forward);
    expect(transition.scale.value, lessThan(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  const frames = <(Duration, String)>[
    (
      Duration.zero,
      'e15bfe5ab364f2ab06dce388026d47795ac04ea854732dea41f91897f17823f0',
    ),
    (
      Duration(milliseconds: 100),
      '79544c422c72a489fdaf647458840933a5d4c99d086156a3737531b1016c11d9',
    ),
    (
      Duration(milliseconds: 200),
      'c2925dc30361d0c119da8cd61ccb5a2c2e23688b08877466edaa4cbe2672790b',
    ),
  ];
  for (final (elapsed, expectedHash) in frames) {
    testWidgets(
        'PulseBadge paints expected ${elapsed.inMilliseconds}ms pixel frame',
        (tester) async {
      final mounted = await _mountBundle(
        tester,
        elapsed: elapsed,
        freezeBeforeReturn: true,
      );
      final hash = await _paintHash(tester, mounted.boundaryKey);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(hash, expectedHash);
    });
  }
}
