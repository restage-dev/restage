import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';

void main() {
  final image = MemoryImage(
      File('test/widgets/fixtures/mask_image.png').readAsBytesSync());
  setUpAll(() async {
    final configFile = File('../../.dart_tool/package_config.json');
    final config = jsonDecode(configFile.readAsStringSync()) as Map;
    final flutter = (config['packages'] as List)
        .cast<Map>()
        .singleWhere((p) => p['name'] == 'flutter');
    final root = configFile.absolute.uri
        .resolve(flutter['rootUri'] as String)
        .toFilePath();
    final font = File(
        '$root/../../bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync()))))
        .load();
  });
  const linear = LinearGradient(colors: [Colors.purple, Colors.orange]);
  const fade = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        Colors.white,
        Colors.white,
        Colors.transparent
      ],
      stops: [
        0,
        0.2,
        0.8,
        1
      ]);
  const vignette =
      RadialGradient(colors: [Colors.white, Colors.black], radius: 0.7);
  final examples = [
    (
      name: 'gradient_text',
      gradient: linear,
      color: null,
      mode: BlendMode.srcIn,
      child: const Text('Explore',
          style: TextStyle(fontSize: 38, color: Colors.white))
    ),
    (
      name: 'gradient_icon',
      gradient: linear,
      color: null,
      mode: BlendMode.srcIn,
      child: const Icon(Icons.star, size: 120, color: Colors.white)
    ),
    (
      name: 'fading_edge',
      gradient: fade,
      color: null,
      mode: BlendMode.dstIn,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 5; i++)
          Padding(
              padding: const EdgeInsets.all(4),
              child: Text('Activity $i',
                  style: const TextStyle(fontSize: 20, color: Colors.indigo))),
      ])
    ),
    (
      name: 'radial_vignette',
      gradient: vignette,
      color: null,
      mode: BlendMode.modulate,
      child: Image(image: image, width: 220, height: 160, fit: BoxFit.cover)
    ),
    (
      name: 'color_tint',
      gradient: null,
      color: Colors.teal,
      mode: BlendMode.modulate,
      child: Image(image: image, width: 220, height: 160, fit: BoxFit.cover)
    ),
  ];
  for (final example in examples) {
    testWidgets('${example.name} matches Flutter and its light golden',
        (tester) async {
      final native = example.gradient == null
          ? ColorFiltered(
              colorFilter: ColorFilter.mode(example.color!, example.mode),
              child: example.child)
          : ShaderMask(
              shaderCallback: example.gradient!.createShader,
              blendMode: example.mode,
              child: example.child);
      Future<void> pump(Widget effect) async {
        await tester.pumpWidget(MaterialApp(
            home: Center(
                child: RepaintBoundary(
          key: const Key('mask-golden'),
          child: ColoredBox(
              color: Colors.white,
              child: SizedBox(
                  width: 260, height: 200, child: Center(child: effect))),
        ))));
        await tester.runAsync(() =>
            precacheImage(image, tester.element(find.byType(Center).first)));
        await tester.pumpAndSettle();
      }

      await pump(native);
      final expected = await tester.runAsync(() => _pixels(tester));
      await pump(RestageShaderMask(
          gradient: example.gradient,
          color: example.color,
          blendMode: example.mode,
          child: example.child));
      expect(await tester.runAsync(() => _pixels(tester)), expected,
          reason: 'pixel parity with Flutter');
      await expectLater(find.byKey(const Key('mask-golden')),
          matchesGoldenFile('goldens/${example.name}.png'));
    });
  }
}

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('mask-golden')));
  final image = await boundary.toImage();
  final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
      .buffer
      .asUint8List();
  image.dispose();
  return pixels;
}
