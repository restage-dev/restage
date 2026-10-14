import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/runtime/first_paint_lease_guard.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _rootLibrary = LibraryName(<String>['test', 'surface']);

class _ImageCompleter extends ImageStreamCompleter {
  void emit(ImageInfo image) => setImage(image);
}

class _ConstraintHost extends SingleChildRenderObjectWidget {
  const _ConstraintHost({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderConstraintHost();
}

class _RenderConstraintHost extends RenderProxyBox {
  @override
  bool get sizedByParent => true;

  @override
  void performResize() {
    size = constraints.biggest;
  }

  @override
  void performLayout() {
    child!.layout(
      const BoxConstraints(maxHeight: double.maxFinite),
      parentUsesSize: false,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {}
}

ui.Image _makeImage() {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 2, 1),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = picture.toImageSync(2, 1);
  picture.dispose();
  return image;
}

Set<String> _semanticsLabels(WidgetTester tester) {
  final Set<String> labels = <String>{};
  void visit(SemanticsNode node) {
    final String label = node.getSemanticsData().label;
    if (label.isNotEmpty) labels.add(label);
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return true;
    });
  }

  for (final RenderView view in tester.binding.renderViews) {
    final SemanticsNode? root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
  }
  return labels;
}

void main() {
  tearDown(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  testWidgets(
    'generated decoded-image failure is owned before paint and stale semantics',
    (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final ui.Image image = _makeImage();
      addTearDown(image.dispose);
      const String url = 'https://example.invalid/owned-image.png';
      final _ImageCompleter completer = _ImageCompleter();
      PaintingBinding.instance.imageCache.putIfAbsent(
        const NetworkImage(url, scale: 1e-309),
        () => completer,
      );
      completer.emit(ImageInfo(image: image.clone(), scale: 1e-309));

      final Runtime runtime = Runtime()
        ..update(_coreLibrary, buildCoreWidgetLibrary())
        ..update(
          _rootLibrary,
          parseLibraryFile('''
import restage.core;
widget Surface = Column(children: [
  Text(text: "image content semantics"),
  FadeInImageAssetNetwork(
    placeholder: "unused.png",
    image: "$url",
    imageScale: 1e-309,
    height: data.height
  )
]);
'''),
        );
      var committed = false;
      var painted = false;
      var afterCommit = false;
      var errors = 0;
      Object? owned;
      final FirstPaintLeaseTransaction transaction = FirstPaintLeaseTransaction(
        canCommit: () => true,
        commit: () => committed = true,
        onPainted: () => painted = true,
        afterCommit: () => afterCommit = true,
        afterRejection: () {},
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: FirstPaintLeaseScope(
            transaction: transaction,
            child: FirstPaintLeaseGuard(
              transaction: transaction,
              armed: true,
              child: RuntimeErrorBoundary(
                onError: (Object error, StackTrace? stack) {
                  errors += 1;
                  owned ??= error;
                },
                errorReplacement: (_, __, ___) =>
                    const Text('image fallback semantics'),
                child: _ConstraintHost(
                  child: RemoteWidget(
                    runtime: runtime,
                    data: DynamicContent(<String, Object?>{
                      'height': double.maxFinite,
                    }),
                    widget: const FullyQualifiedWidgetName(
                      _rootLibrary,
                      'Surface',
                    ),
                    onEvent: (_, __) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(owned, isA<FlutterError>());
      expect(owned.toString(), contains('Image produced a non-finite layout'));
      expect(errors, 1);
      expect(committed, isTrue);
      expect(painted, isFalse);
      expect(afterCommit, isFalse);
      expect(transaction.isCommitted, isTrue);
      expect(transaction.isPaintAcknowledged, isFalse);
      expect(find.text('image fallback semantics'), findsOneWidget);
      expect(_semanticsLabels(tester), contains('image fallback semantics'));
      expect(
          _semanticsLabels(tester), isNot(contains('image content semantics')));
      expect(tester.takeException(), isNotNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      semantics.dispose();
    },
  );
}
