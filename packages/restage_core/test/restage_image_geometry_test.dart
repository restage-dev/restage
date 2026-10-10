import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _rootLibrary = LibraryName(<String>['test', 'surface']);

class _ImageCompleter extends ImageStreamCompleter {
  void emit(ImageInfo image) => setImage(image);
}

class _ConstraintHost extends SingleChildRenderObjectWidget {
  const _ConstraintHost({required this.constraints, required super.child});

  final BoxConstraints constraints;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderConstraintHost(constraints);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderConstraintHost renderObject,
  ) {
    renderObject.childConstraints = constraints;
  }
}

class _RenderConstraintHost extends RenderProxyBox {
  _RenderConstraintHost(this._childConstraints);

  BoxConstraints _childConstraints;

  set childConstraints(BoxConstraints value) {
    if (_childConstraints == value) return;
    _childConstraints = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    child!.layout(_childConstraints, parentUsesSize: true);
    size = constraints.constrain(const Size.square(100));
  }

  @override
  void paint(PaintingContext context, Offset offset) {}
}

ui.Image _makeImage(int width, int height) {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = picture.toImageSync(width, height);
  picture.dispose();
  return image;
}

_ImageCompleter _seedNetwork(String url, double scale, ui.Image image) {
  final _ImageCompleter completer = _ImageCompleter();
  PaintingBinding.instance.imageCache.putIfAbsent(
    NetworkImage(url, scale: scale),
    () => completer,
  );
  completer.emit(ImageInfo(image: image.clone(), scale: scale));
  return completer;
}

Future<RenderImage> _pumpGeneratedFade(
  WidgetTester tester, {
  required String url,
  required double scale,
  required ui.Image image,
  required BoxConstraints constraints,
  double? width,
  double? height,
}) async {
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  _seedNetwork(url, scale, image);
  final String dimensions = <String>[
    if (width != null) 'width: $width',
    if (height != null) 'height: $height',
  ].join(', ');
  final Runtime runtime = Runtime()
    ..update(_coreLibrary, buildCoreWidgetLibrary())
    ..update(
      _rootLibrary,
      parseLibraryFile('''
import restage.core;
widget Surface = FadeInImageAssetNetwork(
  placeholder: "unused.png",
  image: "$url",
  imageScale: $scale,
  $dimensions
);
'''),
    );
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: _ConstraintHost(
        constraints: constraints,
        child: RemoteWidget(
          runtime: runtime,
          data: DynamicContent(),
          widget: const FullyQualifiedWidgetName(_rootLibrary, 'Surface'),
          onEvent: (_, __) {},
        ),
      ),
    ),
  );
  await tester.pump();
  expect(find.byType(RestageFadeInImage, skipOffstage: false), findsOneWidget);
  expect(find.byType(FadeInImage, skipOffstage: false), findsNothing);
  expect(
    tester.widget<RestageFadeInImage>(find.byType(RestageFadeInImage)),
    isA<FadeInImage>(),
  );
  expect(tester.takeException(), isNull);
  return tester.renderObject<RenderImage>(
    find.byWidgetPredicate(
      (Widget widget) => widget is RawImage,
      skipOffstage: false,
    ),
  );
}

void main() {
  tearDown(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  testWidgets('generated fade repairs only non-finite decoded-image results', (
    tester,
  ) async {
    final ui.Image image = _makeImage(2, 1);
    addTearDown(image.dispose);

    RenderImage render = await _pumpGeneratedFade(
      tester,
      url: 'https://example.invalid/tiny.png',
      scale: 1e-309,
      image: image,
      constraints: const BoxConstraints(),
    );
    expect(render.size, const Size(2, 1));
    expect(render.getDryLayout(const BoxConstraints()), const Size(2, 1));
    expect(render.getMinIntrinsicWidth(double.infinity), 0);
    expect(render.getMinIntrinsicHeight(double.infinity), 0);
    expect(render.getMaxIntrinsicWidth(double.infinity), 2);
    expect(render.getMaxIntrinsicHeight(double.infinity), 1);

    const BoxConstraints bounded = BoxConstraints(
      maxWidth: 100,
      maxHeight: 100,
    );
    render = await _pumpGeneratedFade(
      tester,
      url: 'https://example.invalid/bounded.png',
      scale: 1e-309,
      image: image,
      constraints: bounded,
    );
    final RenderImage native = RenderImage(
      image: image.clone(),
      scale: 1e-309,
    );
    addTearDown(native.dispose);
    final Size nativeBounded = native.getDryLayout(bounded);
    expect(nativeBounded, const Size.square(100));
    expect(render.size, nativeBounded);
    expect(render.getDryLayout(bounded), nativeBounded);

    render = await _pumpGeneratedFade(
      tester,
      url: 'https://example.invalid/legal.png',
      scale: 1e-307,
      image: image,
      constraints: const BoxConstraints(),
    );
    final RenderImage legalNative = RenderImage(
      image: image.clone(),
      scale: 1e-307,
    );
    addTearDown(legalNative.dispose);
    final Size legal = legalNative.getDryLayout(const BoxConstraints());
    expect(legal.isFinite, isTrue);
    expect(render.size, legal);
    expect(render.getDryLayout(const BoxConstraints()), legal);

    render = await _pumpGeneratedFade(
      tester,
      url: 'https://example.invalid/width.png',
      scale: 1e-309,
      image: image,
      constraints: const BoxConstraints(),
      width: 50,
    );
    expect(render.size, const Size(50, 25));
    expect(render.getDryLayout(const BoxConstraints()), const Size(50, 25));
  });

  testWidgets('scale-one overflow fails before assigning image geometry', (
    tester,
  ) async {
    final ui.Image image = _makeImage(2, 1);
    addTearDown(image.dispose);
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    _seedNetwork('https://example.invalid/fail.png', 1e-309, image);

    final Runtime runtime = Runtime()
      ..update(_coreLibrary, buildCoreWidgetLibrary())
      ..update(
        _rootLibrary,
        parseLibraryFile('''
import restage.core;
widget Surface = FadeInImageAssetNetwork(
  placeholder: "unused.png",
  image: "https://example.invalid/fail.png",
  imageScale: 1e-309,
  height: data.height
);
'''),
      );
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: _ConstraintHost(
        constraints: const BoxConstraints(maxWidth: 100, maxHeight: 100),
        child: RemoteWidget(
          runtime: runtime,
          data: DynamicContent(<String, Object?>{
            'height': double.maxFinite,
          }),
          widget: const FullyQualifiedWidgetName(_rootLibrary, 'Surface'),
          onEvent: (_, __) {},
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final RenderImage render = tester.renderObject<RenderImage>(
      find.byWidgetPredicate(
        (Widget widget) => widget is RawImage,
        skipOffstage: false,
      ),
    );
    expect(render.size, const Size.square(100));
    expect(
      () => render.getDryLayout(const BoxConstraints()),
      throwsA(isA<FlutterError>()),
    );
    expect(
      () => render.getMaxIntrinsicWidth(double.maxFinite),
      throwsA(isA<FlutterError>()),
    );
  });

  testWidgets('generated image routes retain providers and built-in boundary', (
    tester,
  ) async {
    final List<ui.Image> decoded = <ui.Image>[
      _makeImage(2, 1),
      _makeImage(3, 2),
      _makeImage(4, 3),
      _makeImage(5, 4),
      _makeImage(6, 5),
      _makeImage(7, 6),
    ];
    addTearDown(() {
      for (final ui.Image image in decoded) {
        image.dispose();
      }
    });
    final _ImageCompleter networkCompleter = _seedNetwork(
      'https://example.invalid/one.png',
      1,
      decoded[0],
    );
    final _ImageCompleter assetCompleter = _ImageCompleter();
    PaintingBinding.instance.imageCache.putIfAbsent(
      AssetBundleImageKey(bundle: rootBundle, name: 'one.png', scale: 1),
      () => assetCompleter,
    );
    assetCompleter.emit(ImageInfo(image: decoded[1].clone()));
    final DynamicContent data = DynamicContent(<String, Object?>{
      'network': 'https://example.invalid/one.png',
      'asset': 'one.png',
    });
    final Runtime runtime = Runtime()
      ..update(_coreLibrary, buildCoreWidgetLibrary())
      ..update(
        _rootLibrary,
        parseLibraryFile('''
import restage.core;
widget Surface = Column(children: [
  Image(url: data.network),
  ImageAsset(name: data.asset)
]);
'''),
      );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RemoteWidget(
          runtime: runtime,
          data: data,
          widget: const FullyQualifiedWidgetName(_rootLibrary, 'Surface'),
          onEvent: (_, __) {},
        ),
      ),
    );
    await tester.pump();

    List<RestageImage> images() =>
        tester.widgetList<RestageImage>(find.byType(RestageImage)).toList();
    List<RawImage> leaves() => List<RawImage>.generate(
          2,
          (int index) => tester.widget<RawImage>(
            find.descendant(
              of: find.byType(RestageImage).at(index),
              matching: find.byWidgetPredicate(
                (Widget widget) => widget is RawImage,
              ),
            ),
          ),
        );
    List<RenderImage> renders() => List<RenderImage>.generate(
          2,
          (int index) => tester.renderObject<RenderImage>(
            find.descendant(
              of: find.byType(RestageImage).at(index),
              matching: find.byWidgetPredicate(
                (Widget widget) => widget is RawImage,
              ),
            ),
          ),
        );

    expect(images(), hasLength(2));
    expect(images(), everyElement(isA<Image>()));
    expect(images()[0].image, isA<NetworkImage>());
    expect(
      (images()[0].image as NetworkImage).webHtmlElementStrategy,
      WebHtmlElementStrategy.never,
    );
    expect(images()[1].image, isA<AssetImage>());
    expect(
      leaves().map((RawImage image) => image.image?.width).toList(),
      <int?>[2, 3],
    );
    expect(
      leaves().map((RawImage image) => image.image?.height).toList(),
      <int?>[1, 2],
    );
    expect(
        renders().map((RenderImage image) => image.size).toList(), const <Size>[
      Size(2, 1),
      Size(3, 2),
    ]);
    const BoxConstraints scaleOneOverflow = BoxConstraints.tightForFinite(
      height: double.maxFinite,
    );
    networkCompleter.emit(ImageInfo(image: decoded[2].clone()));
    assetCompleter.emit(ImageInfo(image: decoded[3].clone()));
    await tester.pump();
    expect(
      leaves().map((RawImage image) => image.image?.width).toList(),
      <int?>[4, 5],
    );
    expect(
      leaves().map((RawImage image) => image.image?.height).toList(),
      <int?>[3, 4],
    );
    expect(
        renders().map((RenderImage image) => image.size).toList(), const <Size>[
      Size(4, 3),
      Size(5, 4),
    ]);

    _seedNetwork(
      'https://example.invalid/two.png',
      1,
      decoded[4],
    );
    final _ImageCompleter updatedAssetCompleter = _ImageCompleter();
    PaintingBinding.instance.imageCache.putIfAbsent(
      AssetBundleImageKey(bundle: rootBundle, name: 'two.png', scale: 1),
      () => updatedAssetCompleter,
    );
    updatedAssetCompleter.emit(ImageInfo(image: decoded[5].clone()));
    data
      ..update('network', 'https://example.invalid/two.png')
      ..update('asset', 'two.png');
    await tester.pump();

    expect((images()[0].image as NetworkImage).url, endsWith('two.png'));
    expect((images()[1].image as AssetImage).assetName, 'two.png');
    expect(
      leaves().map((RawImage image) => image.image?.width).toList(),
      <int?>[6, 7],
    );
    expect(
      leaves().map((RawImage image) => image.image?.height).toList(),
      <int?>[5, 6],
    );
    expect(
        renders().map((RenderImage image) => image.size).toList(), const <Size>[
      Size(6, 5),
      Size(7, 6),
    ]);

    for (final RenderImage render in renders()) {
      expect(
        () => render.getDryLayout(scaleOneOverflow),
        throwsA(isA<FlutterError>()),
      );
    }

    expect(find.byType(Image), findsNothing);
  });
}
