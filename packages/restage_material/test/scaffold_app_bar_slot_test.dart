// The `Scaffold.appBar` slot renders a real app bar in the scaffold's own
// bar position, below the status bar inset.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_material/restage_material.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide Switch, WidgetLibrary;

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _materialLibrary =
    LibraryName(<String>['restage', 'material']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'paywall']);

String _paywallSource({String barArgs = '', String scaffoldArgs = ''}) => '''
import restage.core;
import restage.material;
widget Paywall = Scaffold(
  appBar: AppBar(title: Text(text: "Welcome")$barArgs),
  body: Text(text: "body"),$scaffoldArgs
);
''';

const double _topInset = 44;
const double _standardBarHeight = 56;
const double _tallBarHeight = 72;
const double _tabBarHeight = 48;

const String _tabBarSource = '''
import restage.core;
import restage.material;
widget Paywall = DefaultTabController(
  length: 2,
  child: Scaffold(
    appBar: AppBar(
      title: Text(text: "Welcome"),
      bottom: TabBar(
        tabs: [Tab(text: "One"), Tab(text: "Two")],
      ),
      bottomHeight: 48.0,
    ),
    appBarHeight: 104.0,
    body: Text(text: "body"),
  ),
);
''';

void main() {
  test('the catalog entry carries the appBar slot', () {
    final scaffold = kRegistry.findByName('Scaffold', WidgetLibrary.material)!;
    final appBar = scaffold.properties.firstWhere((p) => p.name == 'appBar');
    expect(appBar.type, PropertyType.widget);
    expect(appBar.widgetType, kPreferredSizeWidgetType);
    expect(appBar.constructorNullable, isTrue);

    final height =
        scaffold.properties.firstWhere((p) => p.name == 'appBarHeight');
    expect(height.type, PropertyType.real);
    expect(height.synthetic, kPreferredSizeHeightSyntheticStrategy);
  });

  Future<void> pumpPaywall(
    WidgetTester tester, {
    String barArgs = '',
    String scaffoldArgs = '',
  }) async {
    final runtime = Runtime()
      ..update(_coreLibrary, core.buildCoreWidgetLibrary())
      ..update(_materialLibrary, buildMaterialWidgetLibrary())
      ..update(
        _rootLibrary,
        parseLibraryFile(
          _paywallSource(barArgs: barArgs, scaffoldArgs: scaffoldArgs),
        ),
      );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(top: _topInset)),
        child: MaterialApp(
          home: RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
            onEvent: (_, __) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the bar renders below the status bar inset', (tester) async {
    await pumpPaywall(tester);

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Welcome'), findsOneWidget);

    final barBottom = tester.getRect(find.byType(AppBar)).bottom;
    expect(barBottom, _topInset + _standardBarHeight);
    expect(
        tester.getRect(find.text('body')).top, greaterThanOrEqualTo(barBottom));
  });

  testWidgets('a taller bar pushes the body down', (tester) async {
    await pumpPaywall(
      tester,
      barArgs: ', toolbarHeight: $_tallBarHeight',
      scaffoldArgs: ' appBarHeight: $_tallBarHeight,',
    );

    final barBottom = tester.getRect(find.byType(AppBar)).bottom;
    expect(barBottom, _topInset + _tallBarHeight);
    expect(tester.getRect(find.text('body')).top, barBottom);
  });

  testWidgets('a tab bar under the app bar pushes the body down',
      (tester) async {
    final runtime = Runtime()
      ..update(_coreLibrary, core.buildCoreWidgetLibrary())
      ..update(_materialLibrary, buildMaterialWidgetLibrary())
      ..update(_rootLibrary, parseLibraryFile(_tabBarSource));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(top: _topInset)),
        child: MaterialApp(
          home: RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
            onEvent: (_, __) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('One'), findsOneWidget);

    final barBottom = tester.getRect(find.byType(AppBar)).bottom;
    expect(barBottom, _topInset + _standardBarHeight + _tabBarHeight);
    expect(tester.getRect(find.text('body')).top, barBottom);
  });
}
