import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ColorSpace;

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart' hide svg;
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart'
    show buildCoreWidgetLibrary, RestageDecoders;
import 'package:restage_svg/restage_svg.dart';
import 'package:restage_svg/src/native_values.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

import 'svg_runtime_test.dart' show WaitingBundle, svg;

void main() {
  testWidgets(
    'SVG kind and common Paint type retain separate color filter routes',
    (tester) async {
      const color = Color.from(
        alpha: .75,
        red: .2,
        green: .4,
        blue: .8,
        colorSpace: ColorSpace.displayP3,
      );
      final filters = <ColorFilter?>[];
      final runtime = Runtime()
        ..update(
          const LibraryName(['probe']),
          LocalWidgetLibrary({
            'Probe': (context, source) {
              filters.add(SvgNativeValues.colorFilter(source, ['svg']));
              filters.add(
                RestageDecoders.paint(source, ['paint'])?.colorFilter,
              );
              return const SizedBox();
            },
          }),
        )
        ..update(
          const LibraryName(['surface']),
          parseLibraryFile('''
        import probe;
        widget Root = Probe(
          svg: {kind: "srgbToLinearGamma", type: "mode", color: {a: 0.75, r: 0.2, g: 0.4, b: 0.8, colorSpace: "displayP3"}},
          paint: {colorFilter: {type: "mode", kind: "srgbToLinearGamma", color: {a: 0.75, r: 0.2, g: 0.4, b: 0.8, colorSpace: "displayP3"}, blendMode: "srcIn"}}
        );
      '''),
        );
      addTearDown(runtime.dispose);
      await tester.pumpWidget(
        RemoteWidget(
          runtime: runtime,
          data: DynamicContent(),
          widget: const FullyQualifiedWidgetName(
            LibraryName(['surface']),
            'Root',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(filters, [
        const ColorFilter.srgbToLinearGamma(),
        const ColorFilter.mode(color, BlendMode.srcIn),
      ]);
    },
  );
  testWidgets(
    'compiled exact SVG values preserve native placeholder scopes and directional clipping',
    (tester) async {
      const base = Color.from(
        alpha: .75,
        red: .2,
        green: .4,
        blue: .8,
        colorSpace: ColorSpace.displayP3,
      );
      final pending = Completer<ByteData>();
      final bundle = WaitingBundle(pending.future);
      const surface = LibraryName(['test', 'surface']);
      final runtime = Runtime()
        ..update(
          const LibraryName(['restage', 'core']),
          buildCoreWidgetLibrary(),
        )
        ..update(
          const LibraryName(['restage', 'svg']),
          buildCuratedWidgetLibrary(),
        )
        ..update(
          surface,
          parseLibraryFile(
            'import restage.core; import restage.svg; widget Screen = ${File('test/fixtures/combined_picture.rfwtxt').readAsStringSync().trim()};',
          ),
        );
      addTearDown(runtime.dispose);
      final remote = RemoteWidget(
        runtime: runtime,
        data: DynamicContent(),
        widget: const FullyQualifiedWidgetName(surface, 'Screen'),
      );
      final native = LayoutBuilder(
        builder: (outer, constraints) => DefaultTextStyle(
          style: const TextStyle(fontSize: 27, fontWeight: FontWeight(550)),
          child: ClipPath.shape(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadiusDirectional.only(
                topStart: Radius.circular(8),
              ),
            ),
            child: SvgPicture.asset(
              'tiny.svg',
              package: 'fixture_icons',
              width: 24,
              height: 24,
              color: null,
              theme: SvgTheme(
                currentColor: base,
                fontSize: constraints.maxWidth / 10,
              ),
              colorFilter: const ColorFilter.mode(base, BlendMode.srcIn),
              placeholderBuilder: (localBuildContext) => SizedBox(
                width: DefaultTextStyle.of(localBuildContext).style.fontSize,
                height: DefaultTextStyle.of(outer).style.fontSize,
              ),
            ),
          ),
        ),
      );
      final content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 320, child: native),
            SizedBox(width: 320, child: remote),
          ],
        ),
      );
      for (final (font, direction) in [
        (14.0, TextDirection.ltr),
        (16.0, TextDirection.rtl),
        (16.0, TextDirection.ltr),
      ]) {
        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: bundle,
            child: Directionality(
              textDirection: direction,
              child: DefaultTextStyle(
                style: TextStyle(fontSize: font),
                child: content,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is SizedBox &&
                widget.width == 27 &&
                widget.height == font,
          ),
          findsNWidgets(2),
        );
        final pictures = tester
            .widgetList<SvgPicture>(find.byType(SvgPicture))
            .toList();
        expect(pictures, hasLength(2));
        for (final picture in pictures) {
          final loader = picture.bytesLoader as SvgAssetLoader;
          expect(loader.assetName, 'tiny.svg');
          expect(loader.packageName, 'fixture_icons');
          expect(loader.theme!.currentColor, base);
          expect(loader.theme!.currentColor.colorSpace, ColorSpace.displayP3);
          expect(loader.theme!.fontSize, 32);
          expect(loader.theme!.xHeight, 16);
          expect(
            picture.colorFilter,
            const ColorFilter.mode(base, BlendMode.srcIn),
          );
        }
        final clips = find.byType(ClipPath);
        expect(clips, findsNWidgets(2));
        final paths = <Path>[];
        for (var index = 0; index < 2; index++) {
          final clip = tester.widget<ClipPath>(clips.at(index));
          final render = tester.renderObject<RenderClipPath>(clips.at(index));
          final clipper = clip.clipper! as ShapeBorderClipper;
          expect(clipper.textDirection, direction);
          paths.add(clipper.getClip(render.size));
        }
        expect(paths[1].getBounds(), paths[0].getBounds());
        final bounds = paths[0].getBounds();
        expect(
          paths[1].contains(const Offset(1, 1)),
          direction == TextDirection.rtl,
        );
        expect(
          paths[1].contains(Offset(bounds.width - 1, 1)),
          direction == TextDirection.ltr,
        );
        for (var x = -1.0; x < bounds.width + 2; x += 3) {
          for (var y = -1.0; y < bounds.height + 2; y += 3) {
            expect(
              paths[1].contains(Offset(x, y)),
              paths[0].contains(Offset(x, y)),
            );
          }
        }
      }
      pending.complete(
        ByteData.sublistView(Uint8List.fromList(utf8.encode(svg))),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox && widget.width == 27 && widget.height == 16,
        ),
        findsNothing,
      );
      final pictures = tester
          .widgetList<SvgPicture>(find.byType(SvgPicture))
          .toList();
      for (var index = 0; index < pictures.length; index++) {
        final info = await tester.runAsync(
          () => vg.loadPicture(
            pictures[index].bytesLoader,
            tester.element(find.byType(SvgPicture).at(index)),
          ),
        );
        expect(info!.size, const Size(10, 10));
        info.picture.dispose();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
