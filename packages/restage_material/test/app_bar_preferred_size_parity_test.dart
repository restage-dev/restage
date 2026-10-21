import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_material/restage_material.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide Switch;

const _rootLibrary = LibraryName(['test']);
const _topInset = 24.0;
const _bottomHeight = 30.0;

Runtime _runtime(String appBar, String sizing) => Runtime()
  ..update(
      const LibraryName(['restage', 'core']), core.buildCoreWidgetLibrary())
  ..update(
    const LibraryName(['restage', 'material']),
    buildMaterialWidgetLibrary(),
  )
  ..update(_rootLibrary, parseLibraryFile('''
import restage.core;
import restage.material;
widget Screen = Scaffold(
  appBar: $appBar,
  $sizing
  body: Text(text: "Body"),
);
'''));

Widget _delivered(Runtime runtime, {DynamicContent? data}) => RemoteWidget(
      runtime: runtime,
      data: data ?? DynamicContent(),
      widget: const FullyQualifiedWidgetName(_rootLibrary, 'Screen'),
    );

Future<({double bodyTop, double? naturalHeight, double? effectiveHeight})>
    _measure(
  WidgetTester tester,
  Widget screen, {
  double? themeToolbarHeight = 72,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      appBarTheme: AppBarThemeData(toolbarHeight: themeToolbarHeight),
    ),
    home: MediaQuery(
      data: const MediaQueryData(padding: EdgeInsets.only(top: _topInset)),
      child: screen,
    ),
  ));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final scaffoldFinder = find.byType(Scaffold);
  final scaffold = tester.widget<Scaffold>(scaffoldFinder);
  final size = scaffold.appBar?.preferredSize;
  return (
    bodyTop: tester.getTopLeft(find.text('Body')).dy,
    naturalHeight: size?.height,
    effectiveHeight: size == null
        ? null
        : AppBar.preferredHeightFor(tester.element(scaffoldFinder), size),
  );
}

PreferredSizeWidget _bottom(double height) => PreferredSize(
      preferredSize: Size.fromHeight(height),
      child: SizedBox(height: height),
    );

void main() {
  for (final scenario in [
    (
      name: 'omitted toolbar and bottom',
      toolbarHeight: null,
      bottomHeight: null,
      arguments: '',
      sizing: 'appBarBottomHeight: 0.0,',
    ),
    (
      name: 'explicit null toolbar and bottom',
      toolbarHeight: null,
      bottomHeight: null,
      arguments: 'toolbarHeight: null, bottom: null,',
      sizing: 'appBarToolbarHeight: null, appBarBottomHeight: 0.0,',
    ),
    (
      name: 'zero toolbar height',
      toolbarHeight: 0.0,
      bottomHeight: null,
      arguments: 'toolbarHeight: 0.0,',
      sizing: 'appBarToolbarHeight: 0.0, appBarBottomHeight: 0.0,',
    ),
    (
      name: 'explicit toolbar height',
      toolbarHeight: 40.0,
      bottomHeight: null,
      arguments: 'toolbarHeight: 40.0,',
      sizing: 'appBarToolbarHeight: 40.0, appBarBottomHeight: 0.0,',
    ),
    (
      name: 'themed toolbar with bottom',
      toolbarHeight: null,
      bottomHeight: _bottomHeight,
      arguments: '''
        bottom: PreferredSize(
          preferredSize: 30.0,
          child: SizedBox(height: 30.0),
        ),
        bottomHeight: 30.0,
      ''',
      sizing: 'appBarBottomHeight: 30.0,',
    ),
    (
      name: 'explicit toolbar with bottom',
      toolbarHeight: 40.0,
      bottomHeight: _bottomHeight,
      arguments: '''
        toolbarHeight: 40.0,
        bottom: PreferredSize(
          preferredSize: 30.0,
          child: SizedBox(height: 30.0),
        ),
        bottomHeight: 30.0,
      ''',
      sizing: 'appBarToolbarHeight: 40.0, appBarBottomHeight: 30.0,',
    ),
  ]) {
    testWidgets('delivered sizing matches native ${scenario.name}',
        (tester) async {
      final native = await _measure(
        tester,
        Scaffold(
          appBar: AppBar(
            title: const Text('Title'),
            toolbarHeight: scenario.toolbarHeight,
            bottom: scenario.bottomHeight == null
                ? null
                : _bottom(scenario.bottomHeight!),
          ),
          body: const Text('Body'),
        ),
      );
      final runtime = _runtime(
        'AppBar(title: Text(text: "Title"), ${scenario.arguments})',
        scenario.sizing,
      );
      final delivered = await _measure(tester, _delivered(runtime));
      expect(delivered, native);
      expect(
        delivered.bodyTop,
        _topInset +
            (scenario.toolbarHeight ?? 72) +
            (scenario.bottomHeight ?? 0),
      );
    });
  }

  testWidgets('an absent theme height retains the native toolbar default',
      (tester) async {
    final native = await _measure(
      tester,
      Scaffold(appBar: AppBar(), body: const Text('Body')),
      themeToolbarHeight: null,
    );
    final runtime = _runtime('AppBar()', 'appBarBottomHeight: 0.0,');
    final delivered = await _measure(
      tester,
      _delivered(runtime),
      themeToolbarHeight: null,
    );
    expect(delivered, native);
    expect(delivered.bodyTop, _topInset + kToolbarHeight);
  });

  testWidgets('a fixed PreferredSize keeps its height under an AppBar theme',
      (tester) async {
    final native = await _measure(
      tester,
      Scaffold(appBar: _bottom(44), body: const Text('Body')),
    );
    final runtime = _runtime(
      'PreferredSize(preferredSize: 44.0, child: SizedBox(height: 44.0))',
      'appBarHeight: 44.0,',
    );
    final delivered = await _measure(tester, _delivered(runtime));
    expect(delivered, native);
    expect(delivered.effectiveHeight, 44);
  });

  testWidgets('a null app bar adds no toolbar space', (tester) async {
    final native = await _measure(tester, const Scaffold(body: Text('Body')));
    final delivered = await _measure(tester, _delivered(_runtime('null', '')));
    expect(delivered, native);
    expect(delivered.naturalHeight, isNull);
  });

  testWidgets('the native preferred size tracks runtime theme changes',
      (tester) async {
    final nativeScreen = Scaffold(
      appBar: AppBar(bottom: _bottom(_bottomHeight)),
      body: const Text('Body'),
    );
    final nativeBefore = await _measure(tester, nativeScreen);
    final nativeAfter = await _measure(
      tester,
      nativeScreen,
      themeToolbarHeight: 88,
    );
    final runtime = _runtime('''
      AppBar(
        bottom: PreferredSize(
          preferredSize: 30.0,
          child: SizedBox(height: 30.0),
        ),
        bottomHeight: 30.0,
      )
    ''', 'appBarBottomHeight: 30.0,');
    final screen = _delivered(runtime);
    final deliveredBefore = await _measure(tester, screen);
    final deliveredAfter = await _measure(
      tester,
      screen,
      themeToolbarHeight: 88,
    );
    expect(deliveredBefore, nativeBefore);
    expect(deliveredAfter, nativeAfter);
    expect(deliveredAfter.bodyTop - deliveredBefore.bodyTop, 16);
    expect(deliveredAfter.naturalHeight, deliveredBefore.naturalHeight);
  });

  testWidgets('runtime toolbar values preserve null, zero and bottom sizing',
      (tester) async {
    const heights = <double?>[40, 0, null];
    final native = [
      for (final height in heights)
        await _measure(
          tester,
          Scaffold(
            appBar: AppBar(
              toolbarHeight: height,
              bottom: _bottom(_bottomHeight),
            ),
            body: const Text('Body'),
          ),
        ),
    ];
    final runtime = _runtime('''
      AppBar(
        toolbarHeight: data.style.toolbarHeight,
        bottom: PreferredSize(
          preferredSize: 30.0,
          child: SizedBox(height: 30.0),
        ),
        bottomHeight: 30.0,
      )
    ''', '''
      appBarToolbarHeight: data.style.toolbarHeight,
      appBarBottomHeight: 30.0,
    ''');
    final data = DynamicContent();
    final screen = _delivered(runtime, data: data);
    for (var index = 0; index < heights.length; index++) {
      data.update('style', <String, Object>{
        if (heights[index] case final double height) 'toolbarHeight': height,
      });
      final delivered = await _measure(tester, screen);
      expect(delivered, native[index],
          reason: 'toolbarHeight: ${heights[index]}');
    }
  });

  for (final value in <num>[
    40,
    2e6,
    -1.0,
    double.nan,
    double.infinity,
    double.negativeInfinity,
  ]) {
    testWidgets('toolbar metadata matches its decoded toolbar for $value',
        (tester) async {
      final height = value.isFinite && value >= 0 ? value.toDouble() : null;
      final native = await _measure(
        tester,
        Scaffold(
          appBar: AppBar(
            toolbarHeight: height,
            bottom: _bottom(_bottomHeight),
          ),
          body: const Text('Body'),
        ),
      );
      final runtime = _runtime('''
        AppBar(
          toolbarHeight: data.toolbarHeight,
          bottom: PreferredSize(
            preferredSize: 30.0,
            child: SizedBox(height: 30.0),
          ),
          bottomHeight: 30.0,
        )
      ''', '''
        appBarToolbarHeight: data.toolbarHeight,
        appBarBottomHeight: 30.0,
      ''');
      final data = DynamicContent()..update('toolbarHeight', value);
      final delivered = await _measure(tester, _delivered(runtime, data: data));
      expect(delivered, native);
    });
  }

  for (final themeHeight in <double?>[null, 72]) {
    testWidgets('nested AppBar numeric heights update with theme $themeHeight',
        (tester) async {
      const heights = <num>[40, 0, 31.5];
      final native = <Object>[];
      for (final height in heights) {
        final layout = await _measure(
          tester,
          Scaffold(
            appBar: AppBar(
              title: const Text('Outer'),
              bottom: AppBar(toolbarHeight: height.toDouble()),
            ),
            body: const Text('Body'),
          ),
          themeToolbarHeight: themeHeight,
        );
        native.add(_nestedBarSnapshot(tester, layout));
      }

      final runtime = _runtime('''
        AppBar(
          title: Text(text: "Outer"),
          bottom: AppBar(toolbarHeight: data.bottomHeight),
          bottomHeight: data.bottomHeight,
        )
      ''', 'appBarBottomHeight: data.bottomHeight,');
      final data = DynamicContent();
      final screen = _delivered(runtime, data: data);
      Object? mountedBarState;
      for (var index = 0; index < heights.length; index++) {
        data.update('bottomHeight', heights[index]);
        final layout = await _measure(
          tester,
          screen,
          themeToolbarHeight: themeHeight,
        );
        expect(_nestedBarSnapshot(tester, layout), native[index],
            reason: 'bottomHeight: ${heights[index]}');
        final state = tester.state(find.byType(AppBar).first);
        if (mountedBarState == null) {
          mountedBarState = state;
        } else {
          expect(state, same(mountedBarState));
        }
      }
    });
  }

  for (final themes in <List<double?>>[
    [null, null, null, null, null],
    [72, 72, 72, 72, 72],
    [72, null, 72, null, 72],
  ]) {
    testWidgets('nested AppBar nullable heights update with themes $themes',
        (tester) async {
      const heights = <num?>[null, 40, 0, 31.5, null];
      final native = <Object>[];
      for (var index = 0; index < heights.length; index++) {
        final layout = await _measure(
          tester,
          Scaffold(
            appBar: AppBar(
              title: const Text('Outer'),
              bottom: AppBar(toolbarHeight: heights[index]?.toDouble()),
            ),
            body: const Text('Body'),
          ),
          themeToolbarHeight: themes[index],
        );
        native.add(_nestedBarSnapshot(tester, layout));
      }

      final runtime = _runtime('''
        AppBar(
          title: Text(text: "Outer"),
          bottom: AppBar(toolbarHeight: data.bar.bottomHeight),
          bottomHeight: data.bar.bottomHeight,
        )
      ''', '''
        appBarBottomHeight: {
          '\$restage.constructor.presence': 1,
          '\$restage.constructor.value': data.bar.bottomHeight,
        },
      ''');
      final data = DynamicContent();
      final screen = _delivered(runtime, data: data);
      Object? mountedBarState;
      for (var index = 0; index < heights.length; index++) {
        data.update('bar', {
          if (heights[index] != null) 'bottomHeight': heights[index]!,
        });
        final layout = await _measure(
          tester,
          screen,
          themeToolbarHeight: themes[index],
        );
        expect(_nestedBarSnapshot(tester, layout), native[index],
            reason: 'bottomHeight: ${heights[index]}, theme: ${themes[index]}');
        final state = tester.state(find.byType(AppBar).first);
        if (mountedBarState == null) {
          mountedBarState = state;
        } else {
          expect(state, same(mountedBarState));
        }
      }
    });
  }
}

Object _nestedBarSnapshot(WidgetTester tester, Object layout) {
  final bars = find.byType(AppBar);
  final outer = tester.widget<AppBar>(bars.first);
  return (
    layout: layout,
    outerPreferredHeight: AppBar.preferredHeightFor(
        tester.element(bars.first), outer.preferredSize),
    bottomBounds: tester.getRect(bars.last),
    titleBounds: tester.getRect(find.text('Outer')),
  );
}
