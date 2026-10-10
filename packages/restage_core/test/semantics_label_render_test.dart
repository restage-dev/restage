import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart' show WidgetLibrary;
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide WidgetLibrary;

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'surface']);

void main() {
  test('the catalog entry surfaces label and child at version 7', () {
    final entry = kRegistry.findByName('Semantics', WidgetLibrary.core)!;
    expect(entry.sinceVersion, 7);
    expect(
      entry.properties.where((p) => p.synthetic == null).map((p) => p.name),
      unorderedEquals(<String>['label', 'child']),
    );
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
