import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';

class _ImageCompleter extends ImageStreamCompleter {
  void emit(ImageInfo image) => setImage(image);

  void fail(String message) => reportError(
        exception: StateError(message),
        stack: StackTrace.current,
      );
}

class _ImageProvider extends ImageProvider<String> {
  const _ImageProvider(this.key, this.completer);

  final String key;
  final _ImageCompleter completer;

  @override
  Future<String> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<String>(key);

  @override
  ImageStreamCompleter loadImage(String key, ImageDecoderCallback decode) =>
      completer;
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

void _cache(
  Object key,
  _ImageCompleter completer, {
  ui.Image? image,
  double scale = 1,
}) {
  PaintingBinding.instance.imageCache.putIfAbsent(key, () => completer);
  if (image != null) {
    completer.emit(ImageInfo(image: image.clone(), scale: scale));
  }
}

Finder _rawUnder(Finder ancestor) => find.descendant(
      of: ancestor,
      matching: find.byWidgetPredicate((Widget widget) => widget is RawImage),
    );

List<double> _opacities(WidgetTester tester, Finder finder) => tester
    .widgetList<RawImage>(finder)
    .map((RawImage image) => image.opacity?.value ?? 1)
    .toList();

void main() {
  tearDown(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  testWidgets('frame seam preserves native fields, wrappers, and order', (
    tester,
  ) async {
    final _ImageCompleter completer = _ImageCompleter();
    final _ImageProvider provider = _ImageProvider('fields', completer);
    final List<String> order = <String>[];
    const Key rawKey = ValueKey<String>('native-raw-key');
    final Animation<double> opacity = const AlwaysStoppedAnimation<double>(0.4);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(invertColors: true),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: RestageImage(
            image: provider,
            semanticLabel: 'field image',
            width: 20,
            height: 10,
            color: const ui.Color(0xFF112233),
            opacity: opacity,
            colorBlendMode: ui.BlendMode.srcOver,
            fit: BoxFit.fill,
            alignment: AlignmentDirectional.centerStart,
            repeat: ImageRepeat.repeatX,
            centerSlice: const ui.Rect.fromLTWH(1, 1, 2, 2),
            matchTextDirection: true,
            isAntiAlias: true,
            filterQuality: ui.FilterQuality.high,
            frameBuilder: (context, child, frame, synchronous) {
              order.add('frame:$frame:$synchronous');
              final Semantics semantics = child as Semantics;
              expect(semantics.child, isA<RawImage>());
              return KeyedSubtree(key: rawKey, child: child);
            },
            loadingBuilder: (context, child, progress) {
              order.add('loading:${progress == null}');
              return child;
            },
          ),
        ),
      ),
    );

    expect(order, <String>['frame:null:false', 'loading:true']);
    final Semantics semantics =
        tester.widget<Semantics>(find.byType(Semantics));
    expect(semantics.container, isTrue);
    expect(semantics.properties.label, 'field image');
    expect(semantics.properties.image, isTrue);
    RawImage raw = tester.widget<RawImage>(
      find.byWidgetPredicate((Widget widget) => widget is RawImage),
    );
    expect(raw.image, isNull);
    expect(raw.width, 20);
    expect(raw.height, 10);
    expect(raw.color, const ui.Color(0xFF112233));
    expect(raw.opacity, same(opacity));
    expect(raw.colorBlendMode, ui.BlendMode.srcOver);
    expect(raw.fit, BoxFit.fill);
    expect(raw.alignment, AlignmentDirectional.centerStart);
    expect(raw.repeat, ImageRepeat.repeatX);
    expect(raw.centerSlice, const ui.Rect.fromLTWH(1, 1, 2, 2));
    expect(raw.matchTextDirection, isTrue);
    expect(raw.invertColors, isTrue);
    expect(raw.isAntiAlias, isTrue);
    expect(raw.filterQuality, ui.FilterQuality.high);
    final RenderImage render = tester.renderObject<RenderImage>(
      find.byWidgetPredicate((Widget widget) => widget is RawImage),
    );
    expect(render.textDirection, TextDirection.rtl);

    final ui.Image decoded = _makeImage(2, 1);
    completer.emit(
      ImageInfo(image: decoded, scale: 2, debugLabel: 'decoded fields'),
    );
    await tester.pump();
    raw = tester.widget<RawImage>(
      find.byWidgetPredicate((Widget widget) => widget is RawImage),
    );
    expect(raw.key, isNull);
    expect(raw.image?.width, decoded.width);
    expect(raw.image?.height, decoded.height);
    expect(raw.debugImageLabel, 'decoded fields');
    expect(raw.scale, 2);
    expect(find.byKey(rawKey), findsOneWidget);
    expect(order.takeLast(2), <String>['frame:0:false', 'loading:true']);
    // Source, stream-owned clone, and the one native RawImage render clone.
    expect(decoded.debugGetOpenHandleStackTraces(), hasLength(3));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await tester.pump();
    // The stream's source handle remains until the cache's deferred disposal.
    expect(decoded.debugGetOpenHandleStackTraces(), hasLength(1));
  });

  testWidgets('provider updates, image-size changes, and errors stay native', (
    tester,
  ) async {
    final _ImageCompleter firstCompleter = _ImageCompleter();
    final _ImageCompleter secondCompleter = _ImageCompleter();
    final _ImageProvider first = _ImageProvider('first', firstCompleter);
    final _ImageProvider second = _ImageProvider('second', secondCompleter);

    Widget build(ImageProvider provider) => Directionality(
          textDirection: TextDirection.ltr,
          child: RestageImage(
            image: provider,
            errorBuilder: (_, error, __) => Text('error: $error'),
          ),
        );

    await tester.pumpWidget(build(first));
    final ui.Image firstImage = _makeImage(2, 1);
    firstCompleter.emit(ImageInfo(image: firstImage));
    await tester.pump();
    RenderImage render = tester.renderObject<RenderImage>(
      find.byWidgetPredicate((Widget widget) => widget is RawImage),
    );
    expect(render.image?.width, 2);
    expect(render.image?.height, 1);

    await tester.pumpWidget(build(second));
    final ui.Image secondImage = _makeImage(3, 2);
    secondCompleter.emit(ImageInfo(image: secondImage));
    await tester.pump();
    render = tester.renderObject<RenderImage>(
      find.byWidgetPredicate((Widget widget) => widget is RawImage),
    );
    expect(render.image?.width, 3);
    expect(render.image?.height, 2);

    secondCompleter.fail('target failed');
    await tester.pump();
    expect(find.textContaining('target failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fade lifecycle matches native for async and cached targets', (
    tester,
  ) async {
    final ui.Image placeholder = _makeImage(1, 1);
    final ui.Image target = _makeImage(2, 1);
    addTearDown(placeholder.dispose);
    addTearDown(target.dispose);
    final _ImageCompleter placeholderCompleter = _ImageCompleter();
    final _ImageCompleter targetCompleter = _ImageCompleter();
    _cache(
      AssetBundleImageKey(
        bundle: rootBundle,
        name: 'placeholder.png',
        scale: 1,
      ),
      placeholderCompleter,
      image: placeholder,
    );
    _cache(
      const NetworkImage('https://example.invalid/async.png'),
      targetCompleter,
    );

    Widget fade(bool guarded, String image) {
      const Key nativeKey = ValueKey<String>('native-fade');
      const Key guardedKey = ValueKey<String>('guarded-fade');
      return guarded
          ? RestageFadeInImage.assetNetwork(
              key: guardedKey,
              placeholder: 'placeholder.png',
              placeholderScale: 1,
              image: image,
              imageSemanticLabel: 'guarded fade',
            )
          : FadeInImage.assetNetwork(
              key: nativeKey,
              placeholder: 'placeholder.png',
              placeholderScale: 1,
              image: image,
              imageSemanticLabel: 'native fade',
            );
    }

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: <Widget>[
            fade(false, 'https://example.invalid/async.png'),
            fade(true, 'https://example.invalid/async.png'),
          ],
        ),
      ),
    );
    await tester.pump();
    final Finder native = find.byKey(const ValueKey<String>('native-fade'));
    final Finder guarded = find.byKey(const ValueKey<String>('guarded-fade'));
    expect(_rawUnder(native), findsNWidgets(2));
    expect(_rawUnder(guarded), findsNWidgets(2));

    targetCompleter.emit(ImageInfo(image: target.clone()));
    await tester.pump();
    expect(_rawUnder(native), findsNWidgets(2));
    expect(_rawUnder(guarded), findsNWidgets(2));
    expect(_opacities(tester, _rawUnder(guarded)),
        _opacities(tester, _rawUnder(native)));

    await tester.pump(const Duration(milliseconds: 150));
    expect(_opacities(tester, _rawUnder(guarded)),
        _opacities(tester, _rawUnder(native)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_opacities(tester, _rawUnder(guarded)),
        _opacities(tester, _rawUnder(native)));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 1));
    expect(_rawUnder(native), findsOneWidget);
    expect(_rawUnder(guarded), findsOneWidget);

    final SemanticsHandle semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('native fade'), findsOneWidget);
    expect(find.bySemanticsLabel('guarded fade'), findsOneWidget);
    semantics.dispose();

    final int targetHandlesBeforeUpdate =
        target.debugGetOpenHandleStackTraces()!.length;
    final ui.Image updatedTarget = _makeImage(3, 2);
    addTearDown(updatedTarget.dispose);
    final _ImageCompleter updatedCompleter = _ImageCompleter();
    _cache(
      const NetworkImage('https://example.invalid/updated.png'),
      updatedCompleter,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: <Widget>[
            fade(false, 'https://example.invalid/updated.png'),
            fade(true, 'https://example.invalid/updated.png'),
          ],
        ),
      ),
    );
    expect(_rawUnder(native), findsOneWidget);
    expect(_rawUnder(guarded), findsOneWidget);
    updatedCompleter.emit(ImageInfo(image: updatedTarget.clone()));
    await tester.pump();
    final List<RawImage> nativeUpdated =
        tester.widgetList<RawImage>(_rawUnder(native)).toList();
    final List<RawImage> guardedUpdated =
        tester.widgetList<RawImage>(_rawUnder(guarded)).toList();
    expect(nativeUpdated.single.image?.width, 3);
    expect(nativeUpdated.single.image?.height, 2);
    expect(guardedUpdated.single.image?.width, 3);
    expect(guardedUpdated.single.image?.height, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await tester.pump();
    expect(
      target.debugGetOpenHandleStackTraces()!.length,
      lessThan(targetHandlesBeforeUpdate),
    );

    final ui.Image cached = _makeImage(2, 1);
    addTearDown(cached.dispose);
    final _ImageCompleter cachedCompleter = _ImageCompleter();
    _cache(
      const NetworkImage('https://example.invalid/cached.png'),
      cachedCompleter,
      image: cached,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageFadeInImage.assetNetwork(
          placeholder: 'unused.png',
          placeholderScale: 1,
          image: 'https://example.invalid/cached.png',
        ),
      ),
    );
    expect(find.byType(Stack), findsNothing);
    expect(find.byWidgetPredicate((Widget widget) => widget is RawImage),
        findsOneWidget);
  });

  testWidgets('fade preserves placeholder and target error builders', (
    tester,
  ) async {
    final _ImageCompleter placeholderCompleter = _ImageCompleter();
    final _ImageCompleter targetCompleter = _ImageCompleter();
    _cache(
      AssetBundleImageKey(
        bundle: rootBundle,
        name: 'error-placeholder.png',
        scale: 1,
      ),
      placeholderCompleter,
    );
    _cache(
      const NetworkImage('https://example.invalid/error.png'),
      targetCompleter,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageFadeInImage.assetNetwork(
          placeholder: 'error-placeholder.png',
          placeholderScale: 1,
          placeholderErrorBuilder: (_, __, ___) =>
              const Text('placeholder error'),
          image: 'https://example.invalid/error.png',
          imageErrorBuilder: (_, __, ___) => const Text('target error'),
        ),
      ),
    );
    placeholderCompleter.fail('placeholder');
    await tester.pump();
    expect(find.text('placeholder error'), findsOneWidget);

    targetCompleter.fail('target');
    await tester.pump();
    expect(find.text('target error'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) => skip(length - count);
}
