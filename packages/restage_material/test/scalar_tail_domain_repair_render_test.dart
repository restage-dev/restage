import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_material/restage_material.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide Switch, WidgetLibrary;

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _materialLibrary =
    LibraryName(<String>['restage', 'material']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'surface']);

Future<void> _pump(
  WidgetTester tester,
  String source, {
  Map<String, Object?> data = const <String, Object?>{},
}) async {
  final runtime = Runtime()
    ..update(_coreLibrary, core.buildCoreWidgetLibrary())
    ..update(_materialLibrary, buildMaterialWidgetLibrary())
    ..update(_rootLibrary, parseLibraryFile(source));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: RemoteWidget(
              runtime: runtime,
              data: DynamicContent(data),
              widget: const FullyQualifiedWidgetName(_rootLibrary, 'Surface'),
              onEvent: (_, __) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

const String _imports = '''
import restage.core;
import restage.material;
''';

void main() {
  testWidgets('nonnegative scalar slots restore defaults together',
      (tester) async {
    await _pump(
      tester,
      '''
$_imports
widget Surface = Column(children: [
  SizedBox(height: 80.0, child: AppBar(toolbarHeight: data.nan,
    leadingWidth: data.infinity, title: Text(text: "title"))),
  Divider(height: -1.0, thickness: data.nan),
  Tab(text: "tab", height: data.infinity),
]);
''',
      data: <String, Object?>{
        'nan': double.nan,
        'infinity': double.infinity,
      },
    );

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final divider = tester.widget<Divider>(find.byType(Divider));
    final tab = tester.widget<Tab>(find.byType(Tab));
    expect(appBar.toolbarHeight, isNull);
    expect(appBar.leadingWidth, isNull);
    expect(divider.height, 16);
    expect(divider.thickness, 1);
    expect(tab.height, isNull);
    for (final finder in [find.byType(AppBar), find.byType(Divider)]) {
      final size = tester.getSize(finder);
      expect(size.width.isFinite, isTrue);
      expect(size.height.isFinite, isTrue);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero remains legal for every nonnegative scalar slot',
      (tester) async {
    await _pump(
      tester,
      '''
$_imports
widget Surface = Column(children: [
  SizedBox(height: 80.0, child: AppBar(toolbarHeight: 0.0,
    leadingWidth: 0.0, title: Text(text: "title"))),
  Divider(height: 0.0, thickness: 0.0),
  Tab(text: "tab", height: 0.0),
]);
''',
    );

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final divider = tester.widget<Divider>(find.byType(Divider));
    final tab = tester.widget<Tab>(find.byType(Tab));
    expect(appBar.toolbarHeight, 0);
    expect(appBar.leadingWidth, 0);
    expect(divider.height, 0);
    expect(divider.thickness, 0);
    expect(tab.height, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bounded ratios restore defaults for invalid inputs',
      (tester) async {
    const invalid = <({String expression, Map<String, Object?> data})>[
      (expression: '0.0', data: <String, Object?>{}),
      (expression: '-1.0', data: <String, Object?>{}),
      (expression: '1.1', data: <String, Object?>{}),
      (expression: 'data.nan', data: <String, Object?>{'nan': double.nan}),
      (
        expression: 'data.infinity',
        data: <String, Object?>{'infinity': double.infinity},
      ),
    ];

    for (final value in invalid) {
      await _pump(
        tester,
        '''
$_imports
widget Surface = RestageModalSheet(open: false,
  scrollControlDisabledMaxHeightRatio: ${value.expression},
  child: SizedBox(width: 20.0, height: 20.0));
''',
        data: value.data,
      );
      expect(
        tester
            .widget<RestageModalSheet>(find.byType(RestageModalSheet))
            .scrollControlDisabledMaxHeightRatio,
        0.5625,
      );
      expect(tester.takeException(), isNull);

      await _pump(
        tester,
        '''
$_imports
widget Surface = SizedBox(width: 300.0, height: 100.0,
  child: RestagePager(viewportFraction: ${value.expression},
    children: [Text(text: "one")]));
''',
        data: value.data,
      );
      expect(
        tester.widget<RestagePager>(find.byType(RestagePager)).viewportFraction,
        1,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('tiny positive ratios and one pass through', (tester) async {
    for (final value in ['5e-324', '1.0']) {
      final captured = <String, Widget>{};
      final generated = buildMaterialWidgetLibrary();
      final runtime = Runtime()
        ..update(_coreLibrary, core.buildCoreWidgetLibrary())
        ..update(
          _materialLibrary,
          LocalWidgetLibrary(<String, LocalWidgetBuilder>{
            for (final factory in generated.widgets.entries)
              factory.key: (context, source) {
                captured[factory.key] = factory.value(context, source);
                return const SizedBox.shrink();
              },
          }),
        )
        ..update(
          _rootLibrary,
          parseLibraryFile('''
$_imports
widget Surface = Column(children: [
  RestageModalSheet(open: false,
    scrollControlDisabledMaxHeightRatio: $value,
    child: SizedBox(width: 20.0, height: 20.0)),
  RestagePager(viewportFraction: $value,
    children: [Text(text: "one")]),
]);
'''),
        );
      await tester.pumpWidget(
        MaterialApp(
          home: RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: const FullyQualifiedWidgetName(_rootLibrary, 'Surface'),
            onEvent: (_, __) {},
          ),
        ),
      );
      await tester.pump();

      expect(
        (captured['RestageModalSheet']! as RestageModalSheet)
            .scrollControlDisabledMaxHeightRatio,
        value == '1.0' ? 1 : double.minPositive,
      );
      expect(
        (captured['RestagePager']! as RestagePager).viewportFraction,
        value == '1.0' ? 1 : double.minPositive,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('an open modal assigns the requested finite max height',
      (tester) async {
    await _pump(
      tester,
      '''
$_imports
widget Surface = RestageModalSheet(open: true,
  scrollControlDisabledMaxHeightRatio: 0.5,
  child: SizedBox(width: 20.0, height: 500.0));
''',
    );

    final constrainedBoxes = tester.widgetList<ConstrainedBox>(
      find.descendant(
        of: find.byType(RestageModalSheet),
        matching: find.byType(ConstrainedBox),
      ),
    );
    expect(
      constrainedBoxes.any((box) => box.constraints.maxHeight == 150),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
