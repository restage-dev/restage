import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('actual Flutter PNG encoder matches the accepted screen-sample fixture',
      () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 1, 2),
      ui.Paint()..color = const ui.Color(0xffff0000),
    );
    canvas.drawRect(
      const ui.Rect.fromLTWH(1, 0, 1, 1),
      ui.Paint()..color = const ui.Color(0x8000ff00),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(3, 2);
    try {
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(encoded, isNotNull);
      final bytes = encoded!.buffer.asUint8List(
        encoded.offsetInBytes,
        encoded.lengthInBytes,
      );
      final fixture = File(
        '../restage_shared/test/fixtures/placements/flutter_screen_sample.png',
      ).readAsBytesSync();

      expect(bytes, orderedEquals(fixture));
      final validated = validatePlacementScreenSamplePng(bytes);
      expect(validated.bytes, orderedEquals(fixture));
      expect(validated.width, image.width);
      expect(validated.height, image.height);
    } finally {
      image.dispose();
      picture.dispose();
    }
  });
}
