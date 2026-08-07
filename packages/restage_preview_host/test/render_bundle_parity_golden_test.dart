import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_preview_host/restage_preview_host.dart';
import 'package:rfw/formats.dart';

void main() {
  testWidgets(
    'native library and bundle blob produce byte-identical parity pixels',
    (tester) async {
      final library = parseLibraryFile('''
import restage.core;
widget Preview = Column(children: [
  Text(text: "Render parity", fontSize: 24.0),
  SizedBox(height: 12.0),
  Text(text: data.subtitle, fontSize: 15.0)
]);
''');
      final blob = encodeLibraryBlob(library);
      final environment = RenderEnv(
        theme: <String, Object?>{},
        brightness: 'light',
        locale: 'en-US',
        textScale: 1,
        zoom: 1,
        frame: Size(320, 240),
      );
      const data = <String, Object?>{'subtitle': 'Same Flutter pixels'};
      const nativeKey = Key('nativeParityBoundary');
      const bundleKey = Key('bundleParityBoundary');

      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            textDirection: TextDirection.ltr,
            children: <Widget>[
              _ParityBoundary(
                boundaryKey: nativeKey,
                child: RawRfwRenderSurface.library(
                  epoch: 1,
                  library: library,
                  data: data,
                  environment: environment,
                  registrations: const <RestageWidgetLibraryRegistration>[],
                  entryWidgetName: 'Preview',
                  onRemoteEvent: (_, __) {},
                ),
              ),
              _ParityBoundary(
                boundaryKey: bundleKey,
                child: RawRfwRenderSurface(
                  epoch: 1,
                  blob: blob,
                  data: data,
                  environment: environment,
                  registrations: const <RestageWidgetLibraryRegistration>[],
                  entryWidgetName: 'Preview',
                  onRemoteEvent: (_, __) {},
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final nativeBoundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(nativeKey),
      );
      final bundleBoundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(bundleKey),
      );
      final captures = await tester.runAsync(
        () async => (
          native: await _pixels(nativeBoundary),
          bundle: await _pixels(bundleBoundary),
        ),
      );
      final (:native, :bundle) = captures!;

      expect(native, hasLength(640 * 480 * 4));
      expect(bundle, hasLength(640 * 480 * 4));
      expect(bundle, native);
    },
  );
}

class _ParityBoundary extends StatelessWidget {
  const _ParityBoundary({
    required this.boundaryKey,
    required this.child,
  });

  final Key boundaryKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        key: boundaryKey,
        child: ColoredBox(
          color: Colors.white,
          child: SizedBox(
            width: 320,
            height: 240,
            child: child,
          ),
        ),
      );
}

Future<List<int>> _pixels(RenderRepaintBoundary boundary) async {
  final image = await boundary.toImage(pixelRatio: 2);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
