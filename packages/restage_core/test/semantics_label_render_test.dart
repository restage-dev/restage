import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart' show WidgetLibrary;
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide WidgetLibrary;

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'surface']);

void main() {
  test('the catalog entry surfaces the inert semantics knobs', () {
    final entry = kRegistry.findByName('Semantics', WidgetLibrary.core)!;
    expect(entry.sinceVersion, 7);
    final names =
        entry.properties.where((p) => p.synthetic == null).map((p) => p.name);
    expect(
      names,
      containsAll(<String>[
        'child',
        'label',
        'header',
        'headingLevel',
        'button',
        'image',
        'hidden',
        'liveRegion',
        'excludeSemantics',
        'value',
        'hint',
        'tooltip',
      ]),
    );
    expect(names, isNot(contains('onTap')));
  });

  testWidgets('flags reach the semantics node', (tester) async {
    final handle = tester.ensureSemantics();
    final runtime = Runtime()
      ..update(_coreLibrary, buildCoreWidgetLibrary())
      ..update(
        _rootLibrary,
        parseLibraryFile('''
import restage.core;
widget Screen = Semantics(header: true, headingLevel: 2, label: "Plans", child: Text(text: "Plans"));
'''),
      );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RemoteWidget(
          runtime: runtime,
          data: DynamicContent(),
          widget: const FullyQualifiedWidgetName(_rootLibrary, 'Screen'),
          onEvent: (_, __) {},
        ),
      ),
    );
    await tester.pump();

    final properties =
        tester.widget<Semantics>(find.byType(Semantics).first).properties;
    expect(properties.header, isTrue);
    expect(properties.headingLevel, 2);
    handle.dispose();
  });

  testWidgets('a label names the wrapped subtree', (tester) async {
    final handle = tester.ensureSemantics();
    final runtime = Runtime()
      ..update(_coreLibrary, buildCoreWidgetLibrary())
      ..update(
        _rootLibrary,
        parseLibraryFile('''
import restage.core;
widget Screen = Semantics(label: "Start trial", child: Text(text: "Go"));
'''),
      );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RemoteWidget(
          runtime: runtime,
          data: DynamicContent(),
          widget: const FullyQualifiedWidgetName(_rootLibrary, 'Screen'),
          onEvent: (_, __) {},
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<Semantics>(find.byType(Semantics).first).properties.label,
      'Start trial',
    );
    expect(find.bySemanticsLabel(RegExp('Start trial')), findsOneWidget);
    handle.dispose();
  });
}
