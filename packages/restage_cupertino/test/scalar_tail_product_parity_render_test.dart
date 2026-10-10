import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_cupertino/restage_cupertino.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide WidgetLibrary;

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _cupertinoLibrary =
    LibraryName(<String>['restage', 'cupertino']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'surface']);

RemoteWidget _remoteWidget(
  String body, {
  Map<String, Object?> data = const <String, Object?>{},
}) {
  final runtime = Runtime()
    ..update(_coreLibrary, core.buildCoreWidgetLibrary())
    ..update(_cupertinoLibrary, buildCupertinoWidgetLibrary())
    ..update(
      _rootLibrary,
      parseLibraryFile('''
import restage.core;
import restage.cupertino;
widget Surface = $body;
'''),
    );
  return RemoteWidget(
    runtime: runtime,
    data: DynamicContent(data),
    widget: const FullyQualifiedWidgetName(_rootLibrary, 'Surface'),
    onEvent: (_, __) {},
  );
}

Future<void> _pump(
  WidgetTester tester,
  String body, {
  Map<String, Object?> data = const <String, Object?>{},
}) async {
  await tester.pumpWidget(
    CupertinoApp(
      home: Center(
        child: SizedBox(
          width: 300,
          height: 300,
          child: _remoteWidget(body, data: data),
        ),
      ),
    ),
  );
  await tester.pump();
}

SizedBox _indicatorBox(WidgetTester tester) => tester.widget<SizedBox>(
      find.descendant(
        of: find.byType(CupertinoActivityIndicator),
        matching: find.byType(SizedBox),
      ),
    );

double _pickerOverlayHeight(WidgetTester tester) {
  double? height;
  tester
      .element(find.byType(CupertinoPickerDefaultSelectionOverlay))
      .visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is ConstrainedBox && widget.constraints.hasTightHeight) {
      height = widget.constraints.maxHeight;
      return false;
    }
    return true;
  });
  return height!;
}

Widget _indicatorHost(Widget child) => CupertinoApp(
      home: Center(
        child: SizedBox(
          width: 300,
          height: 300,
          child: Center(child: child),
        ),
      ),
    );

class _HugePickerHost extends SingleChildRenderObjectWidget {
  const _HugePickerHost({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _HugePickerBox();
}

class _HugePickerBox extends RenderProxyBox {
  @override
  void performLayout() {
    child!.layout(
      const BoxConstraints.tightFor(width: 300, height: 1.5e308),
      parentUsesSize: true,
    );
    size = constraints.smallest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {}
}

Widget _pickerHost(Widget child) => CupertinoApp(
      home: _HugePickerHost(child: child),
    );

void main() {
  testWidgets('activity indicator preserves native finite constrained layout',
      (tester) async {
    await tester.pumpWidget(
      _indicatorHost(
        const CupertinoActivityIndicator(
          radius: 1e308,
          animating: false,
        ),
      ),
    );
    final nativeSize = tester.getSize(find.byType(CupertinoActivityIndicator));
    expect(nativeSize, const Size(300, 300));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _indicatorHost(
        _remoteWidget(
          'CupertinoActivityIndicator(radius: 1e308, animating: false)',
        ),
      ),
    );
    final generatedIndicator = tester.widget<CupertinoActivityIndicator>(
      find.byType(CupertinoActivityIndicator),
    );
    final generatedSize =
        tester.getSize(find.byType(CupertinoActivityIndicator));
    expect(generatedSize, const Size(300, 300));
    expect(generatedSize, nativeSize);
    expect(generatedIndicator.radius, 1e308);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity radius keeps the largest tested finite diameter',
      (tester) async {
    await _pump(tester, 'CupertinoActivityIndicator(radius: 8e307)');

    final indicator = tester.widget<CupertinoActivityIndicator>(
      find.byType(CupertinoActivityIndicator),
    );
    expect(indicator.radius, 8e307);
    expect(_indicatorBox(tester).width, 1.6e308);
    expect(tester.getSize(find.byType(CupertinoActivityIndicator)).isFinite,
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity radius rejects hostile bound data', (tester) async {
    for (final value in [double.nan, double.infinity, -1.0, 0.0]) {
      await _pump(
        tester,
        'CupertinoActivityIndicator(radius: data.radius)',
        data: <String, Object?>{'radius': value},
      );
      expect(
        tester
            .widget<CupertinoActivityIndicator>(
              find.byType(CupertinoActivityIndicator),
            )
            .radius,
        10,
      );
      expect(_indicatorBox(tester).width, 20);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('picker overlay preserves native finite constrained layout',
      (tester) async {
    await tester.pumpWidget(
      _pickerHost(
        CupertinoPicker(
          itemExtent: 1e308,
          magnification: 2,
          squeeze: 1,
          onSelectedItemChanged: null,
          children: const [SizedBox(width: 10, height: 10)],
        ),
      ),
      phase: EnginePhase.layout,
    );
    final nativeSize = tester.getSize(
      find.byType(CupertinoPickerDefaultSelectionOverlay),
    );
    expect(nativeSize, const Size(300, 1.5e308));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _pickerHost(
        _remoteWidget(
          'CupertinoPicker(itemExtent: 1e308, magnification: 2.0, '
          'squeeze: 1.0, '
          'children: [SizedBox(width: 10.0, height: 10.0)])',
        ),
      ),
      phase: EnginePhase.layout,
    );
    final generatedPicker =
        tester.widget<CupertinoPicker>(find.byType(CupertinoPicker));
    final generatedSize = tester.getSize(
      find.byType(CupertinoPickerDefaultSelectionOverlay),
    );
    expect(generatedSize, const Size(300, 1.5e308));
    expect(generatedSize, nativeSize);
    expect(generatedPicker.itemExtent, 1e308);
    expect(generatedPicker.magnification, 2);
    expect(tester.takeException(), isNull);

    // This huge-host parity contract stops after layout.
    await tester.pumpWidget(
      const SizedBox.shrink(),
      phase: EnginePhase.layout,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker keeps a finite large overlay product', (tester) async {
    await _pump(
      tester,
      'CupertinoPicker(itemExtent: 5e307, magnification: 2.0, '
      'children: [Text(text: "one")])',
    );

    final picker = tester.widget<CupertinoPicker>(find.byType(CupertinoPicker));
    expect(picker.itemExtent, 5e307);
    expect(picker.magnification, 2);
    expect(_pickerOverlayHeight(tester), 1e308);
    expect(tester.getSize(find.byType(CupertinoPicker)).isFinite, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('required picker extent still fails before construction',
      (tester) async {
    await _pump(
      tester,
      'CupertinoPicker(itemExtent: data.extent, magnification: data.mag, '
      'children: [Text(text: "one")])',
      data: <String, Object?>{
        'extent': double.nan,
        'mag': double.nan,
      },
    );

    expect(tester.takeException(), isA<ArgumentError>());
    expect(find.byType(CupertinoPicker), findsNothing);
  });

  testWidgets('search item size restores default and retains zero',
      (tester) async {
    await _pump(
      tester,
      'CupertinoSearchTextField(itemSize: data.size)',
      data: <String, Object?>{'size': double.nan},
    );
    expect(
      tester
          .widget<CupertinoSearchTextField>(
            find.byType(CupertinoSearchTextField),
          )
          .itemSize,
      20,
    );
    expect(tester.takeException(), isNull);

    await _pump(tester, 'CupertinoSearchTextField(itemSize: 0.0)');
    expect(
      tester
          .widget<CupertinoSearchTextField>(
            find.byType(CupertinoSearchTextField),
          )
          .itemSize,
      0,
    );
    expect(tester.takeException(), isNull);
  });
}
