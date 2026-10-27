import 'dart:convert';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const _core = LibraryName(['restage', 'core']);
const _surface = LibraryName(['test', 'clip']);
const _shape = RoundedRectangleBorder(
  borderRadius: BorderRadius.only(topLeft: Radius.circular(12)),
);
const _directionalShape = RoundedRectangleBorder(
  borderRadius: BorderRadiusDirectional.only(topStart: Radius.circular(12)),
);
const _child = SizedBox(width: 60, height: 40);
const CustomClipper<Path>? _noClipper = null;

Widget _native(String form) => switch (form) {
      'plain' => const ClipPath(child: _child),
      'constNull' => const ClipPath(clipper: _noClipper, child: _child),
      'none' =>
        const ClipPath(clipper: null, clipBehavior: Clip.none, child: _child),
      'directNull' => const ClipPath(
          clipper: ShapeBorderClipper(shape: _shape), child: _child),
      'directLtr' => const ClipPath(
          clipper: ShapeBorderClipper(
              shape: _shape, textDirection: TextDirection.ltr),
          child: _child),
      'directRtl' => const ClipPath(
          clipper: ShapeBorderClipper(
              shape: _shape, textDirection: TextDirection.rtl),
          child: _child),
      'shape' => ClipPath.shape(shape: _shape, child: _child),
      'directionalShape' =>
        ClipPath.shape(shape: _directionalShape, child: _child),
      'directionalLtr' => const ClipPath(
          clipper: ShapeBorderClipper(
              shape: _directionalShape, textDirection: TextDirection.ltr),
          child: _child),
      'directionalRtl' => const ClipPath(
          clipper: ShapeBorderClipper(
              shape: _directionalShape, textDirection: TextDirection.rtl),
          child: _child),
      _ => throw StateError(form),
    };

void main() {
  final compiled = jsonDecode(
          File('test/fixtures/clip_path_compiled.json').readAsStringSync())
      as Map<String, dynamic>;
  for (final form in compiled.keys) {
    testWidgets('compiled $form matches native clipping and direction refresh',
        (tester) async {
      final runtime = Runtime()
        ..update(_core, buildCoreWidgetLibrary())
        ..update(
            _surface,
            decodeLibraryBlob(encodeLibraryBlob(parseLibraryFile(
              'import restage.core; widget Surface = ${compiled[form]};',
            ))));
      addTearDown(runtime.dispose);
      final content = Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _native(form),
          RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: const FullyQualifiedWidgetName(_surface, 'Surface'),
          ),
        ]),
      );
      for (final direction in [
        TextDirection.ltr,
        TextDirection.rtl,
        TextDirection.ltr
      ]) {
        await tester.pumpWidget(Directionality(
          textDirection: direction,
          child: content,
        ));
        expect(tester.takeException(), isNull);
        final clips = find.byType(ClipPath);
        expect(clips, findsNWidgets(2));
        final native = tester.widget<ClipPath>(clips.at(0));
        final delivered = tester.widget<ClipPath>(clips.at(1));
        final nativeRender = tester.renderObject<RenderClipPath>(clips.at(0));
        final deliveredRender =
            tester.renderObject<RenderClipPath>(clips.at(1));
        expect(delivered.clipBehavior, native.clipBehavior);
        expect(deliveredRender.clipBehavior, nativeRender.clipBehavior);
        expect(deliveredRender.size, const Size(60, 40));
        expect(deliveredRender.size, nativeRender.size);
        if (native.clipper == null) {
          expect(delivered.clipper, isNull);
          continue;
        }
        final nativeClipper = native.clipper! as ShapeBorderClipper;
        final deliveredClipper = delivered.clipper! as ShapeBorderClipper;
        expect(deliveredClipper.textDirection, nativeClipper.textDirection);
        expect(
            deliveredClipper.textDirection,
            switch (form) {
              'shape' || 'directionalShape' => direction,
              'directLtr' || 'directionalLtr' => TextDirection.ltr,
              'directRtl' || 'directionalRtl' => TextDirection.rtl,
              _ => null,
            });
        expect(delivered.clipBehavior, Clip.antiAlias);
        final nativePath = nativeClipper.getClip(nativeRender.size);
        final deliveredPath = deliveredClipper.getClip(deliveredRender.size);
        expect(deliveredPath.getBounds(), nativePath.getBounds());
        final roundsRight = form.startsWith('directional') &&
            nativeClipper.textDirection == TextDirection.rtl;
        expect(deliveredPath.contains(const Offset(1, 1)), roundsRight);
        expect(deliveredPath.contains(const Offset(59, 1)), !roundsRight);
        for (var x = -1.0; x <= 61; x += 2) {
          for (var y = -1.0; y <= 41; y += 2) {
            final point = Offset(x, y);
            expect(deliveredPath.contains(point), nativePath.contains(point),
                reason: '$form $direction $point');
          }
        }
      }
    });
  }
}
