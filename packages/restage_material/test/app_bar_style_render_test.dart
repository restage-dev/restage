import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_material/restage_material.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide Switch, WidgetLibrary;

const _rootLibrary = LibraryName(['test']);
const _overlay = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarBrightness: Brightness.dark,
  statusBarIconBrightness: Brightness.light,
  systemNavigationBarColor: Color(0xFF123456),
  systemNavigationBarDividerColor: Color(0xFF654321),
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false,
  systemStatusBarContrastEnforced: true,
);
const _leadingTheme = IconThemeData(
  color: Color(0x80112233),
  size: 25,
  opacity: 0.75,
  fill: 0.5,
  weight: 550,
  grade: -25,
  opticalSize: 42,
  shadows: [
    Shadow(color: Color(0xFFF44336), offset: Offset(2, -3), blurRadius: 4)
  ],
  applyTextScaling: true,
);
const _actionsTheme = IconThemeData(
  color: Color(0xFF445566),
  size: 20,
  opacity: 0.5,
  fill: 1,
  weight: 600,
  grade: 50,
  opticalSize: 40,
  shadows: [],
  applyTextScaling: false,
);

void main() {
  setUp(() {
    core.InstalledIconTable.install(
      const core.RestageIconTable.fromFamilies(
        families: {
          'MaterialIcons': {0xe3dc: Icons.menu, 0xe567: Icons.search},
        },
      ),
    );
  });
  tearDown(core.InstalledIconTable.reset);

  for (final field in [
    'statusBarColor',
    'systemNavigationBarColor',
    'systemNavigationBarDividerColor',
  ]) {
    for (final fromTheme in [false, true]) {
      testWidgets(
        '$field copy layers match native nullable ${fromTheme ? 'theme' : 'data'} updates',
        (tester) async {
          final color = ValueNotifier<Color?>(null);
          addTearDown(color.dispose);
          final data = DynamicContent({
            'theme': <String, Object?>{},
            'overrides': <String, Object?>{},
          });
          final valuePath = fromTheme
              ? 'data.theme.appBarTheme.backgroundColor'
              : 'data.overrides.color';
          final runtime = Runtime()
            ..update(const LibraryName(['restage', 'core']),
                core.buildCoreWidgetLibrary())
            ..update(const LibraryName(['restage', 'material']),
                buildMaterialWidgetLibrary())
            ..update(_rootLibrary, parseLibraryFile('''
import restage.core;
import restage.material;
widget Screen = Scaffold(
  appBar: AppBar(
    systemOverlayStyle: {
      statusBarColor: 0,
      statusBarBrightness: "dark",
      statusBarIconBrightness: "light",
      systemNavigationBarColor: 0xFF123456,
      systemNavigationBarDividerColor: 0xFF654321,
      systemNavigationBarIconBrightness: "dark",
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: true,
      copyWith: [
        {$field: $valuePath},
        {
          statusBarBrightness: null,
          statusBarIconBrightness: "dark",
          systemNavigationBarIconBrightness: null,
          systemNavigationBarContrastEnforced: null,
          systemStatusBarContrastEnforced: false
        },
        {$field: null, statusBarIconBrightness: null, systemStatusBarContrastEnforced: null}
      ]
    }
  )
);
'''));
          const nativeKey = ValueKey('native');
          const deliveredKey = ValueKey('delivered');
          await tester.pumpWidget(MaterialApp(
            home: Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<Color?>(
                    key: nativeKey,
                    valueListenable: color,
                    builder: (context, value, child) => Theme(
                      data: Theme.of(context).copyWith(
                        appBarTheme: AppBarThemeData(backgroundColor: value),
                      ),
                      child: Builder(
                        builder: (context) => Scaffold(
                          appBar: AppBar(
                            systemOverlayStyle: _copyOverlayColor(
                              field,
                              fromTheme
                                  ? Theme.of(context)
                                      .appBarTheme
                                      .backgroundColor
                                  : value,
                            )
                                .copyWith(
                                  statusBarBrightness: null,
                                  statusBarIconBrightness: Brightness.dark,
                                  systemNavigationBarIconBrightness: null,
                                  systemNavigationBarContrastEnforced: null,
                                  systemStatusBarContrastEnforced: false,
                                )
                                .copyWith(
                                  statusBarColor: null,
                                  systemNavigationBarColor: null,
                                  systemNavigationBarDividerColor: null,
                                  statusBarIconBrightness: null,
                                  systemStatusBarContrastEnforced: null,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: RemoteWidget(
                    key: deliveredKey,
                    runtime: runtime,
                    data: data,
                    widget:
                        const FullyQualifiedWidgetName(_rootLibrary, 'Screen'),
                  ),
                ),
              ],
            ),
          ));
          final deliveredElement = tester.element(find.byKey(deliveredKey));
          for (final value in [null, const Color(0xFFAABBCC), null]) {
            color.value = value;
            data
              ..update('theme', {
                'appBarTheme': {
                  if (value != null) 'backgroundColor': value.toARGB32(),
                },
              })
              ..update('overrides', {
                if (value != null) 'color': value.toARGB32(),
              });
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(tester.element(find.byKey(deliveredKey)),
                same(deliveredElement));
            SystemUiOverlayStyle? property(Key key) => tester
                .widget<AppBar>(
                  find.descendant(
                      of: find.byKey(key), matching: find.byType(AppBar)),
                )
                .systemOverlayStyle;
            SystemUiOverlayStyle region(Key key) => tester
                .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
                  find.descendant(
                    of: find.byKey(key),
                    matching:
                        find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
                  ),
                )
                .value;
            expect(property(deliveredKey), property(nativeKey));
            expect(region(deliveredKey), region(nativeKey));
          }
        },
      );
    }
  }

  testWidgets('icon theme operations match native mounted updates',
      (tester) async {
    final state = ValueNotifier<Map<String, Object?>>(const {});
    addTearDown(state.dispose);
    final data = DynamicContent({'icon': <String, Object?>{}});
    final runtime = Runtime()
      ..update(
          const LibraryName(['restage', 'core']), core.buildCoreWidgetLibrary())
      ..update(const LibraryName(['restage', 'material']),
          buildMaterialWidgetLibrary())
      ..update(_rootLibrary, parseLibraryFile('''
import restage.core;
import restage.material;
widget Screen = Scaffold(
  appBar: AppBar(
    leading: Icon(iconCodepoint: 0xe3dc),
    actions: [Icon(iconCodepoint: 0xe567)],
    iconTheme: {
      fallback: true,
      copyWith: [{size: data.icon.size, color: data.icon.color}, {opacity: data.icon.opacity}]
    },
    actionsIconTheme: {
      lerp: {a: {size: 18, opacity: 0.25, weight: 300}, b: data.icon.end, t: data.icon.t},
      copyWith: [{grade: data.icon.grade}]
    },
  ),
);
'''));
    IconThemeData? end(Map<String, Object?> values) => values['end'] == null
        ? null
        : const IconThemeData(size: 30, weight: 500);
    const nativeKey = ValueKey('native');
    const deliveredKey = ValueKey('delivered');
    await tester.pumpWidget(MaterialApp(
      home: Row(
        children: [
          Expanded(
            child: ValueListenableBuilder<Map<String, Object?>>(
              key: nativeKey,
              valueListenable: state,
              builder: (context, values, child) => Scaffold(
                appBar: AppBar(
                  leading: const Icon(Icons.menu),
                  actions: const [Icon(Icons.search)],
                  iconTheme: const IconThemeData.fallback()
                      .copyWith(
                        size: values['size'] as double?,
                        color: values['color'] == null
                            ? null
                            : Color(values['color']! as int),
                      )
                      .copyWith(opacity: values['opacity'] as double?),
                  actionsIconTheme: IconThemeData.lerp(
                    const IconThemeData(size: 18, opacity: 0.25, weight: 300),
                    end(values),
                    (values['t'] as double?) ?? 0,
                  ).copyWith(grade: values['grade'] as double?),
                ),
              ),
            ),
          ),
          Expanded(
            child: RemoteWidget(
              key: deliveredKey,
              runtime: runtime,
              data: data,
              widget: const FullyQualifiedWidgetName(_rootLibrary, 'Screen'),
            ),
          ),
        ],
      ),
    ));
    final deliveredBar = tester.state(find.descendant(
      of: find.byKey(deliveredKey),
      matching: find.byType(AppBar),
    ));
    for (final values in <Map<String, Object?>>[
      {'t': 0.0},
      {'size': 0.0, 't': 0.25, 'end': true, 'grade': 0.0},
      {'size': 31.5, 'color': 0xFF112233, 'opacity': 2.0, 't': 0.5},
      {'t': 1.5, 'end': true, 'grade': -10.0},
      {'t': 0.0},
    ]) {
      state.value = values;
      data.update('icon', {
        for (final entry in values.entries)
          if (entry.key == 'end')
            'end': <String, Object?>{'size': 30, 'weight': 500}
          else
            entry.key: entry.value!,
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.state(find.descendant(
          of: find.byKey(deliveredKey),
          matching: find.byType(AppBar),
        )),
        same(deliveredBar),
      );
      Map<String, Object?> read(Key key) {
        final bar = tester.widget<AppBar>(find.descendant(
          of: find.byKey(key),
          matching: find.byType(AppBar),
        ));
        IconThemeData icon(IconData data) => IconTheme.of(tester.element(
              find.descendant(of: find.byKey(key), matching: find.byIcon(data)),
            ));
        return {
          'iconTheme': bar.iconTheme,
          'actionsIconTheme': bar.actionsIconTheme,
          'leading': icon(Icons.menu),
          'actions': icon(Icons.search),
        };
      }

      expect(read(deliveredKey), read(nativeKey), reason: '$values');
    }
  });

  final cases = <({
    String name,
    String wire,
    SystemUiOverlayStyle? overlay,
    IconThemeData? icons,
    IconThemeData? actions,
  })>[
    (
      name: 'all overlay and icon fields',
      wire: '''
        systemOverlayStyle: {
          statusBarColor: 0,
          statusBarBrightness: "dark",
          statusBarIconBrightness: "light",
          systemNavigationBarColor: 0xFF123456,
          systemNavigationBarDividerColor: 0xFF654321,
          systemNavigationBarIconBrightness: "dark",
          systemNavigationBarContrastEnforced: false,
          systemStatusBarContrastEnforced: true
        },
        iconTheme: {
          color: 0x80112233, size: 25, opacity: 0.75, fill: 0.5,
          weight: 550, grade: -25, opticalSize: 42,
          shadows: [{color: 0xFFF44336, offset: {x: 2, y: -3}, blurRadius: 4}],
          applyTextScaling: true
        },
        actionsIconTheme: {
          color: 0xFF445566, size: 20, opacity: 0.5, fill: 1,
          weight: 600, grade: 50, opticalSize: 40,
          shadows: [], applyTextScaling: false
        },
      ''',
      overlay: _overlay,
      icons: _leadingTheme,
      actions: _actionsTheme,
    ),
    (
      name: 'omitted styles',
      wire: '',
      overlay: null,
      icons: null,
      actions: null
    ),
    (
      name: 'null styles',
      wire:
          'systemOverlayStyle: null, iconTheme: null, actionsIconTheme: null,',
      overlay: null,
      icons: null,
      actions: null,
    ),
    (
      name: 'empty styles',
      wire: 'systemOverlayStyle: {}, iconTheme: {}, actionsIconTheme: {},',
      overlay: const SystemUiOverlayStyle(),
      icons: const IconThemeData(),
      actions: const IconThemeData(),
    ),
    (
      name: 'partial styles and nullable fields',
      wire: '''
        systemOverlayStyle: {statusBarColor: null, statusBarIconBrightness: "dark"},
        iconTheme: {size: 22, color: null, shadows: null},
        actionsIconTheme: {opacity: 0.25, applyTextScaling: null},
      ''',
      overlay:
          const SystemUiOverlayStyle(statusBarIconBrightness: Brightness.dark),
      icons: const IconThemeData(size: 22),
      actions: const IconThemeData(opacity: 0.25),
    ),
    (
      name: 'zero values and false scaling',
      wire: '''
        iconTheme: {size: 0, opacity: 0, fill: 0, grade: 0, shadows: [], applyTextScaling: false},
        actionsIconTheme: {size: 24, opacity: 0, fill: 0, grade: 0, shadows: [], applyTextScaling: false},
      ''',
      overlay: null,
      icons: const IconThemeData(
        size: 0,
        opacity: 0,
        fill: 0,
        grade: 0,
        shadows: [],
        applyTextScaling: false,
      ),
      actions: const IconThemeData(
        size: 24,
        opacity: 0,
        fill: 0,
        grade: 0,
        shadows: [],
        applyTextScaling: false,
      ),
    ),
    (
      name: 'fallback and copyWith layers',
      wire: '''
        iconTheme: {fallback: true, copyWith: [{size: 0, color: null}, {applyTextScaling: true, shadows: []}]},
        actionsIconTheme: {size: 20, copyWith: [{}, {opacity: 2}]},
      ''',
      overlay: null,
      icons: const IconThemeData.fallback()
          .copyWith(size: 0)
          .copyWith(applyTextScaling: true, shadows: []),
      actions: const IconThemeData(size: 20).copyWith().copyWith(opacity: 2),
    ),
    (
      name: 'lerp with nullable endpoints',
      wire: '''
        iconTheme: {lerp: {a: {fallback: true}, b: {size: 30, color: 0xFF445566, weight: 700}, t: 0.75}},
        actionsIconTheme: {lerp: {t: 0.5}, copyWith: [{size: 18}]},
      ''',
      overlay: null,
      icons: IconThemeData.lerp(
        const IconThemeData.fallback(),
        const IconThemeData(
          size: 30,
          color: Color(0xFF445566),
          weight: 700,
        ),
        0.75,
      ),
      actions: IconThemeData.lerp(null, null, 0.5).copyWith(size: 18),
    ),
    (
      name: 'native opacity clamping',
      wire: 'iconTheme: {opacity: 2}, actionsIconTheme: {opacity: -1},',
      overlay: null,
      icons: const IconThemeData(opacity: 2),
      actions: const IconThemeData(opacity: -1),
    ),
  ];

  for (final brightness in Brightness.values) {
    for (final themed in [false, true]) {
      for (final styleCase in cases) {
        testWidgets(
          '${styleCase.name} matches native rendering ($brightness, themed: $themed)',
          (tester) async {
            final theme = ThemeData(
              brightness: brightness,
              appBarTheme: themed
                  ? const AppBarThemeData(
                      systemOverlayStyle: SystemUiOverlayStyle.light,
                      iconTheme: _actionsTheme,
                      actionsIconTheme: _leadingTheme,
                    )
                  : null,
            );
            final native = await _pumpAndRead(
              tester,
              theme: theme,
              child: Scaffold(
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  foregroundColor: const Color(0xFF221133),
                  centerTitle: false,
                  elevation: 0,
                  title: const Text('Welcome'),
                  leading: const Icon(Icons.menu),
                  actions: const [Icon(Icons.search), Text('Done')],
                  titleTextStyle:
                      const TextStyle(fontSize: 19, color: Color(0xFF2196F3)),
                  toolbarTextStyle:
                      const TextStyle(fontSize: 13, color: Color(0xFFF44336)),
                  systemOverlayStyle: styleCase.overlay,
                  iconTheme: styleCase.icons,
                  actionsIconTheme: styleCase.actions,
                ),
              ),
            );
            final runtime = Runtime()
              ..update(const LibraryName(['restage', 'core']),
                  core.buildCoreWidgetLibrary())
              ..update(const LibraryName(['restage', 'material']),
                  buildMaterialWidgetLibrary())
              ..update(_rootLibrary, parseLibraryFile('''
import restage.core;
import restage.material;
widget Screen = Scaffold(
  appBar: AppBar(
    backgroundColor: 0, foregroundColor: 0xFF221133,
    centerTitle: false, elevation: 0,
    title: Text(text: "Welcome"),
    leading: Icon(iconCodepoint: 0xe3dc),
    actions: [Icon(iconCodepoint: 0xe567), Text(text: "Done")],
    titleTextStyle: {fontSize: 19, color: 0xFF2196F3},
    toolbarTextStyle: {fontSize: 13, color: 0xFFF44336},
    ${styleCase.wire}
  ),
);
'''));
            final delivered = await _pumpAndRead(
              tester,
              theme: theme,
              child: RemoteWidget(
                runtime: runtime,
                data: DynamicContent(),
                widget: const FullyQualifiedWidgetName(_rootLibrary, 'Screen'),
              ),
            );
            expect(delivered, native);
          },
        );
      }
    }
  }
}

SystemUiOverlayStyle _copyOverlayColor(String field, Color? color) =>
    switch (field) {
      'statusBarColor' => _overlay.copyWith(statusBarColor: color),
      'systemNavigationBarColor' =>
        _overlay.copyWith(systemNavigationBarColor: color),
      'systemNavigationBarDividerColor' =>
        _overlay.copyWith(systemNavigationBarDividerColor: color),
      _ => throw ArgumentError.value(field),
    };

Future<Map<String, Object?>> _pumpAndRead(
  WidgetTester tester, {
  required ThemeData theme,
  required Widget child,
}) async {
  final captureKey = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(),
    theme: theme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(2)),
      child: child!,
    ),
    home: RepaintBoundary(key: captureKey, child: child),
  ));
  await tester.pump();
  expect(tester.takeException(), isNull);
  final bar = tester.widget<AppBar>(find.byType(AppBar));
  final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
    find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    ),
  );
  Map<String, Object?> icon(IconData data) {
    final finder = find.byIcon(data);
    final glyph = tester.widget<RichText>(find.descendant(
      of: finder,
      matching: find.byType(RichText),
    ));
    return {
      'theme': IconTheme.of(tester.element(finder)),
      'style': glyph.text.style,
      'size': tester.getSize(finder),
    };
  }

  TextStyle? textStyle(String text) => tester
      .widget<RichText>(find.descendant(
        of: find.text(text),
        matching: find.byType(RichText),
      ))
      .text
      .style;
  final boundary =
      captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final pixels = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
    } finally {
      image.dispose();
    }
  });
  expect(pixels, isNotEmpty);
  return {
    'overlayProperty': bar.systemOverlayStyle,
    'iconThemeProperty': bar.iconTheme,
    'actionsIconThemeProperty': bar.actionsIconTheme,
    'overlayRegion': region.value,
    'leading': icon(Icons.menu),
    'actions': icon(Icons.search),
    'titleStyle': textStyle('Welcome'),
    'toolbarStyle': textStyle('Done'),
    'pixels': pixels,
  };
}
